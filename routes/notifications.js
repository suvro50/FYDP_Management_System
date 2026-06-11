const express = require('express');
const router = express.Router();
const db = require('../config/db');

// Helper: derive a human-readable title and navigation link from a notification row
// role must be passed so links go to the correct panel
function enrichNotification(n, role) {
  const titleMap = {
    INVITATION_RECEIVED:  '📩 Team Invitation',
    INVITATION_ACCEPTED:  '✅ Invitation Accepted',
    INVITATION_REJECTED:  '❌ Invitation Rejected',
    REPORT_APPROVED:      '✅ Report Approved',
    REPORT_REJECTED:      '❌ Report Rejected',
    ESCALATION_COMPLETE:  '📤 Reports Escalated',
    STAGE_PROMOTED:       '⬆️ Stage Promoted',
    NEW_GROUP_MESSAGE:    '💬 New Group Message',
    NEW_DIRECT_MESSAGE:   '✉️ New Direct Message',
    SYSTEM_ALERT:         '🔔 Alert',
  };

  n.title = n.title || titleMap[n.notification_type] || '🔔 Notification';

  // Role-based dashboard prefixes
  const isSupervisor    = role === 'SUPERVISOR';
  const isTeacher       = role === 'COURSE_TEACHER';
  const isStudent       = role === 'STUDENT';
  const isPreFydp       = role === 'PRE_FYDP_STUDENT';

  let link = '/notifications';
  const t = n.notification_type;
  const msg = (n.message || '').toLowerCase();
  const title = (n.title || '').toLowerCase();

  if (t === 'INVITATION_RECEIVED' || t === 'INVITATION_ACCEPTED' || t === 'INVITATION_REJECTED') {
    // Only students receive team invitations
    link = isPreFydp ? '/pre-fydp/my-requests' : '/student/dashboard';

  } else if (t === 'REPORT_APPROVED' || t === 'REPORT_REJECTED') {
    // Supervisors/teachers see the approvals panel; students see their reports
    if (isSupervisor) link = '/supervisor/approvals';
    else if (isTeacher) link = '/teacher/inbox';
    else link = '/student/reports';

  } else if (t === 'ESCALATION_COMPLETE') {
    // Teacher completed escalation → teacher inbox; supervisor sees approvals
    if (isSupervisor) link = '/supervisor/approvals';
    else if (isTeacher) link = '/teacher/inbox';
    else link = '/notifications';

  } else if (t === 'STAGE_PROMOTED') {
    if (isSupervisor) link = '/supervisor/groups';
    else if (isTeacher) link = '/teacher/groups';
    else link = '/student/dashboard';

  } else if (t === 'NEW_GROUP_MESSAGE') {
    if (isSupervisor) {
      link = '/supervisor/groups';
    } else if (isTeacher) {
      if (title.includes('supervisor')) link = '/teacher/supervising_groups';
      else link = '/teacher/groups';
    } else {
      // Student
      if (title.includes('members')) link = '/student/my-group-chat';
      else if (title.includes('supervisor')) link = '/student/supervisor-group-chat';
      else if (title.includes('teacher')) link = '/student/teacher-group-chat';
      else link = '/student/my-group-chat';
    }

  } else if (t === 'NEW_DIRECT_MESSAGE') {
    if (isSupervisor) {
      if (title.includes('teacher') || title.includes('course')) link = '/supervisor/chat';
      else link = '/supervisor/student-inbox';
    } else if (isTeacher) {
      if (title.includes('supervisor')) link = '/teacher/supervisor-chat';
      else link = '/teacher/student-inbox';
    } else {
      // Student
      if (title.includes('teacher') || title.includes('course')) link = '/student/teacher-chat';
      else link = '/student/supervisor-chat';
    }

  } else if (t === 'SYSTEM_ALERT') {
    if (title.includes('message') || msg.includes('message') || title.includes('dm') || msg.includes('dm')) {
      if (title.includes('group') || msg.includes('group')) {
        if (isSupervisor) {
          link = '/supervisor/groups';
        } else if (isTeacher) {
          if (title.includes('supervisor')) link = '/teacher/supervising_groups';
          else link = '/teacher/groups';
        } else {
          if (title.includes('members')) link = '/student/my-group-chat';
          else if (title.includes('supervisor')) link = '/student/supervisor-group-chat';
          else if (title.includes('teacher')) link = '/student/teacher-group-chat';
          else link = '/student/my-group-chat';
        }
      } else {
        // DM fallback
        if (isSupervisor) {
          if (title.includes('teacher') || title.includes('course')) link = '/supervisor/chat';
          else link = '/supervisor/student-inbox';
        } else if (isTeacher) {
          if (title.includes('supervisor')) link = '/teacher/supervisor-chat';
          else link = '/teacher/student-inbox';
        } else {
          if (title.includes('teacher') || title.includes('course')) link = '/student/teacher-chat';
          else link = '/student/supervisor-chat';
        }
      }
    } else if (msg.includes('pending') || msg.includes('report') || title.includes('report')) {
      if (isSupervisor) link = '/supervisor/approvals';
      else if (isTeacher) link = '/teacher/inbox';
      else link = '/student/reports';
    } else if (msg.includes('escalat') || title.includes('escalat')) {
      if (isTeacher) link = '/teacher/inbox';
      else if (isSupervisor) link = '/supervisor/approvals';
    }
  }

  // Supervisor request notifications
  if (t === 'SUPERVISOR_REQUEST_RECEIVED') {
    link = isSupervisor ? '/supervisor/requests' : '/notifications';
  } else if (t === 'SUPERVISOR_REQUEST_ACCEPTED') {
    link = isPreFydp || isStudent ? '/student/dashboard' : '/notifications';
  } else if (t === 'SUPERVISOR_REQUEST_REJECTED' || t === 'SUPERVISOR_SLOT_FULL') {
    link = isPreFydp ? '/pre-fydp/dashboard' : '/notifications';
  }

  n.link = link;
  return n;
}

// GET /api/notifications — Paginated notification list
router.get('/', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const role   = req.session.user.role;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;

    const [[{ total }]] = await db.query(
      'SELECT COUNT(*) as total FROM notifications WHERE user_id = ?', [userId]
    );

    const [notifications] = await db.query(
      `SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?`,
      [userId, limit, offset]
    );

    res.json({ notifications: notifications.map(n => enrichNotification(n, role)), pagination: { page, limit, total, totalPages: Math.ceil(total / limit) } });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load notifications' });
  }
});

// GET /api/notifications/count — Unread count for badge
router.get('/count', async (req, res) => {
  try {
    const [[{ count }]] = await db.query(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0',
      [req.session.user.user_id]
    );
    res.json({ unread_count: count });
  } catch (err) {
    res.json({ unread_count: 0 });
  }
});

// PUT /api/notifications/:id/read — Mark as read
router.put('/:id/read', async (req, res) => {
  try {
    await db.query(
      'UPDATE notifications SET is_read = 1 WHERE notification_id = ? AND user_id = ?',
      [req.params.id, req.session.user.user_id]
    );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to mark notification as read' });
  }
});

// PUT /api/notifications/read-all — Mark all as read
router.put('/read-all', async (req, res) => {
  try {
    await db.query(
      'UPDATE notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0',
      [req.session.user.user_id]
    );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to mark all as read' });
  }
});

module.exports = router;

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
    SYSTEM_ALERT:         '🔔 Alert',
  };

  n.title = titleMap[n.notification_type] || '🔔 Notification';

  // Role-based dashboard prefixes
  const isSupervisor    = role === 'SUPERVISOR';
  const isTeacher       = role === 'COURSE_TEACHER';
  const isStudent       = role === 'STUDENT';
  const isPreFydp       = role === 'PRE_FYDP_STUDENT';

  let link = '/notifications';
  const t = n.notification_type;
  const msg = (n.message || '').toLowerCase();

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

  } else if (t === 'SYSTEM_ALERT') {
    if (msg.includes('group message') || msg.includes('new message in')) {
      if (isSupervisor) link = '/supervisor/groups';
      else if (isTeacher) link = '/teacher/groups';
      else link = '/student/my-group-chat';
    } else if (msg.includes('message from') && msg.includes('supervisor')) {
      if (isTeacher) link = '/teacher/supervisor-chat';
      else link = '/student/supervisor-chat';
    } else if (msg.includes('message from') && (msg.includes('teacher') || msg.includes('course'))) {
      link = '/student/teacher-chat';
    } else if (msg.includes('message from') && msg.includes('student')) {
      if (isSupervisor) link = '/supervisor/student-inbox';
      else if (isTeacher) link = '/teacher/student-inbox';
      else link = '/notifications';
    } else if (msg.includes('message from')) {
      // Fallback: DM received
      if (isSupervisor) link = '/supervisor/student-inbox';
      else if (isTeacher) link = '/teacher/student-inbox';
      else link = '/student/supervisor-chat';
    } else if (msg.includes('pending') || msg.includes('report')) {
      if (isSupervisor) link = '/supervisor/approvals';
      else if (isTeacher) link = '/teacher/inbox';
      else link = '/student/reports';
    } else if (msg.includes('escalat')) {
      if (isTeacher) link = '/teacher/inbox';
      else if (isSupervisor) link = '/supervisor/approvals';
    }
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

const express = require('express');
const router = express.Router();
const db = require('../config/db');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ─── File Upload Setup ─────────────────────────────────────────────────────
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '../public/uploads/reports');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const uniqueName = `report_${req.session.user.user_id}_${Date.now()}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  }
});
const upload = multer({ storage, limits: { fileSize: 80 * 1024 * 1024 }, fileFilter: (req, file, cb) => {
  if (file.mimetype === 'application/pdf') cb(null, true);
  else cb(new Error('Only PDF files are allowed'));
}});

// Custom middleware to handle Multer upload and catch errors gracefully
const uploadReport = (req, res, next) => {
  upload.single('report_file')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ error: 'File is too large. Maximum size allowed is 80MB.' });
      }
      return res.status(400).json({ error: `Upload error: ${err.message}` });
    } else if (err) {
      return res.status(400).json({ error: err.message || 'Error uploading file' });
    }
    next();
  });
};

// ─── Middleware: Check group membership ────────────────────────────────────
async function checkGroupStatus(req, res, next) {
  try {
    const studentId = req.session.user.user_id;
    const [groupRows] = await db.query(
      `SELECT gm.group_id, gm.member_role, pg.group_code, pg.project_title,
              pd.domain_name, fs.stage_name, fs.stage_id, pg.supervisor_id,
              s.section_code
       FROM group_members gm
       JOIN project_groups pg ON gm.group_id = pg.group_id
       LEFT JOIN project_domains pd ON pg.project_domain_id = pd.domain_id
       LEFT JOIN fydp_stages fs ON pg.current_stage_id = fs.stage_id
       LEFT JOIN sections s ON pg.section_id = s.section_id
       WHERE gm.student_id = ? AND pg.is_active = 1
       ORDER BY pg.created_at DESC LIMIT 1`,
      [studentId]
    );
    req.activeGroup = groupRows.length > 0 ? groupRows[0] : null;
    next();
  } catch (error) {
    console.error('Error checking group status:', error);
    res.status(500).json({ error: 'Database error' });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/dashboard-data
// ═══════════════════════════════════════════════════════════════════════════
router.get('/dashboard-data', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ type: 'MATCHMAKING' });

    const groupId = req.activeGroup.group_id;

    const [members] = await db.query(
      `SELECT u.full_name, u.university_id, u.user_id, u.profile_photo, gm.member_role
       FROM group_members gm
       JOIN users u ON gm.student_id = u.user_id
       WHERE gm.group_id = ?
       ORDER BY FIELD(gm.member_role,'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER')`,
      [groupId]
    );

    const [supRows] = await db.query(
      `SELECT u.user_id, u.full_name, u.email, d.department_name AS department, u.profile_photo
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.user_id = ?`,
      [req.activeGroup.supervisor_id]
    );

    const [reports] = await db.query(
      `SELECT report_id, week_no, report_title, supervisor_status, supervisor_feedback,
              report_file_path, submitted_at
       FROM weekly_progress_reports
       WHERE group_id = ? AND student_id = ?
       ORDER BY week_no DESC LIMIT 6`,
      [groupId, req.session.user.user_id]
    );

    // Stats
    const [allReports] = await db.query(
      `SELECT supervisor_status FROM weekly_progress_reports WHERE group_id = ? AND student_id = ?`,
      [groupId, req.session.user.user_id]
    );
    const totalReports = allReports.length;
    const approvedCount = allReports.filter(r => r.supervisor_status === 'APPROVED').length;
    const pendingCount = allReports.filter(r => r.supervisor_status === 'PENDING').length;

    // Unread messages count (skip if error)
    let unreadMsgs = [{ cnt: 0 }];
    try {
      [unreadMsgs] = await db.query(
        `SELECT COUNT(*) as cnt FROM group_chat_messages WHERE group_id = ? AND sender_id != ?`,
        [groupId, req.session.user.user_id]
      );
    } catch(e) { /* ignore */ }

    return res.json({
      type: 'FYDP',
      group: req.activeGroup,
      members,
      supervisor: supRows[0] || null,
      recent_reports: reports,
      stats: { totalReports, approvedCount, pendingCount, totalWeeks: 12 }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load dashboard data' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/reports — All my reports (includes per-week status)
//   Now also includes group reports submitted by other group members
// ═══════════════════════════════════════════════════════════════════════════
router.get('/reports', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ reports: [], week_status: [] });
    const groupId = req.activeGroup.group_id;
    const studentId = req.session.user.user_id;

    // Clear weekly progress report notifications for this student
    await db.query(
      `UPDATE notifications 
       SET is_read = 1 
       WHERE user_id = ? 
         AND (notification_type IN ('REPORT_APPROVED', 'REPORT_REJECTED') OR title LIKE '%Report Approved%' OR title LIKE '%Report Rejected%') 
         AND is_read = 0`,
      [studentId]
    );

    // 1. Get this student's own reports
    const [myReports] = await db.query(
      `SELECT wpr.report_id, wpr.week_no, wpr.report_title, wpr.report_content, 
              wpr.supervisor_status, wpr.supervisor_feedback, wpr.supervisor_signed_at, 
              wpr.report_file_path, wpr.submitted_at, wpr.is_group_report,
              u.full_name AS submitted_by_name
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id = ? AND wpr.student_id = ?
       ORDER BY wpr.week_no DESC`,
      [groupId, studentId]
    );

    // 2. Get group reports submitted by OTHER members for weeks this student hasn't submitted
    const myWeeks = myReports.map(r => r.week_no);
    const [otherGroupReports] = await db.query(
      `SELECT wpr.report_id, wpr.week_no, wpr.report_title, wpr.report_content, 
              wpr.supervisor_status, wpr.supervisor_feedback, wpr.supervisor_signed_at, 
              wpr.report_file_path, wpr.submitted_at, wpr.is_group_report,
              u.full_name AS submitted_by_name
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id = ? AND wpr.student_id != ? AND wpr.is_group_report = 1
       ORDER BY wpr.week_no DESC`,
      [groupId, studentId]
    );

    // Merge: for weeks where student has no report, show the group report from another member
    const mergedReports = [...myReports];
    for (const gr of otherGroupReports) {
      if (!myWeeks.includes(gr.week_no)) {
        gr.is_from_group_member = true; // Flag so frontend knows this is someone else's submission
        mergedReports.push(gr);
        myWeeks.push(gr.week_no); // Avoid duplicates if multiple group reports exist
      }
    }
    // Sort by week descending
    mergedReports.sort((a, b) => b.week_no - a.week_no);

    // Build per-week status map for frontend lock logic
    const weekStatusMap = {};
    mergedReports.forEach(r => {
      weekStatusMap[r.week_no] = r.supervisor_status;
    });

    // Compute which week is next available to submit
    let nextAvailableWeek = 1;
    for (let w = 1; w <= 12; w++) {
      const status = weekStatusMap[w];
      if (status === 'APPROVED') {
        nextAvailableWeek = w + 1;
        continue;
      }
      if (status === 'PENDING') {
        nextAvailableWeek = null;
        break;
      }
      if (status === 'REJECTED') {
        // Only allow resubmit if it's the student's own report (not someone else's group report)
        const report = mergedReports.find(r => r.week_no === w);
        if (report && report.is_from_group_member) {
          nextAvailableWeek = null; // Another member's group report was rejected; they must resubmit
        } else {
          nextAvailableWeek = w;
        }
        break;
      }
      nextAvailableWeek = w;
      break;
    }

    if (nextAvailableWeek > 12) nextAvailableWeek = null;

    // 3. Also fetch group members list (used by submit page for group report info)
    const [groupMembers] = await db.query(
      `SELECT u.user_id, u.full_name, u.university_id, gm.member_role
       FROM group_members gm
       JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?
       ORDER BY FIELD(gm.member_role,'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER')`,
      [groupId]
    );

    res.json({
      reports: mergedReports,
      group: req.activeGroup,
      week_status: weekStatusMap,
      next_available_week: nextAvailableWeek,
      group_members: groupMembers
    });
  } catch (err) {
    console.error('Load reports error:', err);
    res.status(500).json({ error: 'Failed to load reports' });
  }
});


// ═══════════════════════════════════════════════════════════════════════════
// POST /api/student/submit-report — Submit weekly report (sequential enforcement)
//   Now supports is_group_report flag for group-wide submissions
// ═══════════════════════════════════════════════════════════════════════════
router.post('/submit-report', checkGroupStatus, uploadReport, async (req, res) => {
  try {
    if (!req.activeGroup) return res.status(403).json({ error: 'You are not in a group' });

    const { week_no, report_title, report_content } = req.body;
    const isGroupReport = req.body.is_group_report === '1' || req.body.is_group_report === 1;
    const studentId = req.session.user.user_id;
    const groupId = req.activeGroup.group_id;
    const weekNum = parseInt(week_no);

    if (!week_no || !report_title) {
      return res.status(400).json({ error: 'Week number and title are required' });
    }

    if (weekNum < 1 || weekNum > 12) {
      return res.status(400).json({ error: 'Invalid week number' });
    }

    // ── Sequential Enforcement ──────────────────────────────────────────
    // Fetch all reports for this student in this group
    const [allMyReports] = await db.query(
      `SELECT week_no, supervisor_status FROM weekly_progress_reports
       WHERE group_id = ? AND student_id = ? ORDER BY week_no ASC`,
      [groupId, studentId]
    );

    // Also fetch group reports from other members (to build complete week status)
    const [otherGroupReports] = await db.query(
      `SELECT week_no, supervisor_status FROM weekly_progress_reports
       WHERE group_id = ? AND student_id != ? AND is_group_report = 1
       ORDER BY week_no ASC`,
      [groupId, studentId]
    );

    const weekStatusMap = {};
    // First fill in group reports from others
    otherGroupReports.forEach(r => { weekStatusMap[r.week_no] = r.supervisor_status; });
    // Then override with this student's own reports (own reports take priority)
    allMyReports.forEach(r => { weekStatusMap[r.week_no] = r.supervisor_status; });

    // Check if this week already has a report from this student
    const myExistingStatus = allMyReports.find(r => r.week_no === weekNum)?.supervisor_status || null;

    if (myExistingStatus === 'APPROVED') {
      return res.status(400).json({ error: `Week ${weekNum} report is already approved. You cannot resubmit.` });
    }

    if (myExistingStatus === 'PENDING') {
      return res.status(400).json({ error: `Week ${weekNum} report is pending review. Please wait for your supervisor's decision.` });
    }

    // ── Group Report Conflict Checks ────────────────────────────────────
    // Check if any member already has a report for this week
    const [existingWeekReports] = await db.query(
      `SELECT wpr.student_id, wpr.supervisor_status, wpr.is_group_report, u.full_name
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id = ? AND wpr.week_no = ?`,
      [groupId, weekNum]
    );

    if (isGroupReport) {
      // Submitting a GROUP report — block if any member already has PENDING/APPROVED for this week
      const conflicting = existingWeekReports.find(r => 
        r.student_id !== studentId && 
        (r.supervisor_status === 'PENDING' || r.supervisor_status === 'APPROVED')
      );
      if (conflicting) {
        return res.status(400).json({ 
          error: `Cannot submit group report for Week ${weekNum}. ${conflicting.full_name} already has a ${conflicting.supervisor_status.toLowerCase()} report for this week.` 
        });
      }
    } else {
      // Submitting a PERSONAL report — block if a group report (PENDING/APPROVED) exists from anyone
      const groupConflict = existingWeekReports.find(r =>
        r.student_id !== studentId &&
        r.is_group_report === 1 &&
        (r.supervisor_status === 'PENDING' || r.supervisor_status === 'APPROVED')
      );
      if (groupConflict) {
        return res.status(400).json({ 
          error: `A group report for Week ${weekNum} was already submitted by ${groupConflict.full_name}. You don't need to submit a personal report.` 
        });
      }
    }

    // ── Sequential Order Check (for fresh submissions) ──────────────────
    if (!myExistingStatus) {
      if (weekNum > 1) {
        const prevWeekStatus = weekStatusMap[weekNum - 1];
        if (prevWeekStatus !== 'APPROVED') {
          let reason = '';
          if (!prevWeekStatus) {
            reason = `You must submit and get Week ${weekNum - 1} approved first.`;
          } else if (prevWeekStatus === 'PENDING') {
            reason = `Week ${weekNum - 1} is still pending review. Wait for approval before submitting Week ${weekNum}.`;
          } else if (prevWeekStatus === 'REJECTED') {
            reason = `Week ${weekNum - 1} was rejected. Please resubmit Week ${weekNum - 1} and get it approved first.`;
          }
          return res.status(400).json({
            error: `Cannot submit Week ${weekNum} yet. ${reason}`
          });
        }
      }
    }

    // If REJECTED, delete the old rejected report first to allow resubmission
    if (myExistingStatus === 'REJECTED') {
      const [oldReport] = await db.query(
        `SELECT report_file_path FROM weekly_progress_reports WHERE group_id = ? AND student_id = ? AND week_no = ?`,
        [groupId, studentId, weekNum]
      );
      if (oldReport.length > 0 && oldReport[0].report_file_path) {
        const oldPath = path.join(__dirname, '../public', oldReport[0].report_file_path);
        if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
      }
      await db.query(
        `DELETE FROM weekly_progress_reports WHERE group_id = ? AND student_id = ? AND week_no = ?`,
        [groupId, studentId, weekNum]
      );
    }

    const filePath = req.file ? `/uploads/reports/${req.file.filename}` : null;

    await db.query(
      `INSERT INTO weekly_progress_reports (group_id, student_id, week_no, report_title, report_content, report_file_path, is_group_report, submitted_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, NOW())`,
      [groupId, studentId, weekNum, report_title, report_content, filePath, isGroupReport ? 1 : 0]
    );

    const actionMsg = myExistingStatus === 'REJECTED' ? 'resubmitted' : 'submitted';
    const reportTypeLabel = isGroupReport ? 'group' : 'personal';

    // ── Notify Supervisor & Course Teacher ───────────────────────────────
    const studentName = req.session.user.full_name;
    try {
      const [[groupInfo]] = await db.query(
        `SELECT pg.supervisor_id, pg.group_code, cts.course_teacher_id
         FROM project_groups pg
         LEFT JOIN course_teacher_sections cts ON cts.section_id = pg.section_id
         WHERE pg.group_id = ?`,
        [groupId]
      );
      if (groupInfo) {
        const notifTitle = myExistingStatus === 'REJECTED'
          ? `🔄 Week ${weekNum} ${isGroupReport ? 'Group ' : ''}Report Resubmitted`
          : `📄 New Week ${weekNum} ${isGroupReport ? 'Group ' : ''}Report Submitted`;
        const notifMsg = `${studentName} has ${actionMsg} a ${reportTypeLabel} Week ${weekNum} report for group ${groupInfo.group_code}.`;

        // Notify supervisor
        if (groupInfo.supervisor_id) {
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
            [groupInfo.supervisor_id, notifTitle, notifMsg]
          );
          const io = req.app.get('io');
          if (io) io.to(`user_${groupInfo.supervisor_id}`).emit('notification', { title: notifTitle, message: notifMsg });
        }
        // Notify course teacher
        if (groupInfo.course_teacher_id) {
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
            [groupInfo.course_teacher_id, notifTitle, notifMsg]
          );
          const io = req.app.get('io');
          if (io) io.to(`user_${groupInfo.course_teacher_id}`).emit('notification', { title: notifTitle, message: notifMsg });
        }
        // Notify other group members
        const [members] = await db.query(
          `SELECT student_id FROM group_members WHERE group_id = ? AND student_id != ?`,
          [groupId, studentId]
        );
        for (const m of members) {
          const studentNotifTitle = myExistingStatus === 'REJECTED'
            ? `🔄 Week ${weekNum} ${isGroupReport ? 'Group ' : ''}Report Resubmitted`
            : `📄 New Week ${weekNum} ${isGroupReport ? 'Group ' : ''}Report Submitted`;
          const studentNotifMsg = `${studentName} has ${actionMsg} a ${reportTypeLabel} Week ${weekNum} report for your group ${groupInfo.group_code}.`;
          
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
            [m.student_id, studentNotifTitle, studentNotifMsg]
          );
          const io = req.app.get('io');
          if (io) io.to(`user_${m.student_id}`).emit('notification', { title: studentNotifTitle, message: studentNotifMsg });
        }
      }
    } catch (notifErr) {
      console.error('Report notification error (non-fatal):', notifErr);
    }

    res.json({ success: true, message: `Week ${weekNum} ${reportTypeLabel} report ${actionMsg} successfully!` });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message || 'Failed to submit report' });
  }
});


// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/group-chat — Group messages
// ═══════════════════════════════════════════════════════════════════════════
router.get('/group-chat', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ messages: [] });
    const chatType = req.query.type || 'STUDENT_ONLY';
    const [messages] = await db.query(
      `SELECT gcm.message_id, gcm.message_text, gcm.attachment_path, gcm.attachment_name,
              gcm.created_at, gcm.sender_id,
              u.full_name as sender_name, u.role as sender_role, u.university_id as sender_uid
       FROM group_chat_messages gcm
       JOIN users u ON gcm.sender_id = u.user_id
       WHERE gcm.group_id = ? AND gcm.chat_type = ?
       ORDER BY gcm.created_at ASC LIMIT 100`,
      [req.activeGroup.group_id, chatType]
    );
    res.json({ messages, group_id: req.activeGroup.group_id });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load chat' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/supervisor-chat — DM with supervisor
// ═══════════════════════════════════════════════════════════════════════════
router.get('/supervisor-chat', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ messages: [], supervisor_id: null });
    const myId = req.session.user.user_id;
    const supId = req.activeGroup.supervisor_id;
    const [messages] = await db.query(
      `SELECT dm.message_id, dm.sender_id, dm.receiver_id, dm.message_text,
              dm.attachment_path, dm.attachment_name, dm.is_read, dm.created_at,
              u.full_name as sender_name, u.role as sender_role
       FROM direct_messages dm
       JOIN users u ON dm.sender_id = u.user_id
       WHERE (dm.sender_id = ? AND dm.receiver_id = ?) OR (dm.sender_id = ? AND dm.receiver_id = ?)
       ORDER BY dm.created_at ASC LIMIT 100`,
      [myId, supId, supId, myId]
    );
    // Mark supervisor's messages as read
    const [updated] = await db.query(
      'UPDATE direct_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
      [supId, myId]
    );
    // Notify supervisor of double tick in real-time
    if (updated.affectedRows > 0) {
      const io = req.app.get('io');
      if (io) io.to(`user_${supId}`).emit('messages_read', { by: myId, sender: supId });
    }

    // Clear DM notifications from supervisor
    const [[supInfo]] = await db.query('SELECT full_name FROM users WHERE user_id = ?', [supId]);
    if (supInfo) {
      await db.query(
        `UPDATE notifications 
         SET is_read = 1 
         WHERE user_id = ? 
           AND (notification_type = 'NEW_DIRECT_MESSAGE' OR notification_type = 'SYSTEM_ALERT')
           AND (title LIKE ? OR message LIKE ?)
           AND is_read = 0`,
        [myId, `%${supInfo.full_name}%`, `%${supInfo.full_name}%`]
      );
    }

    res.json({ messages, supervisor_id: supId });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load supervisor chat' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/teacher-chat — DM with course teacher
// ═══════════════════════════════════════════════════════════════════════════
router.get('/teacher-chat', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ messages: [], teacher_id: null, teacher: null });
    const myId = req.session.user.user_id;
    const sectionCode = req.activeGroup.section_code;
    const stageId = req.activeGroup.stage_id;

    // Find the course teacher for this student's section + stage
    const [ctRows] = await db.query(
      `SELECT u.user_id, u.full_name, d.department_name AS department, u.email
       FROM course_teacher_sections cts
       JOIN users u ON cts.course_teacher_id = u.user_id
       LEFT JOIN departments d ON d.department_id = u.department_id
       JOIN sections s ON cts.section_id = s.section_id
       WHERE s.section_code = ? AND cts.assigned_stage_id = ?
       LIMIT 1`,
      [sectionCode, stageId]
    );
    if (!ctRows.length) return res.json({ messages: [], teacher_id: null, teacher: null, error: 'No course teacher found for your section' });
    
    const teacherId = ctRows[0].user_id;
    const [messages] = await db.query(
      `SELECT dm.message_id, dm.sender_id, dm.receiver_id, dm.message_text,
              dm.attachment_path, dm.attachment_name, dm.created_at,
              u.full_name as sender_name, u.role as sender_role
       FROM direct_messages dm
       JOIN users u ON dm.sender_id = u.user_id
       WHERE (dm.sender_id = ? AND dm.receiver_id = ?) OR (dm.sender_id = ? AND dm.receiver_id = ?)
       ORDER BY dm.created_at ASC LIMIT 100`,
      [myId, teacherId, teacherId, myId]
    );

    // Mark teacher's messages as read
    const [updated] = await db.query(
      'UPDATE direct_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
      [teacherId, myId]
    );
    // Notify teacher of double tick in real-time
    if (updated.affectedRows > 0) {
      const io = req.app.get('io');
      if (io) io.to(`user_${teacherId}`).emit('messages_read', { by: myId, sender: teacherId });
    }

    // Clear DM notifications from teacher
    await db.query(
      `UPDATE notifications 
       SET is_read = 1 
       WHERE user_id = ? 
         AND (notification_type = 'NEW_DIRECT_MESSAGE' OR notification_type = 'SYSTEM_ALERT')
         AND (title LIKE ? OR message LIKE ?)
         AND is_read = 0`,
      [myId, `%${ctRows[0].full_name}%`, `%${ctRows[0].full_name}%`]
    );

    res.json({ messages, teacher_id: teacherId, teacher: ctRows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load teacher chat' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// DELETE /api/student/reports/:reportId — Cancel/Delete a PENDING report
// ═══════════════════════════════════════════════════════════════════════════
router.delete('/reports/:reportId', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.status(403).json({ error: 'Not in a group' });
    const { reportId } = req.params;
    const studentId = req.session.user.user_id;

    // Only allow deleting own PENDING reports
    const [rows] = await db.query(
      `SELECT report_id, supervisor_status, report_file_path FROM weekly_progress_reports 
       WHERE report_id = ? AND student_id = ?`,
      [reportId, studentId]
    );
    if (!rows.length) return res.status(404).json({ error: 'Report not found' });
    if (rows[0].supervisor_status !== 'PENDING') {
      return res.status(400).json({ error: 'Only PENDING reports can be cancelled' });
    }

    // Delete file if exists
    if (rows[0].report_file_path) {
      const filePath = path.join(__dirname, '../public', rows[0].report_file_path);
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    }

    await db.query('DELETE FROM weekly_progress_reports WHERE report_id = ?', [reportId]);
    res.json({ success: true, message: 'Report cancelled successfully' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to cancel report' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/tasks — View tasks assigned by Supervisor or Course Teacher
// Shows group-wide tasks AND tasks individually assigned to this student
// ═══════════════════════════════════════════════════════════════════════════
router.get('/tasks', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ tasks: [], group: null });
    const groupId = req.activeGroup.group_id;
    const studentId = req.session.user.user_id;

    // Fetch all tasks for this group, join with creator info
    const [tasks] = await db.query(
      `SELECT gt.task_id, gt.group_id, gt.supervisor_id, gt.week_no,
              gt.title, gt.description, gt.file_path, gt.file_name,
              gt.due_date, gt.assigned_to, gt.created_at,
              u.full_name AS creator_name, u.role AS creator_role
       FROM group_tasks gt
       JOIN users u ON u.user_id = gt.supervisor_id
       WHERE gt.group_id = ?
       ORDER BY gt.week_no DESC, gt.created_at DESC`,
      [groupId]
    );

    // Filter: show tasks where assigned_to is NULL (all members) or includes this student
    const myTasks = tasks.filter(t => {
      if (!t.assigned_to) return true; // NULL = all members
      try {
        const assigned = typeof t.assigned_to === 'string' ? JSON.parse(t.assigned_to) : t.assigned_to;
        return Array.isArray(assigned) && assigned.includes(studentId);
      } catch(e) { return true; }
    });

    res.json({ tasks: myTasks, group: req.activeGroup });
  } catch (err) {
    console.error('Student tasks error:', err);
    res.status(500).json({ error: 'Failed to load tasks' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/student/my-task-submissions — Get my submissions for all tasks
// ═══════════════════════════════════════════════════════════════════════════
router.get('/my-task-submissions', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ submissions: [] });
    const studentId = req.session.user.user_id;
    const groupId = req.activeGroup.group_id;

    const [submissions] = await db.query(
      `SELECT ts.submission_id, ts.task_id, ts.status, ts.grade, ts.feedback, ts.rejection_reason,
              ts.notes, ts.file_path, ts.file_name, ts.submitted_at, ts.reviewed_at
       FROM task_submissions ts
       WHERE ts.student_id = ? AND ts.group_id = ?
       ORDER BY ts.submitted_at DESC`,
      [studentId, groupId]
    );

    res.json({ submissions });
  } catch (err) {
    console.error('My task submissions error:', err);
    res.status(500).json({ error: 'Failed to load submissions' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/student/tasks/:taskId/submit — Submit a task
// ═══════════════════════════════════════════════════════════════════════════
const taskSubmitUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const dir = path.join(__dirname, '../public/uploads/task_submissions');
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      const unique = `tsub_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
      cb(null, unique + path.extname(file.originalname));
    }
  }),
  limits: { fileSize: 80 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.doc', '.docx', '.zip', '.rar', '.png', '.jpg', '.jpeg'];
    if (allowed.includes(path.extname(file.originalname).toLowerCase())) cb(null, true);
    else cb(new Error('File type not allowed'));
  }
});

router.post('/tasks/:taskId/submit', checkGroupStatus, taskSubmitUpload.single('submission_file'), async (req, res) => {
  try {
    if (!req.activeGroup) return res.status(403).json({ error: 'You are not in a group' });
    const studentId = req.session.user.user_id;
    const groupId = req.activeGroup.group_id;
    const taskId = req.params.taskId;
    const { notes } = req.body;

    // Verify the task exists and belongs to this group
    const [[task]] = await db.query(
      `SELECT gt.*, pg.supervisor_id, pg.group_code
       FROM group_tasks gt
       JOIN project_groups pg ON pg.group_id = gt.group_id
       WHERE gt.task_id = ? AND gt.group_id = ?`,
      [taskId, groupId]
    );
    if (!task) return res.status(404).json({ error: 'Task not found' });

    // Verify student is assigned to this task
    if (task.assigned_to) {
      const assigned = typeof task.assigned_to === 'string' ? JSON.parse(task.assigned_to) : task.assigned_to;
      if (Array.isArray(assigned) && !assigned.includes(studentId)) {
        return res.status(403).json({ error: 'You are not assigned to this task' });
      }
    }

    // Check for duplicate submission
    const [[existing]] = await db.query(
      'SELECT submission_id, status, file_path FROM task_submissions WHERE task_id = ? AND student_id = ?',
      [taskId, studentId]
    );
    if (existing) {
      if (existing.status === 'NEW') {
        return res.status(400).json({ error: 'You have already submitted this task. Please wait for the supervisor to review it.' });
      }
      if (existing.status === 'ACCEPTED') {
        return res.status(400).json({ error: 'This task has already been accepted. You cannot resubmit.' });
      }
      // REJECTED — delete old submission (and file) so student can resubmit
      if (existing.file_path) {
        const oldPath = path.join(__dirname, '../public', existing.file_path);
        if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
      }
      await db.query('DELETE FROM task_submissions WHERE submission_id = ?', [existing.submission_id]);
    }

    const filePath = req.file ? `/uploads/task_submissions/${req.file.filename}` : null;
    const fileName = req.file ? req.file.originalname : null;

    await db.query(
      `INSERT INTO task_submissions (task_id, student_id, group_id, notes, file_path, file_name)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [taskId, studentId, groupId, notes || null, filePath, fileName]
    );

    // Notify supervisor
    const studentName = req.session.user.full_name;
    if (task.supervisor_id) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)`,
        [task.supervisor_id, 'SYSTEM_ALERT',
         `📋 Task Submitted: ${task.title}`,
         `${studentName} has submitted "${task.title}" (Week ${task.week_no}) in group ${task.group_code}.`]
      );
      const io = req.app.get('io');
      if (io) {
        io.to(`user_${task.supervisor_id}`).emit('notification', {
          title: `📋 Task Submitted: ${task.title}`,
          message: `${studentName} submitted a task.`
        });
      }
    }

    res.json({ success: true, message: 'Task submitted successfully!' });
  } catch (err) {
    console.error('Task submit error:', err);
    res.status(500).json({ error: err.message || 'Failed to submit task' });
  }
});

module.exports = { router, checkGroupStatus };

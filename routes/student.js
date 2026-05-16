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
// GET /api/student/reports — All my reports
// ═══════════════════════════════════════════════════════════════════════════
router.get('/reports', checkGroupStatus, async (req, res) => {
  try {
    if (!req.activeGroup) return res.json({ reports: [] });
    const [reports] = await db.query(
      `SELECT report_id, week_no, report_title, report_content, supervisor_status,
              supervisor_feedback, supervisor_signed_at, report_file_path, submitted_at
       FROM weekly_progress_reports
       WHERE group_id = ? AND student_id = ?
       ORDER BY week_no DESC`,
      [req.activeGroup.group_id, req.session.user.user_id]
    );
    res.json({ reports, group: req.activeGroup });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load reports' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/student/submit-report — Submit weekly report
// ═══════════════════════════════════════════════════════════════════════════
router.post('/submit-report', checkGroupStatus, uploadReport, async (req, res) => {
  try {
    if (!req.activeGroup) return res.status(403).json({ error: 'You are not in a group' });

    const { week_no, report_title, report_content } = req.body;
    const studentId = req.session.user.user_id;
    const groupId = req.activeGroup.group_id;

    if (!week_no || !report_title) {
      return res.status(400).json({ error: 'Week number and title are required' });
    }

    // Check duplicate
    const [existing] = await db.query(
      `SELECT report_id FROM weekly_progress_reports WHERE group_id = ? AND student_id = ? AND week_no = ?`,
      [groupId, studentId, week_no]
    );
    if (existing.length > 0) {
      return res.status(400).json({ error: `You already submitted a report for Week ${week_no}` });
    }

    const filePath = req.file ? `/uploads/reports/${req.file.filename}` : null;

    await db.query(
      `INSERT INTO weekly_progress_reports (group_id, student_id, week_no, report_title, report_content, report_file_path, submitted_at)
       VALUES (?, ?, ?, ?, ?, ?, NOW())`,
      [groupId, studentId, week_no, report_title, report_content, filePath]
    );

    res.json({ success: true, message: `Week ${week_no} report submitted successfully!` });
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

module.exports = { router, checkGroupStatus };

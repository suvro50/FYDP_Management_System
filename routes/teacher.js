const express = require('express');
const router = express.Router();
const db = require('../config/db');

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/stats — Dashboard statistics
// ═══════════════════════════════════════════════════════════════════════════
router.get('/stats', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;

    const [[sectionCount]] = await db.query(
      'SELECT COUNT(DISTINCT section_code) as count FROM course_teacher_sections WHERE course_teacher_id = ?',
      [teacherId]
    );
    const [[groupCount]] = await db.query(
      `SELECT COUNT(DISTINCT pg.group_id) as count
       FROM project_groups pg
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cts.course_teacher_id = ? AND pg.is_active = 1`,
      [teacherId]
    );
    const [[pendingInbox]] = await db.query(
      `SELECT COUNT(*) as count FROM course_teacher_inbox cti
       JOIN project_groups pg ON pg.group_id = cti.group_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cts.course_teacher_id = ? AND cti.escalation_status = 'PENDING_REVIEW'`,
      [teacherId]
    );
    const [[studentCount]] = await db.query(
      `SELECT COUNT(DISTINCT gm.student_id) as count
       FROM group_members gm
       JOIN project_groups pg ON pg.group_id = gm.group_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cts.course_teacher_id = ? AND pg.is_active = 1`,
      [teacherId]
    );
    const [[reviewedWeek]] = await db.query(
      `SELECT COUNT(*) as count FROM course_teacher_inbox cti
       JOIN project_groups pg ON pg.group_id = cti.group_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cts.course_teacher_id = ? AND cti.escalation_status = 'REVIEWED'
       AND cti.reviewed_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,
      [teacherId]
    );

    res.json({
      totalSections: sectionCount.count,
      totalGroups: groupCount.count,
      pendingInbox: pendingInbox.count,
      totalStudents: studentCount.count,
      reviewedThisWeek: reviewedWeek.count
    });
  } catch (err) {
    console.error('Teacher stats error:', err);
    res.status(500).json({ error: 'Failed to load stats' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/sections — Sections assigned to this teacher
// ═══════════════════════════════════════════════════════════════════════════
router.get('/sections', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const [sections] = await db.query(
      `SELECT cts.*, fs.stage_name, fs.stage_order,
              COUNT(DISTINCT pg.group_id) as group_count
       FROM course_teacher_sections cts
       JOIN fydp_stages fs ON fs.stage_id = cts.assigned_stage_id
       LEFT JOIN project_groups pg ON pg.section_code = cts.section_code AND pg.is_active = 1
       WHERE cts.course_teacher_id = ?
       GROUP BY cts.mapping_id, cts.section_code, cts.assigned_stage_id, fs.stage_name, fs.stage_order
       ORDER BY fs.stage_order, cts.section_code`,
      [teacherId]
    );
    res.json({ sections });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load sections' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/groups — All groups in teacher's sections
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const [groups] = await db.query(
      `SELECT pg.*, fs.stage_name, fs.stage_order, pd.domain_name,
              sup.full_name as supervisor_name,
              (SELECT COUNT(*) FROM group_members gm2 WHERE gm2.group_id = pg.group_id) as member_count,
              (SELECT COUNT(*) FROM course_teacher_inbox cti
               WHERE cti.group_id = pg.group_id AND cti.escalation_status = 'PENDING_REVIEW') as pending_inbox,
              (SELECT MAX(wpr.week_no) FROM weekly_progress_reports wpr
               WHERE wpr.group_id = pg.group_id AND wpr.supervisor_status = 'APPROVED') as latest_approved_week
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
       JOIN users sup ON sup.user_id = pg.supervisor_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cts.course_teacher_id = ? AND pg.is_active = 1
       ORDER BY fs.stage_order, pg.section_code, pg.group_code`,
      [teacherId]
    );

    for (let g of groups) {
      const [members] = await db.query(
        `SELECT gm.student_id, gm.member_role, u.full_name, u.university_id
         FROM group_members gm
         JOIN users u ON u.user_id = gm.student_id
         WHERE gm.group_id = ?`,
        [g.group_id]
      );
      g.members = members;
    }

    res.json({ groups });
  } catch (err) {
    console.error('Teacher groups error:', err);
    res.status(500).json({ error: 'Failed to load groups' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/inbox — Escalated packages
// ═══════════════════════════════════════════════════════════════════════════
router.get('/inbox', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const statusFilter = req.query.status || '';

    let where = `WHERE cts.course_teacher_id = ?`;
    const params = [teacherId];
    if (statusFilter) {
      where += ` AND cti.escalation_status = ?`;
      params.push(statusFilter);
    }

    const [items] = await db.query(
      `SELECT cti.*, pg.group_code, pg.project_title, pg.section_code,
              fs.stage_name, sup.full_name as supervisor_name,
              (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = cti.group_id) as member_count,
              (SELECT COUNT(*) FROM weekly_progress_reports wpr
               WHERE wpr.group_id = cti.group_id AND wpr.week_no = cti.week_no
               AND wpr.supervisor_status = 'APPROVED') as approved_count
       FROM course_teacher_inbox cti
       JOIN project_groups pg ON pg.group_id = cti.group_id
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN users sup ON sup.user_id = pg.supervisor_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       ${where}
       ORDER BY CASE cti.escalation_status WHEN 'PENDING_REVIEW' THEN 0 ELSE 1 END,
                cti.escalated_at DESC`,
      params
    );

    res.json({ items });
  } catch (err) {
    console.error('Teacher inbox error:', err);
    res.status(500).json({ error: 'Failed to load inbox' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/inbox/:id/reports — Individual student reports for a package
// ═══════════════════════════════════════════════════════════════════════════
router.get('/inbox/:id/reports', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const inboxId = req.params.id;

    const [[inbox]] = await db.query(
      `SELECT cti.*, pg.group_code, pg.project_title FROM course_teacher_inbox cti
       JOIN project_groups pg ON pg.group_id = cti.group_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cti.inbox_id = ? AND cts.course_teacher_id = ?`,
      [inboxId, teacherId]
    );
    if (!inbox) return res.status(403).json({ error: 'Not authorized' });

    const [reports] = await db.query(
      `SELECT wpr.*, u.full_name as student_name, u.university_id as student_uid,
              gm.member_role
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       JOIN group_members gm ON gm.student_id = wpr.student_id AND gm.group_id = wpr.group_id
       WHERE wpr.group_id = ? AND wpr.week_no = ?
       ORDER BY u.full_name`,
      [inbox.group_id, inbox.week_no]
    );

    res.json({ inbox, reports });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load reports' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/teacher/inbox/:id/review — Mark package as REVIEWED or FLAGGED
// ═══════════════════════════════════════════════════════════════════════════
router.post('/inbox/:id/review', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const inboxId = req.params.id;
    const { status, notes } = req.body;

    if (!status || !['REVIEWED', 'FLAGGED'].includes(status)) {
      return res.status(400).json({ error: 'Status must be REVIEWED or FLAGGED' });
    }

    const [[inbox]] = await db.query(
      `SELECT cti.*, pg.group_code, pg.project_title FROM course_teacher_inbox cti
       JOIN project_groups pg ON pg.group_id = cti.group_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cti.inbox_id = ? AND cts.course_teacher_id = ?`,
      [inboxId, teacherId]
    );
    if (!inbox) return res.status(403).json({ error: 'Not authorized' });

    await db.query(
      `UPDATE course_teacher_inbox
       SET escalation_status = ?, reviewed_at = NOW(), reviewed_by = ?, notes = ?
       WHERE inbox_id = ?`,
      [status, teacherId, notes || null, inboxId]
    );

    // Notify group members
    const [members] = await db.query(
      'SELECT student_id FROM group_members WHERE group_id = ?',
      [inbox.group_id]
    );

    const teacherName = req.session.user.full_name;
    const io = req.app.get('io');
    for (const m of members) {
      const notifMsg = status === 'FLAGGED'
        ? `⚠️ Your Week ${inbox.week_no} package for ${inbox.group_code} has been flagged by ${teacherName}. ${notes ? 'Note: ' + notes : ''}`
        : `✅ Your Week ${inbox.week_no} package for ${inbox.group_code} has been reviewed by ${teacherName}.`;
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, message) VALUES (?, 'SYSTEM_ALERT', ?)`,
        [m.student_id, notifMsg]
      );
      if (io) io.to(`user_${m.student_id}`).emit('notification', { message: notifMsg });
    }

    res.json({ success: true, message: `Package ${status.toLowerCase()} successfully` });
  } catch (err) {
    console.error('Review inbox error:', err);
    res.status(500).json({ error: 'Failed to review package' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/students-status — All students in teacher's sections
// ═══════════════════════════════════════════════════════════════════════════
router.get('/students-status', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const [students] = await db.query(
      `SELECT DISTINCT u.user_id, u.full_name, u.university_id, u.is_active,
              gm.member_role, pg.group_id, pg.group_code, pg.project_title,
              pg.section_code, fs.stage_name, sup.full_name as supervisor_name
       FROM course_teacher_sections cts
       JOIN project_groups pg ON pg.section_code = cts.section_code AND pg.is_active = 1
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN group_members gm ON gm.group_id = pg.group_id
       JOIN users u ON u.user_id = gm.student_id
       JOIN users sup ON sup.user_id = pg.supervisor_id
       WHERE cts.course_teacher_id = ?
       ORDER BY pg.section_code, pg.group_code, u.full_name`,
      [teacherId]
    );
    res.json({ students });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load students' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// ANNOUNCEMENTS
// ═══════════════════════════════════════════════════════════════════════════

// GET /api/teacher/announcements — List announcements created by this teacher
router.get('/announcements', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const [rows] = await db.query(
      `SELECT * FROM announcements WHERE author_id = ? ORDER BY created_at DESC`,
      [teacherId]
    );
    res.json({ announcements: rows });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load announcements' });
  }
});

// POST /api/teacher/announcements — Create a new announcement
router.post('/announcements', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const { title, content, target_role, target_section } = req.body;

    if (!title || !content) {
      return res.status(400).json({ error: 'Title and content are required' });
    }

    const [result] = await db.query(
      `INSERT INTO announcements (author_id, title, content, target_role, target_section)
       VALUES (?, ?, ?, ?, ?)`,
      [teacherId, title, content, target_role || 'ALL', target_section || null]
    );

    // Notify target users
    const io = req.app.get('io');
    const msg = `📢 New Announcement: ${title}`;
    
    let userQuery = 'SELECT user_id FROM users WHERE is_active = 1';
    const queryParams = [];
    
    if (target_role && target_role !== 'ALL') {
      userQuery += ' AND role = ?';
      queryParams.push(target_role);
    }

    const [usersToNotify] = await db.query(userQuery, queryParams);
    
    for (const u of usersToNotify) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, message) VALUES (?, 'SYSTEM_ALERT', ?)`,
        [u.user_id, msg]
      );
      if (io) io.to(`user_${u.user_id}`).emit('notification', { message: msg });
    }

    res.json({ success: true, announcement_id: result.insertId });
  } catch (err) {
    console.error('Create announcement error:', err);
    res.status(500).json({ error: 'Failed to create announcement' });
  }
});

// DELETE /api/teacher/announcements/:id
router.delete('/announcements/:id', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const [result] = await db.query(
      'DELETE FROM announcements WHERE announcement_id = ? AND author_id = ?',
      [req.params.id, teacherId]
    );
    if (result.affectedRows === 0) return res.status(404).json({ error: 'Announcement not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete announcement' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// EVALUATIONS / GRADING
// ═══════════════════════════════════════════════════════════════════════════

// GET /api/teacher/evaluations/:groupId
router.get('/evaluations/:groupId', async (req, res) => {
  try {
    const [rows] = await db.query(
      'SELECT * FROM group_evaluations WHERE group_id = ?',
      [req.params.groupId]
    );
    res.json({ evaluations: rows });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load evaluations' });
  }
});

// POST /api/teacher/evaluations/:groupId
router.post('/evaluations/:groupId', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const groupId = req.params.groupId;
    const { evaluation_type, score, feedback } = req.body;

    if (!evaluation_type || score === undefined) {
      return res.status(400).json({ error: 'Evaluation type and score are required' });
    }

    await db.query(
      `INSERT INTO group_evaluations (group_id, teacher_id, evaluation_type, score, feedback)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE score = VALUES(score), feedback = VALUES(feedback), teacher_id = VALUES(teacher_id), evaluated_at = NOW()`,
      [groupId, teacherId, evaluation_type, score, feedback || null]
    );

    res.json({ success: true });
  } catch (err) {
    console.error('Save evaluation error:', err);
    res.status(500).json({ error: 'Failed to save evaluation' });
  }
});

// Get all group evaluations for teacher's sections
router.get('/grades', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const query = `
        SELECT 
            pg.group_id, pg.group_code, pg.project_title,
            u.full_name as supervisor_name,
            ge.evaluation_type, ge.score
        FROM project_groups pg
        JOIN course_teacher_sections cts ON pg.section_code = cts.section_code
        LEFT JOIN users u ON pg.supervisor_id = u.user_id
        LEFT JOIN group_evaluations ge ON pg.group_id = ge.group_id
        WHERE cts.course_teacher_id = ?
        ORDER BY pg.group_code, ge.evaluation_type
    `;
    const [results] = await db.query(query, [teacherId]);
    
    // Pivot results to group by group_id
    const grades = {};
    results.forEach(row => {
      if (!grades[row.group_id]) {
        grades[row.group_id] = {
          group_id: row.group_id,
          group_code: row.group_code,
          project_title: row.project_title,
          supervisor_name: row.supervisor_name,
          evaluations: {}
        };
      }
      if (row.evaluation_type) {
        grades[row.group_id].evaluations[row.evaluation_type] = row.score;
      }
    });
    
    res.json({ success: true, grades: Object.values(grades) });
  } catch (err) {
    console.error('Grades API error:', err);
    res.status(500).json({ success: false, message: 'Database error' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/groups-by-stage
// Returns: { stages: [ { stage_name, sections: [ { section_code, groups:[...] } ] } ] }
// This powers the 4-layer navigation: FYDP → Section → Groups → Group Detail
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups-by-stage', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;

    // All stages
    const [stages] = await db.query('SELECT * FROM fydp_stages ORDER BY stage_order');

    // All groups in teacher's sections, with full detail
    const [groups] = await db.query(
      `SELECT pg.*, fs.stage_name, fs.stage_order, pd.domain_name,
              sup.full_name as supervisor_name,
              (SELECT COUNT(*) FROM group_members gm2 WHERE gm2.group_id = pg.group_id) as member_count,
              (SELECT COUNT(DISTINCT wpr.week_no) FROM weekly_progress_reports wpr
               WHERE wpr.group_id = pg.group_id AND wpr.supervisor_status = 'APPROVED') as approved_count
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
       JOIN users sup ON sup.user_id = pg.supervisor_id
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE cts.course_teacher_id = ? AND pg.is_active = 1
       ORDER BY fs.stage_order, pg.section_code, pg.group_code`,
      [teacherId]
    );

    // Attach members + color status to each group
    for (let g of groups) {
      const [members] = await db.query(
        `SELECT gm.student_id, gm.member_role, u.full_name, u.university_id, u.email
         FROM group_members gm JOIN users u ON u.user_id = gm.student_id
         WHERE gm.group_id = ?`,
        [g.group_id]
      );
      g.members = members;
      g.total_weeks = 12;

      // Latest reports for color coding
      const [latestReports] = await db.query(
        `SELECT week_no, supervisor_status, submitted_at FROM weekly_progress_reports
         WHERE group_id = ? ORDER BY week_no DESC, submitted_at DESC LIMIT 10`,
        [g.group_id]
      );
      if (latestReports.length === 0) {
        g.color_status = 'red';
      } else {
        const latestWeek = latestReports[0].week_no;
        const latest = latestReports.filter(r => r.week_no === latestWeek);
        const allApproved = latest.every(r => r.supervisor_status === 'APPROVED');
        const somePending = latest.some(r => r.supervisor_status === 'PENDING');
        const daysSince = (Date.now() - new Date(latestReports[0].submitted_at)) / (1000*60*60*24);
        if (daysSince > 7 && somePending) g.color_status = 'red';
        else if (allApproved && latest.length >= g.member_count) g.color_status = 'green';
        else g.color_status = 'yellow';
      }

      const [[pending]] = await db.query(
        `SELECT COUNT(*) as count FROM weekly_progress_reports
         WHERE group_id = ? AND supervisor_status = 'PENDING'`,
        [g.group_id]
      );
      g.pending_count = pending.count;
      g.submitted_count = g.approved_count; // teacher sees only approved
    }

    // Build stage → section → groups hierarchy
    const stageData = stages.map(s => {
      const stageGroups = groups.filter(g => g.stage_name === s.stage_name);
      // Group by section
      const sectionMap = {};
      stageGroups.forEach(g => {
        if (!sectionMap[g.section_code]) {
          sectionMap[g.section_code] = { section_code: g.section_code, groups: [] };
        }
        sectionMap[g.section_code].groups.push(g);
      });
      return {
        stage_id: s.stage_id,
        stage_name: s.stage_name,
        stage_order: s.stage_order,
        sections: Object.values(sectionMap),
        total_groups: stageGroups.length,
        total_sections: Object.keys(sectionMap).length
      };
    });

    res.json({ stages: stageData });
  } catch (err) {
    console.error('Teacher groups-by-stage error:', err);
    res.status(500).json({ error: 'Failed to load groups' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/groups/:id/weekly-summary
// Returns only SUPERVISOR-APPROVED reports (teacher sees what supervisor accepted)
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/weekly-summary', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const groupId = req.params.id;

    // Verify teacher has access to this group
    const [[access]] = await db.query(
      `SELECT pg.group_id FROM project_groups pg
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE pg.group_id = ? AND cts.course_teacher_id = ? AND pg.is_active = 1`,
      [groupId, teacherId]
    );
    if (!access) return res.status(403).json({ error: 'Access denied' });

    // Members
    const [members] = await db.query(
      `SELECT gm.student_id, u.full_name, u.university_id
       FROM group_members gm JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?`,
      [groupId]
    );

    // Only supervisor-approved reports visible to course teacher
    const [reports] = await db.query(
      `SELECT wpr.report_id, wpr.student_id, wpr.week_no, wpr.report_title,
              wpr.supervisor_status, wpr.submitted_at, wpr.supervisor_feedback,
              wpr.supervisor_signed_at, wpr.report_file_path,
              u.full_name as student_name, u.university_id as student_uid
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id = ? AND wpr.supervisor_status = 'APPROVED'
       ORDER BY wpr.week_no, u.full_name`,
      [groupId]
    );

    // Group by week
    const weekMap = {};
    reports.forEach(r => {
      if (!weekMap[r.week_no]) weekMap[r.week_no] = { week_no: r.week_no, reports: [] };
      weekMap[r.week_no].reports.push(r);
    });

    const weeks = Object.values(weekMap).sort((a, b) => a.week_no - b.week_no);
    weeks.forEach(w => {
      w.submitted_count = w.reports.length; // all are approved
      w.approved_count = w.reports.length;
      w.pending_count = 0;
      w.total_members = members.length;
    });

    res.json({ weeks, members, total_members: members.length });
  } catch (err) {
    console.error('Teacher weekly summary error:', err);
    res.status(500).json({ error: 'Failed to load weekly summary' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// Task management for Course Teacher (same capability as supervisor)
// ═══════════════════════════════════════════════════════════════════════════

const multer = require('multer');
const path = require('path');
const fs = require('fs');

const teacherTaskUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const dir = path.join(__dirname, '../public/uploads/tasks');
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      const unique = `ctask_${Date.now()}_${Math.random().toString(36).substr(2,6)}`;
      cb(null, unique + path.extname(file.originalname));
    }
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.doc', '.docx'];
    if (allowed.includes(path.extname(file.originalname).toLowerCase())) cb(null, true);
    else cb(new Error('Only PDF/DOC files allowed'));
  }
});

// GET /api/teacher/groups/:id/tasks
router.get('/groups/:id/tasks', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const groupId = req.params.id;

    // Access check
    const [[access]] = await db.query(
      `SELECT pg.group_id FROM project_groups pg
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE pg.group_id = ? AND cts.course_teacher_id = ? AND pg.is_active = 1`,
      [groupId, teacherId]
    );
    if (!access) return res.status(403).json({ error: 'Access denied' });

    // Return tasks created by either supervisor OR this teacher for this group
    const [tasks] = await db.query(
      `SELECT gt.*, u.full_name as creator_name,
              CASE WHEN gt.supervisor_id = ? THEN 1 ELSE 0 END as created_by_me
       FROM group_tasks gt
       JOIN users u ON u.user_id = gt.supervisor_id
       WHERE gt.group_id = ?
       ORDER BY gt.week_no DESC, gt.created_at DESC`,
      [teacherId, groupId]
    );
    res.json({ tasks });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load tasks' });
  }
});

// POST /api/teacher/groups/:id/tasks
router.post('/groups/:id/tasks', teacherTaskUpload.single('task_file'), async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const groupId = req.params.id;

    // Access check
    const [[group]] = await db.query(
      `SELECT pg.group_id, pg.group_code FROM project_groups pg
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE pg.group_id = ? AND cts.course_teacher_id = ? AND pg.is_active = 1`,
      [groupId, teacherId]
    );
    if (!group) return res.status(403).json({ error: 'Access denied' });

    const { title, description, week_no, due_date } = req.body;
    if (!title || !week_no) return res.status(400).json({ error: 'Title and week number are required' });

    const filePath = req.file ? `/uploads/tasks/${req.file.filename}` : null;
    const fileName = req.file ? req.file.originalname : null;

    // Insert — supervisor_id column reused to store assignor id (teacher in this case)
    const [result] = await db.query(
      `INSERT INTO group_tasks (group_id, supervisor_id, week_no, title, description, file_path, file_name, due_date)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [groupId, teacherId, week_no, title, description || null, filePath, fileName, due_date || null]
    );

    // Notify all group members
    const [members] = await db.query(
      'SELECT student_id FROM group_members WHERE group_id = ?',
      [groupId]
    );
    const io = req.app.get('io');
    const teacherName = req.session.user.full_name;
    for (const m of members) {
      const notifMsg = `📋 Course Teacher assigned a new task for Week ${week_no}: "${title}" in group ${group.group_code}.`;
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
        [m.student_id, `📋 New Task (Week ${week_no})`, notifMsg]
      );
      if (io) io.to(`user_${m.student_id}`).emit('notification', { message: notifMsg });
    }

    res.json({ success: true, task_id: result.insertId });
  } catch (err) {
    console.error('Teacher create task error:', err);
    res.status(500).json({ error: err.message || 'Failed to create task' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/teacher/groups/:id/week/:weekNo/reports
// Returns per-student report detail for a specific week in a group
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/week/:weekNo/reports', async (req, res) => {
  try {
    const teacherId = req.session.user.user_id;
    const groupId   = req.params.id;
    const weekNo    = parseInt(req.params.weekNo, 10);

    // Access check
    const [[access]] = await db.query(
      `SELECT pg.group_id, pg.group_code, pg.section_code FROM project_groups pg
       JOIN course_teacher_sections cts ON cts.section_code = pg.section_code
       WHERE pg.group_id = ? AND cts.course_teacher_id = ? AND pg.is_active = 1`,
      [groupId, teacherId]
    );
    if (!access) return res.status(403).json({ error: 'Access denied' });

    // All members
    const [members] = await db.query(
      `SELECT gm.student_id, gm.member_role, u.full_name, u.university_id
       FROM group_members gm JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?`,
      [groupId]
    );

    // Reports for this week (teacher sees APPROVED reports + any pending for context)
    const [reports] = await db.query(
      `SELECT wpr.report_id, wpr.student_id, wpr.week_no, wpr.report_title,
              wpr.report_content, wpr.supervisor_status, wpr.submitted_at,
              wpr.supervisor_feedback, wpr.supervisor_signed_at, wpr.report_file_path,
              u.full_name as student_name, u.university_id as student_uid,
              gm.member_role
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       JOIN group_members gm ON gm.student_id = wpr.student_id AND gm.group_id = wpr.group_id
       WHERE wpr.group_id = ? AND wpr.week_no = ?
       ORDER BY u.full_name`,
      [groupId, weekNo]
    );

    const totalMembers  = members.length;
    const submitted     = reports.length;
    const approved      = reports.filter(r => r.supervisor_status === 'APPROVED').length;
    const missing       = totalMembers - submitted;

    res.json({
      group_code:    access.group_code,
      section_code:  access.section_code,
      week_no:       weekNo,
      total_members: totalMembers,
      submitted,
      approved,
      missing,
      members,
      reports
    });
  } catch (err) {
    console.error('Teacher week reports error:', err);
    res.status(500).json({ error: 'Failed to load week reports' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// SUPERVISING GROUP SECTION — Teacher acting as Supervisor
// ═══════════════════════════════════════════════════════════════════════════

// GET /api/teacher/supervising-groups — Groups where teacher is the supervisor
router.get('/supervising-groups', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [stages] = await db.query('SELECT * FROM fydp_stages ORDER BY stage_order');
    const [groups] = await db.query(
      `SELECT pg.*, fs.stage_name, fs.stage_order, pd.domain_name,
              (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = pg.group_id) as member_count
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
       WHERE pg.supervisor_id = ? AND pg.is_active = 1
       ORDER BY fs.stage_order, pg.group_code`,
      [supId]
    );

    for (let g of groups) {
      const [members] = await db.query(
        `SELECT gm.student_id, gm.member_role, u.full_name, u.university_id, u.email
         FROM group_members gm JOIN users u ON u.user_id = gm.student_id
         WHERE gm.group_id = ?`, [g.group_id]);
      g.members = members;

      const [[aw]] = await db.query(
        `SELECT COUNT(DISTINCT week_no) as count FROM weekly_progress_reports
         WHERE group_id = ? AND supervisor_status = 'APPROVED'`, [g.group_id]);
      g.approved_weeks = aw.count;
      g.approved_count = aw.count;
      g.total_weeks = 12;

      const [[sc]] = await db.query(
        `SELECT COUNT(DISTINCT week_no) as count FROM weekly_progress_reports
         WHERE group_id = ?`, [g.group_id]);
      g.submitted_count = sc.count;

      const [latestReports] = await db.query(
        `SELECT week_no, supervisor_status, submitted_at FROM weekly_progress_reports
         WHERE group_id = ? ORDER BY week_no DESC, submitted_at DESC LIMIT 10`, [g.group_id]);

      if (latestReports.length === 0) { g.color_status = 'yellow'; }
      else {
        const lw = latestReports[0].week_no;
        const lr = latestReports.filter(r => r.week_no === lw);
        const allA = lr.every(r => r.supervisor_status === 'APPROVED');
        const someP = lr.some(r => r.supervisor_status === 'PENDING');
        const days = (Date.now() - new Date(latestReports[0].submitted_at)) / (1000*60*60*24);
        if (days > 7 && someP) g.color_status = 'red';
        else if (allA && lr.length >= g.member_count) g.color_status = 'green';
        else g.color_status = 'yellow';
      }

      const [[pc]] = await db.query(
        `SELECT COUNT(*) as count FROM weekly_progress_reports
         WHERE group_id = ? AND supervisor_status = 'PENDING'`, [g.group_id]);
      g.pending_count = pc.count;
    }

    const stageData = stages.map(s => ({
      stage_id: s.stage_id, stage_name: s.stage_name, stage_order: s.stage_order,
      groups: groups.filter(g => g.stage_name === s.stage_name)
    }));
    res.json({ stages: stageData });
  } catch (err) {
    console.error('Teacher supervising-groups error:', err);
    res.status(500).json({ error: 'Failed to load supervising groups' });
  }
});

// GET /api/teacher/supervising-groups/:id/weekly-summary
router.get('/supervising-groups/:id/weekly-summary', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]);
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const [members] = await db.query(
      `SELECT gm.student_id, u.full_name, u.university_id
       FROM group_members gm JOIN users u ON u.user_id=gm.student_id
       WHERE gm.group_id=?`, [req.params.id]);

    const [reports] = await db.query(
      `SELECT wpr.report_id, wpr.student_id, wpr.week_no, wpr.report_title,
              wpr.supervisor_status, wpr.submitted_at, wpr.supervisor_feedback,
              wpr.report_file_path, u.full_name as student_name
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id=? ORDER BY wpr.week_no, u.full_name`, [req.params.id]);

    const weekMap = {};
    reports.forEach(r => {
      if (!weekMap[r.week_no]) weekMap[r.week_no] = { week_no: r.week_no, reports: [] };
      weekMap[r.week_no].reports.push(r);
    });
    const weeks = Object.values(weekMap).sort((a,b) => a.week_no - b.week_no);
    weeks.forEach(w => {
      w.submitted_count = w.reports.length;
      w.pending_count = w.reports.filter(r => r.supervisor_status === 'PENDING').length;
      w.approved_count = w.reports.filter(r => r.supervisor_status === 'APPROVED').length;
      w.rejected_count = w.reports.filter(r => r.supervisor_status === 'REJECTED').length;
      w.total_members = members.length;
    });
    res.json({ weeks, members, total_members: members.length });
  } catch (err) {
    console.error('Supervising weekly-summary error:', err);
    res.status(500).json({ error: 'Failed to load weekly summary' });
  }
});

// GET /api/teacher/supervising-groups/:id/week/:weekNo/reports
router.get('/supervising-groups/:id/week/:weekNo/reports', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const groupId = req.params.id;
    const weekNo = parseInt(req.params.weekNo, 10);
    const [[access]] = await db.query(
      'SELECT group_id, group_code FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [groupId, supId]);
    if (!access) return res.status(403).json({ error: 'Access denied' });

    const [members] = await db.query(
      `SELECT gm.student_id, gm.member_role, u.full_name, u.university_id
       FROM group_members gm JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?`, [groupId]);

    const [reports] = await db.query(
      `SELECT wpr.report_id, wpr.student_id, wpr.week_no, wpr.report_title,
              wpr.report_content, wpr.supervisor_status, wpr.submitted_at,
              wpr.supervisor_feedback, wpr.supervisor_signed_at, wpr.report_file_path,
              u.full_name as student_name, u.university_id as student_uid, gm.member_role
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       JOIN group_members gm ON gm.student_id = wpr.student_id AND gm.group_id = wpr.group_id
       WHERE wpr.group_id = ? AND wpr.week_no = ?
       ORDER BY u.full_name`, [groupId, weekNo]);

    const totalMembers = members.length;
    const submitted = reports.length;
    const approved = reports.filter(r => r.supervisor_status === 'APPROVED').length;
    const pending = reports.filter(r => r.supervisor_status === 'PENDING').length;
    const missing = totalMembers - submitted;

    res.json({ group_code: access.group_code, week_no: weekNo,
      total_members: totalMembers, submitted, approved, pending, missing, members, reports });
  } catch (err) {
    console.error('Supervising week reports error:', err);
    res.status(500).json({ error: 'Failed to load week reports' });
  }
});

// POST /api/teacher/supervising-groups/reports/:id/review — Approve/Reject
router.post('/supervising-groups/reports/:id/review', async (req, res) => {
  try {
    const reportId = req.params.id;
    const supId = req.session.user.user_id;
    const { status, feedback } = req.body;
    if (!status || !['APPROVED', 'REJECTED'].includes(status))
      return res.status(400).json({ error: 'Status must be APPROVED or REJECTED' });

    await db.query('CALL sp_approve_weekly_report(?, ?, ?, ?)',
      [reportId, supId, status, feedback || null]);

    const [[report]] = await db.query(
      `SELECT wpr.student_id, wpr.week_no, pg.group_code
       FROM weekly_progress_reports wpr JOIN project_groups pg ON pg.group_id = wpr.group_id
       WHERE wpr.report_id = ?`, [reportId]);

    if (report) {
      const supName = req.session.user.full_name;
      const notifTitle = status === 'APPROVED'
        ? `✅ Week ${report.week_no} Report Approved`
        : `❌ Week ${report.week_no} Report Rejected`;
      const notifMsg = status === 'APPROVED'
        ? `Your Week ${report.week_no} report for ${report.group_code} has been approved by ${supName}.`
        : `Your Week ${report.week_no} report for ${report.group_code} was rejected by ${supName}. Reason: ${feedback}`;
      await db.query('INSERT INTO notifications (user_id, type, title, message) VALUES (?, ?, ?, ?)',
        [report.student_id, status === 'APPROVED' ? 'REPORT_APPROVED' : 'REPORT_REJECTED', notifTitle, notifMsg]);
    }
    res.json({ success: true, message: `Report ${status.toLowerCase()} successfully` });
  } catch (err) {
    console.error('Supervising review error:', err);
    res.status(400).json({ error: err.message || 'Failed to review report' });
  }
});

// GET /api/teacher/supervising-groups/:id/tasks
router.get('/supervising-groups/:id/tasks', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]);
    if (!group) return res.status(403).json({ error: 'Not your group' });
    const [tasks] = await db.query(
      'SELECT * FROM group_tasks WHERE group_id=? ORDER BY week_no DESC, created_at DESC',
      [req.params.id]);
    res.json({ tasks });
  } catch (err) { res.status(500).json({ error: 'Failed to load tasks' }); }
});

// POST /api/teacher/supervising-groups/:id/tasks
const supTaskUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const dir = path.join(__dirname, '../public/uploads/tasks');
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      cb(null, `task_${Date.now()}_${Math.random().toString(36).substr(2,6)}${path.extname(file.originalname)}`);
    }
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.doc', '.docx'];
    if (allowed.includes(path.extname(file.originalname).toLowerCase())) cb(null, true);
    else cb(new Error('Only PDF/DOC files allowed'));
  }
});

router.post('/supervising-groups/:id/tasks', supTaskUpload.single('task_file'), async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id, group_code FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]);
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const { title, description, week_no, due_date } = req.body;
    if (!title || !week_no) return res.status(400).json({ error: 'Title and week number required' });

    const filePath = req.file ? `/uploads/tasks/${req.file.filename}` : null;
    const fileName = req.file ? req.file.originalname : null;

    const [result] = await db.query(
      `INSERT INTO group_tasks (group_id, supervisor_id, week_no, title, description, file_path, file_name, due_date)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [req.params.id, supId, week_no, title, description || null, filePath, fileName, due_date || null]);

    const [members] = await db.query('SELECT student_id FROM group_members WHERE group_id=?', [req.params.id]);
    for (const m of members) {
      await db.query('INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)',
        [m.student_id, 'SYSTEM_ALERT', `📋 New Task: Week ${week_no}`,
         `Your supervisor assigned a new task for Week ${week_no}: "${title}" in group ${group.group_code}.`]);
    }
    res.json({ success: true, task_id: result.insertId });
  } catch (err) {
    console.error('Supervising create task error:', err);
    res.status(500).json({ error: err.message || 'Failed to create task' });
  }
});

module.exports = router;

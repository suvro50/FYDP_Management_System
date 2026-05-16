const express = require('express');
const router = express.Router();
const db = require('../config/db');

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/stats — Dashboard statistics (matches Master Prompt)
//   Stats: My Total Groups, Pending Reports, Approved This Week,
//          Count per stage: FYDP-1 / FYDP-2 / FYDP-3
// ═══════════════════════════════════════════════════════════════════════════
router.get('/stats', async (req, res) => {
  try {
    const supId = req.session.user.user_id;

    const [
      [totalGroups], [pendingReports], [approvedThisWeek],
      [stageBreakdown], [totalStudents]
    ] = await Promise.all([
      // My Total Groups (active only)
      db.query(
        "SELECT COUNT(*) as count FROM project_groups WHERE supervisor_id=? AND is_active=1",
        [supId]
      ),
      // Pending Reports across all my groups
      db.query(
        `SELECT COUNT(*) as count FROM weekly_progress_reports wpr
         JOIN project_groups pg ON pg.group_id = wpr.group_id
         WHERE pg.supervisor_id=? AND wpr.supervisor_status='PENDING'`,
        [supId]
      ),
      // Approved this week (last 7 days)
      db.query(
        `SELECT COUNT(*) as count FROM weekly_progress_reports wpr
         JOIN project_groups pg ON pg.group_id = wpr.group_id
         WHERE pg.supervisor_id=? AND wpr.supervisor_status='APPROVED'
         AND wpr.supervisor_signed_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,
        [supId]
      ),
      // Count per stage: FYDP-1 / FYDP-2 / FYDP-3
      db.query(
        `SELECT fs.stage_name, fs.stage_order, COUNT(pg.group_id) as count
         FROM fydp_stages fs
         LEFT JOIN project_groups pg ON pg.current_stage_id = fs.stage_id
           AND pg.supervisor_id = ? AND pg.is_active = 1
         GROUP BY fs.stage_id, fs.stage_name, fs.stage_order
         ORDER BY fs.stage_order`,
        [supId]
      ),
      // Total students under me
      db.query(
        `SELECT COUNT(DISTINCT gm.student_id) as count FROM group_members gm
         JOIN project_groups pg ON pg.group_id = gm.group_id
         WHERE pg.supervisor_id=? AND pg.is_active=1`,
        [supId]
      )
    ]);

    res.json({
      totalGroups: totalGroups[0].count,
      pendingReports: pendingReports[0].count,
      approvedThisWeek: approvedThisWeek[0].count,
      stageBreakdown: stageBreakdown,
      totalStudents: totalStudents[0].count
    });
  } catch (err) {
    console.error('Supervisor stats error:', err);
    res.status(500).json({ error: 'Failed to load stats' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups — Groups organized by FYDP stage
//   Returns: { stages: [ { stage_name, groups: [...] } ] }
//   Each group has: members, progress bar data, color coding, report status
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups', async (req, res) => {
  try {
    const supId = req.session.user.user_id;

    // Get all stages
    const [stages] = await db.query(
      'SELECT * FROM fydp_stages ORDER BY stage_order'
    );

    // Get all my groups with full details
    const [groups] = await db.query(
      `SELECT pg.group_id, pg.group_code, pg.project_title, pg.supervisor_id,
              pg.is_active, pg.created_at,
              fs.stage_name, fs.stage_order, pd.domain_name,
              s.section_code,
              (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = pg.group_id) as member_count
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
       LEFT JOIN sections s ON s.section_id = pg.section_id
       WHERE pg.supervisor_id = ? AND pg.is_active = 1
       ORDER BY fs.stage_order, pg.group_code`,
      [supId]
    );

    // For each group, get members + report stats + latest week info
    for (let g of groups) {
      // Members
      const [members] = await db.query(
        `SELECT gm.student_id, gm.member_role, u.user_id, u.full_name, u.university_id, u.email
         FROM group_members gm
         JOIN users u ON u.user_id = gm.student_id
         WHERE gm.group_id = ?`,
        [g.group_id]
      );
      g.members = members;

      // Report stats: total approved weeks out of 12
      const [[approvedWeeks]] = await db.query(
        `SELECT COUNT(DISTINCT week_no) as count 
         FROM weekly_progress_reports 
         WHERE group_id = ? AND supervisor_status = 'APPROVED'`,
        [g.group_id]
      );
      g.approved_weeks = approvedWeeks.count;
      g.total_weeks = 12;

      // Latest week status for color coding
      const [latestReports] = await db.query(
        `SELECT wpr.week_no, wpr.supervisor_status, wpr.submitted_at
         FROM weekly_progress_reports wpr
         WHERE wpr.group_id = ?
         ORDER BY wpr.week_no DESC, wpr.submitted_at DESC
         LIMIT 10`,
        [g.group_id]
      );
      g.latest_reports = latestReports;

      // Determine color status
      // 🟢 Green = All members approved for latest week
      // 🟡 Yellow = Some pending
      // 🔴 Red = 7+ days since last submission (overdue)
      if (latestReports.length === 0) {
        g.color_status = 'red'; // No reports at all = overdue
      } else {
        const latestWeek = latestReports[0].week_no;
        const reportsForLatest = latestReports.filter(r => r.week_no === latestWeek);
        const allApproved = reportsForLatest.every(r => r.supervisor_status === 'APPROVED');
        const somePending = reportsForLatest.some(r => r.supervisor_status === 'PENDING');
        const lastSubmitDate = new Date(latestReports[0].submitted_at);
        const daysSince = (Date.now() - lastSubmitDate.getTime()) / (1000 * 60 * 60 * 24);

        if (daysSince > 7 && somePending) {
          g.color_status = 'red';
        } else if (allApproved && reportsForLatest.length >= g.member_count) {
          g.color_status = 'green';
        } else {
          g.color_status = 'yellow';
        }
      }

      // Pending count
      const [[pendingCount]] = await db.query(
        `SELECT COUNT(*) as count FROM weekly_progress_reports
         WHERE group_id = ? AND supervisor_status = 'PENDING'`,
        [g.group_id]
      );
      g.pending_count = pendingCount.count;
    }

    // Organize groups by stage
    const stageData = stages.map(s => ({
      stage_id: s.stage_id,
      stage_name: s.stage_name,
      stage_order: s.stage_order,
      groups: groups.filter(g => g.stage_name === s.stage_name)
    }));

    res.json({ stages: stageData });
  } catch (err) {
    console.error('Supervisor groups error:', err);
    res.status(500).json({ error: 'Failed to load groups' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups/:id/reports — Full weekly report history for a group
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/reports', async (req, res) => {
  try {
    const supId = req.session.user.user_id;

    // Verify supervisor owns this group
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const [reports] = await db.query(
      `SELECT wpr.*, u.full_name as student_name, u.university_id as student_uid
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id = ?
       ORDER BY wpr.week_no DESC, u.full_name`,
      [req.params.id]
    );

    res.json({ reports });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load report history' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/pending-reports — Reports awaiting approval
// ═══════════════════════════════════════════════════════════════════════════
router.get('/pending-reports', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const statusFilter = req.query.status || '';

    let where = 'WHERE pg.supervisor_id = ?';
    const params = [supId];

    if (statusFilter) {
      where += ' AND wpr.supervisor_status = ?';
      params.push(statusFilter);
    }

    const [reports] = await db.query(
      `SELECT wpr.*, pg.group_code, pg.project_title, u.full_name as student_name,
              u.university_id as student_uid, fs.stage_name
       FROM weekly_progress_reports wpr
       JOIN project_groups pg ON pg.group_id = wpr.group_id
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN users u ON u.user_id = wpr.student_id
       ${where}
       ORDER BY 
         CASE wpr.supervisor_status WHEN 'PENDING' THEN 0 ELSE 1 END,
         wpr.submitted_at DESC`,
      params
    );

    res.json({ reports });
  } catch (err) {
    console.error('Pending reports error:', err);
    res.status(500).json({ error: 'Failed to load reports' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/supervisor/reports/:id/review — Approve or reject via SP
// ═══════════════════════════════════════════════════════════════════════════
router.post('/reports/:id/review', async (req, res) => {
  try {
    const reportId = req.params.id;
    const supId = req.session.user.user_id;
    const { status, feedback } = req.body;

    if (!status || !['APPROVED', 'REJECTED'].includes(status)) {
      return res.status(400).json({ error: 'Status must be APPROVED or REJECTED' });
    }

    // Call stored procedure — handles auth check + triggers escalation
    await db.query(
      'CALL sp_approve_weekly_report(?, ?, ?, ?)',
      [reportId, supId, status, feedback || null]
    );

    // Get report details for notification
    const [[report]] = await db.query(
      `SELECT wpr.student_id, wpr.week_no, pg.group_code
       FROM weekly_progress_reports wpr
       JOIN project_groups pg ON pg.group_id = wpr.group_id
       WHERE wpr.report_id = ?`,
      [reportId]
    );

    if (report) {
      const supName = req.session.user.full_name;
      const notifType = status === 'APPROVED' ? 'REPORT_APPROVED' : 'REPORT_REJECTED';
      const notifTitle = status === 'APPROVED'
        ? `✅ Week ${report.week_no} Report Approved`
        : `❌ Week ${report.week_no} Report Rejected`;
      const notifMsg = status === 'APPROVED'
        ? `Your Week ${report.week_no} report for ${report.group_code} has been approved by ${supName}.`
        : `Your Week ${report.week_no} report for ${report.group_code} was rejected by ${supName}. Reason: ${feedback}. Please correct and resubmit.`;

      await db.query(
        'INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)',
        [report.student_id, notifType, notifTitle, notifMsg]
      );
    }

    res.json({
      success: true,
      message: `Report ${status.toLowerCase()} successfully`
    });
  } catch (err) {
    console.error('Review report error:', err);
    res.status(400).json({ error: err.message || 'Failed to review report' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/students-status — All students under this supervisor
// Reflects UCAM auto-synced data (drop/fail handled by admin sync API)
// ═══════════════════════════════════════════════════════════════════════════
router.get('/students-status', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [students] = await db.query(
      `SELECT u.user_id, u.full_name, u.university_id, u.is_active,
              gm.group_id, gm.member_role, pg.group_code, pg.project_title
       FROM group_members gm
       JOIN users u ON u.user_id = gm.student_id
       JOIN project_groups pg ON pg.group_id = gm.group_id
       WHERE pg.supervisor_id = ? AND pg.is_active = 1
       ORDER BY pg.group_code, u.full_name`,
      [supId]
    );
    res.json({ students });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load students' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/export-groups — Export all groups to CSV
// ═══════════════════════════════════════════════════════════════════════════
router.get('/export-groups', async (req, res) => {
  try {
    const { Parser } = require('json2csv');
    const supId = req.session.user.user_id;

    // Get all groups and members
    const [rows] = await db.query(
      `SELECT 
        pg.group_code as 'Group Code',
        pg.project_title as 'Project Title',
        pd.domain_name as 'Domain',
        fs.stage_name as 'Stage',
        u.university_id as 'Student ID',
        u.full_name as 'Student Name',
        gm.member_role as 'Role',
        u.email as 'Email'
       FROM project_groups pg
       JOIN project_domains pd ON pg.project_domain_id = pd.domain_id
       JOIN fydp_stages fs ON pg.current_stage_id = fs.stage_id
       JOIN group_members gm ON pg.group_id = gm.group_id
       JOIN users u ON gm.student_id = u.user_id
       WHERE pg.supervisor_id = ? AND pg.is_active = 1
       ORDER BY fs.stage_name, pg.group_code, gm.member_role`,
      [supId]
    );

    if (rows.length === 0) {
      return res.status(404).send('No groups found to export.');
    }

    const parser = new Parser();
    const csv = parser.parse(rows);

    res.header('Content-Type', 'text/csv');
    res.attachment(`FYDP_Groups_Export_${new Date().toISOString().split('T')[0]}.csv`);
    return res.send(csv);

  } catch (err) {
    console.error('Export error:', err);
    res.status(500).send('Server Error generating CSV');
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups/:id/weekly-summary
// Returns report status grouped by week, with per-student detail
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/weekly-summary', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    // Get all members
    const [members] = await db.query(
      `SELECT gm.student_id, u.full_name, u.university_id
       FROM group_members gm JOIN users u ON u.user_id=gm.student_id
       WHERE gm.group_id=?`,
      [req.params.id]
    );

    // Get all reports for this group
    const [reports] = await db.query(
      `SELECT wpr.report_id, wpr.student_id, wpr.week_no, wpr.report_title,
              wpr.supervisor_status, wpr.submitted_at, wpr.supervisor_feedback,
              wpr.report_file_path, u.full_name as student_name
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id=? ORDER BY wpr.week_no, u.full_name`,
      [req.params.id]
    );

    // Group by week
    const weekMap = {};
    reports.forEach(r => {
      if (!weekMap[r.week_no]) weekMap[r.week_no] = { week_no: r.week_no, reports: [] };
      weekMap[r.week_no].reports.push(r);
    });

    const weeks = Object.values(weekMap).sort((a, b) => a.week_no - b.week_no);
    weeks.forEach(w => {
      w.submitted_count = w.reports.length;
      w.pending_count = w.reports.filter(r => r.supervisor_status === 'PENDING').length;
      w.approved_count = w.reports.filter(r => r.supervisor_status === 'APPROVED').length;
      w.rejected_count = w.reports.filter(r => r.supervisor_status === 'REJECTED').length;
      w.total_members = members.length;
    });

    res.json({ weeks, members, total_members: members.length });
  } catch (err) {
    console.error('Weekly summary error:', err);
    res.status(500).json({ error: 'Failed to load weekly summary' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups/:id/approved-reports
// Returns all approved reports for a group (archive view)
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/approved-reports', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const [reports] = await db.query(
      `SELECT wpr.report_id, wpr.week_no, wpr.report_title, wpr.report_content,
              wpr.supervisor_status, wpr.submitted_at, wpr.supervisor_signed_at,
              wpr.supervisor_feedback, wpr.report_file_path,
              u.full_name as student_name, u.university_id as student_uid
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       WHERE wpr.group_id=? AND wpr.supervisor_status='APPROVED'
       ORDER BY wpr.week_no DESC, u.full_name`,
      [req.params.id]
    );

    res.json({ reports });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load approved reports' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups/:id/tasks — List tasks for a group
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/tasks', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const [tasks] = await db.query(
      `SELECT * FROM group_tasks WHERE group_id=? ORDER BY week_no DESC, created_at DESC`,
      [req.params.id]
    );
    res.json({ tasks });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load tasks' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/supervisor/groups/:id/tasks — Create a task for a group
// ═══════════════════════════════════════════════════════════════════════════
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const taskUpload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const dir = path.join(__dirname, '../public/uploads/tasks');
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (req, file, cb) => {
      const unique = `task_${Date.now()}_${Math.random().toString(36).substr(2,6)}`;
      cb(null, unique + path.extname(file.originalname));
    }
  }),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.doc', '.docx'];
    if (allowed.includes(path.extname(file.originalname).toLowerCase())) cb(null, true);
    else cb(new Error('Only PDF/DOC files allowed'));
  }
});

router.post('/groups/:id/tasks', taskUpload.single('task_file'), async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id, group_code FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const { title, description, week_no, due_date } = req.body;
    if (!title || !week_no) return res.status(400).json({ error: 'Title and week number are required' });

    const filePath = req.file ? `/uploads/tasks/${req.file.filename}` : null;
    const fileName = req.file ? req.file.originalname : null;

    const [result] = await db.query(
      `INSERT INTO group_tasks (group_id, supervisor_id, week_no, title, description, file_path, file_name, due_date)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [req.params.id, supId, week_no, title, description || null, filePath, fileName, due_date || null]
    );

    // Notify all group members
    const [members] = await db.query(
      `SELECT gm.student_id FROM group_members gm WHERE gm.group_id=?`,
      [req.params.id]
    );
    for (const m of members) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)`,
        [m.student_id, 'SYSTEM_ALERT',
         `📋 New Task: Week ${week_no}`,
         `Your supervisor assigned a new task for Week ${week_no}: "${title}" in group ${group.group_code}.`]
      );
    }

    res.json({ success: true, task_id: result.insertId });
  } catch (err) {
    console.error('Create task error:', err);
    res.status(500).json({ error: err.message || 'Failed to create task' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// DELETE /api/supervisor/groups/:gid/tasks/:tid — Delete a task
// ═══════════════════════════════════════════════════════════════════════════
router.delete('/groups/:gid/tasks/:tid', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[task]] = await db.query(
      `SELECT gt.* FROM group_tasks gt
       JOIN project_groups pg ON pg.group_id = gt.group_id
       WHERE gt.task_id=? AND pg.supervisor_id=?`,
      [req.params.tid, supId]
    );
    if (!task) return res.status(403).json({ error: 'Task not found or not yours' });

    // Delete the file if exists
    if (task.file_path) {
      const fullPath = path.join(__dirname, '../public', task.file_path);
      if (fs.existsSync(fullPath)) fs.unlinkSync(fullPath);
    }

    await db.query('DELETE FROM group_tasks WHERE task_id=?', [req.params.tid]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete task' });
  }
});

module.exports = router;


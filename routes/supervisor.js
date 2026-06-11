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
// GET /api/supervisor/chart-data — Weekly report chart data for dashboard
//   Returns: { weeks: [ { week_no, submitted, approved, rejected, pending } ] }
// ═══════════════════════════════════════════════════════════════════════════
router.get('/chart-data', async (req, res) => {
  try {
    const supId = req.session.user.user_id;

    const [rows] = await db.query(
      `SELECT
         wpr.week_no,
         COUNT(*)                                                     AS submitted,
         SUM(CASE WHEN wpr.supervisor_status = 'APPROVED' THEN 1 ELSE 0 END) AS approved,
         SUM(CASE WHEN wpr.supervisor_status = 'REJECTED' THEN 1 ELSE 0 END) AS rejected,
         SUM(CASE WHEN wpr.supervisor_status = 'PENDING'  THEN 1 ELSE 0 END) AS pending
       FROM weekly_progress_reports wpr
       JOIN project_groups pg ON pg.group_id = wpr.group_id
       WHERE pg.supervisor_id = ? AND pg.is_active = 1
       GROUP BY wpr.week_no
       ORDER BY wpr.week_no`,
      [supId]
    );

    res.json({ weeks: rows });
  } catch (err) {
    console.error('Chart data error:', err);
    res.status(500).json({ error: 'Failed to load chart data' });
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
      `SELECT pg.group_id, pg.group_code, pg.group_name, pg.project_title, pg.supervisor_id,
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

      // Report stats: approved weeks + total submitted + total approved reports
      const [[reportStats]] = await db.query(
        `SELECT
           COUNT(DISTINCT week_no)                                              AS approved_weeks,
           (SELECT COUNT(*) FROM weekly_progress_reports WHERE group_id = ?)    AS submitted_count,
           (SELECT COUNT(*) FROM weekly_progress_reports WHERE group_id = ? AND supervisor_status = 'APPROVED') AS approved_count
         FROM weekly_progress_reports
         WHERE group_id = ? AND supervisor_status = 'APPROVED'`,
        [g.group_id, g.group_id, g.group_id]
      );
      g.approved_weeks  = reportStats.approved_weeks;
      g.submitted_count = reportStats.submitted_count;
      g.approved_count  = reportStats.approved_count;
      g.total_weeks     = 12;

      // Latest week status for color coding
      const [latestReports] = await db.query(
        `SELECT wpr.week_no, wpr.supervisor_status, wpr.submitted_at
         FROM weekly_progress_reports wpr
         WHERE wpr.group_id = ?
         ORDER BY wpr.week_no DESC, wpr.submitted_at DESC
         LIMIT 20`,
        [g.group_id]
      );
      g.latest_reports = latestReports;

      // Determine color status
      // 🟢 Green = Latest week has ALL APPROVED and ZERO PENDING reports
      // 🟡 Yellow = No reports yet OR some reports still pending
      // 🔴 Red = 7+ days since last submission with unresolved pending
      if (latestReports.length === 0) {
        g.color_status = 'green'; // No reports yet = approved (nothing pending)
      } else {
        const latestWeek = latestReports[0].week_no;
        const reportsForLatest = latestReports.filter(r => r.week_no === latestWeek);
        const allApproved = reportsForLatest.every(r => r.supervisor_status === 'APPROVED');
        const somePending = reportsForLatest.some(r => r.supervisor_status === 'PENDING');
        const lastSubmitDate = new Date(latestReports[0].submitted_at);
        const daysSince = (Date.now() - lastSubmitDate.getTime()) / (1000 * 60 * 60 * 24);

        if (somePending && daysSince > 7) {
          // Pending report not actioned for 7+ days = Overdue
          g.color_status = 'red';
        } else if (allApproved && !somePending) {
          // All reports for the latest week are approved, none pending = Green
          // Works correctly for both individual AND group reports
          g.color_status = 'green';
        } else {
          g.color_status = 'yellow';
        }
      }

      // Pending count (for badge on cards)
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

    // Clear report submission notifications for this supervisor
    await db.query(
      `UPDATE notifications 
       SET is_read = 1 
       WHERE user_id = ? 
         AND (title LIKE '%Report Submitted%' OR message LIKE '%report submitted%' OR title LIKE '%Report Resubmitted%' OR message LIKE '%report resubmitted%') 
         AND is_read = 0`,
      [supId]
    );

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

    // Clear report submission notifications for this supervisor
    await db.query(
      `UPDATE notifications 
       SET is_read = 1 
       WHERE user_id = ? 
         AND (title LIKE '%Report Submitted%' OR message LIKE '%report submitted%' OR title LIKE '%Report Resubmitted%' OR message LIKE '%report resubmitted%') 
         AND is_read = 0`,
      [supId]
    );

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

    // For group reports, also fetch group member count
    for (const r of reports) {
      if (r.is_group_report) {
        const [[memberCount]] = await db.query(
          `SELECT COUNT(*) as count FROM group_members WHERE group_id = ?`,
          [r.group_id]
        );
        r.group_member_count = memberCount.count;
      }
    }

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

    // Get full report details for notification + group propagation
    const [[report]] = await db.query(
      `SELECT wpr.student_id, wpr.week_no, wpr.group_id, wpr.is_group_report,
              wpr.report_title, wpr.report_content, wpr.report_file_path,
              pg.group_code
       FROM weekly_progress_reports wpr
       JOIN project_groups pg ON pg.group_id = wpr.group_id
       WHERE wpr.report_id = ?`,
      [reportId]
    );

    if (report) {
      const supName = req.session.user.full_name;
      const notifType = status === 'APPROVED' ? 'REPORT_APPROVED' : 'REPORT_REJECTED';

      // ── Group Report Auto-Propagation ─────────────────────────────────
      if (report.is_group_report && status === 'APPROVED') {
        // Get all group members EXCEPT the original submitter
        const [members] = await db.query(
          `SELECT gm.student_id FROM group_members gm
           WHERE gm.group_id = ? AND gm.student_id != ?`,
          [report.group_id, report.student_id]
        );

        for (const member of members) {
          // Check if this member already has an APPROVED report for this week
          const [[existing]] = await db.query(
            `SELECT report_id FROM weekly_progress_reports
             WHERE group_id = ? AND student_id = ? AND week_no = ? AND supervisor_status = 'APPROVED'`,
            [report.group_id, member.student_id, report.week_no]
          );

          if (!existing) {
            // Delete any existing rejected/pending personal report for this member+week
            await db.query(
              `DELETE FROM weekly_progress_reports
               WHERE group_id = ? AND student_id = ? AND week_no = ?`,
              [report.group_id, member.student_id, report.week_no]
            );

            // Insert a mirror approved report for this member
            await db.query(
              `INSERT INTO weekly_progress_reports 
               (group_id, student_id, week_no, report_title, report_content, 
                report_file_path, is_group_report, supervisor_status, 
                supervisor_feedback, supervisor_signed_at, submitted_at)
               VALUES (?, ?, ?, ?, ?, ?, 1, 'APPROVED', ?, NOW(), NOW())`,
              [report.group_id, member.student_id, report.week_no,
               report.report_title, report.report_content, report.report_file_path,
               feedback || 'Auto-approved via group report']
            );
          }

          // Notify each group member
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)`,
            [member.student_id, notifType,
             `✅ Week ${report.week_no} Group Report Approved`,
             `The group report for Week ${report.week_no} in ${report.group_code} has been approved by ${supName}. Your week is automatically marked as approved.`]
          );
          const io = req.app.get('io');
          if (io) io.to(`user_${member.student_id}`).emit('notification', {
            title: `✅ Week ${report.week_no} Group Report Approved`,
            message: `Your Week ${report.week_no} is auto-approved via group report.`
          });
        }
      }

      // Notify the original submitter
      const notifTitle = status === 'APPROVED'
        ? `✅ Week ${report.week_no} ${report.is_group_report ? 'Group ' : ''}Report Approved`
        : `❌ Week ${report.week_no} ${report.is_group_report ? 'Group ' : ''}Report Rejected`;
      const notifMsg = status === 'APPROVED'
        ? `Your Week ${report.week_no} ${report.is_group_report ? 'group ' : ''}report for ${report.group_code} has been approved by ${supName}.`
        : `Your Week ${report.week_no} ${report.is_group_report ? 'group ' : ''}report for ${report.group_code} was rejected by ${supName}. Reason: ${feedback}. Please correct and resubmit.`;

      await db.query(
        'INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)',
        [report.student_id, notifType, notifTitle, notifMsg]
      );

      // Notify course teacher
      try {
        const [[groupInfo]] = await db.query(
          `SELECT cts.course_teacher_id
           FROM project_groups pg
           LEFT JOIN course_teacher_sections cts ON cts.section_id = pg.section_id
           WHERE pg.group_id = ?`,
          [report.group_id]
        );
        if (groupInfo && groupInfo.course_teacher_id) {
          const ctNotifTitle = status === 'APPROVED'
            ? `✅ Week ${report.week_no} Report Approved`
            : `❌ Week ${report.week_no} Report Rejected`;
          const ctNotifMsg = `${supName} has ${status.toLowerCase()} the Week ${report.week_no} report for group ${report.group_code}.`;
          
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
            [groupInfo.course_teacher_id, ctNotifTitle, ctNotifMsg]
          );
          const io = req.app.get('io');
          if (io) io.to(`user_${groupInfo.course_teacher_id}`).emit('notification', { title: ctNotifTitle, message: ctNotifMsg });
        }
      } catch (ctErr) {
        console.error('Course teacher review notification error (non-fatal):', ctErr);
      }

      // If group report rejected, also notify other group members
      if (report.is_group_report && status === 'REJECTED') {
        const [members] = await db.query(
          `SELECT gm.student_id FROM group_members gm
           WHERE gm.group_id = ? AND gm.student_id != ?`,
          [report.group_id, report.student_id]
        );
        for (const member of members) {
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)`,
            [member.student_id, 'SYSTEM_ALERT',
             `❌ Week ${report.week_no} Group Report Rejected`,
             `The group report for Week ${report.week_no} in ${report.group_code} was rejected. The submitter needs to correct and resubmit.`]
          );
        }
      }
    }

    res.json({
      success: true,
      message: `Report ${status.toLowerCase()} successfully${report && report.is_group_report && status === 'APPROVED' ? ' (all group members updated)' : ''}`
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
      'SELECT group_id, created_at FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    // Clear report submission notifications for this supervisor
    await db.query(
      `UPDATE notifications 
       SET is_read = 1 
       WHERE user_id = ? 
         AND (title LIKE '%Report Submitted%' OR message LIKE '%report submitted%' OR title LIKE '%Report Resubmitted%' OR message LIKE '%report resubmitted%') 
         AND is_read = 0`,
      [supId]
    );

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
              wpr.supervisor_signed_at, wpr.report_file_path, wpr.is_group_report,
              wpr.report_content AS progress_summary,
              u.full_name as student_name, u.university_id as student_uid, gm.member_role
       FROM weekly_progress_reports wpr
       JOIN users u ON u.user_id = wpr.student_id
       JOIN group_members gm ON gm.student_id = wpr.student_id AND gm.group_id = wpr.group_id
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

    const msPerWeek = 1000 * 60 * 60 * 24 * 7;
    const createdAt = new Date(group.created_at);
    let activeWeek = Math.floor((Date.now() - createdAt.getTime()) / msPerWeek) + 1;
    if (activeWeek < 1) activeWeek = 1;
    if (activeWeek > 12) activeWeek = 12;

    res.json({
      weeks,
      members,
      total_members: members.length,
      active_week: activeWeek
    });
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

    const { title, description, week_no, due_date, assigned_to } = req.body;
    if (!title || !week_no) return res.status(400).json({ error: 'Title and week number are required' });

    const filePath = req.file ? `/uploads/tasks/${req.file.filename}` : null;
    const fileName = req.file ? req.file.originalname : null;

    // Parse assigned_to: null/empty = all members, otherwise JSON array of student IDs
    let assignedToJson = null;
    let assignedStudentIds = null;
    if (assigned_to && assigned_to !== 'all') {
      try {
        const parsed = JSON.parse(assigned_to);
        if (Array.isArray(parsed) && parsed.length > 0) {
          assignedStudentIds = parsed.map(id => parseInt(id));
          assignedToJson = JSON.stringify(assignedStudentIds);
        }
      } catch(e) { /* invalid JSON = assign to all */ }
    }

    const [result] = await db.query(
      `INSERT INTO group_tasks (group_id, supervisor_id, week_no, title, description, file_path, file_name, due_date, assigned_to)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [req.params.id, supId, week_no, title, description || null, filePath, fileName, due_date || null, assignedToJson]
    );

    // Notify selected students (or all if none specified)
    const [members] = await db.query(
      `SELECT gm.student_id FROM group_members gm WHERE gm.group_id=?`,
      [req.params.id]
    );

    const membersToNotify = assignedStudentIds
      ? members.filter(m => assignedStudentIds.includes(m.student_id))
      : members;

    for (const m of membersToNotify) {
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

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups/:id/task-history — All tasks with submission progress
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/task-history', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    // Get all tasks for this group
    const [tasks] = await db.query(
      `SELECT gt.*, u.full_name AS creator_name
       FROM group_tasks gt
       JOIN users u ON u.user_id = gt.supervisor_id
       WHERE gt.group_id = ?
       ORDER BY gt.week_no DESC, gt.created_at DESC`,
      [req.params.id]
    );

    // Get all group members
    const [members] = await db.query(
      `SELECT gm.student_id, u.full_name, u.university_id
       FROM group_members gm
       JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?`,
      [req.params.id]
    );

    // For each task, compute submission progress
    for (const task of tasks) {
      // Determine who is assigned
      let assignedIds;
      if (!task.assigned_to) {
        assignedIds = members.map(m => m.student_id);
      } else {
        const parsed = typeof task.assigned_to === 'string' ? JSON.parse(task.assigned_to) : task.assigned_to;
        assignedIds = Array.isArray(parsed) ? parsed : members.map(m => m.student_id);
      }
      task.total_assigned = assignedIds.length;

      // Get submissions for this task
      const [submissions] = await db.query(
        `SELECT ts.submission_id, ts.student_id, ts.status, ts.grade, ts.submitted_at,
                u.full_name, u.university_id
         FROM group_task_submissions ts
         JOIN users u ON u.user_id = ts.student_id
         WHERE ts.task_id = ?`,
        [task.task_id]
      );
      task.submissions = submissions;
      task.submitted_count = submissions.length;
      task.reviewed_count = submissions.filter(s => s.status === 'REVIEWED').length;
      task.new_count = submissions.filter(s => s.status === 'NEW').length;

      // Compute overall task status
      if (task.submitted_count === 0) {
        task.task_status = 'Pending';
      } else if (task.reviewed_count === task.total_assigned && task.total_assigned > 0) {
        task.task_status = 'Reviewed';
      } else if (task.submitted_count >= task.total_assigned) {
        task.task_status = 'Submitted';
      } else {
        task.task_status = 'Partial';
      }

      // Assigned members with their submission status
      task.assigned_members = assignedIds.map(sid => {
        const member = members.find(m => m.student_id === sid);
        const sub = submissions.find(s => s.student_id === sid);
        return {
          student_id: sid,
          full_name: member?.full_name || 'Unknown',
          university_id: member?.university_id || '',
          submission_status: sub ? sub.status : 'Pending',
          grade: sub?.grade || null,
          submitted_at: sub?.submitted_at || null
        };
      });
    }

    res.json({ tasks, members });
  } catch (err) {
    console.error('Task history error:', err);
    res.status(500).json({ error: 'Failed to load task history' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/supervisor/groups/:id/task-submissions — All submissions for a group
// ═══════════════════════════════════════════════════════════════════════════
router.get('/groups/:id/task-submissions', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[group]] = await db.query(
      'SELECT group_id FROM project_groups WHERE group_id=? AND supervisor_id=?',
      [req.params.id, supId]
    );
    if (!group) return res.status(403).json({ error: 'Not your group' });

    const statusFilter = req.query.status || '';
    let where = 'WHERE ts.group_id = ?';
    const params = [req.params.id];

    if (statusFilter) {
      where += ' AND ts.status = ?';
      params.push(statusFilter);
    }

    const [submissions] = await db.query(
      `SELECT ts.*, gt.title AS task_title, gt.week_no, gt.due_date,
              u.full_name AS student_name, u.university_id AS student_uid
       FROM group_task_submissions ts
       JOIN group_tasks gt ON gt.task_id = ts.task_id
       JOIN users u ON u.user_id = ts.student_id
       ${where}
       ORDER BY
         CASE ts.status WHEN 'NEW' THEN 0 WHEN 'SUBMITTED' THEN 0 ELSE 1 END,
         ts.submitted_at DESC`,
      params
    );

    // Count stats
    const [[counts]] = await db.query(
      `SELECT
         COUNT(*) AS total,
         SUM(ts.status IN ('NEW','SUBMITTED')) AS new_count,
         SUM(ts.status IN ('REVIEWED','ACCEPTED','REJECTED','ACKNOWLEDGED')) AS reviewed_count
       FROM group_task_submissions ts
       WHERE ts.group_id = ?`,
      [req.params.id]
    );

    res.json({
      submissions,
      counts: {
        total: counts.total || 0,
        new_count: counts.new_count || 0,
        reviewed_count: counts.reviewed_count || 0
      }
    });
  } catch (err) {
    console.error('Task submissions error:', err);
    res.status(500).json({ error: 'Failed to load task submissions' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/supervisor/task-submissions/:id/review — Accept / Reject / Grade
// ═══════════════════════════════════════════════════════════════════════════
router.post('/task-submissions/:id/review', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const submissionId = req.params.id;
    const { grade, feedback, status, rejection_reason } = req.body;

    const finalStatus = status || 'REVIEWED';
    if (!['REVIEWED', 'ACCEPTED', 'REJECTED'].includes(finalStatus)) {
      return res.status(400).json({ error: 'Invalid status value' });
    }
    if (finalStatus === 'REJECTED' && !rejection_reason) {
      return res.status(400).json({ error: 'A rejection reason is required' });
    }

    // Verify this submission belongs to a group supervised by this user
    const [[submission]] = await db.query(
      `SELECT ts.*, pg.supervisor_id, pg.group_code, gt.title AS task_title, gt.week_no
       FROM group_task_submissions ts
       JOIN project_groups pg ON pg.group_id = ts.group_id
       JOIN group_tasks gt ON gt.task_id = ts.task_id
       WHERE ts.submission_id = ?`,
      [submissionId]
    );
    if (!submission) return res.status(404).json({ error: 'Submission not found' });
    if (submission.supervisor_id !== supId) return res.status(403).json({ error: 'Not your group' });

    await db.query(
      `UPDATE group_task_submissions
       SET grade = ?, feedback = ?, status = ?, rejection_reason = ?, reviewed_at = NOW()
       WHERE submission_id = ?`,
      [grade || null, feedback || null, finalStatus, rejection_reason || null, submissionId]
    );

    // Notify the student
    const supName = req.session.user.full_name;
    let notifTitle, notifMsg;

    if (finalStatus === 'ACCEPTED') {
      notifTitle = `✅ Task Accepted: ${submission.task_title}`;
      notifMsg = `Your submission for "${submission.task_title}" (Week ${submission.week_no}) in ${submission.group_code} has been accepted by ${supName}.${grade ? ` Grade: ${grade}.` : ''}${feedback ? ` Feedback: ${feedback}` : ''}`;
    } else if (finalStatus === 'REJECTED') {
      notifTitle = `❌ Task Rejected: ${submission.task_title}`;
      notifMsg = `Your submission for "${submission.task_title}" (Week ${submission.week_no}) in ${submission.group_code} was rejected by ${supName}. Reason: ${rejection_reason}. Please revise and resubmit.`;
    } else {
      notifTitle = `📝 Task Reviewed: ${submission.task_title}`;
      notifMsg = `Your submission for "${submission.task_title}" (Week ${submission.week_no}) in ${submission.group_code} has been reviewed by ${supName}.${grade ? ` Grade: ${grade}.` : ''}${feedback ? ` Feedback: ${feedback}` : ''}`;
    }

    await db.query(
      `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, ?, ?, ?)`,
      [submission.student_id, 'SYSTEM_ALERT', notifTitle, notifMsg]
    );

    const io = req.app.get('io');
    if (io) {
      io.to(`user_${submission.student_id}`).emit('notification', {
        title: notifTitle,
        message: finalStatus === 'REJECTED' ? `Reason: ${rejection_reason}` : `Grade: ${grade || 'N/A'}`
      });
    }

    res.json({ success: true, message: `Submission ${finalStatus.toLowerCase()} successfully` });
  } catch (err) {
    console.error('Review submission error:', err);
    res.status(500).json({ error: 'Failed to review submission' });
  }
});

// ══════════════════════════════════════════════════════════════════════════
// FYDP-1 SUPERVISOR REQUEST MANAGEMENT
// Pre-FYDP groups send requests → supervisor accepts/rejects
// On accept: group transitions from pre_fydp_groups → project_groups (FYDP-1)
// ══════════════════════════════════════════════════════════════════════════

// ── Stats for dashboard badge ──────────────────────────────────────────────
router.get('/fydp1-request-stats', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const [[{ pending_count }]] = await db.query(
      `SELECT COUNT(*) as pending_count FROM supervisor_requests
       WHERE supervisor_id = ? AND request_status = 'PENDING'`,
      [supId]
    );
    res.json({ pending_count });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load request stats' });
  }
});

// ── List FYDP-1 Requests (PENDING/ACCEPTED/REJECTED) ──────────────────────
router.get('/fydp1-requests', async (req, res) => {
  try {
    const supId = req.session.user.user_id;
    const statusFilter = req.query.status || '';

    let where = 'WHERE sr.supervisor_id = ?';
    const params = [supId];

    if (statusFilter) {
      where += ' AND sr.request_status = ?';
      params.push(statusFilter);
    }

    const [requests] = await db.query(
      `SELECT sr.*,
              g.group_name, g.description as group_description, g.max_members,
              g.github_url, g.created_by,
              pd.domain_name,
              u_lead.full_name as leader_name, u_lead.email as leader_email,
              d_lead.short_code as leader_dept,
              (SELECT COUNT(*) FROM pre_fydp_group_members WHERE group_id = g.group_id) as member_count
       FROM supervisor_requests sr
       JOIN pre_fydp_groups g ON g.group_id = sr.pre_fydp_group_id
       JOIN project_domains pd ON pd.domain_id = g.domain_id
       JOIN users u_lead ON u_lead.user_id = g.created_by
       JOIN departments d_lead ON d_lead.department_id = u_lead.department_id
       ${where}
       ORDER BY
         CASE sr.request_status WHEN 'PENDING' THEN 0 WHEN 'ACCEPTED' THEN 1 ELSE 2 END,
         sr.created_at DESC`,
      params
    );

    // Enrich with group members and skills
    for (const req_item of requests) {
      const [members] = await db.query(
        `SELECT gm.user_id, gm.member_role, u.full_name, u.email,
                d.short_code as department, u.university_id
         FROM pre_fydp_group_members gm
         JOIN users u ON u.user_id = gm.user_id
         JOIN departments d ON d.department_id = u.department_id
         WHERE gm.group_id = ?`,
        [req_item.pre_fydp_group_id]
      );
      req_item.members = members;

      const [skills] = await db.query(
        `SELECT s.skill_name FROM pre_fydp_group_required_skills pgrs
         JOIN skills s ON s.skill_id = pgrs.skill_id
         WHERE pgrs.group_id = ?`,
        [req_item.pre_fydp_group_id]
      );
      req_item.required_skills = skills.map(s => s.skill_name);
    }

    res.json({ requests });
  } catch (err) {
    console.error('FYDP-1 requests error:', err);
    res.status(500).json({ error: 'Failed to load FYDP-1 requests' });
  }
});

// ── Accept/Reject FYDP-1 Request ──────────────────────────────────────────
router.patch('/fydp1-requests/:id', async (req, res) => {
  const conn = await db.getConnection();
  try {
    const supId = req.session.user.user_id;
    const supName = req.session.user.full_name;
    const requestId = req.params.id;
    const { action, rejection_reason } = req.body; // 'accept' or 'reject'

    if (!action || !['accept', 'reject'].includes(action)) {
      conn.release();
      return res.status(400).json({ error: 'Action must be "accept" or "reject"' });
    }

    await conn.beginTransaction();

    // 1. Get the request and verify ownership
    const [[request]] = await conn.query(
      `SELECT sr.*, g.group_name, g.domain_id, g.max_members, g.github_url, g.created_by,
              pd.domain_name,
              (SELECT COUNT(*) FROM pre_fydp_group_members WHERE group_id = g.group_id) as member_count
       FROM supervisor_requests sr
       JOIN pre_fydp_groups g ON g.group_id = sr.pre_fydp_group_id
       JOIN project_domains pd ON pd.domain_id = g.domain_id
       WHERE sr.request_id = ? AND sr.supervisor_id = ?`,
      [requestId, supId]
    );

    if (!request) {
      await conn.rollback();
      conn.release();
      return res.status(404).json({ error: 'Request not found' });
    }
    if (request.request_status !== 'PENDING') {
      await conn.rollback();
      conn.release();
      return res.status(400).json({ error: `This request is already ${request.request_status.toLowerCase()}` });
    }

    if (action === 'reject') {
      // ── REJECT ─────────────────────────────────────────────────────
      await conn.query(
        `UPDATE supervisor_requests
         SET request_status = 'REJECTED', rejection_reason = ?, responded_at = NOW()
         WHERE request_id = ?`,
        [rejection_reason || null, requestId]
      );

      await conn.commit();
      conn.release();

      // Notify group leader
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type, is_read)
         VALUES (?, 'SUPERVISOR_REQUEST_REJECTED', ?, ?, ?, 'supervisor_requests', 0)`,
        [
          request.created_by,
          `❌ Supervisor Request Rejected — ${supName}`,
          `${supName} has declined your FYDP-1 supervisor request for "${request.group_name}".${rejection_reason ? ` Reason: ${rejection_reason}` : ''} You can request another supervisor.`,
          requestId
        ]
      );

      // Real-time
      const io = req.app.get('io');
      if (io) {
        io.to(`user_${request.created_by}`).emit('notification', {
          title: `❌ Supervisor Request Rejected`,
          message: `${supName} declined your request. Choose another supervisor.`
        });
      }

      return res.json({ success: true, message: 'Request rejected' });
    }

    // ── ACCEPT ─────────────────────────────────────────────────────────
    // 2. Check FYDP-1 slot availability (max 3)
    const [[slotCheck]] = await conn.query(
      `SELECT COUNT(*) as fydp1_count FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       WHERE pg.supervisor_id = ? AND pg.is_active = 1 AND fs.stage_name = 'FYDP-1'`,
      [supId]
    );
    if (slotCheck.fydp1_count >= 3) {
      await conn.rollback();
      conn.release();
      return res.status(400).json({
        error: 'You already have 3 groups in FYDP-1. You cannot accept more groups.'
      });
    }

    // 3. Get FYDP-1 stage_id
    const [[fydp1Stage]] = await conn.query(
      `SELECT stage_id FROM fydp_stages WHERE stage_name = 'FYDP-1'`
    );
    if (!fydp1Stage) {
      await conn.rollback();
      conn.release();
      return res.status(500).json({ error: 'FYDP-1 stage not found in database' });
    }

    // 4. Get default section (first available)
    const [[defaultSection]] = await conn.query(
      `SELECT section_id FROM sections WHERE is_active = 1 ORDER BY section_id LIMIT 1`
    );
    if (!defaultSection) {
      await conn.rollback();
      conn.release();
      return res.status(500).json({ error: 'No active section found for assignment' });
    }

    // 5. Auto-generate group code (UIU-GXXX)
    const [[maxCode]] = await conn.query(
      `SELECT MAX(CAST(SUBSTRING(group_code, 6) AS UNSIGNED)) as max_num
       FROM project_groups WHERE group_code LIKE 'UIU-G%'`
    );
    const nextNum = (maxCode?.max_num || 0) + 1;
    const groupCode = `UIU-G${String(nextNum).padStart(3, '0')}`;

    // 6. Create project_groups entry (FYDP-1)
    const [pgResult] = await conn.query(
      `INSERT INTO project_groups
         (group_code, group_name, project_title, project_domain_id, supervisor_id,
          current_stage_id, section_id, project_status, is_active)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'ACTIVE', 1)`,
      [groupCode, request.group_name, request.project_title, request.domain_id, supId,
       fydp1Stage.stage_id, defaultSection.section_id]
    );
    const newGroupId = pgResult.insertId;

    // 7. Get all pre-FYDP group members
    const [preFydpMembers] = await conn.query(
      `SELECT gm.user_id, gm.member_role FROM pre_fydp_group_members gm
       WHERE gm.group_id = ?`, [request.pre_fydp_group_id]
    );

    // 8. Map pre-FYDP members → FYDP group_members
    const roleMap = {
      'Lead': 'TEAM_LEAD',
      'Frontend': 'DEVELOPER',
      'Backend': 'DEVELOPER',
      'ML Engineer': 'DEVELOPER',
      'DevOps': 'DEVELOPER',
      'Security': 'DEVELOPER',
      'Tester': 'TESTER',
      'Data Engineer': 'DATA_ENGINEER',
      'Other': 'DEVELOPER'
    };

    for (const member of preFydpMembers) {
      const fydpRole = roleMap[member.member_role] || 'DEVELOPER';
      await conn.query(
        `INSERT INTO group_members (group_id, student_id, member_role)
         VALUES (?, ?, ?)`,
        [newGroupId, member.user_id, fydpRole]
      );

      // 9. Change user role from PRE_FYDP_STUDENT → STUDENT
      await conn.query(
        `UPDATE users SET role = 'STUDENT' WHERE user_id = ? AND role = 'PRE_FYDP_STUDENT'`,
        [member.user_id]
      );

      // 10. Update user_profiles: PRE_FYDP → FYDP
      await conn.query(
        `UPDATE user_profiles SET profile_type = 'FYDP', availability_status = 'IN_TEAM'
         WHERE user_id = ? AND profile_type = 'PRE_FYDP'`,
        [member.user_id]
      );
    }

    // 11. Mark supervisor request as ACCEPTED
    await conn.query(
      `UPDATE supervisor_requests
       SET request_status = 'ACCEPTED', responded_at = NOW()
       WHERE request_id = ?`,
      [requestId]
    );

    // 12. Auto-reject all OTHER pending requests from this group
    const [otherPendingFromGroup] = await conn.query(
      `SELECT sr.request_id, sr.supervisor_id, u.full_name as other_sup_name
       FROM supervisor_requests sr
       JOIN users u ON u.user_id = sr.supervisor_id
       WHERE sr.pre_fydp_group_id = ? AND sr.request_id != ? AND sr.request_status = 'PENDING'`,
      [request.pre_fydp_group_id, requestId]
    );

    for (const otherReq of otherPendingFromGroup) {
      await conn.query(
        `UPDATE supervisor_requests
         SET request_status = 'AUTO_REJECTED', rejection_reason = 'Group was accepted by another supervisor', responded_at = NOW()
         WHERE request_id = ?`,
        [otherReq.request_id]
      );
    }

    // 13. Check if supervisor now has 3 FYDP-1 groups → auto-reject remaining pending requests to this supervisor
    const newFydp1Count = slotCheck.fydp1_count + 1;
    if (newFydp1Count >= 3) {
      const [remainingPending] = await conn.query(
        `SELECT sr.request_id, sr.pre_fydp_group_id, g.created_by, g.group_name
         FROM supervisor_requests sr
         JOIN pre_fydp_groups g ON g.group_id = sr.pre_fydp_group_id
         WHERE sr.supervisor_id = ? AND sr.request_status = 'PENDING'`,
        [supId]
      );

      for (const pendReq of remainingPending) {
        await conn.query(
          `UPDATE supervisor_requests
           SET request_status = 'AUTO_REJECTED', rejection_reason = 'Supervisor has reached maximum 3 groups for FYDP-1', responded_at = NOW()
           WHERE request_id = ?`,
          [pendReq.request_id]
        );
      }

      // Notify those groups after commit
      // (store for post-commit notifications)
      request._autoRejectedForSlotFull = remainingPending;
    }

    // 14. Mark the pre-FYDP group as CLOSED
    await conn.query(
      `UPDATE pre_fydp_groups SET group_status = 'CLOSED' WHERE group_id = ?`,
      [request.pre_fydp_group_id]
    );

    await conn.commit();
    conn.release();

    // ── Post-commit notifications (outside transaction) ──────────────

    // Notify all group members
    for (const member of preFydpMembers) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type, is_read)
         VALUES (?, 'SUPERVISOR_REQUEST_ACCEPTED', ?, ?, ?, 'supervisor_requests', 0)`,
        [
          member.user_id,
          `🎉 Supervisor Accepted — Welcome to FYDP-1!`,
          `${supName} has accepted your group "${request.group_name}" for FYDP-1! Your group code is ${groupCode}. You have been promoted to FYDP Student. Good luck!`,
          requestId
        ]
      );

      const io = req.app.get('io');
      if (io) {
        io.to(`user_${member.user_id}`).emit('notification', {
          title: `🎉 Welcome to FYDP-1!`,
          message: `${supName} accepted your group. You are now an FYDP Student!`
        });
      }
    }

    // Notify other supervisors whose requests were auto-rejected
    for (const otherReq of otherPendingFromGroup) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, is_read)
         VALUES (?, 'SYSTEM_ALERT', ?, ?, 0)`,
        [
          otherReq.supervisor_id,
          `ℹ️ Request Auto-Closed — ${request.group_name}`,
          `The group "${request.group_name}" has been accepted by another supervisor. Their request to you has been automatically closed.`
        ]
      );
    }

    // Notify groups auto-rejected due to slot full
    if (request._autoRejectedForSlotFull) {
      for (const pendReq of request._autoRejectedForSlotFull) {
        await db.query(
          `INSERT INTO notifications (user_id, notification_type, title, message, is_read)
           VALUES (?, 'SUPERVISOR_SLOT_FULL', ?, ?, 0)`,
          [
            pendReq.created_by,
            `⚠️ Supervisor Full — ${supName}`,
            `${supName} has reached the maximum of 3 groups for FYDP-1. Your request has been automatically declined. Please choose another supervisor.`
          ]
        );
      }
    }

    res.json({
      success: true,
      message: `Group "${request.group_name}" accepted and transitioned to FYDP-1! Group code: ${groupCode}`,
      group_code: groupCode,
      new_group_id: newGroupId
    });

  } catch (err) {
    try { await conn.rollback(); } catch(e) {}
    conn.release();
    console.error('Accept/Reject FYDP-1 request error:', err);
    res.status(500).json({ error: err.message || 'Failed to process request' });
  }
});

module.exports = router;

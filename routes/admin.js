const express = require("express");
const router = express.Router();
const db = require("../config/db");

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/stats — Dashboard statistics
// ═══════════════════════════════════════════════════════════════════════════
router.get("/stats", async (req, res) => {
  try {
    // All counts in parallel for performance
    const [
      [students],
      [supervisors],
      [courseTeachers],
      [activeGroups],
      [stageGroups],
      [domainGroups],
      [pendingReports],
      [recentAudit],
    ] = await Promise.all([
      db.query(
        "SELECT COUNT(*) as count FROM users WHERE role='STUDENT' AND is_active=1",
      ),
      db.query(
        "SELECT COUNT(*) as count FROM users WHERE role='SUPERVISOR' AND is_active=1",
      ),
      db.query(
        "SELECT COUNT(*) as count FROM users WHERE role='COURSE_TEACHER' AND is_active=1",
      ),
      db.query(
        "SELECT COUNT(*) as count FROM project_groups WHERE project_status='ACTIVE' AND is_active=1",
      ),
      db.query(`SELECT fs.stage_name, COUNT(pg.group_id) as count
                FROM fydp_stages fs
                LEFT JOIN project_groups pg ON pg.current_stage_id = fs.stage_id 
                  AND pg.is_active=1 AND pg.project_status='ACTIVE'
                GROUP BY fs.stage_id, fs.stage_name
                ORDER BY fs.stage_order`),
      db.query(`SELECT pd.domain_name, COUNT(pg.group_id) as count
                FROM project_domains pd
                LEFT JOIN project_groups pg ON pg.project_domain_id = pd.domain_id
                  AND pg.is_active=1
                GROUP BY pd.domain_id, pd.domain_name
                ORDER BY count DESC`),
      db.query(
        "SELECT COUNT(*) as count FROM weekly_progress_reports WHERE supervisor_status='PENDING'",
      ),
      db.query("SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT 10"),
    ]);

    res.json({
      students: students[0].count,
      supervisors: supervisors[0].count,
      courseTeachers: courseTeachers[0].count,
      activeGroups: activeGroups[0].count,
      stageGroups: stageGroups,
      domainGroups: domainGroups.filter((d) => d.count > 0),
      pendingReports: pendingReports[0].count,
      recentAudit: recentAudit,
    });
  } catch (err) {
    console.error("Admin stats error:", err);
    res.status(500).json({ error: "Failed to load dashboard stats" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/users — Paginated, filterable user list
// ═══════════════════════════════════════════════════════════════════════════
router.get("/users", async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;
    const { role, department, status, search } = req.query;

    let where = "WHERE 1=1";
    const params = [];

    if (role) {
      where += " AND u.role = ?";
      params.push(role);
    }
    if (department) {
      where += " AND d.department_name = ?";
      params.push(department);
    }
    if (status) {
      where += " AND u.account_status = ?";
      params.push(status);
    }
    if (search) {
      where +=
        " AND (u.full_name LIKE ? OR u.university_id LIKE ? OR u.email LIKE ?)";
      params.push(`%${search}%`, `%${search}%`, `%${search}%`);
    }

    const [[{ total }]] = await db.query(
      `SELECT COUNT(*) as total FROM users u LEFT JOIN departments d ON d.department_id = u.department_id ${where}`,
      params,
    );

    const [users] = await db.query(
      `SELECT u.user_id, u.university_id, u.full_name, u.email, u.role,
              d.department_name as department, u.batch, u.phone, u.account_status, u.is_active,
              u.created_at
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       ${where}
       ORDER BY u.created_at DESC
       LIMIT ? OFFSET ?`,
      [...params, limit, offset],
    );

    res.json({
      users,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (err) {
    console.error("Admin users error:", err);
    res.status(500).json({ error: "Failed to load users" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/admin/users — Create new user
// ═══════════════════════════════════════════════════════════════════════════
router.post("/users", async (req, res) => {
  try {
    const {
      university_id,
      full_name,
      email,
      password,
      role,
      department,
      batch,
      phone,
    } = req.body;

    if (
      !university_id ||
      !full_name ||
      !email ||
      !password ||
      !role ||
      !department
    ) {
      return res.status(400).json({
        error:
          "Required fields: university_id, full_name, email, password, role, department",
      });
    }

    // Resolve department name/short_code to department_id
    const [deptRows] = await db.query(
      `SELECT department_id FROM departments WHERE department_name = ? OR short_code = ? LIMIT 1`,
      [department, department]
    );
    if (deptRows.length === 0) {
      return res.status(400).json({ error: "Invalid department specified" });
    }
    const departmentId = deptRows[0].department_id;

    const [result] = await db.query(
      `INSERT INTO users (university_id, full_name, email, password_hash, role, department_id, batch, phone)
       VALUES (?, ?, ?, SHA2(?, 256), ?, ?, ?, ?)`,
      [
        university_id,
        full_name,
        email,
        password,
        role,
        departmentId,
        batch || null,
        phone || null,
      ],
    );

    // If student, create student_profiles entry
    if (role === "STUDENT") {
      await db.query(`INSERT INTO student_profiles (student_id) VALUES (?)`, [
        result.insertId,
      ]);
    }

    res.json({
      success: true,
      user_id: result.insertId,
      message: "User created successfully",
    });
  } catch (err) {
    if (err.code === "ER_DUP_ENTRY") {
      return res
        .status(400)
        .json({ error: "University ID or email already exists" });
    }
    console.error("Create user error:", err);
    res.status(500).json({ error: "Failed to create user" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// PUT /api/admin/users/:id — Update user
// ═══════════════════════════════════════════════════════════════════════════
router.put("/users/:id", async (req, res) => {
  try {
    const { full_name, email, role, department, batch, phone, account_status, new_password } =
      req.body;
    const userId = req.params.id;

    // Server-side validation
    if (!full_name || !full_name.trim()) {
      return res.status(400).json({ error: "Full name is required" });
    }
    if (!email || !email.trim()) {
      return res.status(400).json({ error: "Email is required" });
    }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ error: "Invalid email format" });
    }
    if (!role || !['STUDENT', 'SUPERVISOR', 'COURSE_TEACHER', 'ADMIN'].includes(role)) {
      return res.status(400).json({ error: "Invalid role specified" });
    }
    if (account_status && !['ACTIVE', 'SUSPENDED', 'DEACTIVATED'].includes(account_status)) {
      return res.status(400).json({ error: "Invalid account status" });
    }

    // Resolve department name/short_code to department_id
    let departmentId = null;
    if (department) {
      const [deptRows] = await db.query(
        `SELECT department_id FROM departments WHERE department_name = ? OR short_code = ? LIMIT 1`,
        [department, department]
      );
      if (deptRows.length === 0) {
        return res.status(400).json({ error: "Invalid department specified" });
      }
      departmentId = deptRows[0].department_id;
    }

    await db.query(
      `UPDATE users SET full_name=?, email=?, role=?, department_id=COALESCE(?, department_id), batch=?, phone=?, account_status=?
       WHERE user_id=?`,
      [
        full_name.trim(),
        email.trim(),
        role,
        departmentId,
        batch || null,
        phone || null,
        account_status || 'ACTIVE',
        userId,
      ],
    );

    // Handle password reset if new_password is provided
    if (new_password && new_password.trim()) {
      if (new_password.length < 4) {
        return res.status(400).json({ error: "Password must be at least 4 characters" });
      }
      await db.query(
        `UPDATE users SET password_hash = SHA2(?, 256) WHERE user_id = ?`,
        [new_password, userId]
      );
    }

    res.json({ success: true, message: "User updated successfully" });
  } catch (err) {
    if (err.code === "ER_DUP_ENTRY") {
      return res
        .status(400)
        .json({ error: "Email or University ID already in use" });
    }
    console.error("Update user error:", err);
    res.status(500).json({ error: "Failed to update user" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// DELETE /api/admin/users/:id — Soft delete user
// ═══════════════════════════════════════════════════════════════════════════
router.delete("/users/:id", async (req, res) => {
  try {
    const targetId = parseInt(req.params.id);
    const currentUserId = req.session?.user?.user_id;

    // Prevent self-deactivation
    if (targetId === currentUserId) {
      return res.status(400).json({ error: "You cannot deactivate your own account" });
    }

    await db.query(
      `UPDATE users SET is_active = 0, deleted_at = NOW(), account_status = 'DEACTIVATED'
       WHERE user_id = ?`,
      [targetId],
    );
    res.json({ success: true, message: "User deactivated successfully" });
  } catch (err) {
    console.error("Delete user error:", err);
    res.status(500).json({ error: "Failed to deactivate user" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/groups — Paginated group list
// ═══════════════════════════════════════════════════════════════════════════
router.get("/groups", async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const offset = (page - 1) * limit;
    const { stage, section, status, supervisor, search } = req.query;

    let where = "WHERE 1=1";
    const params = [];

    if (stage) {
      where += " AND fs.stage_name = ?";
      params.push(stage);
    }
    if (section) {
      where += " AND s.section_code = ?";
      params.push(section);
    }
    if (status) {
      where += " AND pg.project_status = ?";
      params.push(status);
    }
    if (supervisor) {
      where += " AND pg.supervisor_id = ?";
      params.push(supervisor);
    }
    if (search) {
      where += " AND (pg.group_code LIKE ? OR pg.project_title LIKE ?)";
      params.push(`%${search}%`, `%${search}%`);
    }

    const [[{ total }]] = await db.query(
      `SELECT COUNT(*) as total FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN sections s ON s.section_id = pg.section_id ${where}`,
      params,
    );

    const [groups] = await db.query(
      `SELECT pg.*, fs.stage_name, pd.domain_name, u.full_name as supervisor_name,
              s.section_code,
              (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = pg.group_id) as member_count
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
       JOIN users u ON u.user_id = pg.supervisor_id
       JOIN sections s ON s.section_id = pg.section_id
       ${where}
       ORDER BY pg.created_at DESC LIMIT ? OFFSET ?`,
      [...params, limit, offset],
    );

    res.json({
      groups,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (err) {
    console.error("Admin groups error:", err);
    res.status(500).json({ error: "Failed to load groups" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/groups/:id/members — Group member details
// ═══════════════════════════════════════════════════════════════════════════
router.get("/groups/:id/members", async (req, res) => {
  try {
    const [members] = await db.query(
      `SELECT gm.*, u.full_name, u.university_id, u.email
       FROM group_members gm
       JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?`,
      [req.params.id],
    );
    res.json({ members });
  } catch (err) {
    res.status(500).json({ error: "Failed to load members" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/admin/promote-group — Call sp_promote_fydp_stage
// ═══════════════════════════════════════════════════════════════════════════
router.post("/promote-group", async (req, res) => {
  try {
    const {
      group_id,
      new_stage_id,
      new_domain_id,
      new_project_title,
      change_reason,
    } = req.body;
    const admin_id = req.session.user.user_id;

    const [result] = await db.query(
      "CALL sp_promote_fydp_stage(?, ?, ?, ?, ?, ?)",
      [
        group_id,
        new_stage_id,
        new_domain_id || null,
        new_project_title || null,
        admin_id,
        change_reason || "Stage promotion",
      ],
    );

    res.json({
      success: true,
      message: "Group promoted successfully",
      result: result[0],
    });
  } catch (err) {
    console.error("Promote error:", err);
    res.status(400).json({ error: err.message || "Promotion failed" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/audit-logs — Audit trail
// ═══════════════════════════════════════════════════════════════════════════
router.get("/audit-logs", async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 15;
    const offset = (page - 1) * limit;

    const [[{ total }]] = await db.query(
      "SELECT COUNT(*) as total FROM audit_log",
    );
    const [logs] = await db.query(
      `SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT ? OFFSET ?`,
      [limit, offset],
    );

    res.json({
      logs,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (err) {
    res.status(500).json({ error: "Failed to load audit logs" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/topic-history — Topic change history
// ═══════════════════════════════════════════════════════════════════════════
router.get("/topic-history", async (req, res) => {
  try {
    const [history] = await db.query(
      `SELECT tch.*, pg.group_code, u.full_name as admin_name,
              pd_old.domain_name as old_domain, pd_new.domain_name as new_domain
       FROM topic_change_history tch
       JOIN project_groups pg ON pg.group_id = tch.group_id
       JOIN users u ON u.user_id = tch.changed_by_admin
       LEFT JOIN project_domains pd_old ON pd_old.domain_id = tch.old_domain_id
       LEFT JOIN project_domains pd_new ON pd_new.domain_id = tch.new_domain_id
       ORDER BY tch.changed_at DESC LIMIT 50`,
    );
    res.json({ history });
  } catch (err) {
    res.status(500).json({ error: "Failed to load topic history" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/supervisors — Supervisor list (for dropdowns)
// ═══════════════════════════════════════════════════════════════════════════
router.get("/supervisors", async (req, res) => {
  try {
    const [supervisors] = await db.query(
      `SELECT u.user_id, u.full_name, d.department_name as department,
              COUNT(pg.group_id) as assigned_groups
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       LEFT JOIN project_groups pg ON pg.supervisor_id = u.user_id AND pg.is_active=1
       WHERE u.role='SUPERVISOR' AND u.is_active=1
       GROUP BY u.user_id
       ORDER BY u.full_name`,
    );
    res.json({ supervisors });
  } catch (err) {
    console.error('supervisors error:', err);
    res.status(500).json({ error: "Failed to load supervisors" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/course-teachers — Course teacher list (for dropdown)
// ═══════════════════════════════════════════════════════════════════════════
router.get('/course-teachers', async (req, res) => {
  try {
    const [teachers] = await db.query(
      `SELECT u.user_id, u.full_name, d.department_name as department,
              COUNT(DISTINCT cts.mapping_id) as assigned_sections
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       LEFT JOIN course_teacher_sections cts ON cts.course_teacher_id = u.user_id
       WHERE u.role='COURSE_TEACHER' AND u.is_active=1
       GROUP BY u.user_id
       ORDER BY u.full_name`
    );
    res.json({ teachers });
  } catch (err) {
    console.error('course-teachers error:', err);
    res.status(500).json({ error: 'Failed to load course teachers' });
  }
});

// GET /api/admin/assign-supervisor/groups — groups with their supervisor info
router.get("/assign-supervisor/groups", async (req, res) => {
  try {
    const { stage, search, unassigned } = req.query;
    let where = "WHERE pg.is_active=1";
    const params = [];
    if (stage) {
      where += " AND fs.stage_name=?";
      params.push(stage);
    }
    if (search) {
      where += " AND (pg.group_code LIKE ? OR u_sup.full_name LIKE ?)";
      params.push(`%${search}%`, `%${search}%`);
    }
    if (unassigned === "1") {
      where += " AND pg.supervisor_id IS NULL";
    }

    const [groups] = await db.query(
      `SELECT pg.group_id, pg.group_code, s.section_code,
              fs.stage_name, pd.domain_name,
              pg.supervisor_id,
              u_sup.full_name as supervisor_name,
              (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id=pg.group_id) as member_count
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id=pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id=pg.project_domain_id
       JOIN sections s ON s.section_id=pg.section_id
       LEFT JOIN users u_sup ON u_sup.user_id=pg.supervisor_id
       ${where}
       ORDER BY pg.group_code`,
      params,
    );
    res.json({ groups });
  } catch (err) {
    res.status(500).json({ error: "Failed to load groups" });
  }
});

// PUT /api/admin/assign-supervisor — assign supervisor to a group
router.put("/assign-supervisor", async (req, res) => {
  try {
    const { group_id, supervisor_id } = req.body;
    if (!group_id) return res.status(400).json({ error: "group_id required" });

    await db.query(
      "UPDATE project_groups SET supervisor_id=? WHERE group_id=?",
      [supervisor_id || null, group_id],
    );

    // Notify supervisor if assigned
    if (supervisor_id) {
      const [[grp]] = await db.query(
        "SELECT group_code FROM project_groups WHERE group_id=?",
        [group_id],
      );
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
        [
          supervisor_id,
          "📋 New Group Assigned",
          `Group ${grp?.group_code || ""} has been assigned to you by Admin.`,
        ],
      );
    }
    res.json({ success: true, message: "Supervisor assigned successfully" });
  } catch (err) {
    res.status(500).json({ error: "Failed to assign supervisor" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/stages — FYDP stages (for dropdowns)
// ═══════════════════════════════════════════════════════════════════════════
router.get("/stages", async (req, res) => {
  try {
    const [stages] = await db.query(
      "SELECT * FROM fydp_stages ORDER BY stage_order",
    );
    res.json({ stages });
  } catch (err) {
    res.status(500).json({ error: "Failed to load stages" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/domains — Project domains (for dropdowns)
// ═══════════════════════════════════════════════════════════════════════════
router.get("/domains", async (req, res) => {
  try {
    const [domains] = await db.query(
      "SELECT * FROM project_domains ORDER BY domain_name",
    );
    res.json({ domains });
  } catch (err) {
    res.status(500).json({ error: "Failed to load domains" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/sections — Distinct section codes
// ═══════════════════════════════════════════════════════════════════════════
router.get("/sections", async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT section_id, section_code FROM sections ORDER BY section_code`,
    );
    res.json({ sections: rows });
  } catch (err) {
    res.status(500).json({ error: "Failed to load sections" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/group-full/:id — Full group details for modal
// ═══════════════════════════════════════════════════════════════════════════
router.get("/group-full/:id", async (req, res) => {
  try {
    const [[group]] = await db.query(
      `SELECT pg.*, fs.stage_name, fs.stage_id, pd.domain_name,
              u.full_name as supervisor_name
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id = pg.project_domain_id
       LEFT JOIN users u ON u.user_id = pg.supervisor_id
       WHERE pg.group_id = ?`,
      [req.params.id],
    );
    const [members] = await db.query(
      `SELECT gm.member_role, u.full_name, u.university_id
       FROM group_members gm JOIN users u ON u.user_id = gm.student_id
       WHERE gm.group_id = ?`,
      [req.params.id],
    );
    res.json({ group, members });
  } catch (err) {
    res.status(500).json({ error: "Failed to load group details" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/import-errors — Import error logs
// ═══════════════════════════════════════════════════════════════════════════
router.get("/import-errors", async (req, res) => {
  try {
    const [errors] = await db.query(
      "SELECT * FROM import_error_logs ORDER BY logged_at DESC LIMIT 100",
    );
    res.json({ errors });
  } catch (err) {
    res.status(500).json({ error: "Failed to load import errors" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/admin/ucam-sync/student-status — UCAM Student Drop/Fail Sync
// When UCAM reports a student dropped or failed, update the system
// ═══════════════════════════════════════════════════════════════════════════
router.post("/ucam-sync/student-status", async (req, res) => {
  try {
    const { student_id, status } = req.body; // status: 'DROPPED' or 'FAILED'

    if (!student_id || !["DROPPED", "FAILED"].includes(status)) {
      return res
        .status(400)
        .json({ error: "student_id and status (DROPPED/FAILED) required" });
    }

    // Deactivate the student
    await db.query(
      "UPDATE users SET is_active = 0 WHERE user_id = ? AND role = ?",
      [student_id, "STUDENT"],
    );

    // Get student's group info before removing
    const [memberships] = await db.query(
      `SELECT gm.group_id, pg.group_code, pg.supervisor_id 
       FROM group_members gm
       JOIN project_groups pg ON pg.group_id = gm.group_id
       WHERE gm.student_id = ?`,
      [student_id],
    );

    // Get student name
    const [[student]] = await db.query(
      "SELECT full_name, university_id FROM users WHERE user_id = ?",
      [student_id],
    );

    // Remove from all groups
    await db.query("DELETE FROM group_members WHERE student_id = ?", [
      student_id,
    ]);

    // Notify supervisors
    for (const m of memberships) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
        [
          m.supervisor_id,
          `⚠️ Student ${status}`,
          `${student.full_name} (${student.university_id}) has ${status.toLowerCase()} from the course and has been removed from group ${m.group_code}.`,
        ],
      );
    }

    res.json({
      success: true,
      message: `Student marked as ${status} and removed from groups`,
    });
  } catch (err) {
    console.error("UCAM sync error:", err);
    res.status(500).json({ error: "Sync failed" });
  }
});

// POST /api/admin/ucam-sync/group — UCAM Group Auto-Sync
// When supervisor accepts a group on UCAM, this endpoint is called
// to automatically create the group in our system (no manual approval needed)
router.post("/ucam-sync/group", async (req, res) => {
  try {
    const {
      group_code,
      project_title,
      domain_name,
      stage_name,
      section_code,
      supervisor_id,
      student_ids,
    } = req.body;

    if (!group_code || !project_title || !supervisor_id) {
      return res.status(400).json({
        error: "group_code, project_title, and supervisor_id required",
      });
    }

    // Check if group already exists (prevent duplicates)
    const [[existing]] = await db.query(
      "SELECT group_id FROM project_groups WHERE group_code = ?",
      [group_code],
    );
    if (existing) {
      return res
        .status(409)
        .json({ error: `Group ${group_code} already exists` });
    }

    // Resolve stage ID
    const [[stage]] = await db.query(
      "SELECT stage_id FROM fydp_stages WHERE stage_name = ?",
      [stage_name || "FYDP-1"],
    );

    // Resolve domain ID
    let domainId = 1;
    if (domain_name) {
      const [[domain]] = await db.query(
        "SELECT domain_id FROM project_domains WHERE domain_name = ?",
        [domain_name],
      );
      if (domain) domainId = domain.domain_id;
    }

    // Resolve section ID from section_code
    let sectionId = null;
    if (section_code) {
      const [[sec]] = await db.query(
        'SELECT section_id FROM sections WHERE section_code = ?', [section_code]
      );
      if (sec) sectionId = sec.section_id;
    }

    // Create the group directly — already accepted on UCAM
    const [insertResult] = await db.query(
      `INSERT INTO project_groups (group_code, project_title, project_domain_id, supervisor_id, current_stage_id, section_id)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        group_code,
        project_title,
        domainId,
        supervisor_id,
        stage.stage_id,
        sectionId,
      ],
    );

    const groupId = insertResult.insertId;

    // Add students to group
    if (student_ids) {
      const ids = student_ids
        .split(",")
        .map((id) => parseInt(id.trim()))
        .filter((id) => !isNaN(id));
      for (let i = 0; i < ids.length; i++) {
        try {
          await db.query(
            "INSERT INTO group_members (group_id, student_id, member_role) VALUES (?, ?, ?)",
            [groupId, ids[i], i === 0 ? "LEADER" : "MEMBER"],
          );
          // Notify student
          await db.query(
            `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
            [
              ids[i],
              "✅ Group Confirmed",
              `You have been added to group ${group_code} — "${project_title}". Check your dashboard for details.`,
            ],
          );
        } catch (e) {
          /* skip if already exists */
        }
      }
    }

    // Notify supervisor
    await db.query(
      `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
      [
        supervisor_id,
        "📋 New Group Synced from UCAM",
        `Group "${project_title}" (${group_code}) has been synced from UCAM and is now active in your dashboard.`,
      ],
    );

    res.json({
      success: true,
      message: "Group synced and created",
      group_id: groupId,
    });
  } catch (err) {
    console.error("UCAM group sync error:", err);
    res.status(500).json({ error: err.message || "Failed to sync group" });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/admin/teacher-sections — all current teacher-section mappings
// ═══════════════════════════════════════════════════════════════════════════
router.get('/teacher-sections', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT cts.mapping_id, cts.course_teacher_id, cts.assigned_stage_id,
              s.section_code, s.section_id,
              u.full_name as teacher_name, d.department_name as department,
              fs.stage_name,
              COUNT(DISTINCT pg.group_id) as group_count
       FROM course_teacher_sections cts
       JOIN users u ON u.user_id = cts.course_teacher_id
       LEFT JOIN departments d ON d.department_id = u.department_id
       JOIN fydp_stages fs ON fs.stage_id = cts.assigned_stage_id
       JOIN sections s ON s.section_id = cts.section_id
       LEFT JOIN project_groups pg ON pg.section_id = cts.section_id AND pg.is_active=1
       GROUP BY cts.mapping_id
       ORDER BY fs.stage_order, s.section_code, u.full_name`
    );
    res.json({ mappings: rows });
  } catch (err) {
    console.error('teacher-sections error:', err);
    res.status(500).json({ error: 'Failed to load teacher sections' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// POST /api/admin/assign-teacher — assign teacher to section+stage
// ═══════════════════════════════════════════════════════════════════════════
router.post('/assign-teacher', async (req, res) => {
  try {
    const { teacher_id, section_code, stage_id } = req.body;
    if (!teacher_id || !section_code || !stage_id)
      return res.status(400).json({ error: 'teacher_id, section_code, stage_id required' });

    // Resolve section_id from section_code
    const [[sec]] = await db.query(
      'SELECT section_id FROM sections WHERE section_code = ?', [section_code]
    );
    if (!sec) return res.status(404).json({ error: `Section '${section_code}' not found` });

    await db.query(
      `INSERT INTO course_teacher_sections (course_teacher_id, section_id, assigned_stage_id)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE assigned_stage_id = VALUES(assigned_stage_id)`,
      [teacher_id, sec.section_id, stage_id]
    );

    const [[st]] = await db.query('SELECT stage_name FROM fydp_stages WHERE stage_id=?', [stage_id]);
    await db.query(
      `INSERT INTO notifications (user_id, notification_type, title, message) VALUES (?, 'SYSTEM_ALERT', ?, ?)`,
      [teacher_id, '📋 Section Assigned', `You have been assigned to section ${section_code} (${st?.stage_name}) by Admin.`]
    );

    res.json({ success: true, message: 'Teacher assigned to section' });
  } catch (err) {
    console.error('Assign teacher error:', err);
    res.status(500).json({ error: 'Failed to assign teacher' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// DELETE /api/admin/teacher-sections/:id — remove a mapping
// ═══════════════════════════════════════════════════════════════════════════
router.delete('/teacher-sections/:id', async (req, res) => {
  try {
    await db.query('DELETE FROM course_teacher_sections WHERE mapping_id=?', [req.params.id]);
    res.json({ success: true, message: 'Assignment removed' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to remove assignment' });
  }
});

module.exports = router;

const express = require('express');
const router = express.Router();
const db = require('../config/db');

// ── Dashboard Stats ────────────────────────────────────────────────────────
router.get('/dashboard-stats', async (req, res) => {
  try {
    const userId = req.session.user.user_id;

    // Open groups count
    const [[{ open_groups }]] = await db.query(
      `SELECT COUNT(*) as open_groups FROM pre_fydp_groups WHERE group_status = 'OPEN'`
    );

    // Distinct domains for open groups
    const [[{ domain_count }]] = await db.query(
      `SELECT COUNT(DISTINCT domain_id) as domain_count FROM pre_fydp_groups WHERE group_status = 'OPEN'`
    );

    // Pending outgoing requests
    const [[{ pending_requests }]] = await db.query(
      `SELECT COUNT(*) as pending_requests FROM pre_fydp_join_requests 
       WHERE sender_id = ? AND request_status = 'PENDING'`, [userId]
    );

    // Incoming requests (for groups I created)
    const [[{ incoming_requests }]] = await db.query(
      `SELECT COUNT(*) as incoming_requests FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       WHERE g.created_by = ? AND jr.request_status = 'PENDING' AND jr.sender_id != ?`,
      [userId, userId]
    );

    // Profile strength
    const [profileRows] = await db.query(
      `SELECT profile_strength FROM pre_fydp_profiles WHERE user_id = ?`, [userId]
    );
    const profile_strength = profileRows.length > 0 ? profileRows[0].profile_strength : 0;

    res.json({
      open_groups,
      domain_count,
      pending_requests,
      incoming_requests,
      profile_strength
    });
  } catch (err) {
    console.error('Pre-FYDP dashboard stats error:', err);
    res.status(500).json({ error: 'Failed to load dashboard stats' });
  }
});

// ── My Group Status (am I in any group?) ──────────────────────────────────
router.get('/my-group-status', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const [rows] = await db.query(
      `SELECT gm.group_id, g.group_name FROM pre_fydp_group_members gm
       JOIN pre_fydp_groups g ON gm.group_id = g.group_id
       WHERE gm.user_id = ?`, [userId]
    );
    if (rows.length > 0) {
      res.json({ in_team: true, group_id: rows[0].group_id, group_name: rows[0].group_name });
    } else {
      res.json({ in_team: false, group_id: null, group_name: null });
    }
  } catch (err) {
    res.status(500).json({ error: 'Failed to check group status' });
  }
});

// ── List All Open Groups ───────────────────────────────────────────────────

router.get('/groups', async (req, res) => {
  try {
    const { domain, skill, search } = req.query;

    let sql = `
      SELECT g.group_id, g.group_name, pd.domain_name as domain, g.description,
             g.max_members, g.github_url, g.created_by, g.group_status, g.created_at,
             u.full_name as creator_name, d.short_code as creator_dept,
             (SELECT COUNT(*) FROM pre_fydp_group_members gm WHERE gm.group_id = g.group_id) as member_count
      FROM pre_fydp_groups g
      JOIN users u ON g.created_by = u.user_id
      JOIN departments d ON u.department_id = d.department_id
      JOIN project_domains pd ON g.domain_id = pd.domain_id
      WHERE 1=1
    `;
    const params = [];

    if (domain && domain !== 'All Domains') {
      sql += ` AND pd.domain_name = ?`;
      params.push(domain);
    }
    if (skill && skill !== 'All Skills') {
      sql += ` AND g.group_id IN (
        SELECT pgrs.group_id FROM pre_fydp_group_required_skills pgrs
        JOIN skills s ON pgrs.skill_id = s.skill_id
        WHERE s.skill_name = ?
      )`;
      params.push(skill);
    }
    if (search) {
      sql += ` AND (g.group_name LIKE ? OR g.description LIKE ? OR u.full_name LIKE ?)`;
      params.push(`%${search}%`, `%${search}%`, `%${search}%`);
    }
    sql += ` ORDER BY g.created_at DESC`;

    const [groups] = await db.query(sql, params);

    // Get members and skills for each group
    for (const group of groups) {
      const [members] = await db.query(
        `SELECT gm.member_id, gm.user_id, gm.member_role, u.full_name, d.short_code as department 
         FROM pre_fydp_group_members gm
         JOIN users u ON gm.user_id = u.user_id
         JOIN departments d ON u.department_id = d.department_id
         WHERE gm.group_id = ?`, [group.group_id]
      );
      group.members = members;

      // Find lead
      const lead = members.find(m => m.member_role === 'Lead');
      group.lead_name = lead ? lead.full_name : group.creator_name;

      // Get required skills
      const [skillRows] = await db.query(
        `SELECT s.skill_name FROM pre_fydp_group_required_skills pgrs
         JOIN skills s ON pgrs.skill_id = s.skill_id
         WHERE pgrs.group_id = ?`, [group.group_id]
      );
      group.required_skills = skillRows.map(s => s.skill_name);
    }

    res.json(groups);
  } catch (err) {
    console.error('Pre-FYDP list groups error:', err);
    res.status(500).json({ error: 'Failed to load groups' });
  }
});

// ── Get Unique Domains ─────────────────────────────────────────────────────
router.get('/domains', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT DISTINCT pd.domain_name 
       FROM project_domains pd
       ORDER BY pd.domain_name`
    );
    res.json(rows.map(r => r.domain_name));
  } catch (err) {
    res.status(500).json({ error: 'Failed to load domains' });
  }
});

// ── Get All Skills ─────────────────────────────────────────────────────────
router.get('/skills', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT skill_id, skill_name, skill_category FROM skills ORDER BY skill_name`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to load skills' });
  }
});

// ── Create Group ───────────────────────────────────────────────────────────
router.post('/groups', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { group_name, domain, description, required_skills, max_members, github_url } = req.body;

    if (!group_name || !domain) {
      return res.status(400).json({ error: 'Group name and domain are required' });
    }

    // Block if user is already in any group (as member or creator)
    const [alreadyIn] = await db.query(
      `SELECT gm.group_id, g.group_name FROM pre_fydp_group_members gm
       JOIN pre_fydp_groups g ON gm.group_id = g.group_id
       WHERE gm.user_id = ?`, [userId]
    );
    if (alreadyIn.length > 0) {
      return res.status(400).json({
        error: `You are already in the group "${alreadyIn[0].group_name}". You cannot create another group.`
      });
    }

    // Resolve domain_id
    const [domainRows] = await db.query(
      `SELECT domain_id FROM project_domains WHERE domain_name = ?`, [domain]
    );
    if (domainRows.length === 0) {
      return res.status(400).json({ error: 'Invalid domain selected' });
    }
    const domain_id = domainRows[0].domain_id;


    const [result] = await db.query(
      `INSERT INTO pre_fydp_groups (group_name, domain_id, description, max_members, github_url, created_by)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [group_name, domain_id, description || null, max_members || 5, github_url || null, userId]
    );

    const groupId = result.insertId;

    // Add creator as lead member
    await db.query(
      `INSERT INTO pre_fydp_group_members (group_id, user_id, member_role) VALUES (?, ?, 'Lead')`,
      [groupId, userId]
    );

    // Add required skills if provided
    if (required_skills && Array.isArray(required_skills) && required_skills.length > 0) {
      for (const skillName of required_skills) {
        // Find or insert skill
        const [existingSkill] = await db.query(
          `SELECT skill_id FROM skills WHERE skill_name = ?`, [skillName.trim()]
        );
        let skill_id;
        if (existingSkill.length > 0) {
          skill_id = existingSkill[0].skill_id;
        } else {
          const [newSkill] = await db.query(
            `INSERT INTO skills (skill_name, skill_category) VALUES (?, 'Other')`, [skillName.trim()]
          );
          skill_id = newSkill.insertId;
        }
        await db.query(
          `INSERT IGNORE INTO pre_fydp_group_required_skills (group_id, skill_id) VALUES (?, ?)`,
          [groupId, skill_id]
        ).catch(() => {}); // ignore duplicates
      }
    }

    // Update user profile to IN_TEAM
    await db.query(
      `UPDATE pre_fydp_profiles SET availability_status = 'IN_TEAM' WHERE user_id = ?`,
      [userId]
    ).catch(() => {});

    res.json({ success: true, group_id: groupId, message: 'Group created successfully!' });
  } catch (err) {
    console.error('Pre-FYDP create group error:', err);
    res.status(500).json({ error: 'Failed to create group' });
  }
});

// ── Send Join Request ──────────────────────────────────────────────────────
router.post('/join-request', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { group_id, message } = req.body;

    // Check if already a member of THIS group
    const [existing] = await db.query(
      `SELECT * FROM pre_fydp_group_members WHERE group_id = ? AND user_id = ?`,
      [group_id, userId]
    );
    if (existing.length > 0) {
      return res.status(400).json({ error: 'You are already a member of this group' });
    }

    // Block if already a member of ANY group
    const [anyGroup] = await db.query(
      `SELECT gm.group_id, g.group_name FROM pre_fydp_group_members gm
       JOIN pre_fydp_groups g ON gm.group_id = g.group_id
       WHERE gm.user_id = ?`, [userId]
    );
    if (anyGroup.length > 0) {
      return res.status(400).json({
        error: `You are already a member of "${anyGroup[0].group_name}". Leave that group first before joining another.`
      });
    }

    // Check if already has a pending request

    const [pendingReq] = await db.query(
      `SELECT * FROM pre_fydp_join_requests 
       WHERE group_id = ? AND sender_id = ? AND request_status = 'PENDING'`,
      [group_id, userId]
    );
    if (pendingReq.length > 0) {
      return res.status(400).json({ error: 'You already have a pending request for this group' });
    }

    // Check if group is full
    const [[group]] = await db.query(
      `SELECT g.max_members, 
              (SELECT COUNT(*) FROM pre_fydp_group_members gm WHERE gm.group_id = g.group_id) as member_count
       FROM pre_fydp_groups g WHERE g.group_id = ?`, [group_id]
    );
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.member_count >= group.max_members) {
      return res.status(400).json({ error: 'This group is already full' });
    }

    await db.query(
      `INSERT INTO pre_fydp_join_requests (group_id, sender_id, message) VALUES (?, ?, ?)`,
      [group_id, userId, message || null]
    );

    res.json({ success: true, message: 'Join request sent!' });
  } catch (err) {
    console.error('Pre-FYDP join request error:', err);
    res.status(500).json({ error: 'Failed to send join request' });
  }
});

// ── My Requests (Sent & Received) ──────────────────────────────────────────
router.get('/my-requests', async (req, res) => {
  try {
    const userId = req.session.user.user_id;

    // Sent requests
    const [sent] = await db.query(
      `SELECT jr.request_id, jr.group_id, jr.sender_id, jr.request_type, jr.message, jr.request_status, jr.created_at,
              g.group_name, pd.domain_name as domain, u.full_name as group_lead
       FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       JOIN project_domains pd ON g.domain_id = pd.domain_id
       JOIN users u ON g.created_by = u.user_id
       WHERE jr.sender_id = ?
       ORDER BY jr.created_at DESC`, [userId]
    );

    // Received requests (for groups I own) — both JOIN and LEAVE
    const [received] = await db.query(
      `SELECT jr.request_id, jr.group_id, jr.sender_id, jr.request_type, jr.message, jr.request_status, jr.created_at,
              g.group_name, pd.domain_name as domain,
              u.full_name as sender_name, d.short_code as sender_dept,
              p.preferred_role
       FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       JOIN project_domains pd ON g.domain_id = pd.domain_id
       JOIN users u ON jr.sender_id = u.user_id
       JOIN departments d ON u.department_id = d.department_id
       LEFT JOIN pre_fydp_profiles p ON jr.sender_id = p.user_id
       WHERE g.created_by = ? AND jr.sender_id != ?
       ORDER BY jr.created_at DESC`, [userId, userId]
    );

    // Enrich received with sender skills (from pivot table)
    for (const req of received) {
      const [skillRows] = await db.query(
        `SELECT s.skill_name FROM pre_fydp_student_skills pss
         JOIN skills s ON pss.skill_id = s.skill_id
         WHERE pss.user_id = ?`, [req.sender_id]
      );
      req.sender_skills = skillRows.map(s => s.skill_name);
    }

    res.json({ sent, received });
  } catch (err) {
    console.error('Pre-FYDP my requests error:', err);
    res.status(500).json({ error: 'Failed to load requests' });
  }
});

// ── Accept/Reject Join Request ─────────────────────────────────────────────
router.patch('/join-request/:id', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { id } = req.params;
    const { action } = req.body; // 'accept' or 'reject'

    // Verify ownership
    const [rows] = await db.query(
      `SELECT jr.*, g.created_by, g.max_members,
              (SELECT COUNT(*) FROM pre_fydp_group_members gm WHERE gm.group_id = g.group_id) as member_count
       FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       WHERE jr.request_id = ?`, [id]
    );

    if (rows.length === 0) return res.status(404).json({ error: 'Request not found' });
    const request = rows[0];

    if (request.created_by !== userId) {
      return res.status(403).json({ error: 'Only the group owner can accept/reject requests' });
    }

    if (action === 'accept') {
      if (request.member_count >= request.max_members) {
        return res.status(400).json({ error: 'Group is already full' });
      }
      // Add to group members
      await db.query(
        `INSERT IGNORE INTO pre_fydp_group_members (group_id, user_id, member_role) VALUES (?, ?, 'Other')`,
        [request.group_id, request.sender_id]
      );
      // Update status
      await db.query(
        `UPDATE pre_fydp_join_requests SET request_status = 'ACCEPTED', responded_at = NOW() WHERE request_id = ?`,
        [id]
      );

      // Update sender profile to IN_TEAM
      await db.query(
        `UPDATE pre_fydp_profiles SET availability_status = 'IN_TEAM' WHERE user_id = ?`,
        [request.sender_id]
      ).catch(() => {});

      // Auto-cancel all other pending join requests from this user
      await db.query(
        `UPDATE pre_fydp_join_requests
         SET request_status = 'CANCELLED', responded_at = NOW()
         WHERE sender_id = ? AND request_id != ? AND request_status = 'PENDING' AND request_type = 'JOIN_REQUEST'`,
        [request.sender_id, id]
      );

      // Check if group is now full and update status
      const [[{ new_count }]] = await db.query(
        `SELECT COUNT(*) as new_count FROM pre_fydp_group_members WHERE group_id = ?`,
        [request.group_id]
      );
      if (new_count >= request.max_members) {
        await db.query(
          `UPDATE pre_fydp_groups SET group_status = 'FULL' WHERE group_id = ?`,
          [request.group_id]
        );
      }
    } else {
      await db.query(
        `UPDATE pre_fydp_join_requests SET request_status = 'REJECTED', responded_at = NOW() WHERE request_id = ?`,
        [id]
      );
    }

    // ── Send notification to the requester ────────────────────────────────
    // Fetch group name for the notification message
    const [[grpInfo]] = await db.query(
      `SELECT g.group_name, u.full_name as owner_name
       FROM pre_fydp_groups g JOIN users u ON g.created_by = u.user_id
       WHERE g.group_id = ?`, [request.group_id]
    );

    if (grpInfo) {
      const notifType = action === 'accept' ? 'INVITATION_ACCEPTED' : 'INVITATION_REJECTED';
      const notifTitle = action === 'accept'
        ? `🎉 Request Accepted — ${grpInfo.group_name}`
        : `Request Rejected — ${grpInfo.group_name}`;
      const notifMsg = action === 'accept'
        ? `${grpInfo.owner_name} accepted your request to join "${grpInfo.group_name}". Welcome to the team!`
        : `${grpInfo.owner_name} declined your request to join "${grpInfo.group_name}".`;

      await db.query(
        `INSERT INTO notifications
           (user_id, notification_type, title, message, reference_entity_id, reference_entity_type, is_read)
         VALUES (?, ?, ?, ?, ?, 'pre_fydp_join_requests', 0)`,
        [request.sender_id, notifType, notifTitle, notifMsg, id]
      ).catch(err => console.error('Notification insert failed:', err.message));
    }

    res.json({ success: true, message: `Request ${action}ed successfully` });
  } catch (err) {
    console.error('Pre-FYDP accept/reject error:', err);
    res.status(500).json({ error: 'Failed to update request' });
  }
});

// ── Find Teammates (Solo Students) ─────────────────────────────────────────
router.get('/teammates', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { domain, skill } = req.query;

    let sql = `
      SELECT u.user_id, u.full_name, d.short_code as department, u.batch, 
             p.bio, p.cgpa, p.preferred_role,
             p.github_url, p.linkedin_url, p.availability_status, p.profile_strength
      FROM users u
      JOIN pre_fydp_profiles p ON u.user_id = p.user_id
      JOIN departments d ON u.department_id = d.department_id
      WHERE u.role = 'PRE_FYDP_STUDENT' AND u.user_id != ? AND u.account_status = 'ACTIVE'
            AND p.availability_status = 'LOOKING'
    `;
    const params = [userId];

    if (domain && domain !== 'All Domains') {
      sql += ` AND u.user_id IN (
        SELECT pdi.user_id FROM pre_fydp_student_domain_interests pdi
        JOIN project_domains pd ON pdi.domain_id = pd.domain_id
        WHERE pd.domain_name = ?
      )`;
      params.push(domain);
    }
    if (skill && skill !== 'All Skills') {
      sql += ` AND u.user_id IN (
        SELECT pss.user_id FROM pre_fydp_student_skills pss
        JOIN skills s ON pss.skill_id = s.skill_id
        WHERE s.skill_name = ?
      )`;
      params.push(skill);
    }

    sql += ` ORDER BY p.profile_strength DESC`;
    const [students] = await db.query(sql, params);

    // Enrich each student with their skills and domain interests
    for (const student of students) {
      const [skillRows] = await db.query(
        `SELECT s.skill_name FROM pre_fydp_student_skills pss
         JOIN skills s ON pss.skill_id = s.skill_id
         WHERE pss.user_id = ?`, [student.user_id]
      );
      student.skills = skillRows.map(s => s.skill_name);

      const [domainRows] = await db.query(
        `SELECT pd.domain_name FROM pre_fydp_student_domain_interests pdi
         JOIN project_domains pd ON pdi.domain_id = pd.domain_id
         WHERE pdi.user_id = ?`, [student.user_id]
      );
      student.domain_interests = domainRows.map(d => d.domain_name);
    }

    res.json(students);
  } catch (err) {
    console.error('Pre-FYDP find teammates error:', err);
    res.status(500).json({ error: 'Failed to load teammates' });
  }
});

// ── Get My Profile ─────────────────────────────────────────────────────────
router.get('/profile', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const [rows] = await db.query(
      `SELECT u.full_name, u.email, d.short_code as department, u.batch, u.phone,
              p.profile_id, p.bio, p.cgpa, p.preferred_role, p.github_url, p.linkedin_url,
              p.portfolio_url, p.availability_status, p.profile_strength
       FROM users u
       JOIN departments d ON u.department_id = d.department_id
       LEFT JOIN pre_fydp_profiles p ON u.user_id = p.user_id
       WHERE u.user_id = ?`, [userId]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'User not found' });
    
    const profile = rows[0];

    // Get skills from pivot table
    const [skillRows] = await db.query(
      `SELECT s.skill_name FROM pre_fydp_student_skills pss
       JOIN skills s ON pss.skill_id = s.skill_id
       WHERE pss.user_id = ?`, [userId]
    );
    profile.skills = skillRows.map(s => s.skill_name);

    // Get domain interests from pivot table
    const [domainRows] = await db.query(
      `SELECT pd.domain_name FROM pre_fydp_student_domain_interests pdi
       JOIN project_domains pd ON pdi.domain_id = pd.domain_id
       WHERE pdi.user_id = ?`, [userId]
    );
    profile.domain_interests = domainRows.map(d => d.domain_name);

    res.json(profile);
  } catch (err) {
    console.error('Pre-FYDP profile error:', err);
    res.status(500).json({ error: 'Failed to load profile' });
  }
});

// ── Update Profile ─────────────────────────────────────────────────────────
router.put('/profile', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { bio, cgpa, skills, domain_interests, preferred_role, github_url, linkedin_url, portfolio_url } = req.body;

    // Calculate profile strength
    let strength = 10; // base
    if (bio) strength += 15;
    if (cgpa) strength += 10;
    if (skills && skills.length > 0) strength += 20;
    if (domain_interests && domain_interests.length > 0) strength += 15;
    if (preferred_role) strength += 10;
    if (github_url) strength += 10;
    if (linkedin_url) strength += 5;
    if (portfolio_url) strength += 5;
    strength = Math.min(strength, 100);

    // Map preferred_role from display name to enum value if needed
    const roleMap = {
      'Frontend Developer': 'FRONTEND_DEVELOPER',
      'Backend Developer': 'BACKEND_DEVELOPER',
      'Full-stack Developer': 'FULL_STACK_DEVELOPER',
      'ML Engineer': 'ML_ENGINEER',
      'Security Analyst': 'SECURITY_ANALYST',
      'Embedded Developer': 'EMBEDDED_DEVELOPER',
      'UI/UX Designer': 'UI_UX_DESIGNER',
      'Data Analyst': 'DATA_SCIENTIST',
      'DevOps Engineer': 'DEVOPS_ENGINEER'
    };
    const roleEnum = roleMap[preferred_role] || preferred_role || null;

    // Upsert profile
    const [existing] = await db.query(
      `SELECT profile_id FROM pre_fydp_profiles WHERE user_id = ?`, [userId]
    );

    if (existing.length > 0) {
      await db.query(
        `UPDATE pre_fydp_profiles SET bio=?, cgpa=?, preferred_role=?, 
         github_url=?, linkedin_url=?, portfolio_url=?, profile_strength=?
         WHERE user_id = ?`,
        [bio || null, cgpa || null, roleEnum, github_url || null, linkedin_url || null, portfolio_url || null, strength, userId]
      );
    } else {
      await db.query(
        `INSERT INTO pre_fydp_profiles 
         (user_id, bio, cgpa, preferred_role, github_url, linkedin_url, portfolio_url, profile_strength)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [userId, bio || null, cgpa || null, roleEnum, github_url || null, linkedin_url || null, portfolio_url || null, strength]
      );
    }

    // Update skills — replace all existing
    if (skills !== undefined) {
      await db.query(`DELETE FROM pre_fydp_student_skills WHERE user_id = ?`, [userId]);
      if (Array.isArray(skills) && skills.length > 0) {
        for (const skillName of skills) {
          const trimmed = skillName.trim();
          if (!trimmed) continue;
          // Find or create skill
          let [existingSkill] = await db.query(
            `SELECT skill_id FROM skills WHERE skill_name = ?`, [trimmed]
          );
          let skill_id;
          if (existingSkill.length > 0) {
            skill_id = existingSkill[0].skill_id;
          } else {
            const [newSkill] = await db.query(
              `INSERT INTO skills (skill_name, skill_category) VALUES (?, 'Other')`, [trimmed]
            );
            skill_id = newSkill.insertId;
          }
          await db.query(
            `INSERT IGNORE INTO pre_fydp_student_skills (user_id, skill_id, proficiency_level) VALUES (?, ?, 'INTERMEDIATE')`,
            [userId, skill_id]
          );
        }
      }
    }

    // Update domain interests — replace all existing
    if (domain_interests !== undefined) {
      await db.query(`DELETE FROM pre_fydp_student_domain_interests WHERE user_id = ?`, [userId]);
      if (Array.isArray(domain_interests) && domain_interests.length > 0) {
        for (const domainName of domain_interests) {
          const trimmed = domainName.trim();
          if (!trimmed) continue;
          const [domRows] = await db.query(
            `SELECT domain_id FROM project_domains WHERE domain_name = ?`, [trimmed]
          );
          if (domRows.length > 0) {
            await db.query(
              `INSERT IGNORE INTO pre_fydp_student_domain_interests (user_id, domain_id, interest_level) VALUES (?, ?, 'HIGH')`,
              [userId, domRows[0].domain_id]
            );
          }
        }
      }
    }

    res.json({ success: true, profile_strength: strength, message: 'Profile updated!' });
  } catch (err) {
    console.error('Pre-FYDP update profile error:', err);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// ── Cancel Sent Request ────────────────────────────────────────────────────
router.delete('/join-request/:id', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { id } = req.params;

    const [result] = await db.query(
      `UPDATE pre_fydp_join_requests SET request_status = 'CANCELLED' 
       WHERE request_id = ? AND sender_id = ? AND request_status = 'PENDING'`,
      [id, userId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Request not found or already processed' });
    }

    res.json({ success: true, message: 'Request cancelled' });
  } catch (err) {
    console.error('Pre-FYDP cancel request error:', err);
    res.status(500).json({ error: 'Failed to cancel request' });
  }
});

// ── Send Leave Request ─────────────────────────────────────────────────────
router.post('/leave-request', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { group_id, message } = req.body;

    // Verify user is actually in this group
    const [membership] = await db.query(
      `SELECT * FROM pre_fydp_group_members WHERE group_id = ? AND user_id = ?`,
      [group_id, userId]
    );
    if (membership.length === 0) {
      return res.status(400).json({ error: 'You are not a member of this group' });
    }

    // Block if user is the Lead (owner) — leader cannot leave their own group
    if (membership[0].member_role === 'Lead') {
      return res.status(400).json({ error: 'As the group leader, you cannot leave your own group. You can delete the group instead.' });
    }

    // Check if already has a pending leave request
    const [pending] = await db.query(
      `SELECT * FROM pre_fydp_join_requests
       WHERE group_id = ? AND sender_id = ? AND request_type = 'LEAVE_REQUEST' AND request_status = 'PENDING'`,
      [group_id, userId]
    );
    if (pending.length > 0) {
      return res.status(400).json({ error: 'You already have a pending leave request for this group' });
    }

    await db.query(
      `INSERT INTO pre_fydp_join_requests (group_id, sender_id, request_type, message)
       VALUES (?, ?, 'LEAVE_REQUEST', ?)`,
      [group_id, userId, message || 'I would like to leave this group.']
    );

    // Notify the group leader
    const [[groupInfo]] = await db.query(
      `SELECT g.created_by, g.group_name, u.full_name as sender_name
       FROM pre_fydp_groups g, users u
       WHERE g.group_id = ? AND u.user_id = ?`, [group_id, userId]
    );
    if (groupInfo) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type, is_read)
         VALUES (?, 'LEAVE_REQUEST', ?, ?, ?, 'pre_fydp_join_requests', 0)`,
        [groupInfo.created_by, `🚪 Leave Request — ${groupInfo.group_name}`,
         `${groupInfo.sender_name} wants to leave your group "${groupInfo.group_name}". Review the request.`,
         group_id]
      ).catch(() => {});
    }

    res.json({ success: true, message: 'Leave request sent to the group leader!' });
  } catch (err) {
    console.error('Pre-FYDP leave request error:', err);
    res.status(500).json({ error: 'Failed to send leave request' });
  }
});

// ── Accept/Reject Leave Request ────────────────────────────────────────────
router.patch('/leave-request/:id', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    const { id } = req.params;
    const { action } = req.body; // 'accept' or 'reject'

    // Get the request and verify ownership
    const [rows] = await db.query(
      `SELECT jr.*, g.created_by, g.group_name
       FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       WHERE jr.request_id = ? AND jr.request_type = 'LEAVE_REQUEST'`, [id]
    );

    if (rows.length === 0) return res.status(404).json({ error: 'Leave request not found' });
    const request = rows[0];

    if (request.created_by !== userId) {
      return res.status(403).json({ error: 'Only the group leader can approve leave requests' });
    }

    if (request.request_status !== 'PENDING') {
      return res.status(400).json({ error: 'This request has already been processed' });
    }

    if (action === 'accept') {
      // Remove the member from the group
      await db.query(
        `DELETE FROM pre_fydp_group_members WHERE group_id = ? AND user_id = ?`,
        [request.group_id, request.sender_id]
      );

      // Update request status
      await db.query(
        `UPDATE pre_fydp_join_requests SET request_status = 'ACCEPTED', responded_at = NOW() WHERE request_id = ?`, [id]
      );

      // Reset their profile to AVAILABLE
      await db.query(
        `UPDATE pre_fydp_profiles SET availability_status = 'AVAILABLE' WHERE user_id = ?`,
        [request.sender_id]
      ).catch(() => {});

      // If group was FULL, re-open it
      await db.query(
        `UPDATE pre_fydp_groups SET group_status = 'OPEN' WHERE group_id = ? AND group_status = 'FULL'`,
        [request.group_id]
      ).catch(() => {});

      // Notify the member that they've been released
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type, is_read)
         VALUES (?, 'LEAVE_APPROVED', ?, ?, ?, 'pre_fydp_join_requests', 0)`,
        [request.sender_id,
         `✅ Leave Approved — ${request.group_name}`,
         `Your request to leave "${request.group_name}" has been approved. You are now free to join or create another group.`,
         id]
      ).catch(() => {});

    } else {
      // Reject — member stays in the group
      await db.query(
        `UPDATE pre_fydp_join_requests SET request_status = 'REJECTED', responded_at = NOW() WHERE request_id = ?`, [id]
      );

      // Notify the member
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type, is_read)
         VALUES (?, 'LEAVE_REJECTED', ?, ?, ?, 'pre_fydp_join_requests', 0)`,
        [request.sender_id,
         `❌ Leave Denied — ${request.group_name}`,
         `Your request to leave "${request.group_name}" was declined by the group leader.`,
         id]
      ).catch(() => {});
    }

    res.json({ success: true, message: `Leave request ${action}ed successfully` });
  } catch (err) {
    console.error('Pre-FYDP leave request action error:', err);
    res.status(500).json({ error: 'Failed to process leave request' });
  }
});

module.exports = router;

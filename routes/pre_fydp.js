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
      `SELECT COUNT(DISTINCT domain) as domain_count FROM pre_fydp_groups WHERE group_status = 'OPEN'`
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

// ── List All Open Groups ───────────────────────────────────────────────────
router.get('/groups', async (req, res) => {
  try {
    const { domain, skill, search } = req.query;
    
    let sql = `
      SELECT g.*, u.full_name as creator_name, u.department as creator_dept,
        (SELECT COUNT(*) FROM pre_fydp_group_members gm WHERE gm.group_id = g.group_id) as member_count
      FROM pre_fydp_groups g
      JOIN users u ON g.created_by = u.user_id
      WHERE 1=1
    `;
    const params = [];

    if (domain && domain !== 'All Domains') {
      sql += ` AND g.domain = ?`;
      params.push(domain);
    }
    if (skill && skill !== 'All Skills') {
      sql += ` AND JSON_CONTAINS(g.required_skills, JSON_QUOTE(?))`;
      params.push(skill);
    }
    if (search) {
      sql += ` AND (g.group_name LIKE ? OR g.description LIKE ? OR u.full_name LIKE ?)`;
      params.push(`%${search}%`, `%${search}%`, `%${search}%`);
    }
    sql += ` ORDER BY g.created_at DESC`;

    const [groups] = await db.query(sql, params);

    // Get members for each group
    for (const group of groups) {
      const [members] = await db.query(
        `SELECT gm.*, u.full_name, u.department 
         FROM pre_fydp_group_members gm
         JOIN users u ON gm.user_id = u.user_id
         WHERE gm.group_id = ?`, [group.group_id]
      );
      group.members = members;
      // Find lead
      const lead = members.find(m => m.member_role === 'Lead');
      group.lead_name = lead ? lead.full_name : group.creator_name;
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
      `SELECT DISTINCT domain FROM pre_fydp_groups ORDER BY domain`
    );
    res.json(rows.map(r => r.domain));
  } catch (err) {
    res.status(500).json({ error: 'Failed to load domains' });
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

    const [result] = await db.query(
      `INSERT INTO pre_fydp_groups (group_name, domain, description, required_skills, max_members, github_url, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [group_name, domain, description || null, 
       required_skills ? JSON.stringify(required_skills) : null,
       max_members || 5, github_url || null, userId]
    );

    // Add creator as lead member
    await db.query(
      `INSERT INTO pre_fydp_group_members (group_id, user_id, member_role) VALUES (?, ?, 'Lead')`,
      [result.insertId, userId]
    );

    res.json({ success: true, group_id: result.insertId, message: 'Group created successfully!' });
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

    // Check if already a member
    const [existing] = await db.query(
      `SELECT * FROM pre_fydp_group_members WHERE group_id = ? AND user_id = ?`,
      [group_id, userId]
    );
    if (existing.length > 0) {
      return res.status(400).json({ error: 'You are already a member of this group' });
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
      `SELECT jr.*, g.group_name, g.domain, u.full_name as group_lead
       FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       JOIN users u ON g.created_by = u.user_id
       WHERE jr.sender_id = ?
       ORDER BY jr.created_at DESC`, [userId]
    );

    // Received requests (for groups I own)
    const [received] = await db.query(
      `SELECT jr.*, g.group_name, g.domain, u.full_name as sender_name, 
              u.department as sender_dept, p.skills as sender_skills, p.preferred_role
       FROM pre_fydp_join_requests jr
       JOIN pre_fydp_groups g ON jr.group_id = g.group_id
       JOIN users u ON jr.sender_id = u.user_id
       LEFT JOIN pre_fydp_profiles p ON jr.sender_id = p.user_id
       WHERE g.created_by = ? AND jr.sender_id != ?
       ORDER BY jr.created_at DESC`, [userId, userId]
    );

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
        `INSERT IGNORE INTO pre_fydp_group_members (group_id, user_id, member_role) VALUES (?, ?, 'Member')`,
        [request.group_id, request.sender_id]
      );
      // Update status
      await db.query(
        `UPDATE pre_fydp_join_requests SET request_status = 'ACCEPTED', responded_at = NOW() WHERE request_id = ?`,
        [id]
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
      SELECT u.user_id, u.full_name, u.department, u.batch, 
             p.bio, p.cgpa, p.skills, p.domain_interests, p.preferred_role,
             p.github_url, p.linkedin_url, p.availability_status, p.profile_strength
      FROM users u
      JOIN pre_fydp_profiles p ON u.user_id = p.user_id
      WHERE u.role = 'PRE_FYDP_STUDENT' AND u.user_id != ? AND u.account_status = 'ACTIVE'
            AND p.availability_status = 'LOOKING'
    `;
    const params = [userId];

    if (domain && domain !== 'All Domains') {
      sql += ` AND JSON_CONTAINS(p.domain_interests, JSON_QUOTE(?))`;
      params.push(domain);
    }
    if (skill && skill !== 'All Skills') {
      sql += ` AND JSON_CONTAINS(p.skills, JSON_QUOTE(?))`;
      params.push(skill);
    }

    sql += ` ORDER BY p.profile_strength DESC`;
    const [students] = await db.query(sql, params);
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
      `SELECT u.full_name, u.email, u.department, u.batch, u.phone,
              p.*
       FROM users u
       LEFT JOIN pre_fydp_profiles p ON u.user_id = p.user_id
       WHERE u.user_id = ?`, [userId]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'User not found' });
    res.json(rows[0]);
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

    // Upsert profile
    const [existing] = await db.query(
      `SELECT profile_id FROM pre_fydp_profiles WHERE user_id = ?`, [userId]
    );

    if (existing.length > 0) {
      await db.query(
        `UPDATE pre_fydp_profiles SET bio=?, cgpa=?, skills=?, domain_interests=?, 
         preferred_role=?, github_url=?, linkedin_url=?, portfolio_url=?, profile_strength=?
         WHERE user_id = ?`,
        [bio, cgpa, skills ? JSON.stringify(skills) : null,
         domain_interests ? JSON.stringify(domain_interests) : null,
         preferred_role, github_url, linkedin_url, portfolio_url, strength, userId]
      );
    } else {
      await db.query(
        `INSERT INTO pre_fydp_profiles 
         (user_id, bio, cgpa, skills, domain_interests, preferred_role, github_url, linkedin_url, portfolio_url, profile_strength)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [userId, bio, cgpa, skills ? JSON.stringify(skills) : null,
         domain_interests ? JSON.stringify(domain_interests) : null,
         preferred_role, github_url, linkedin_url, portfolio_url, strength]
      );
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

module.exports = router;

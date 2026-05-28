const express = require('express');
const router = express.Router();
const db = require('../config/db');
const multer = require('multer');
const path = require('path');

// ── Multer config for file uploads (PDF, images) ──────────────────────────
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(__dirname, '..', 'public', 'uploads')),
  filename: (req, file, cb) => {
    const unique = Date.now() + '-' + Math.round(Math.random() * 1E6);
    cb(null, unique + path.extname(file.originalname));
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 } // 50MB
});

// Helper for upload with error handling
const uploadSingle = (field) => (req, res, next) => {
  upload.single(field)(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') return res.status(400).json({ error: 'File too large (max 50MB)' });
      return res.status(400).json({ error: err.message });
    } else if (err) {
      return res.status(400).json({ error: err.message });
    }
    next();
  });
};

// ═══════════════════════════════════════════════════════════════════════════
// DIRECT MESSAGES (Supervisor ↔ Course Teacher)
// ═══════════════════════════════════════════════════════════════════════════

// GET /api/chat/contacts — Get my chat contacts (supervisors or teachers)
router.get('/contacts', async (req, res) => {
  try {
    const user = req.session.user;
    let targetRole;

    if (user.role === 'SUPERVISOR') targetRole = 'COURSE_TEACHER';
    else if (user.role === 'COURSE_TEACHER') targetRole = 'SUPERVISOR';
    else return res.status(403).json({ error: 'Chat not available for your role' });

    const [contacts] = await db.query(
      `SELECT u.user_id, u.full_name, u.email, d.short_code AS department,
              (SELECT COUNT(*) FROM direct_messages dm 
               WHERE dm.sender_id = u.user_id AND dm.receiver_id = ? AND dm.is_read = 0
              ) as unread_count
       FROM users u 
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.role = ? AND u.is_active = 1
       ORDER BY u.full_name`,
      [user.user_id, targetRole]
    );

    // Enrich contacts with section/group info
    for (let c of contacts) {
      if (targetRole === 'COURSE_TEACHER') {
        // Get sections managed by this course teacher (join sections for section_code)
        const [sections] = await db.query(
          `SELECT s.section_code FROM course_teacher_sections cts
           JOIN sections s ON s.section_id = cts.section_id
           WHERE cts.course_teacher_id = ?`,
          [c.user_id]
        );
        c.sections = sections.map(s => s.section_code);

        // Get groups in those sections via section_id FK
        const [groups] = await db.query(
          `SELECT pg.group_code, pg.project_title FROM project_groups pg
           JOIN course_teacher_sections cts ON cts.section_id = pg.section_id
           WHERE cts.course_teacher_id = ? AND pg.is_active = 1`,
          [c.user_id]
        );
        c.groups = groups;
      } else if (targetRole === 'SUPERVISOR') {
        // Get groups managed by this supervisor
        const [groups] = await db.query(
          `SELECT pg.group_code, pg.project_title FROM project_groups pg 
           WHERE pg.supervisor_id = ? AND pg.is_active = 1`,
          [c.user_id]
        );
        c.groups = groups;
      }
    }

    res.json({ contacts });
  } catch (err) {
    console.error('Contacts error:', err);
    res.status(500).json({ error: 'Failed to load contacts' });
  }
});

// GET /api/chat/messages/:userId — Get messages between me and userId
router.get('/messages/:userId', async (req, res) => {
  try {
    const myId = req.session.user.user_id;
    const otherId = req.params.userId;

    const [messages] = await db.query(
      `SELECT dm.*, u.full_name as sender_name
       FROM direct_messages dm
       JOIN users u ON u.user_id = dm.sender_id
       WHERE (dm.sender_id = ? AND dm.receiver_id = ?)
          OR (dm.sender_id = ? AND dm.receiver_id = ?)
       ORDER BY dm.created_at ASC`,
      [myId, otherId, otherId, myId]
    );

    // Mark received messages as read
    const [updated] = await db.query(
      'UPDATE direct_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
      [otherId, myId]
    );

    // Notify sender that messages have been read (real-time double tick)
    if (updated.affectedRows > 0) {
      const io = req.app.get('io');
      if (io) io.to(`user_${otherId}`).emit('messages_read', { by: myId, sender: otherId });
    }

    // Clear DM notifications from other user
    const [[partnerInfo]] = await db.query('SELECT full_name FROM users WHERE user_id = ?', [otherId]);
    if (partnerInfo) {
      await db.query(
        `UPDATE notifications 
         SET is_read = 1 
         WHERE user_id = ? 
           AND (notification_type = 'NEW_DIRECT_MESSAGE' OR notification_type = 'SYSTEM_ALERT') 
           AND (title LIKE ? OR message LIKE ?) 
           AND is_read = 0`,
        [myId, `%${partnerInfo.full_name}%`, `%${partnerInfo.full_name}%`]
      );
    }

    res.json({ messages });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load messages' });
  }
});

// POST /api/chat/direct/send — Student DM alias (receiver_id in body)
router.post('/direct/send', uploadSingle('attachment'), async (req, res) => {
  try {
    const myId = req.session.user.user_id;
    const { receiver_id, message_text } = req.body;
    if (!receiver_id || (!message_text && !req.file)) {
      return res.status(400).json({ error: 'receiver_id and message or file are required' });
    }
    let attachmentPath = null, attachmentName = null;
    if (req.file) {
      attachmentPath = '/uploads/' + req.file.filename;
      attachmentName = req.file.originalname;
    }
    const [result] = await db.query(
      `INSERT INTO direct_messages (sender_id, receiver_id, message_text, attachment_path, attachment_name) VALUES (?, ?, ?, ?, ?)`,
      [myId, receiver_id, message_text || '', attachmentPath, attachmentName]
    );
    const io = req.app.get('io');
    if (io) {
      const msgData = { message_id: result.insertId, sender_id: myId, receiver_id: parseInt(receiver_id), sender_name: req.session.user.full_name, sender_role: req.session.user.role, message_text, attachment_path: attachmentPath, attachment_name: attachmentName, created_at: new Date().toISOString() };
      io.to(`user_${receiver_id}`).emit('new_dm', msgData);
      io.to(`user_${myId}`).emit('new_dm', msgData);
    }

    // Persistent notification for receiver
    const senderName = req.session.user.full_name;
    const preview = (message_text || '').substring(0, 60) || (attachmentName ? `📎 ${attachmentName}` : 'Sent a file');
    let senderRoleLabel = 'User';
    if (req.session.user.role === 'STUDENT') senderRoleLabel = 'Student';
    else if (req.session.user.role === 'SUPERVISOR') senderRoleLabel = 'Supervisor';
    else if (req.session.user.role === 'COURSE_TEACHER') senderRoleLabel = 'Course Teacher';

    const notifTitle = `💬 DM from ${senderRoleLabel}: ${senderName}`;

    await db.query(
      `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type) VALUES (?, 'NEW_DIRECT_MESSAGE', ?, ?, ?, 'direct_messages')`,
      [receiver_id, notifTitle, preview, result.insertId]
    );
    if (io) {
      io.to(`user_${receiver_id}`).emit('notification', { title: notifTitle, message: preview });
    }

    res.json({ 
      success: true, 
      message_id: result.insertId,
      attachment_path: attachmentPath,
      attachment_name: attachmentName
    });
  } catch (err) {
    console.error('Direct send error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// POST /api/chat/messages — Send a direct message (original)
router.post('/messages', uploadSingle('attachment'), async (req, res) => {
  try {
    const myId = req.session.user.user_id;
    const { receiver_id, message_text } = req.body;

    if (!receiver_id || (!message_text && !req.file)) {
      return res.status(400).json({ error: 'receiver_id and message or file are required' });
    }

    let attachmentPath = null, attachmentName = null;
    if (req.file) {
      attachmentPath = '/uploads/' + req.file.filename;
      attachmentName = req.file.originalname;
    }

    const [result] = await db.query(
      `INSERT INTO direct_messages (sender_id, receiver_id, message_text, attachment_path, attachment_name)
       VALUES (?, ?, ?, ?, ?)`,
      [myId, receiver_id, message_text || '', attachmentPath, attachmentName]
    );

    // Create notification for receiver
    const senderName = req.session.user.full_name;
    const preview = (message_text || '').substring(0, 60) || (attachmentName ? `📎 ${attachmentName}` : 'Sent a file');
    let senderRoleLabel = 'User';
    if (req.session.user.role === 'STUDENT') senderRoleLabel = 'Student';
    else if (req.session.user.role === 'SUPERVISOR') senderRoleLabel = 'Supervisor';
    else if (req.session.user.role === 'COURSE_TEACHER') senderRoleLabel = 'Course Teacher';

    const notifTitle = `💬 DM from ${senderRoleLabel}: ${senderName}`;

    await db.query(
      `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type) 
       VALUES (?, 'NEW_DIRECT_MESSAGE', ?, ?, ?, 'direct_messages')`,
      [receiver_id, notifTitle, preview, result.insertId]
    );

    // Socket emission
    const io = req.app.get('io');
    if (io) {
      const room = `dm_${Math.min(myId, receiver_id)}_${Math.max(myId, receiver_id)}`;
      const messageData = {
        message_id: result.insertId,
        sender_id: myId,
        receiver_id: receiver_id,
        sender_name: req.session.user.full_name,
        message_text,
        attachment_path: attachmentPath,
        attachment_name: attachmentName,
        created_at: new Date().toISOString()
      };
      io.to(room).emit('new_message', messageData);
      io.to(`user_${receiver_id}`).emit('notification', { title: notifTitle, message: preview });
    }

    // Email notification
    const { sendEmail } = require('../utils/email');
    const [recvRows] = await db.query('SELECT email FROM users WHERE user_id = ?', [receiver_id]);
    if (recvRows.length > 0) {
      sendEmail({
        to: recvRows[0].email,
        subject: `New Direct Message from ${req.session.user.full_name}`,
        html: `<p>You have a new message from ${req.session.user.full_name}:</p><blockquote style="border-left:4px solid #ccc;padding-left:10px;">${message_text}</blockquote><p><a href="http://localhost:3000/login">Login to reply</a></p>`
      });
    }

    res.json({
      success: true,
      message_id: result.insertId,
      attachment_path: attachmentPath,
      attachment_name: attachmentName
    });
  } catch (err) {
    console.error('Send message error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// DELETE /api/chat/direct/:messageId — Delete a direct message
router.delete('/direct/:messageId', async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const myId = req.session.user.user_id;

    const [[msg]] = await db.query('SELECT attachment_path, receiver_id FROM direct_messages WHERE message_id = ? AND sender_id = ?', [messageId, myId]);
    
    if (!msg) return res.status(404).json({ error: 'Message not found or unauthorized' });

    if (msg.attachment_path) {
      const fs = require('fs');
      const filepath = path.join(__dirname, '..', 'public', msg.attachment_path);
      if (fs.existsSync(filepath)) fs.unlinkSync(filepath);
    }

    await db.query(
      `UPDATE direct_messages SET message_text = '🚫 This message was deleted', attachment_path = NULL, attachment_name = NULL WHERE message_id = ? AND sender_id = ?`,
      [messageId, myId]
    );

    const io = req.app.get('io');
    if (io) {
      io.to(`user_${msg.receiver_id}`).emit('message_deleted', { message_id: messageId, type: 'direct' });
      io.to(`user_${myId}`).emit('message_deleted', { message_id: messageId, type: 'direct' });
      // If we use dm_room:
      const room = `dm_${Math.min(myId, msg.receiver_id)}_${Math.max(myId, msg.receiver_id)}`;
      io.to(room).emit('message_deleted', { message_id: messageId, type: 'direct' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Delete message error:', err);
    res.status(500).json({ error: 'Failed to delete message' });
  }
});

// GET /api/chat/unread-count — Total unread DMs for badge, optionally split by role for students
router.get('/unread-count', async (req, res) => {
  try {
    const userId = req.session.user.user_id;
    
    // Default total count
    const [[{ count }]] = await db.query(
      'SELECT COUNT(*) as count FROM direct_messages WHERE receiver_id = ? AND is_read = 0',
      [userId]
    );

    let supervisor_unread = 0;
    let teacher_unread = 0;

    if (req.session.user.role === 'STUDENT') {
      // Get student's group and supervisor/teacher via group_members + project_groups
      const [[gm]] = await db.query(
        `SELECT pg.group_id, pg.supervisor_id, cts.course_teacher_id
         FROM group_members gm
         JOIN project_groups pg ON pg.group_id = gm.group_id AND pg.is_active = 1
         LEFT JOIN course_teacher_sections cts ON cts.section_id = pg.section_id
         WHERE gm.student_id = ? LIMIT 1`,
        [userId]
      );
      if (gm) {
        if (gm.supervisor_id) {
          const [[{ supCount }]] = await db.query(
            'SELECT COUNT(*) as supCount FROM direct_messages WHERE receiver_id = ? AND sender_id = ? AND is_read = 0',
            [userId, gm.supervisor_id]
          );
          supervisor_unread = supCount;
        }
        if (gm.course_teacher_id) {
          const [[{ tcCount }]] = await db.query(
            'SELECT COUNT(*) as tcCount FROM direct_messages WHERE receiver_id = ? AND sender_id = ? AND is_read = 0',
            [userId, gm.course_teacher_id]
          );
          teacher_unread = tcCount;
        }
      }
    }

    res.json({ unread_count: count, supervisor_unread, teacher_unread });
  } catch (err) {
    res.json({ unread_count: 0, supervisor_unread: 0, teacher_unread: 0 });
  }
});

// GET /api/chat/supervisor/student-inbox — All students who DMed this supervisor
router.get('/supervisor/student-inbox', async (req, res) => {
  try {
    const user = req.session.user;
    if (user.role !== 'SUPERVISOR') return res.status(403).json({ error: 'Supervisor only' });
    const myId = user.user_id;

    // Step 1: Get all unique student IDs who have any DM with this supervisor
    const [partners] = await db.query(
      `SELECT DISTINCT 
         CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS student_id
       FROM direct_messages
       WHERE (sender_id = ? OR receiver_id = ?)`,
      [myId, myId, myId]
    );

    if (!partners.length) return res.json({ conversations: [] });

    const studentIds = partners.map(p => p.student_id);

    // Step 2: Get student info (one row per student, avoid ONLY_FULL_GROUP_BY)
    const placeholders = studentIds.map(() => '?').join(',');
    const [students] = await db.query(
      `SELECT u.user_id, u.full_name, u.university_id, u.email, u.role,
              ANY_VALUE(pg.group_code) as group_code,
              ANY_VALUE(pg.project_title) as project_title,
              ANY_VALUE(gm.member_role) as member_role
       FROM users u
       LEFT JOIN group_members gm ON gm.student_id = u.user_id
       LEFT JOIN project_groups pg ON pg.group_id = gm.group_id AND pg.supervisor_id = ?
       WHERE u.user_id IN (${placeholders}) AND u.role = 'STUDENT'
       GROUP BY u.user_id, u.full_name, u.university_id, u.email, u.role`,
      [myId, ...studentIds]
    );

    // Step 3: For each student, get latest message & unread count
    const conversations = [];
    for (const s of students) {
      const [[latest]] = await db.query(
        `SELECT message_text, created_at, sender_id, is_read
         FROM direct_messages
         WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
         ORDER BY created_at DESC LIMIT 1`,
        [myId, s.user_id, s.user_id, myId]
      );
      const [[{ unread_count }]] = await db.query(
        `SELECT COUNT(*) as unread_count FROM direct_messages
         WHERE sender_id = ? AND receiver_id = ? AND is_read = 0`,
        [s.user_id, myId]
      );
      conversations.push({
        ...s,
        last_message: latest?.message_text || '',
        last_time: latest?.created_at || null,
        last_sender_id: latest?.sender_id || null,
        unread_count: unread_count || 0
      });
    }

    // Sort by latest message time descending
    conversations.sort((a, b) => new Date(b.last_time || 0) - new Date(a.last_time || 0));
    res.json({ conversations });
  } catch (err) {
    console.error('Student inbox error:', err.message);
    res.status(500).json({ error: 'Failed to load student inbox: ' + err.message });
  }
});

// GET /api/chat/supervisor/student-messages/:studentId — DM thread with a student
router.get('/supervisor/student-messages/:studentId', async (req, res) => {
  try {
    const myId = req.session.user.user_id;
    const otherId = parseInt(req.params.studentId);

    const [messages] = await db.query(
      `SELECT dm.*, u.full_name as sender_name, u.role as sender_role
       FROM direct_messages dm
       JOIN users u ON u.user_id = dm.sender_id
       WHERE (dm.sender_id = ? AND dm.receiver_id = ?)
          OR (dm.sender_id = ? AND dm.receiver_id = ?)
       ORDER BY dm.created_at ASC`,
      [myId, otherId, otherId, myId]
    );

    // Mark student's messages as read & emit double-tick to student
    const [updated] = await db.query(
      'UPDATE direct_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
      [otherId, myId]
    );
    if (updated.affectedRows > 0) {
      const io = req.app.get('io');
      if (io) io.to(`user_${otherId}`).emit('messages_read', { by: myId, sender: otherId });
    }

    // Clear DM notifications from student
    const [[studentInfo]] = await db.query('SELECT full_name FROM users WHERE user_id = ?', [otherId]);
    if (studentInfo) {
      await db.query(
        `UPDATE notifications 
         SET is_read = 1 
         WHERE user_id = ? 
           AND (notification_type = 'NEW_DIRECT_MESSAGE' OR notification_type = 'SYSTEM_ALERT') 
           AND (title LIKE ? OR message LIKE ?) 
           AND is_read = 0`,
        [myId, `%${studentInfo.full_name}%`, `%${studentInfo.full_name}%`]
      );
    }

    res.json({ messages });
  } catch (err) {
    console.error('Student messages error:', err.message);
    res.status(500).json({ error: 'Failed to load messages: ' + err.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GROUP CHAT (Supervisor ↔ Group Members — separated per group)
// ═══════════════════════════════════════════════════════════════════════════

// GET /api/chat/group-unread-count — Total unread group messages from notifications
router.get('/group-unread-count', async (req, res) => {
  try {
    const [[{ count }]] = await db.query(
      "SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0 AND message LIKE 'New group message%'",
      [req.session.user.user_id]
    );
    res.json({ unread_count: count });
  } catch (err) {
    res.json({ unread_count: 0 });
  }
});

// GET /api/chat/group/:groupId/messages — Get group chat messages
router.get('/group/:groupId/messages', async (req, res) => {
  try {
    const chatType = req.query.type || 'STUDENT_ONLY';
    const [messages] = await db.query(
      `SELECT gcm.*, u.full_name as sender_name, u.role as sender_role
       FROM group_chat_messages gcm
       JOIN users u ON u.user_id = gcm.sender_id
       WHERE gcm.group_id = ? AND gcm.chat_type = ?
       ORDER BY gcm.created_at ASC`,
      [req.params.groupId, chatType]
    );

    // Clear group chat notifications for this user
    await db.query(
      `UPDATE notifications 
       SET is_read = 1 
       WHERE user_id = ? 
         AND (notification_type = 'NEW_GROUP_MESSAGE' OR title LIKE '%Group Message%' OR message LIKE '%group message%' OR message LIKE 'New group message%') 
         AND is_read = 0`,
      [req.session.user.user_id]
    );

    res.json({ messages });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load group chat' });
  }
});

// POST /api/chat/group/:groupId/messages — Send group chat message
router.post('/group/:groupId/messages', uploadSingle('attachment'), async (req, res) => {
  try {
    const myId = req.session.user.user_id;
    const groupId = req.params.groupId;
    const { message_text, chat_type } = req.body;
    const type = chat_type || 'STUDENT_ONLY';

    if (!message_text && !req.file) return res.status(400).json({ error: 'Message or file required' });

    let attachmentPath = null, attachmentName = null;
    if (req.file) {
      attachmentPath = '/uploads/' + req.file.filename;
      attachmentName = req.file.originalname;
    }

    const [result] = await db.query(
      `INSERT INTO group_chat_messages (group_id, sender_id, message_text, attachment_path, attachment_name, chat_type)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [groupId, myId, message_text || '', attachmentPath, attachmentName, type]
    );

    // Socket emission
    const io = req.app.get('io');
    if (io) {
      const messageData = {
        message_id: result.insertId,
        group_id: groupId,
        sender_id: myId,
        sender_name: req.session.user.full_name,
        sender_role: req.session.user.role,
        message_text,
        attachment_path: attachmentPath,
        attachment_name: attachmentName,
        chat_type: type,
        created_at: new Date().toISOString()
      };
      io.to(`group_${groupId}`).emit('new_group_message', messageData);
    }

    // ─────────────────────────────────────────────────────────────────
    // Notification for other group members + supervisor + course teacher
    // ─────────────────────────────────────────────────────────────────
    const [members] = await db.query(
      'SELECT student_id as user_id FROM group_members WHERE group_id = ? AND student_id != ?',
      [groupId, myId]
    );
    const notifyUsers = members.map(m => m.user_id);

    // Always notify supervisor (regardless of chat type)
    const [sup] = await db.query('SELECT supervisor_id FROM project_groups WHERE group_id = ?', [groupId]);
    if (sup.length > 0 && sup[0].supervisor_id && sup[0].supervisor_id !== myId) {
      if (!notifyUsers.includes(sup[0].supervisor_id)) notifyUsers.push(sup[0].supervisor_id);
    }

    // Always notify course teacher (regardless of chat type)
    const [teach] = await db.query(
      `SELECT cts.course_teacher_id
       FROM project_groups pg
       JOIN course_teacher_sections cts ON cts.section_id = pg.section_id
       WHERE pg.group_id = ?
       LIMIT 1`,
      [groupId]
    );
    if (teach.length > 0 && teach[0].course_teacher_id && teach[0].course_teacher_id !== myId) {
      if (!notifyUsers.includes(teach[0].course_teacher_id)) notifyUsers.push(teach[0].course_teacher_id);
    }

    const senderName = req.session.user.full_name;
    const msgPreview = (message_text || '').substring(0, 60) || (attachmentName ? `📎 ${attachmentName}` : 'Sent a file');
    
    let channelLabel = 'Members';
    if (type === 'WITH_SUPERVISOR') channelLabel = 'Supervisor';
    else if (type === 'WITH_TEACHER') channelLabel = 'Teacher';

    const notifTitle = `💬 Group Message (${channelLabel}): ${senderName}`;

    for (const uid of notifyUsers) {
      await db.query(
        `INSERT INTO notifications (user_id, notification_type, title, message, reference_entity_id, reference_entity_type) VALUES (?, 'NEW_GROUP_MESSAGE', ?, ?, ?, 'group_chat_messages')`,
        [uid, notifTitle, msgPreview, result.insertId]
      );
      if (io) {
        io.to(`user_${uid}`).emit('notification', { title: notifTitle, message: msgPreview });
      }
    }

    res.json({ success: true, message_id: result.insertId });
  } catch (err) {
    console.error('Group chat error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// DELETE /api/chat/group/messages/:messageId — Delete a group message
router.delete('/group/messages/:messageId', async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const myId = req.session.user.user_id;

    const [[msg]] = await db.query('SELECT attachment_path, group_id FROM group_chat_messages WHERE message_id = ? AND sender_id = ?', [messageId, myId]);
    
    if (!msg) return res.status(404).json({ error: 'Message not found or unauthorized' });

    if (msg.attachment_path) {
      const fs = require('fs');
      const filepath = path.join(__dirname, '..', 'public', msg.attachment_path);
      if (fs.existsSync(filepath)) fs.unlinkSync(filepath);
    }

    await db.query(
      `UPDATE group_chat_messages SET message_text = '🚫 This message was deleted', attachment_path = NULL, attachment_name = NULL WHERE message_id = ? AND sender_id = ?`,
      [messageId, myId]
    );

    const io = req.app.get('io');
    if (io) {
      io.to(`group_${msg.group_id}`).emit('message_deleted', { message_id: messageId, type: 'group', group_id: msg.group_id });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Delete group message error:', err);
    res.status(500).json({ error: 'Failed to delete message' });
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// COURSE TEACHER ↔ STUDENT DIRECT MESSAGES
// ═══════════════════════════════════════════════════════════════════════════

// GET /api/chat/teacher/student-inbox — All students who DMed this teacher
router.get('/teacher/student-inbox', async (req, res) => {
  try {
    const user = req.session.user;
    if (user.role !== 'COURSE_TEACHER') return res.status(403).json({ error: 'Course Teacher only' });
    const myId = user.user_id;

    // Step 1: Get all unique partner IDs who have any DM with this teacher
    const [partners] = await db.query(
      `SELECT DISTINCT
         CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS student_id
       FROM direct_messages
       WHERE (sender_id = ? OR receiver_id = ?)`,
      [myId, myId, myId]
    );

    if (!partners.length) return res.json({ conversations: [] });

    const studentIds = partners.map(p => p.student_id);
    const placeholders = studentIds.map(() => '?').join(',');

    // Step 2: Get student info (only STUDENT role)
    const [students] = await db.query(
      `SELECT u.user_id, u.full_name, u.university_id, u.email, u.role,
              ANY_VALUE(pg.group_code) as group_code,
              ANY_VALUE(pg.project_title) as project_title,
              ANY_VALUE(gm.member_role) as member_role
       FROM users u
       LEFT JOIN group_members gm ON gm.student_id = u.user_id
       LEFT JOIN project_groups pg ON pg.group_id = gm.group_id
       LEFT JOIN course_teacher_sections cts ON cts.section_id = pg.section_id
         AND cts.course_teacher_id = ?
       WHERE u.user_id IN (${placeholders}) AND u.role = 'STUDENT'
       GROUP BY u.user_id, u.full_name, u.university_id, u.email, u.role`,
      [myId, ...studentIds]
    );

    // Step 3: Enrich each student with last message & unread count
    const conversations = [];
    for (const s of students) {
      const [[latest]] = await db.query(
        `SELECT message_text, created_at, sender_id, is_read
         FROM direct_messages
         WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
         ORDER BY created_at DESC LIMIT 1`,
        [myId, s.user_id, s.user_id, myId]
      );
      const [[{ unread_count }]] = await db.query(
        `SELECT COUNT(*) as unread_count FROM direct_messages
         WHERE sender_id = ? AND receiver_id = ? AND is_read = 0`,
        [s.user_id, myId]
      );
      conversations.push({
        ...s,
        last_message: latest?.message_text || '',
        last_time: latest?.created_at || null,
        last_sender_id: latest?.sender_id || null,
        unread_count: unread_count || 0
      });
    }

    conversations.sort((a, b) => new Date(b.last_time || 0) - new Date(a.last_time || 0));
    res.json({ conversations });
  } catch (err) {
    console.error('Teacher student-inbox error:', err.message);
    res.status(500).json({ error: 'Failed to load student inbox: ' + err.message });
  }
});

// GET /api/chat/teacher/student-messages/:studentId — DM thread with a student
router.get('/teacher/student-messages/:studentId', async (req, res) => {
  try {
    const user = req.session.user;
    if (user.role !== 'COURSE_TEACHER') return res.status(403).json({ error: 'Course Teacher only' });
    const myId = user.user_id;
    const otherId = parseInt(req.params.studentId);

    const [messages] = await db.query(
      `SELECT dm.*, u.full_name as sender_name, u.role as sender_role
       FROM direct_messages dm
       JOIN users u ON u.user_id = dm.sender_id
       WHERE (dm.sender_id = ? AND dm.receiver_id = ?)
          OR (dm.sender_id = ? AND dm.receiver_id = ?)
       ORDER BY dm.created_at ASC`,
      [myId, otherId, otherId, myId]
    );

    // Mark student's messages as read & emit double-tick to student
    const [updated] = await db.query(
      'UPDATE direct_messages SET is_read = 1 WHERE sender_id = ? AND receiver_id = ? AND is_read = 0',
      [otherId, myId]
    );
    if (updated.affectedRows > 0) {
      const io = req.app.get('io');
      if (io) io.to(`user_${otherId}`).emit('messages_read', { by: myId, sender: otherId });
    }

    // Clear DM notifications from student
    const [[studentInfo]] = await db.query('SELECT full_name FROM users WHERE user_id = ?', [otherId]);
    if (studentInfo) {
      await db.query(
        `UPDATE notifications 
         SET is_read = 1 
         WHERE user_id = ? 
           AND (notification_type = 'NEW_DIRECT_MESSAGE' OR notification_type = 'SYSTEM_ALERT') 
           AND (title LIKE ? OR message LIKE ?) 
           AND is_read = 0`,
        [myId, `%${studentInfo.full_name}%`, `%${studentInfo.full_name}%`]
      );
    }

    res.json({ messages });
  } catch (err) {
    console.error('Teacher student-messages error:', err.message);
    res.status(500).json({ error: 'Failed to load messages: ' + err.message });
  }
});

module.exports = router;


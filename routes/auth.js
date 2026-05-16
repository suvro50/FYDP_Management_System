const express = require('express');
const router = express.Router();
const db = require('../config/db');

// GET /login — serve login page
router.get('/login', (req, res) => {
  if (req.session?.user) {
    return res.redirect(getDashboardUrl(req.session.user.role));
  }
  res.sendFile('login.html', { root: './views' });
});

// POST /auth/login — authenticate user
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const [rows] = await db.query(
      `SELECT u.user_id, u.university_id, u.full_name, u.email, u.role,
              d.department_name AS department, u.batch,
              u.phone, u.profile_photo, u.account_status
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.email = ? AND u.password_hash = SHA2(?, 256) AND u.is_active = 1`,
      [email, password]
    );

    if (rows.length === 0) {
      return res.status(401).json({ error: 'Invalid email or password' });
    }

    const user = rows[0];

    if (user.account_status !== 'ACTIVE') {
      return res.status(403).json({ error: 'Your account has been suspended or deactivated' });
    }

    // Set session
    req.session.user = {
      user_id: user.user_id,
      university_id: user.university_id,
      full_name: user.full_name,
      email: user.email,
      role: user.role,
      department: user.department,
      batch: user.batch,
      phone: user.phone,
      profile_photo: user.profile_photo
    };

    res.json({
      success: true,
      redirect: getDashboardUrl(user.role),
      user: { full_name: user.full_name, role: user.role }
    });

  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Server error. Please try again.' });
  }
});

// POST /auth/logout
router.post('/logout', (req, res) => {
  req.session.destroy(err => {
    if (err) console.error('Logout error:', err);
    res.json({ success: true, redirect: '/login' });
  });
});

// GET /auth/me — get current session user
router.get('/me', (req, res) => {
  if (!req.session?.user) {
    return res.status(401).json({ error: 'Not authenticated' });
  }
  res.json({ user: req.session.user });
});

function getDashboardUrl(role) {
  switch (role) {
    case 'ADMIN': return '/admin/dashboard';
    case 'SUPERVISOR': return '/supervisor/dashboard';
    case 'COURSE_TEACHER': return '/teacher/dashboard';
    case 'STUDENT': return '/student/dashboard';
    case 'PRE_FYDP_STUDENT': return '/pre-fydp/dashboard';
    default: return '/login';
  }
}

module.exports = router;

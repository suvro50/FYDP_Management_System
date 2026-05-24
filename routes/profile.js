const express = require('express');
const router = express.Router();
const db = require('../config/db');
const multer = require('multer');
const path = require('path');

// Multer config for profile photos
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, path.join(__dirname, '..', 'public', 'uploads')),
  filename: (req, file, cb) => {
    cb(null, 'profile-' + req.session.user.user_id + '-' + Date.now() + path.extname(file.originalname));
  }
});
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['.jpg', '.jpeg', '.png', '.gif'];
    if (allowed.includes(path.extname(file.originalname).toLowerCase())) cb(null, true);
    else cb(new Error('Only image files allowed'));
  }
});

// GET /api/profile/me — Get my full profile
router.get('/me', async (req, res) => {
  try {
    const [[user]] = await db.query(
      `SELECT u.user_id, u.full_name, u.email, u.university_id,
              d.department_name AS department, u.role,
              u.profile_photo, u.phone, u.is_active, u.created_at
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.user_id = ?`,
      [req.session.user.user_id]
    );
    res.json({ user });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load profile' });
  }
});

// GET /api/profile/:userId — View any user's public profile
router.get('/:userId', async (req, res) => {
  try {
    const [[user]] = await db.query(
      `SELECT u.user_id, u.full_name, u.email, u.university_id,
              d.department_name AS department, u.role,
              u.profile_photo, u.phone, u.created_at
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.user_id = ? AND u.is_active = 1`,
      [req.params.userId]
    );
    if (!user) return res.status(404).json({ error: 'User not found' });

    // For Pre-FYDP students, also return their Pre-FYDP profile data
    if (user.role === 'PRE_FYDP_STUDENT') {
      const [[pfProfile]] = await db.query(
        `SELECT p.bio, p.cgpa, p.preferred_role, p.github_url,
                p.linkedin_url, p.portfolio_url, p.profile_strength, p.availability_status
         FROM pre_fydp_profiles p
         WHERE p.user_id = ?`,
        [req.params.userId]
      );
      if (pfProfile) {
        user.bio             = pfProfile.bio;
        user.cgpa            = pfProfile.cgpa;
        user.preferred_role  = pfProfile.preferred_role;
        user.github_url      = pfProfile.github_url;
        user.linkedin_url    = pfProfile.linkedin_url;
        user.portfolio_url   = pfProfile.portfolio_url;
        user.profile_strength= pfProfile.profile_strength;
        user.availability_status = pfProfile.availability_status;
      }

      // Skills
      const [skillRows] = await db.query(
        `SELECT s.skill_name FROM pre_fydp_student_skills pss
         JOIN skills s ON pss.skill_id = s.skill_id
         WHERE pss.user_id = ?`,
        [req.params.userId]
      );
      user.skills = skillRows.map(s => s.skill_name);

      // Domain interests
      const [domainRows] = await db.query(
        `SELECT pd.domain_name FROM pre_fydp_student_domain_interests pdi
         JOIN project_domains pd ON pdi.domain_id = pd.domain_id
         WHERE pdi.user_id = ?`,
        [req.params.userId]
      );
      user.domain_interests = domainRows.map(d => d.domain_name);
    }

    res.json({ user });
  } catch (err) {
    res.status(500).json({ error: 'Failed to load profile' });
  }
});

// PUT /api/profile/update — Update my profile info
router.put('/update', async (req, res) => {
  try {
    const { phone, full_name } = req.body;
    const userId = req.session.user.user_id;

    await db.query(
      'UPDATE users SET phone = ?, full_name = ? WHERE user_id = ?',
      [phone || null, full_name, userId]
    );

    // Update session
    if (full_name) req.session.user.full_name = full_name;

    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// POST /api/profile/photo — Upload profile photo
router.post('/photo', upload.single('photo'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No photo uploaded' });

    const photoPath = '/uploads/' + req.file.filename;
    await db.query(
      'UPDATE users SET profile_photo = ? WHERE user_id = ?',
      [photoPath, req.session.user.user_id]
    );

    res.json({ success: true, photo_path: photoPath });
  } catch (err) {
    res.status(500).json({ error: 'Failed to upload photo' });
  }
});

module.exports = router;

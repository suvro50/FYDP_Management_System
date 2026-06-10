require('dotenv').config();
const express = require('express');
const session = require('express-session');
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Create HTTP server and Socket.io
const http = require('http');
const server = http.createServer(app);
const { Server } = require('socket.io');
const io = new Server(server, {
  cors: { origin: '*' }
});

// Make io accessible in routes
app.set('io', io);

io.on('connection', (socket) => {
  console.log('Socket connected:', socket.id);
  // Join a personal room for user-specific notifications
  socket.on('join_user', (userId) => {
    socket.join(`user_${userId}`);
    console.log(`User ${userId} joined room user_${userId}`);
  });
  // Join a group chat room
  socket.on('join_group', (groupId) => {
    socket.join(`group_${groupId}`);
  });
  // Join a direct message room
  socket.on('join_dm', ({ u1, u2 }) => {
    const room = `dm_${Math.min(u1, u2)}_${Math.max(u1, u2)}`;
    socket.join(room);
  });
  // Admin joins the admin_room to receive real-time login alerts
  socket.on('join_admin', () => {
    socket.join('admin_room');
    console.log(`Admin socket ${socket.id} joined admin_room`);
  });
});

// ── Middleware ──────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Session
app.use(session({
  secret: process.env.SESSION_SECRET || 'fydp_secret',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    maxAge: 8 * 60 * 60 * 1000, // 8 hours
    sameSite: 'lax'
  }
}));

// Static files
app.use(express.static(path.join(__dirname, 'public')));

// ── Auth Routes ────────────────────────────────────────────────────────────
const authRoutes = require('./routes/auth');
app.use('/', authRoutes);
app.use('/auth', authRoutes);

// ── Auth & Role Middleware ─────────────────────────────────────────────────
const isAuth = require('./middleware/auth.middleware');
const requireRole = require('./middleware/role.middleware');

// ── API Routes ─────────────────────────────────────────────────────────────
const adminRoutes = require('./routes/admin');
const supervisorRoutes = require('./routes/supervisor');
const chatRoutes = require('./routes/chat');
const notificationRoutes = require('./routes/notifications');
const profileRoutes = require('./routes/profile');
const teacherRoutes = require('./routes/teacher');
const preFydpRoutes = require('./routes/pre_fydp');

const { router: studentRoutes, checkGroupStatus } = require('./routes/student');

app.use('/api/admin', isAuth, requireRole('ADMIN'), adminRoutes);
app.use('/api/supervisor', isAuth, requireRole('SUPERVISOR', 'COURSE_TEACHER'), supervisorRoutes);
app.use('/api/student', isAuth, requireRole('STUDENT'), studentRoutes);
app.use('/api/teacher', isAuth, requireRole('COURSE_TEACHER'), teacherRoutes);
app.use('/api/pre-fydp', isAuth, requireRole('PRE_FYDP_STUDENT'), preFydpRoutes);
app.use('/api/chat', isAuth, chatRoutes);
app.use('/api/notifications', isAuth, notificationRoutes);
app.use('/api/profile', isAuth, profileRoutes);

// UCAM Webhook Demo
const ucamDemoRoutes = require('./routes/ucam_demo');
app.use('/ucam-demo', ucamDemoRoutes);

// ── Page Routes (serve HTML files) ─────────────────────────────────────────
// Admin pages
app.get('/admin/dashboard', isAuth, requireRole('ADMIN'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/admin/dashboard.html'));
});
app.get('/admin/users', isAuth, requireRole('ADMIN'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/admin/users.html'));
});
app.get('/admin/groups', isAuth, requireRole('ADMIN'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/admin/groups.html'));
});
app.get('/admin/assign-supervisor', isAuth, requireRole('ADMIN'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/admin/assign_supervisor.html'));
});
app.get('/admin/assign-groups', isAuth, requireRole('ADMIN'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/admin/assign_groups.html'));
});
app.get('/admin/assign-teacher', isAuth, requireRole('ADMIN'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/admin/assign_teacher.html'));
});

// ── Supervisor Pages ───────────────────────────────────────────────────────
app.get('/supervisor/dashboard', isAuth, requireRole('SUPERVISOR', 'COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/supervisor/dashboard.html'));
});
app.get('/supervisor/groups', isAuth, requireRole('SUPERVISOR', 'COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/supervisor/groups.html'));
});
app.get('/supervisor/approvals', isAuth, requireRole('SUPERVISOR', 'COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/supervisor/approvals.html'));
});
app.get('/supervisor/chat', isAuth, requireRole('SUPERVISOR', 'COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/supervisor/chat.html'));
});
app.get('/supervisor/student-inbox', isAuth, requireRole('SUPERVISOR'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/supervisor/student_inbox.html'));
});

// Notifications page (all roles)
app.get('/notifications', isAuth, (req, res) => {
  res.sendFile('notifications.html', { root: './views' });
});
app.get('/profile', isAuth, (req, res) => {
  res.sendFile('profile.html', { root: './views' });
});

// Course Teacher pages
app.get('/teacher/dashboard', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/dashboard.html'));
});
app.get('/teacher/inbox', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/inbox.html'));
});
app.get('/teacher/groups', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/groups.html'));
});
app.get('/teacher/supervising-groups', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/supervising_groups.html'));
});
app.get('/teacher/student-inbox', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/student_inbox.html'));
});
app.get('/teacher/supervisor-chat', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/supervisor_chat.html'));
});
app.get('/teacher/announcements', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/announcements.html'));
});
app.get('/teacher/students', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/students.html'));
});
app.get('/teacher/grades', isAuth, requireRole('COURSE_TEACHER'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/teacher/grades.html'));
});

// ── Pre-FYDP Student Pages ─────────────────────────────────────────────────
app.get('/pre-fydp/dashboard', isAuth, requireRole('PRE_FYDP_STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/pre_fydp/dashboard.html'));
});
app.get('/pre-fydp/find-teammates', isAuth, requireRole('PRE_FYDP_STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/pre_fydp/find_teammates.html'));
});
app.get('/pre-fydp/my-requests', isAuth, requireRole('PRE_FYDP_STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/pre_fydp/my_requests.html'));
});
app.get('/pre-fydp/profile-settings', isAuth, requireRole('PRE_FYDP_STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/pre_fydp/profile_settings.html'));
});

// Student pages (Dynamic based on Group Status)
app.get('/student/dashboard', isAuth, requireRole('STUDENT'), checkGroupStatus, (req, res) => {
  if (req.activeGroup) {
    res.sendFile(path.join(__dirname, 'views/student/dashboard_fydp.html'));
  } else {
    res.sendFile(path.join(__dirname, 'views/student/dashboard_matchmaking.html'));
  }
});
app.get('/student/submit-report', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/submit_report.html'));
});
app.get('/student/reports', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/reports.html'));
});
app.get('/student/my-group-chat', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/my_group_chat.html'));
});
app.get('/student/supervisor-chat', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/supervisor_chat.html'));
});
app.get('/student/teacher-chat', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/teacher_chat.html'));
});
app.get('/student/supervisor-group-chat', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/supervisor_group_chat.html'));
});
app.get('/student/teacher-group-chat', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/teacher_group_chat.html'));
});
app.get('/student/tasks', isAuth, requireRole('STUDENT'), (req, res) => {
  res.sendFile(path.join(__dirname, 'views/student/tasks.html'));
});

// ── Root redirect ──────────────────────────────────────────────────────────
app.get('/', (req, res) => {
  if (req.session?.user) {
    const authRoutes = require('./routes/auth');
    const role = req.session.user.role;
    const dashMap = {
      'ADMIN': '/admin/dashboard',
      'SUPERVISOR': '/supervisor/dashboard',
      'COURSE_TEACHER': '/teacher/dashboard',
      'STUDENT': '/student/dashboard',
      'PRE_FYDP_STUDENT': '/pre-fydp/dashboard'
    };
    return res.redirect(dashMap[role] || '/login');
  }
  res.redirect('/login');
});

// ── Start Server ───────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(`\n🚀 FYDP System running at http://localhost:${PORT}`);
  console.log(`📌 Login: http://localhost:${PORT}/login\n`);
});

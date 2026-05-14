// Block wrong roles — return 403 or redirect
module.exports = (...roles) => (req, res, next) => {
  if (!req.session?.user) {
    return res.redirect('/login');
  }
  const userRole = req.session.user.role;
  let hasRole = roles.includes(userRole);
  if (roles.includes('SUPERVISOR') && userRole === 'COURSE_TEACHER') {
    hasRole = true;
  }
  if (!hasRole) {
    if (req.xhr || req.headers.accept?.includes('application/json')) {
      return res.status(403).json({ error: 'Access denied' });
    }
    return res.status(403).send(`
      <div style="text-align:center;padding:100px;font-family:Inter,sans-serif;">
        <h1 style="color:#ef4444;font-size:48px;">403</h1>
        <p style="color:#666;font-size:18px;">Access Denied — You don't have permission to view this page.</p>
        <a href="/" style="color:#1a237e;">Go Home</a>
      </div>
    `);
  }
  next();
};

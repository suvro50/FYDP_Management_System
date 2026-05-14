// Redirect unauthenticated users to /login
module.exports = (req, res, next) => {
  if (!req.session || !req.session.user) {
    if (req.xhr || req.headers.accept?.includes('application/json')) {
      return res.status(401).json({ error: 'Not authenticated' });
    }
    return res.redirect('/login');
  }
  next();
};

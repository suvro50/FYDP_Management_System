// Fix passwords to match the demo button credentials in login.html
const db = require('./config/db');

async function fixPasswords() {
  const updates = [
    // Admin
    { email: 'admin@uiu.ac.bd',               password: 'admin123' },
    // Supervisors
    { email: 'tanvir@uiu.ac.bd',              password: 'sup123' },
    { email: 'nadia@uiu.ac.bd',               password: 'sup123' },
    { email: 'karim@uiu.ac.bd',               password: 'sup123' },
    // Course Teachers
    { email: 'shafiq@uiu.ac.bd',              password: 'ct123' },
    { email: 'farhana@uiu.ac.bd',             password: 'ct123' },
    // FYDP Students
    { email: 'arif@student.uiu.ac.bd',        password: 'stu123' },
    { email: 'bristy@student.uiu.ac.bd',      password: 'stu123' },
    { email: 'cyrus@student.uiu.ac.bd',       password: 'stu123' },
    { email: 'dina@student.uiu.ac.bd',        password: 'stu123' },
    { email: 'emon@student.uiu.ac.bd',        password: 'stu123' },
    { email: 'farhan@student.uiu.ac.bd',      password: 'stu123' },
    { email: 'gita@student.uiu.ac.bd',        password: 'stu123' },
    { email: 'hasan@student.uiu.ac.bd',       password: 'stu123' },
    { email: 'israt@student.uiu.ac.bd',       password: 'stu123' },
    { email: 'jahir@student.uiu.ac.bd',       password: 'stu123' },
    { email: 'kamrul@student.uiu.ac.bd',      password: 'stu123' },
    { email: 'lima@student.uiu.ac.bd',        password: 'stu123' },
    // Pre-FYDP Students
    { email: 'suvrojit@student.uiu.ac.bd',    password: 'pre123' },
    { email: 'zainab@student.uiu.ac.bd',      password: 'pre123' },
    { email: 'hamza@student.uiu.ac.bd',       password: 'pre123' },
    { email: 'nusrat@student.uiu.ac.bd',      password: 'pre123' },
    { email: 'rafiq@student.uiu.ac.bd',       password: 'pre123' },
    { email: 'samira@student.uiu.ac.bd',      password: 'pre123' },
  ];

  let ok = 0;
  for (const { email, password } of updates) {
    const [res] = await db.query(
      'UPDATE users SET password_hash = SHA2(?, 256) WHERE email = ?',
      [password, email]
    );
    if (res.affectedRows > 0) {
      console.log(`✅ ${email} → password: ${password}`);
      ok++;
    } else {
      console.log(`⚠️  Not found: ${email}`);
    }
  }

  console.log(`\nDone: ${ok}/${updates.length} updated`);
  process.exit(0);
}

fixPasswords().catch(e => { console.error(e.message); process.exit(1); });

const db = require('./config/db');
async function check() {
  // Check what hash is stored
  const [[user]] = await db.query('SELECT user_id, email, password_hash, is_active, account_status FROM users WHERE email = ?', ['tanvir@uiu.ac.bd']);
  console.log('Stored hash:', user.password_hash);
  console.log('Is active:', user.is_active);
  console.log('Account status:', user.account_status);

  // Check what SHA2('123456',256) produces
  const [[row1]] = await db.query("SELECT SHA2('123456', 256) AS sha");
  console.log('SHA2(123456):', row1.sha);

  // Do they match?
  console.log('Match:', user.password_hash === row1.sha);

  // Also check what the login query actually does
  const [rows] = await db.query(
    "SELECT user_id, full_name FROM users WHERE email = ? AND password_hash = SHA2(?, 256) AND is_active = 1",
    ['tanvir@uiu.ac.bd', '123456']
  );
  console.log('Login query result:', rows.length > 0 ? rows[0] : 'NO MATCH');

  process.exit(0);
}
check().catch(e => { console.error(e.message); process.exit(1); });

const db = require('./config/db');

async function alter() {
  try {
    await db.query('ALTER TABLE users MODIFY university_id VARCHAR(20) NULL;');
    console.log('Success: university_id now allows NULL.');
  } catch (err) {
    console.error('Error:', err);
  } finally {
    process.exit();
  }
}
alter();

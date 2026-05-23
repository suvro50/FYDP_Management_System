const db = require('./config/db');

async function run() {
  try {
    console.log('Altering notifications table to add title column...');
    await db.query(`
      ALTER TABLE notifications 
      ADD COLUMN title VARCHAR(255) NULL AFTER notification_type
    `);
    console.log('Success! Column title added successfully.');
    process.exit(0);
  } catch (err) {
    if (err.errno === 1060 || err.code === 'ER_DUP_FIELDNAME') {
      console.log('Column title already exists.');
      process.exit(0);
    }
    console.error('Error altering table:', err);
    process.exit(1);
  }
}

run();

const db = require('./config/db');

async function addColumn(name, definition, after) {
  try {
    await db.query(`ALTER TABLE users ADD COLUMN ${name} ${definition} AFTER ${after}`);
    console.log(`✅ Column '${name}' added successfully.`);
  } catch (err) {
    if (err.code === 'ER_DUP_FIELDNAME') {
      console.log(`ℹ️  Column '${name}' already exists — skipping.`);
    } else {
      throw err;
    }
  }
}

async function migrate() {
  try {
    await addColumn('otp_code',       'VARCHAR(6) NULL',  'is_active');
    await addColumn('otp_expires_at', 'DATETIME NULL',    'otp_code');

    console.log('\n🎉 Migration complete! Users table is ready for OTP features.');
  } catch (err) {
    console.error('❌ Migration error:', err.message);
  } finally {
    process.exit(0);
  }
}

migrate();

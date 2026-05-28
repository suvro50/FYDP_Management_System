/**
 * Migration: Add ACCEPTED/REJECTED status + rejection_reason to task_submissions
 * Run: node migrate_task_submission_status.js
 */
const db = require('./config/db');

(async () => {
  try {
    console.log('Migrating task_submissions table...');

    // Alter status ENUM to include ACCEPTED and REJECTED
    await db.query(`
      ALTER TABLE task_submissions
        MODIFY COLUMN status ENUM('NEW','REVIEWED','ACCEPTED','REJECTED') NOT NULL DEFAULT 'NEW'
          COMMENT 'NEW=awaiting review, REVIEWED=graded, ACCEPTED=approved, REJECTED=rejected with reason'
    `);
    console.log('✅ status ENUM updated');

    // Add rejection_reason column if not exists
    try {
      await db.query(`
        ALTER TABLE task_submissions
          ADD COLUMN rejection_reason TEXT NULL DEFAULT NULL
            COMMENT 'Supervisor reason for rejection'
            AFTER feedback
      `);
      console.log('✅ rejection_reason column added');
    } catch (e) {
      if (e.code === 'ER_DUP_FIELDNAME') {
        console.log('ℹ️  rejection_reason column already exists, skipping');
      } else throw e;
    }

    console.log('✅ Migration complete!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
})();

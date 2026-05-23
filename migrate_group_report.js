/**
 * Migration: Add is_group_report column to weekly_progress_reports
 * Run: node migrate_group_report.js
 */
const db = require('./config/db');

async function migrate() {
  try {
    // Check if column already exists
    const [cols] = await db.query(
      `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
       WHERE TABLE_SCHEMA = DATABASE() 
       AND TABLE_NAME = 'weekly_progress_reports' 
       AND COLUMN_NAME = 'is_group_report'`
    );

    if (cols.length > 0) {
      console.log('✅ Column "is_group_report" already exists. Nothing to do.');
      process.exit(0);
    }

    await db.query(
      `ALTER TABLE weekly_progress_reports 
       ADD COLUMN is_group_report TINYINT(1) NOT NULL DEFAULT 0 
       AFTER report_file_path`
    );

    console.log('✅ Added "is_group_report" column to weekly_progress_reports');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
}

migrate();

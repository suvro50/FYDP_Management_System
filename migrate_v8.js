// v8.0 Live DB Migration Script
// Adds all columns needed by the backend that were missing from the live database

const db = require('./config/db');

async function migrate() {
  const alters = [
    // ── users ──────────────────────────────────────────────────────────────────
    "ALTER TABLE users ADD COLUMN batch VARCHAR(20) NULL COMMENT 'v8.0 Batch e.g. B.Sc 57'",
    "ALTER TABLE users ADD COLUMN otp_code VARCHAR(6) NULL COMMENT 'v8.0 6-digit OTP'",
    "ALTER TABLE users ADD COLUMN otp_expires_at DATETIME NULL COMMENT 'v8.0 OTP expiry'",

    // ── weekly_progress_reports ────────────────────────────────────────────────
    "ALTER TABLE weekly_progress_reports ADD COLUMN report_file_path VARCHAR(500) NULL COMMENT 'v8.0 Legacy file path'",
    "ALTER TABLE weekly_progress_reports ADD COLUMN is_group_report TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'v8.0 Group-wide report flag'",

    // ── group_tasks ────────────────────────────────────────────────────────────
    "ALTER TABLE group_tasks ADD COLUMN file_path VARCHAR(500) NULL COMMENT 'v8.0 Task attachment path'",
    "ALTER TABLE group_tasks ADD COLUMN file_name VARCHAR(255) NULL COMMENT 'v8.0 Task attachment name'",
    "ALTER TABLE group_tasks ADD COLUMN assigned_to JSON NULL COMMENT 'v8.0 JSON array of assigned student_ids'",

    // ── group_task_submissions ─────────────────────────────────────────────────
    "ALTER TABLE group_task_submissions ADD COLUMN group_id INT UNSIGNED NULL COMMENT 'v8.0 Denormalized group ref'",
    "ALTER TABLE group_task_submissions ADD COLUMN notes TEXT NULL COMMENT 'v8.0 Student notes'",
    "ALTER TABLE group_task_submissions ADD COLUMN file_path VARCHAR(500) NULL COMMENT 'v8.0 Submission file path'",
    "ALTER TABLE group_task_submissions ADD COLUMN file_name VARCHAR(255) NULL COMMENT 'v8.0 Submission file name'",
    "ALTER TABLE group_task_submissions ADD COLUMN grade VARCHAR(10) NULL COMMENT 'v8.0 Grade'",
    "ALTER TABLE group_task_submissions ADD COLUMN feedback TEXT NULL COMMENT 'v8.0 Supervisor feedback'",
    "ALTER TABLE group_task_submissions ADD COLUMN rejection_reason TEXT NULL COMMENT 'v8.0 Rejection reason'",

    // ── group_chat_messages ────────────────────────────────────────────────────
    "ALTER TABLE group_chat_messages ADD COLUMN attachment_path VARCHAR(500) NULL COMMENT 'v8.0 Legacy attachment path'",
    "ALTER TABLE group_chat_messages ADD COLUMN attachment_name VARCHAR(255) NULL COMMENT 'v8.0 Legacy attachment name'",

    // ── direct_messages ────────────────────────────────────────────────────────
    "ALTER TABLE direct_messages ADD COLUMN attachment_path VARCHAR(500) NULL COMMENT 'v8.0 Legacy attachment path'",
    "ALTER TABLE direct_messages ADD COLUMN attachment_name VARCHAR(255) NULL COMMENT 'v8.0 Legacy attachment name'",

    // ── ENUM extensions ────────────────────────────────────────────────────────
    "ALTER TABLE group_task_submissions MODIFY COLUMN status ENUM('SUBMITTED','ACKNOWLEDGED','NEEDS_REVISION','NEW','ACCEPTED','REJECTED','REVIEWED') NOT NULL DEFAULT 'SUBMITTED'",
    "ALTER TABLE pre_fydp_join_requests MODIFY COLUMN request_type ENUM('JOIN_REQUEST','INVITATION','LEAVE_REQUEST') NOT NULL DEFAULT 'JOIN_REQUEST'",
  ];

  let ok = 0, skipped = 0, failed = 0;

  for (const sql of alters) {
    try {
      await db.query(sql);
      console.log(`✅ OK: ${sql.substring(0, 90)}`);
      ok++;
    } catch (e) {
      if (e.code === 'ER_DUP_FIELDNAME') {
        console.log(`⏭️  SKIP (already exists): ${sql.substring(13, 90)}`);
        skipped++;
      } else {
        console.error(`❌ FAIL: ${e.message.substring(0, 120)}`);
        console.error(`   SQL: ${sql}`);
        failed++;
      }
    }
  }

  console.log(`\n═══════════════════════════════════`);
  console.log(`Migration complete: ✅ ${ok} ok  ⏭️ ${skipped} skipped  ❌ ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

migrate().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});

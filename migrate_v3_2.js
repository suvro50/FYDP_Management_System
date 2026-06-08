/**
 * Migration: Align live database with database.sql v3.2
 * Adds all columns/tables that are missing from the live DB.
 *
 * Run: node migrate_v3_2.js
 *
 * Safe to run multiple times — uses IF NOT EXISTS / checks before altering.
 */
const db = require('./config/db');

async function runMigration() {
  console.log('\n🔄 Starting database migration to v3.2...\n');
  let success = 0;
  let skipped = 0;

  async function run(label, sql) {
    try {
      await db.query(sql);
      console.log(`  ✅ ${label}`);
      success++;
    } catch (err) {
      if (
        err.code === 'ER_DUP_FIELDNAME' ||
        err.code === 'ER_TABLE_EXISTS_ERROR' ||
        err.code === 'ER_DUP_KEYNAME' ||
        err.message.includes('Duplicate column') ||
        err.message.includes('already exists')
      ) {
        console.log(`  ⏭️  ${label} — already exists, skipped`);
        skipped++;
      } else {
        console.error(`  ❌ ${label} — FAILED: ${err.message}`);
      }
    }
  }

  // ─── 1. users table ───────────────────────────────────────────────────────
  await run(
    'users.otp_code column',
    `ALTER TABLE users ADD COLUMN otp_code VARCHAR(10) NULL COMMENT 'Temporary OTP for email verification / password reset' AFTER is_active`
  );
  await run(
    'users.otp_expires_at column',
    `ALTER TABLE users ADD COLUMN otp_expires_at DATETIME NULL COMMENT 'OTP expiry timestamp (10 min TTL)' AFTER otp_code`
  );

  // ─── 2. weekly_progress_reports table ─────────────────────────────────────
  await run(
    'weekly_progress_reports.is_group_report column',
    `ALTER TABLE weekly_progress_reports 
     ADD COLUMN is_group_report TINYINT(1) NOT NULL DEFAULT 0 
     COMMENT '1 = submitted on behalf of entire group' 
     AFTER report_file_path`
  );

  // ─── 3. group_tasks table ─────────────────────────────────────────────────
  await run(
    'group_tasks.assigned_to column',
    `ALTER TABLE group_tasks 
     ADD COLUMN assigned_to JSON NULL 
     COMMENT 'JSON array of student user_ids — NULL means all members' 
     AFTER due_date`
  );

  // ─── 4. pre_fydp_join_requests.request_type ENUM ──────────────────────────
  await run(
    'pre_fydp_join_requests.request_type ENUM (add LEAVE_REQUEST)',
    `ALTER TABLE pre_fydp_join_requests 
     MODIFY COLUMN request_type ENUM('JOIN_REQUEST','INVITATION','LEAVE_REQUEST') 
     NOT NULL DEFAULT 'JOIN_REQUEST'`
  );

  // ─── 5. notifications.notification_type ENUM ──────────────────────────────
  await run(
    'notifications.notification_type ENUM (add LEAVE_REQUEST, LEAVE_APPROVED, LEAVE_REJECTED)',
    `ALTER TABLE notifications 
     MODIFY COLUMN notification_type ENUM(
       'INVITATION_RECEIVED','INVITATION_ACCEPTED','INVITATION_REJECTED',
       'REPORT_APPROVED','REPORT_REJECTED','ESCALATION_COMPLETE',
       'STAGE_PROMOTED','SYSTEM_ALERT',
       'NEW_GROUP_MESSAGE','NEW_DIRECT_MESSAGE',
       'LEAVE_REQUEST','LEAVE_APPROVED','LEAVE_REJECTED'
     ) NOT NULL`
  );

  // ─── 6. task_submissions table ────────────────────────────────────────────
  await run(
    'task_submissions table',
    `CREATE TABLE IF NOT EXISTS task_submissions (
        submission_id   INT UNSIGNED        NOT NULL AUTO_INCREMENT,
        task_id         INT UNSIGNED        NOT NULL COMMENT 'FK → group_tasks',
        student_id      INT UNSIGNED        NOT NULL COMMENT 'FK → users — the submitting student',
        group_id        INT UNSIGNED        NOT NULL COMMENT 'FK → project_groups — denormalised for fast filtering',
        notes           TEXT                NULL COMMENT 'Student notes / comments on submission',
        file_path       VARCHAR(500)        NULL COMMENT 'Relative server path e.g. /uploads/task_submissions/file.pdf',
        file_name       VARCHAR(255)        NULL COMMENT 'Original filename shown in UI',
        status          ENUM('NEW','REVIEWED','ACCEPTED','REJECTED') NOT NULL DEFAULT 'NEW'
                        COMMENT 'NEW = awaiting review, REVIEWED = graded, ACCEPTED/REJECTED by supervisor',
        grade           VARCHAR(10)         NULL COMMENT 'Supervisor-assigned grade e.g. A+, B, 85',
        feedback        TEXT                NULL COMMENT 'Supervisor review feedback',
        rejection_reason TEXT               NULL COMMENT 'Reason for rejection (required when status=REJECTED)',
        submitted_at    DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
        reviewed_at     DATETIME            NULL COMMENT 'Timestamp of supervisor review',
        PRIMARY KEY (submission_id),
        UNIQUE KEY uq_ts_task_student (task_id, student_id),
        CONSTRAINT fk_ts_task    FOREIGN KEY (task_id)    REFERENCES group_tasks(task_id)       ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_ts_student FOREIGN KEY (student_id) REFERENCES users(user_id)             ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_ts_group   FOREIGN KEY (group_id)   REFERENCES project_groups(group_id)   ON DELETE CASCADE ON UPDATE CASCADE,
        INDEX idx_ts_group   (group_id),
        INDEX idx_ts_student (student_id),
        INDEX idx_ts_status  (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
      COMMENT='[v3.2] Student task submissions — supervisor review/grade/feedback workflow'`
  );

  console.log(`\n✅ Migration complete! ${success} applied, ${skipped} skipped.`);
  console.log('🚀 You can now restart the server.\n');
  process.exit(0);
}

runMigration().catch(err => {
  console.error('\n❌ Migration crashed:', err.message);
  process.exit(1);
});

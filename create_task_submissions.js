/**
 * Migration: Create task_submissions table
 * Run: node create_task_submissions.js
 *
 * NOTE: This table is now also defined in database.sql (v3.2 — Section 6: Messaging).
 *       This migration script exists for incremental deployment on live databases
 *       that were created before v3.2. For fresh installs, running database.sql is sufficient.
 */
const db = require('./config/db');

(async () => {
  try {
    console.log('Creating task_submissions table...');

    await db.query(`
      CREATE TABLE IF NOT EXISTS task_submissions (
          submission_id   INT UNSIGNED        NOT NULL AUTO_INCREMENT,
          task_id         INT UNSIGNED        NOT NULL
                                              COMMENT 'FK → group_tasks',
          student_id      INT UNSIGNED        NOT NULL
                                              COMMENT 'FK → users — student who submitted',
          group_id        INT UNSIGNED        NOT NULL
                                              COMMENT 'FK → project_groups',
          notes           TEXT                NULL
                                              COMMENT 'Student notes / comments',
          file_path       VARCHAR(500)        NULL
                                              COMMENT 'Relative server path e.g. /uploads/task_submissions/file.pdf',
          file_name       VARCHAR(255)        NULL
                                              COMMENT 'Original filename shown in UI',
          status          ENUM('NEW','REVIEWED','ACCEPTED','REJECTED')
                                              NOT NULL DEFAULT 'NEW'
                                              COMMENT 'NEW = awaiting review, REVIEWED = graded, ACCEPTED/REJECTED by supervisor',
          grade           VARCHAR(10)         NULL
                                              COMMENT 'Supervisor grade e.g. A+, B, 85',
          feedback        TEXT                NULL
                                              COMMENT 'Supervisor feedback to student',
          rejection_reason TEXT               NULL
                                              COMMENT 'Reason for rejection (required when status=REJECTED)',
          submitted_at    DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
          reviewed_at     DATETIME            NULL
                                              COMMENT 'Timestamp of supervisor review',
          PRIMARY KEY (submission_id),
          UNIQUE KEY uq_ts_task_student (task_id, student_id),
          CONSTRAINT fk_ts_task
              FOREIGN KEY (task_id) REFERENCES group_tasks(task_id)
              ON DELETE CASCADE ON UPDATE CASCADE,
          CONSTRAINT fk_ts_student
              FOREIGN KEY (student_id) REFERENCES users(user_id)
              ON DELETE CASCADE ON UPDATE CASCADE,
          CONSTRAINT fk_ts_group
              FOREIGN KEY (group_id) REFERENCES project_groups(group_id)
              ON DELETE CASCADE ON UPDATE CASCADE,
          INDEX idx_ts_group (group_id),
          INDEX idx_ts_student (student_id),
          INDEX idx_ts_status (status)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='[v3.2] Student task submissions — supervisor review/grade/feedback workflow';
    `);

    console.log('✅ task_submissions table created successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
})();

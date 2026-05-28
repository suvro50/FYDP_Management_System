/**
 * Migration: Create task_submissions table
 * Run: node create_task_submissions.js
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
          grade           VARCHAR(10)         NULL
                                              COMMENT 'Supervisor grade e.g. A, B+, C, F or None',
          feedback        TEXT                NULL
                                              COMMENT 'Supervisor feedback to student',
          status          ENUM('NEW','REVIEWED')
                                              NOT NULL DEFAULT 'NEW'
                                              COMMENT 'NEW = awaiting review, REVIEWED = graded',
          submitted_at    DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
          reviewed_at     DATETIME            NULL,
          PRIMARY KEY (submission_id),
          UNIQUE KEY uq_task_student (task_id, student_id),
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
          INDEX idx_ts_status (status),
          INDEX idx_ts_task (task_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='Student task submissions with supervisor grading — created by migration';
    `);

    console.log('✅ task_submissions table created successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
})();

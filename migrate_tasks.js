const db = require('./config/db');

async function migrate() {
  try {
    // Check notifications table columns
    const [cols] = await db.query('SHOW COLUMNS FROM notifications');
    const hasTitle = cols.some(c => c.Field === 'title');

    if (!hasTitle) {
      await db.query('ALTER TABLE notifications ADD COLUMN title VARCHAR(255) NULL AFTER notification_type');
      console.log('Added title column to notifications');
    } else {
      console.log('notifications.title already exists');
    }

    // Check notification_type vs type column issue in the route
    // The route uses INSERT with 'type' column but table has 'notification_type'
    const hasType = cols.some(c => c.Field === 'type');
    console.log('Has type column:', hasType, '| Has notification_type:', cols.some(c => c.Field === 'notification_type'));

    // Create group_tasks table
    const createTasksSQL = `
      CREATE TABLE IF NOT EXISTS group_tasks (
        task_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
        group_id      INT UNSIGNED NOT NULL,
        supervisor_id INT UNSIGNED NOT NULL,
        week_no       TINYINT UNSIGNED NOT NULL,
        title         VARCHAR(300) NOT NULL,
        description   TEXT NULL,
        file_path     VARCHAR(500) NULL,
        file_name     VARCHAR(255) NULL,
        due_date      DATE NULL,
        created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (task_id),
        CONSTRAINT fk_gt_group FOREIGN KEY (group_id) REFERENCES project_groups(group_id) ON DELETE CASCADE,
        CONSTRAINT fk_gt_supervisor FOREIGN KEY (supervisor_id) REFERENCES users(user_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `;
    await db.query(createTasksSQL);
    console.log('group_tasks table ready');

    // Check if weekly_progress_reports has report_file_path column
    const [wprCols] = await db.query('SHOW COLUMNS FROM weekly_progress_reports');
    const hasFilePath = wprCols.some(c => c.Field === 'report_file_path');
    if (!hasFilePath) {
      await db.query('ALTER TABLE weekly_progress_reports ADD COLUMN report_file_path VARCHAR(500) NULL AFTER supervisor_feedback');
      console.log('Added report_file_path column to weekly_progress_reports');
    } else {
      console.log('report_file_path already exists');
    }

    // Check if group_tasks has assigned_to column (for individual task assignment)
    const [gtCols] = await db.query('SHOW COLUMNS FROM group_tasks');
    const hasAssignedTo = gtCols.some(c => c.Field === 'assigned_to');
    if (!hasAssignedTo) {
      await db.query("ALTER TABLE group_tasks ADD COLUMN assigned_to JSON NULL COMMENT 'JSON array of student user_ids. NULL = all members' AFTER due_date");
      console.log('Added assigned_to column to group_tasks');
    } else {
      console.log('group_tasks.assigned_to already exists');
    }

    console.log('Migration complete!');
    process.exit(0);
  } catch (err) {
    console.error('Migration error:', err.message);
    process.exit(1);
  }
}

migrate();

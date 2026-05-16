require('dotenv').config();
const db = require('./config/db');

async function run() {
  try {
    // Create group_chat_messages
    await db.query(`
      CREATE TABLE IF NOT EXISTS group_chat_messages (
        message_id    INT UNSIGNED     NOT NULL AUTO_INCREMENT,
        group_id      INT UNSIGNED     NOT NULL,
        sender_id     INT UNSIGNED     NOT NULL,
        message_text  TEXT             NULL,
        attachment_path VARCHAR(500)   DEFAULT NULL,
        attachment_name VARCHAR(255)   DEFAULT NULL,
        chat_type     ENUM('STUDENT_ONLY','WITH_SUPERVISOR','WITH_TEACHER') NOT NULL DEFAULT 'STUDENT_ONLY',
        created_at    DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (message_id),
        INDEX idx_group_type (group_id, chat_type),
        INDEX idx_sender (sender_id),
        FOREIGN KEY (group_id) REFERENCES project_groups(group_id) ON DELETE CASCADE,
        FOREIGN KEY (sender_id) REFERENCES users(user_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ group_chat_messages table created/exists');

    // Create direct_messages
    await db.query(`
      CREATE TABLE IF NOT EXISTS direct_messages (
        message_id      INT UNSIGNED   NOT NULL AUTO_INCREMENT,
        sender_id       INT UNSIGNED   NOT NULL,
        receiver_id     INT UNSIGNED   NOT NULL,
        message_text    TEXT           NULL,
        attachment_path VARCHAR(500)   DEFAULT NULL,
        attachment_name VARCHAR(255)   DEFAULT NULL,
        is_read         TINYINT(1)     NOT NULL DEFAULT 0,
        created_at      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (message_id),
        INDEX idx_receiver_read (receiver_id, is_read),
        INDEX idx_sender (sender_id),
        FOREIGN KEY (sender_id) REFERENCES users(user_id) ON DELETE CASCADE,
        FOREIGN KEY (receiver_id) REFERENCES users(user_id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ direct_messages table created/exists');

    process.exit(0);
  } catch (e) {
    console.error('❌ Error:', e.message);
    process.exit(1);
  }
}
run();

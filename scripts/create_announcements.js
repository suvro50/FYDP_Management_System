const db = require('../config/db');

const sql = `
CREATE TABLE IF NOT EXISTS announcements (
    announcement_id INT UNSIGNED        NOT NULL  AUTO_INCREMENT,
    author_id       INT UNSIGNED        NOT NULL,
    title           VARCHAR(255)        NOT NULL,
    content         TEXT                NOT NULL,
    target_role     VARCHAR(50)         NOT NULL  DEFAULT 'ALL',
    target_section  VARCHAR(100)        NULL,
    created_at      DATETIME            NOT NULL  DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (announcement_id),
    CONSTRAINT fk_ann_author
        FOREIGN KEY (author_id) REFERENCES users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_ann_author (author_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
`;

db.query(sql)
  .then(() => {
    console.log('✅ announcements table created successfully');
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ ERROR:', err.message);
    process.exit(1);
  });

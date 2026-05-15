const db = require('./config/db');

(async () => {
  try {
    const sql = `ALTER TABLE group_chat_messages 
                 MODIFY COLUMN chat_type 
                 ENUM('STUDENT_ONLY','WITH_SUPERVISOR','WITH_TEACHER') 
                 NOT NULL DEFAULT 'STUDENT_ONLY'`;
    const [r] = await db.query(sql);
    console.log('SUCCESS: chat_type ENUM updated -', r.message || 'done');
  } catch (e) {
    console.error('ERROR:', e.message);
  } finally {
    process.exit(0);
  }
})();

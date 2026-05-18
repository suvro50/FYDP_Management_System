const db = require('./config/db');

async function migrate() {
  await db.query(
    "ALTER TABLE notifications MODIFY COLUMN notification_type ENUM('INVITATION_RECEIVED','INVITATION_ACCEPTED','INVITATION_REJECTED','REPORT_APPROVED','REPORT_REJECTED','ESCALATION_COMPLETE','STAGE_PROMOTED','SYSTEM_ALERT','NEW_GROUP_MESSAGE','NEW_DIRECT_MESSAGE','LEAVE_APPROVED','LEAVE_REJECTED','LEAVE_REQUEST') NOT NULL"
  );
  console.log('✅ Added LEAVE_APPROVED, LEAVE_REJECTED, LEAVE_REQUEST to notification_type enum');
  process.exit(0);
}

migrate().catch(e => { console.error(e); process.exit(1); });

/**
 * Migration: Create supervisor_requests table
 * 
 * This table tracks requests from Pre-FYDP groups to supervisors.
 * When a supervisor accepts, the group transitions to FYDP-1.
 */
require('dotenv').config();
const db = require('./config/db');

async function migrate() {
  console.log('🚀 Starting supervisor_requests migration...\n');

  try {
    // 1. Create supervisor_requests table
    console.log('1️⃣  Creating supervisor_requests table...');
    await db.query(`
      CREATE TABLE IF NOT EXISTS supervisor_requests (
        request_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
        pre_fydp_group_id  INT UNSIGNED  NOT NULL,
        supervisor_id      INT UNSIGNED  NOT NULL,
        project_title      VARCHAR(300)  NOT NULL,
        project_abstract   TEXT          NULL,
        request_status     ENUM('PENDING','ACCEPTED','REJECTED','CANCELLED','AUTO_REJECTED')
                           NOT NULL DEFAULT 'PENDING',
        rejection_reason   TEXT          NULL,
        responded_at       DATETIME      NULL,
        created_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (request_id),
        UNIQUE KEY uq_sr_group_supervisor (pre_fydp_group_id, supervisor_id),
        CONSTRAINT fk_sr_group FOREIGN KEY (pre_fydp_group_id)
          REFERENCES pre_fydp_groups(group_id) ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT fk_sr_supervisor FOREIGN KEY (supervisor_id)
          REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
        INDEX idx_sr_supervisor (supervisor_id),
        INDEX idx_sr_status (request_status),
        INDEX idx_sr_group (pre_fydp_group_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        COMMENT='Pre-FYDP group → Supervisor requests. Accepted = transition to FYDP-1';
    `);
    console.log('   ✅ supervisor_requests table created.\n');

    // 2. Add new notification types if they don't exist
    // The notifications table uses ENUM, so we need to ALTER it to add new types
    console.log('2️⃣  Updating notifications ENUM to include supervisor request types...');
    try {
      await db.query(`
        ALTER TABLE notifications
        MODIFY COLUMN notification_type
          ENUM('INVITATION_RECEIVED','INVITATION_ACCEPTED',
               'INVITATION_REJECTED','REPORT_APPROVED',
               'REPORT_REJECTED','ESCALATION_COMPLETE',
               'STAGE_PROMOTED','SYSTEM_ALERT',
               'NEW_GROUP_MESSAGE','NEW_DIRECT_MESSAGE',
               'TASK_ASSIGNED','TASK_REVIEWED',
               'PASSWORD_RESET_REQUESTED',
               'SUPERVISOR_REQUEST_RECEIVED',
               'SUPERVISOR_REQUEST_ACCEPTED',
               'SUPERVISOR_REQUEST_REJECTED',
               'SUPERVISOR_SLOT_FULL',
               'LEAVE_REQUEST','LEAVE_APPROVED','LEAVE_REJECTED')
          NOT NULL
      `);
      console.log('   ✅ Notification types updated.\n');
    } catch (enumErr) {
      if (enumErr.message.includes('Duplicate')) {
        console.log('   ⚠️  Notification types already exist (skipping).\n');
      } else {
        console.warn('   ⚠️  Could not update ENUM (non-fatal):', enumErr.message);
        console.log('   Will use SYSTEM_ALERT as fallback for notifications.\n');
      }
    }

    // 3. Add reference_entity_type for supervisor_requests
    console.log('3️⃣  Updating reference_entity_type ENUM...');
    try {
      await db.query(`
        ALTER TABLE notifications
        MODIFY COLUMN reference_entity_type
          ENUM('matchmaking_team_invitations','project_groups',
               'course_teacher_inbox','weekly_progress_reports',
               'pre_fydp_join_requests','group_chat_messages',
               'direct_messages','group_tasks','supervisor_requests')
          NULL
      `);
      console.log('   ✅ reference_entity_type updated.\n');
    } catch (refErr) {
      console.warn('   ⚠️  Could not update reference_entity_type (non-fatal):', refErr.message, '\n');
    }

    // 4. Verify
    const [tables] = await db.query(`SHOW TABLES LIKE 'supervisor_requests'`);
    if (tables.length > 0) {
      console.log('🎉 Migration complete! supervisor_requests table is ready.');
    } else {
      console.error('❌ Migration failed — table not found after creation.');
    }

    // 5. Show table structure
    const [cols] = await db.query(`DESCRIBE supervisor_requests`);
    console.log('\n📋 Table structure:');
    cols.forEach(c => {
      console.log(`   ${c.Field.padEnd(22)} ${c.Type.padEnd(45)} ${c.Null === 'YES' ? 'NULL' : 'NOT NULL'}`);
    });

  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    console.error(err);
  }

  process.exit(0);
}

migrate();

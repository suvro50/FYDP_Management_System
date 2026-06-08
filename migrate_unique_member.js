/**
 * Migration: Add UNIQUE constraint on user_id in pre_fydp_group_members
 * 
 * This enforces at the database level that a student can only be in ONE group at a time.
 * Before adding the constraint, it cleans up any duplicate memberships (keeps the earliest).
 */
const db = require('./config/db');

async function migrate() {
  console.log('=== Migration: Enforce one-group-per-student ===\n');

  // 1. Find students who are in multiple groups
  const [dupes] = await db.query(`
    SELECT user_id, COUNT(*) as group_count, GROUP_CONCAT(group_id) as group_ids
    FROM pre_fydp_group_members
    GROUP BY user_id
    HAVING COUNT(*) > 1
  `);

  if (dupes.length > 0) {
    console.log(`Found ${dupes.length} student(s) in multiple groups. Cleaning up...`);
    for (const dupe of dupes) {
      console.log(`  User ${dupe.user_id} is in groups: ${dupe.group_ids}`);
      // Keep the earliest membership (lowest member_id), remove the rest
      const [memberships] = await db.query(
        `SELECT member_id, group_id FROM pre_fydp_group_members 
         WHERE user_id = ? ORDER BY joined_at ASC, member_id ASC`, [dupe.user_id]
      );
      const keep = memberships[0];
      const removeIds = memberships.slice(1).map(m => m.member_id);
      console.log(`    Keeping member_id=${keep.member_id} (group ${keep.group_id}), removing: ${removeIds.join(', ')}`);
      await db.query(
        `DELETE FROM pre_fydp_group_members WHERE member_id IN (${removeIds.map(() => '?').join(',')})`,
        removeIds
      );
    }
    console.log('Cleanup done.\n');
  } else {
    console.log('No duplicate memberships found. Good!\n');
  }

  // 2. Check if unique constraint already exists
  const [indexes] = await db.query(`
    SHOW INDEX FROM pre_fydp_group_members WHERE Key_name = 'uq_pfgm_user_id'
  `);

  if (indexes.length > 0) {
    console.log('UNIQUE constraint uq_pfgm_user_id already exists. Skipping.');
  } else {
    console.log('Adding UNIQUE constraint on user_id...');
    await db.query(`
      ALTER TABLE pre_fydp_group_members ADD CONSTRAINT uq_pfgm_user_id UNIQUE (user_id)
    `);
    console.log('UNIQUE constraint added successfully!');
  }

  console.log('\n=== Migration complete ===');
  process.exit(0);
}

migrate().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});

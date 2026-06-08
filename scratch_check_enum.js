const db = require('./config/db');

async function forceRemoveMember() {
  // Get user info for suvrojit
  const [[user]] = await db.query(`SELECT user_id, full_name FROM users WHERE email = 'suvrojit@student.uiu.ac.bd'`);
  console.log(`User: ${user.full_name} (ID: ${user.user_id})`);

  // Check current memberships
  const [memberships] = await db.query(`
    SELECT gm.group_id, g.group_name, gm.member_role 
    FROM pre_fydp_group_members gm 
    JOIN pre_fydp_groups g ON gm.group_id = g.group_id 
    WHERE gm.user_id = ?`, [user.user_id]);
  console.log('Current memberships:', JSON.stringify(memberships, null, 2));

  if (memberships.length === 0) {
    console.log('Not in any group!');
    process.exit(0);
  }

  for (const m of memberships) {
    // Remove from group
    await db.query(`DELETE FROM pre_fydp_group_members WHERE group_id = ? AND user_id = ?`, [m.group_id, user.user_id]);
    console.log(`✅ Removed from group "${m.group_name}"`);

    // Cancel any pending leave requests for this group
    await db.query(`
      UPDATE pre_fydp_join_requests 
      SET request_status = 'CANCELLED', responded_at = NOW() 
      WHERE sender_id = ? AND group_id = ? AND request_status = 'PENDING'`, 
      [user.user_id, m.group_id]);
    console.log(`✅ Cancelled pending leave requests for "${m.group_name}"`);

    // If group was FULL, re-open it
    await db.query(`
      UPDATE pre_fydp_groups SET group_status = 'OPEN' 
      WHERE group_id = ? AND group_status = 'FULL'`, [m.group_id]);
  }

  // Reset availability to LOOKING
  await db.query(`
    UPDATE user_profiles SET availability_status = 'LOOKING' 
    WHERE user_id = ? AND profile_type = 'PRE_FYDP'`, [user.user_id]);
  console.log(`✅ Reset availability to LOOKING`);

  // Also cancel all other pending join/leave requests
  await db.query(`
    UPDATE pre_fydp_join_requests 
    SET request_status = 'CANCELLED', responded_at = NOW() 
    WHERE sender_id = ? AND request_status = 'PENDING'`, [user.user_id]);
  console.log(`✅ Cancelled all pending requests`);

  console.log('\n🎉 Done! You are now free to join or create another group.');
  process.exit(0);
}

forceRemoveMember().catch(e => { console.error(e); process.exit(1); });

const db = require('./config/db');
async function checkAllGroups() {
  // Get all active groups with member counts
  const [groups] = await db.query(
    "SELECT pg.group_id, pg.group_code, pg.project_title, " +
    "COUNT(gm.student_id) as member_count " +
    "FROM project_groups pg " +
    "LEFT JOIN group_members gm ON pg.group_id = gm.group_id " +
    "WHERE pg.is_active = 1 " +
    "GROUP BY pg.group_id, pg.group_code, pg.project_title " +
    "ORDER BY pg.group_id"
  );
  console.log('All active groups:');
  groups.forEach(g => {
    const status = g.member_count < 4 ? '❌ UNDER (needs ' + (4 - g.member_count) + ' more)' :
                   g.member_count > 5 ? '⚠️  OVER' : '✅ OK';
    console.log(` ${g.group_code}: ${g.member_count} members ${status} | ${g.project_title}`);
  });

  // Get all students NOT in any active group
  const [available] = await db.query(
    "SELECT u.user_id, u.university_id, u.full_name " +
    "FROM users u " +
    "WHERE u.role = 'STUDENT' AND u.is_active = 1 " +
    "AND u.user_id NOT IN (" +
    "  SELECT gm.student_id FROM group_members gm " +
    "  JOIN project_groups pg ON gm.group_id = pg.group_id WHERE pg.is_active = 1" +
    ")"
  );
  console.log('\nAvailable students (not in any group): ' + available.length);
  available.forEach(s => console.log(' -', s.university_id, s.full_name));
  process.exit(0);
}
checkAllGroups().catch(e => { console.error(e.message); process.exit(1); });

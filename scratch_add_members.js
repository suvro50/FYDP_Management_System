const db = require('./config/db');
const crypto = require('crypto');

async function createAndAddStudents() {
  // Get CSE department ID and UIU-G004 group_id
  const [[cse]] = await db.query("SELECT department_id FROM departments WHERE short_code = 'CSE'");
  const [[grp]] = await db.query("SELECT group_id FROM project_groups WHERE group_code = 'UIU-G004'");

  const newStudents = [
    { university_id: 'STU013', full_name: 'Mehedi Hasan',   email: 'mehedi@student.uiu.ac.bd',   phone: '01811000013' },
    { university_id: 'STU014', full_name: 'Nadia Sultana',  email: 'nadia.s@student.uiu.ac.bd',  phone: '01811000014' },
  ];

  const passwordHash = crypto.createHash('sha256').update('stu123').digest('hex');

  for (const s of newStudents) {
    // Insert user
    const [result] = await db.query(
      "INSERT INTO users (university_id, full_name, email, password_hash, role, department_id, phone, account_status) " +
      "VALUES (?, ?, ?, ?, 'STUDENT', ?, ?, 'ACTIVE')",
      [s.university_id, s.full_name, s.email, passwordHash, cse.department_id, s.phone]
    );
    const userId = result.insertId;

    // Insert into group_members
    await db.query(
      "INSERT INTO group_members (group_id, student_id, member_role) VALUES (?, ?, 'DEVELOPER')",
      [grp.group_id, userId]
    );

    console.log(`✅ Created & added: ${s.full_name} (${s.university_id}) → user_id: ${userId}`);
  }

  // Final summary
  console.log('\n=== FINAL GROUP SUMMARY ===');
  const [final] = await db.query(
    "SELECT pg.group_code, pg.project_title, COUNT(gm.student_id) as member_count " +
    "FROM project_groups pg " +
    "LEFT JOIN group_members gm ON pg.group_id = gm.group_id " +
    "WHERE pg.is_active = 1 " +
    "GROUP BY pg.group_id, pg.group_code, pg.project_title ORDER BY pg.group_id"
  );
  final.forEach(g => {
    const status = g.member_count < 4 ? '❌ UNDER' : g.member_count > 5 ? '⚠️ OVER' : '✅ OK';
    console.log(` ${g.group_code}: ${g.member_count} members ${status} — ${g.project_title}`);
  });

  // Show UIU-G004 members
  console.log('\nUIU-G004 members:');
  const [members] = await db.query(
    "SELECT u.university_id, u.full_name, gm.member_role " +
    "FROM group_members gm JOIN users u ON gm.student_id = u.user_id " +
    "WHERE gm.group_id = ? ORDER BY gm.joined_at",
    [grp.group_id]
  );
  members.forEach(m => console.log(` - ${m.university_id} ${m.full_name} | ${m.member_role}`));

  process.exit(0);
}
createAndAddStudents().catch(e => { console.error(e.message); process.exit(1); });

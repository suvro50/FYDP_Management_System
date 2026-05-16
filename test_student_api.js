require('dotenv').config();
const db = require('./config/db');

async function test() {
  try {
    const studentId = 7;
    const groupId = 1;
    const supervisorId = 2;

    // Test 1: members
    const [members] = await db.query(
      `SELECT u.full_name, u.university_id, u.user_id, u.profile_photo, gm.member_role
       FROM group_members gm
       JOIN users u ON gm.student_id = u.user_id
       WHERE gm.group_id = ?
       ORDER BY FIELD(gm.member_role,'TEAM_LEAD','DEVELOPER','DESIGNER','RESEARCHER','TESTER','DATA_ENGINEER')`,
      [groupId]
    );
    console.log('✅ members:', members.length);

    // Test 2: supervisor with dept JOIN
    const [supRows] = await db.query(
      `SELECT u.user_id, u.full_name, u.email, d.department_name AS department, u.profile_photo
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE u.user_id = ?`,
      [supervisorId]
    );
    console.log('✅ supervisor:', supRows[0]?.full_name, '| dept:', supRows[0]?.department);

    // Test 3: reports
    const [reports] = await db.query(
      `SELECT report_id, week_no, report_title, supervisor_status, supervisor_feedback,
              report_file_path, submitted_at
       FROM weekly_progress_reports
       WHERE group_id = ? AND student_id = ?
       ORDER BY week_no DESC LIMIT 6`,
      [groupId, studentId]
    );
    console.log('✅ reports:', reports.length);

    // Test 4: allReports stats
    const [allReports] = await db.query(
      `SELECT supervisor_status FROM weekly_progress_reports WHERE group_id = ? AND student_id = ?`,
      [groupId, studentId]
    );
    console.log('✅ allReports:', allReports.length);

    // Test 5: group_chat_messages - does this table exist?
    const [unreadMsgs] = await db.query(
      `SELECT COUNT(*) as cnt FROM group_chat_messages WHERE group_id = ? AND sender_id != ?`,
      [groupId, studentId]
    );
    console.log('✅ unread messages:', unreadMsgs[0]?.cnt);

    console.log('\n🎉 All queries passed!');
    process.exit(0);
  } catch (e) {
    console.error('\n❌ FAILED:', e.message);
    console.error('SQL State:', e.sqlState);
    console.error('SQL Message:', e.sqlMessage);
    process.exit(1);
  }
}

test();

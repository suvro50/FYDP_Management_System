const db = require('./config/db');

async function run() {
  try {
    const [groups] = await db.execute(`
      SELECT g.group_id, g.project_title, COUNT(gm.student_id) AS member_count
      FROM project_groups g
      LEFT JOIN group_members gm ON g.group_id = gm.group_id
      GROUP BY g.group_id
      ORDER BY member_count ASC
    `);
    console.log("Groups and their member counts:");
    console.table(groups);
  } catch (err) {
    console.error(err);
  } finally {
    process.exit(0);
  }
}
run();

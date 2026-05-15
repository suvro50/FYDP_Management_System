const db = require('./config/db');

async function run() {
  try {
    const [groups] = await db.execute(`
      SELECT g.group_id, g.project_title, COUNT(gm.student_id) AS member_count
      FROM project_groups g
      LEFT JOIN group_members gm ON g.group_id = gm.group_id
      GROUP BY g.group_id
      HAVING member_count < 4
    `);

    if (groups.length === 0) {
      console.log("All groups already have at least 4 members.");
      process.exit(0);
    }

    console.log(`Found ${groups.length} groups that need members.`);

    const dummyHash = '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9';
    let totalAdded = 0;

    for (const group of groups) {
      const missingCount = 4 - group.member_count;
      console.log(`Adding ${missingCount} members to Group ${group.group_id} (${group.project_title})`);

      for (let i = 0; i < missingCount; i++) {
        // Create a new dummy student
        const randId = Math.floor(Math.random() * 1000000);
        const name = `Dummy Student ${randId}`;
        const email = `dummy${randId}@example.com`;
        const uniId = `011${randId}`; // Mock UIU ID

        // Insert into users
        const [userRes] = await db.execute(
          `INSERT INTO users (full_name, email, password_hash, role, university_id, department, batch) VALUES (?, ?, ?, 'STUDENT', ?, 'CSE', '201')`,
          [name, email, dummyHash, uniId]
        );
        const newUserId = userRes.insertId;

        // Insert into student_profiles
        await db.execute(
          `INSERT INTO student_profiles (student_id, cgpa, preferred_team_role) VALUES (?, 3.50, 'DEVELOPER')`,
          [newUserId]
        );

        // Add to group_members
        const roles = ['DEVELOPER', 'DESIGNER', 'TESTER', 'RESEARCHER'];
        const role = roles[i % roles.length];
        
        await db.execute(
          `INSERT INTO group_members (group_id, student_id, member_role) VALUES (?, ?, ?)`,
          [group.group_id, newUserId, role]
        );
        
        totalAdded++;
      }
    }

    console.log(`✅ Successfully added ${totalAdded} members across ${groups.length} groups.`);

  } catch (err) {
    console.error("Error:", err);
  } finally {
    process.exit(0);
  }
}
run();

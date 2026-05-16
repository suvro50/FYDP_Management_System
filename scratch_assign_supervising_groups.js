const db = require('./config/db');

async function run() {
  try {
    console.log("Assigning groups...");
    
    // Group 1 (UIU-G001): Assign supervisor 5 (Shafiq Alam), Stage 1 (FYDP-1)
    await db.query("UPDATE project_groups SET supervisor_id = 5, current_stage_id = 1 WHERE group_id = 1");
    console.log("- Assigned Group UIU-G001 to Shafiq Alam under FYDP-1");

    // Group 2 (UIU-G002): Assign supervisor 5, Stage 2 (FYDP-2)
    await db.query("UPDATE project_groups SET supervisor_id = 5, current_stage_id = 2 WHERE group_id = 2");
    console.log("- Assigned Group UIU-G002 to Shafiq Alam under FYDP-2");

    // Group 3 (UIU-G003): Assign supervisor 5, Stage 3 (FYDP-3)
    await db.query("UPDATE project_groups SET supervisor_id = 5, current_stage_id = 3 WHERE group_id = 3");
    console.log("- Assigned Group UIU-G003 to Shafiq Alam under FYDP-3");

    console.log("Groups updated successfully!");

    // Verify after update
    const [groups] = await db.query(`
      SELECT pg.group_id, pg.group_code, pg.project_title, pg.supervisor_id, pg.current_stage_id,
             fs.stage_name, s.section_code, sup.full_name as supervisor_name
      FROM project_groups pg
      JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
      JOIN sections s ON s.section_id = pg.section_id
      LEFT JOIN users sup ON sup.user_id = pg.supervisor_id
      WHERE pg.is_active = 1 AND pg.supervisor_id = 5
    `);
    console.log("\nShafiq Alam's Supervising Groups:");
    console.table(groups);

  } catch (err) {
    console.error(err);
  } finally {
    process.exit(0);
  }
}
run();

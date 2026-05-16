const db = require('./config/db');

async function run() {
  try {
    const [columns] = await db.query("SHOW COLUMNS FROM weekly_progress_reports");
    console.log("weekly_progress_reports Table Columns:");
    console.table(columns);
  } catch (err) {
    console.error(err);
  } finally {
    process.exit(0);
  }
}
run();

const db = require('./config/db');

async function run() {
  try {
    const [columns] = await db.query("SHOW COLUMNS FROM users");
    console.log("Users Table Columns:");
    console.table(columns);

    const [users] = await db.query("SELECT * FROM users");
    console.log("All Users:");
    console.table(users);
  } catch (err) {
    console.error(err);
  } finally {
    process.exit(0);
  }
}
run();

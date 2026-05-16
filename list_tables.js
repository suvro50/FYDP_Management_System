require('dotenv').config();
const db = require('./config/db');
async function run() {
  const [tables] = await db.query('SHOW TABLES');
  tables.forEach(t => console.log(Object.values(t)[0]));
  process.exit(0);
}
run().catch(e => { console.error(e.message); process.exit(1); });

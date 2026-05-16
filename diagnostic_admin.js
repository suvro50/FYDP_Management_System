const db = require('./config/db');

async function test() {
  console.log('=== ADMIN QUERY DIAGNOSTICS (FIXED) ===\n');

  // Test: users list with fixed query (departments JOIN)
  try {
    const [u] = await db.query(
      `SELECT u.user_id, u.university_id, u.full_name, u.email, u.role,
              d.department_name as department, u.batch, u.phone, u.account_status, u.is_active,
              u.created_at
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       WHERE 1=1
       ORDER BY u.created_at DESC LIMIT 5 OFFSET 0`
    );
    console.log('✅ users list: OK -', u.length, 'rows');
    if (u.length > 0) console.log('   Sample:', u[0].full_name, '|', u[0].role, '| dept:', u[0].department);
  } catch(e) { console.error('❌ users list FAIL:', e.message); }

  // Test: supervisors with fixed query
  try {
    const [s] = await db.query(
      `SELECT u.user_id, u.full_name, d.department_name as department,
              COUNT(pg.group_id) as assigned_groups
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       LEFT JOIN project_groups pg ON pg.supervisor_id = u.user_id AND pg.is_active=1
       WHERE u.role='SUPERVISOR' AND u.is_active=1
       GROUP BY u.user_id
       ORDER BY u.full_name`
    );
    console.log('✅ supervisors: OK -', s.length, 'rows');
    if (s.length > 0) console.log('   Sample:', s[0].full_name, '| dept:', s[0].department, '| groups:', s[0].assigned_groups);
  } catch(e) { console.error('❌ supervisors FAIL:', e.message); }

  // Test: course-teachers with fixed query
  try {
    const [t] = await db.query(
      `SELECT u.user_id, u.full_name, d.department_name as department,
              COUNT(DISTINCT cts.mapping_id) as assigned_sections
       FROM users u
       LEFT JOIN departments d ON d.department_id = u.department_id
       LEFT JOIN course_teacher_sections cts ON cts.course_teacher_id = u.user_id
       WHERE u.role='COURSE_TEACHER' AND u.is_active=1
       GROUP BY u.user_id
       ORDER BY u.full_name`
    );
    console.log('✅ course-teachers: OK -', t.length, 'rows');
    if (t.length > 0) console.log('   Sample:', t[0].full_name, '| dept:', t[0].department, '| sections:', t[0].assigned_sections);
  } catch(e) { console.error('❌ course-teachers FAIL:', e.message); }

  // Test: teacher-sections with fixed query
  try {
    const [r] = await db.query(
      `SELECT cts.mapping_id, cts.course_teacher_id, cts.assigned_stage_id,
              s.section_code, s.section_id,
              u.full_name as teacher_name, d.department_name as department,
              fs.stage_name,
              COUNT(DISTINCT pg.group_id) as group_count
       FROM course_teacher_sections cts
       JOIN users u ON u.user_id = cts.course_teacher_id
       LEFT JOIN departments d ON d.department_id = u.department_id
       JOIN fydp_stages fs ON fs.stage_id = cts.assigned_stage_id
       JOIN sections s ON s.section_id = cts.section_id
       LEFT JOIN project_groups pg ON pg.section_id = cts.section_id AND pg.is_active=1
       GROUP BY cts.mapping_id
       ORDER BY fs.stage_order, s.section_code, u.full_name`
    );
    console.log('✅ teacher-sections: OK -', r.length, 'rows');
    if (r.length > 0) console.log('   Sample:', r[0].teacher_name, '| section:', r[0].section_code, '| stage:', r[0].stage_name);
  } catch(e) { console.error('❌ teacher-sections FAIL:', e.message); }

  // Test: admin dashboard stats
  try {
    const [[s1]] = await db.query("SELECT COUNT(*) as count FROM users WHERE role='STUDENT' AND is_active=1");
    const [[s2]] = await db.query("SELECT COUNT(*) as count FROM users WHERE role='SUPERVISOR' AND is_active=1");
    const [[s3]] = await db.query("SELECT COUNT(*) as count FROM users WHERE role='COURSE_TEACHER' AND is_active=1");
    const [[s4]] = await db.query("SELECT COUNT(*) as count FROM project_groups WHERE project_status='ACTIVE' AND is_active=1");
    console.log(`✅ dashboard stats: students=${s1.count}, supervisors=${s2.count}, teachers=${s3.count}, groups=${s4.count}`);
  } catch(e) { console.error('❌ dashboard stats FAIL:', e.message); }

  // Test: assign-supervisor/groups
  try {
    const [g] = await db.query(
      `SELECT pg.group_id, pg.group_code, s.section_code, fs.stage_name,
              pg.supervisor_id, u_sup.full_name as supervisor_name,
              (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id=pg.group_id) as member_count
       FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id=pg.current_stage_id
       JOIN project_domains pd ON pd.domain_id=pg.project_domain_id
       JOIN sections s ON s.section_id=pg.section_id
       LEFT JOIN users u_sup ON u_sup.user_id=pg.supervisor_id
       WHERE pg.is_active=1
       ORDER BY pg.group_code LIMIT 3`
    );
    console.log('✅ assign-supervisor/groups: OK -', g.length, 'rows');
  } catch(e) { console.error('❌ assign-supervisor/groups FAIL:', e.message); }

  // Test: admin groups list
  try {
    const [[{total}]] = await db.query(
      `SELECT COUNT(*) as total FROM project_groups pg
       JOIN fydp_stages fs ON fs.stage_id = pg.current_stage_id
       JOIN sections s ON s.section_id = pg.section_id WHERE 1=1`
    );
    console.log('✅ admin groups count: OK -', total, 'rows');
  } catch(e) { console.error('❌ admin groups FAIL:', e.message); }

  // Test: audit_log table exists?
  try {
    const [[{cnt}]] = await db.query("SELECT COUNT(*) as cnt FROM audit_log");
    console.log('✅ audit_log: OK -', cnt, 'rows');
  } catch(e) { console.error('❌ audit_log FAIL:', e.message, '(table may not exist)'); }

  console.log('\n=== DONE ===');
  process.exit(0);
}

test().catch(err => { console.error('FATAL:', err); process.exit(1); });

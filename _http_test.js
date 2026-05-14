// HTTP integration test for teacher dashboard endpoints
require('dotenv').config();
const http = require('http');

function req(options, postData = null) {
  return new Promise((resolve, reject) => {
    const r = http.request(options, res => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        resolve({ status: res.statusCode, headers: res.headers, body });
      });
    });
    r.on('error', reject);
    if (postData) r.write(postData);
    r.end();
  });
}

async function run() {
  console.log('=== TEACHER DASHBOARD HTTP INTEGRATION TESTS ===\n');

  // Step 1: Login
  const loginData = JSON.stringify({ email: 'shafiq@uiu.ac.bd', password: 'ct123' });
  const loginRes = await req({
    hostname: 'localhost', port: 3000, path: '/login',
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(loginData) }
  }, loginData);

  const setCookie = loginRes.headers['set-cookie'];
  const loginBody = JSON.parse(loginRes.body);

  if (loginRes.status === 200 && loginBody.success) {
    console.log('✅ POST /login              →', loginRes.status, '| redirect:', loginBody.redirect, '| user:', loginBody.user.full_name);
  } else {
    console.log('❌ POST /login              →', loginRes.status, loginRes.body);
    process.exit(1);
  }

  const cookie = setCookie ? setCookie[0].split(';')[0] : '';

  // Helper: authenticated GET
  async function authGet(path) {
    const r = await req({
      hostname: 'localhost', port: 3000, path,
      method: 'GET',
      headers: { Cookie: cookie }
    });
    return r;
  }

  // Step 2: Dashboard page
  const dash = await authGet('/teacher/dashboard');
  console.log(dash.status === 200 ? '✅' : '❌', 'GET /teacher/dashboard      →', dash.status);

  // Step 3: Inbox page
  const inbox = await authGet('/teacher/inbox');
  console.log(inbox.status === 200 ? '✅' : '❌', 'GET /teacher/inbox         →', inbox.status);

  // Step 4: Groups page
  const groups = await authGet('/teacher/groups');
  console.log(groups.status === 200 ? '✅' : '❌', 'GET /teacher/groups        →', groups.status);

  // Step 5: Student inbox page
  const si = await authGet('/teacher/student-inbox');
  console.log(si.status === 200 ? '✅' : '❌', 'GET /teacher/student-inbox →', si.status);

  // Step 6: Supervisor chat page
  const sc = await authGet('/teacher/supervisor-chat');
  console.log(sc.status === 200 ? '✅' : '❌', 'GET /teacher/supervisor-chat →', sc.status);

  // Step 7: API - Stats
  const stats = await authGet('/api/teacher/stats');
  const statsBody = JSON.parse(stats.body);
  if (stats.status === 200 && statsBody.sections !== undefined) {
    console.log('✅ GET /api/teacher/stats   →', stats.status, '| sections:', statsBody.sections, '| groups:', statsBody.groups, '| pending:', statsBody.pendingInbox, '| students:', statsBody.students);
  } else {
    console.log('❌ GET /api/teacher/stats   →', stats.status, stats.body.substring(0, 100));
  }

  // Step 8: API - Sections
  const secs = await authGet('/api/teacher/sections');
  const secsBody = JSON.parse(secs.body);
  if (secs.status === 200 && secsBody.sections) {
    console.log('✅ GET /api/teacher/sections →', secs.status, '|', secsBody.sections.length, 'sections:', secsBody.sections.map(s => s.section_code).join(', '));
  } else {
    console.log('❌ GET /api/teacher/sections →', secs.status, secs.body.substring(0, 100));
  }

  // Step 9: API - Groups
  const grps = await authGet('/api/teacher/groups');
  const grpsBody = JSON.parse(grps.body);
  if (grps.status === 200 && grpsBody.groups) {
    console.log('✅ GET /api/teacher/groups  →', grps.status, '|', grpsBody.groups.length, 'groups:', grpsBody.groups.map(g => g.group_code).join(', '));
  } else {
    console.log('❌ GET /api/teacher/groups  →', grps.status, grps.body.substring(0, 100));
  }

  // Step 10: API - Inbox
  const inboxApi = await authGet('/api/teacher/inbox');
  const inboxBody = JSON.parse(inboxApi.body);
  if (inboxApi.status === 200 && inboxBody.inbox) {
    console.log('✅ GET /api/teacher/inbox   →', inboxApi.status, '|', inboxBody.inbox.length, 'item(s)');
    if (inboxBody.inbox.length > 0) {
      const firstId = inboxBody.inbox[0].inbox_id;
      // Step 11: Inbox detail
      const detail = await authGet('/api/teacher/inbox/' + firstId);
      const detailBody = JSON.parse(detail.body);
      if (detail.status === 200 && detailBody.package) {
        console.log('✅ GET /api/teacher/inbox/:id →', detail.status, '|', detailBody.reports?.length, 'reports in package');
      } else {
        console.log('❌ GET /api/teacher/inbox/:id →', detail.status, detail.body.substring(0, 100));
      }
    }
  } else {
    console.log('❌ GET /api/teacher/inbox   →', inboxApi.status, inboxApi.body.substring(0, 100));
  }

  // Step 12: Chat - Student inbox
  const chatSI = await authGet('/api/chat/teacher/student-inbox');
  const chatSIBody = JSON.parse(chatSI.body);
  if (chatSI.status === 200 && chatSIBody.conversations !== undefined) {
    console.log('✅ GET /api/chat/teacher/student-inbox →', chatSI.status, '|', chatSIBody.conversations.length, 'conversation(s)');
  } else {
    console.log('❌ GET /api/chat/teacher/student-inbox →', chatSI.status, chatSI.body.substring(0, 100));
  }

  // Step 13: Supervisor chat contacts
  const supChat = await authGet('/api/chat/supervisors');
  const supBody = JSON.parse(supChat.body);
  if (supChat.status === 200) {
    console.log('✅ GET /api/chat/supervisors →', supChat.status, '|', (supBody.supervisors || supBody.contacts || supBody.users || []).length, 'contact(s)');
  } else {
    console.log('⚠️  GET /api/chat/supervisors →', supChat.status, supChat.body.substring(0, 80));
  }

  // Step 14: Profile (me)
  const me = await authGet('/auth/me');
  const meBody = JSON.parse(me.body);
  if (me.status === 200 && meBody.user) {
    console.log('✅ GET /auth/me             →', me.status, '| role:', meBody.user.role, '| name:', meBody.user.full_name);
  } else {
    console.log('❌ GET /auth/me             →', me.status);
  }

  console.log('\n=== ALL TESTS COMPLETE ===');
  process.exit(0);
}

run().catch(e => { console.error('FATAL:', e.message); process.exit(1); });

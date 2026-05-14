const express = require('express');
const router = express.Router();
const db = require('../config/db');

// Show the demo UI
router.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>UCAM Webhook Demo</title>
      <style>
        body { font-family: sans-serif; padding: 40px; background: #f0f2f5; }
        .card { background: #fff; padding: 30px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); max-width: 600px; margin: 0 auto; }
        h2 { margin-top: 0; color: #1565c0; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input, select { width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 6px; box-sizing: border-box; }
        button { background: #1565c0; color: white; border: none; padding: 12px 20px; border-radius: 6px; cursor: pointer; font-size: 16px; width: 100%; }
        button:hover { background: #0d47a1; }
        .response { margin-top: 20px; padding: 15px; background: #e8f5e9; border-radius: 6px; display: none; }
      </style>
    </head>
    <body>
      <div class="card">
        <h2>🚀 UCAM Webhook Demo</h2>
        <p>This simulates UCAM sending a newly formed and approved FYDP group to our system.</p>
        
        <div class="form-group">
          <label>Group Code (Must be unique)</label>
          <input type="text" id="groupCode" value="UIU-G" onclick="if(this.value==='UIU-G') this.value='UIU-G' + Math.floor(Math.random() * 900 + 100);">
        </div>
        <div class="form-group">
          <label>Project Title</label>
          <input type="text" id="projectTitle" value="AI Driven Webhook Tester">
        </div>
        <div class="form-group">
          <label>Domain</label>
          <select id="domain">
            <option value="Machine Learning">Machine Learning</option>
            <option value="Web Engineering">Web Engineering</option>
            <option value="Cybersecurity">Cybersecurity</option>
          </select>
        </div>
        <div class="form-group">
          <label>Supervisor ID (Must exist in our DB)</label>
          <input type="number" id="supervisorId" value="6" placeholder="e.g. 6">
        </div>
        <div class="form-group">
          <label>Student 1 ID (Leader)</label>
          <input type="number" id="student1" value="2" placeholder="e.g. 2">
        </div>
        
        <button onclick="triggerWebhook()">Send Webhook Request</button>
        
        <div id="response" class="response"></div>
      </div>

      <script>
        async function triggerWebhook() {
          const payload = {
            group_code: document.getElementById('groupCode').value,
            project_title: document.getElementById('projectTitle').value,
            domain: document.getElementById('domain').value,
            stage_name: 'FYDP-1',
            supervisor_id: parseInt(document.getElementById('supervisorId').value),
            members: [
              { student_id: parseInt(document.getElementById('student1').value), role: 'TEAM_LEAD' }
            ]
          };
          
          try {
            const res = await fetch('/ucam-demo/webhook', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(payload)
            });
            const data = await res.json();
            const respDiv = document.getElementById('response');
            respDiv.style.display = 'block';
            if (data.error) {
              respDiv.style.background = '#ffebee';
              respDiv.style.color = '#c62828';
              respDiv.innerHTML = '<strong>Error:</strong> ' + data.details;
            } else {
              respDiv.style.background = '#e8f5e9';
              respDiv.style.color = '#2e7d32';
              respDiv.innerHTML = '<strong>Success!</strong> ' + data.message + ' (Group ID: ' + data.group_id + ')';
            }
          } catch(e) {
            alert('Error: ' + e.message);
          }
        }
      </script>
    </body>
    </html>
  `);
});

// The actual Webhook Endpoint
router.post('/webhook', async (req, res) => {
  try {
    const { group_code, project_title, domain, stage_name, supervisor_id, members } = req.body;
    
    // Get IDs
    const [domainRows] = await db.query('SELECT domain_id FROM project_domains LIMIT 1');
    const [stageRows] = await db.query('SELECT stage_id FROM fydp_stages WHERE stage_name = ?', ['FYDP-1']);
    const domainId = domainRows[0] ? domainRows[0].domain_id : 1;
    const stageId = stageRows[0] ? stageRows[0].stage_id : 1;

    // Insert Group
    const [grpResult] = await db.query(
      `INSERT INTO project_groups (group_code, project_title, project_domain_id, current_stage_id, supervisor_id, section_code)
       VALUES (?, ?, ?, ?, ?, 'A')`,
      [group_code, project_title, domainId, stageId, supervisor_id]
    );
    
    const groupId = grpResult.insertId;
    
    // Insert Members
    for (const m of members) {
      await db.query(
        `INSERT INTO group_members (group_id, student_id, member_role) VALUES (?, ?, ?)`,
        [groupId, m.student_id, m.role]
      );
    }
    
    res.json({ success: true, message: 'Group successfully imported from UCAM', group_id: groupId });
  } catch(e) {
    console.error(e);
    res.status(500).json({ error: 'Webhook processing failed', details: e.message });
  }
});

module.exports = router;

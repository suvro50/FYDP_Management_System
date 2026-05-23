// ── admin_assign_teacher.js ───────────────────────────────────────────────
let mappingsCache = [];

document.addEventListener('DOMContentLoaded', async () => {
  const user = await getCurrentUser();
  if (user) {
    document.getElementById('userName').textContent = user.full_name;
    document.getElementById('userAvatar').textContent = getInitials(user.full_name);
  }
  await Promise.all([loadDropdowns(), loadMappings()]);
});

async function loadDropdowns() {
  try {
    const [tData, sData, stData] = await Promise.all([
      apiFetch('/api/admin/course-teachers'),
      apiFetch('/api/admin/sections'),
      apiFetch('/api/admin/stages')
    ]);

    const selT = document.getElementById('selTeacher');
    (tData.teachers || []).forEach(u => {
      const o = document.createElement('option');
      o.value = u.user_id;
      o.textContent = `${u.full_name}${u.department ? ' (' + u.department + ')' : ''} — ${u.assigned_sections} sections`;
      selT.appendChild(o);
    });

    const selS = document.getElementById('selSection');
    (sData.sections || []).forEach(s => {
      const o = document.createElement('option');
      o.value = s.section_code; o.textContent = `Section: ${s.section_code}`;
      selS.appendChild(o);
    });

    const selSt = document.getElementById('selStage');
    (stData.stages || []).forEach(st => {
      const o = document.createElement('option');
      o.value = st.stage_id; o.textContent = st.stage_name;
      selSt.appendChild(o);
    });
  } catch (e) {
    console.error('Dropdown error', e);
  }
}

async function loadMappings() {
  const tbody = document.getElementById('mapTableBody');
  tbody.innerHTML = '<tr class="empty-row"><td colspan="5"><i class="fas fa-spinner fa-spin"></i> Loading...</td></tr>';
  try {
    const data = await apiFetch('/api/admin/teacher-sections');
    mappingsCache = data.mappings || [];
    renderTable(mappingsCache);
    updateSummary(mappingsCache);
  } catch (err) {
    tbody.innerHTML = `<tr class="empty-row"><td colspan="5" style="color:#ef4444;">${err.message}</td></tr>`;
  }
}

function renderTable(rows) {
  const tbody = document.getElementById('mapTableBody');
  if (!rows.length) {
    tbody.innerHTML = '<tr class="empty-row"><td colspan="5"><i class="fas fa-inbox"></i><br>No assignments yet</td></tr>';
    return;
  }
  const stageClass = { 'FYDP-1': 'stage-pill-1', 'FYDP-2': 'stage-pill-2', 'FYDP-3': 'stage-pill-3' };
  tbody.innerHTML = rows.map(m => `
    <tr data-id="${m.mapping_id}">
      <td>
        <div style="font-weight:700;color:#e2e8f0;">${escapeHtml(m.teacher_name)}</div>
        <div style="font-size:0.68rem;color:#475569;">${escapeHtml(m.department || '')}</div>
      </td>
      <td><span class="sec-pill">${escapeHtml(m.section_code)}</span></td>
      <td><span class="sec-pill ${stageClass[m.stage_name] || 'stage-pill-1'}">${m.stage_name}</span></td>
      <td style="color:#64748b;text-align:center;">${m.group_count}</td>
      <td><button class="btn-remove" onclick="removeMapping(${m.mapping_id}, this)"><i class="fas fa-unlink"></i> Remove</button></td>
    </tr>`).join('');
}

function updateSummary(rows) {
  document.getElementById('sumMappings').textContent = rows.length;
  const teachers = new Set(rows.map(r => r.course_teacher_id));
  const sections = new Set(rows.map(r => r.section_code));
  document.getElementById('sumTeachers').textContent = teachers.size;
  document.getElementById('sumSections').textContent = sections.size;
}

function filterTable() {
  const q = document.getElementById('mapSearch').value.toLowerCase();
  const filtered = mappingsCache.filter(m =>
    m.teacher_name.toLowerCase().includes(q) ||
    m.section_code.toLowerCase().includes(q) ||
    m.stage_name.toLowerCase().includes(q)
  );
  renderTable(filtered);
}

async function doAssign() {
  const teacher_id = document.getElementById('selTeacher').value;
  const section_code = document.getElementById('selSection').value;
  const stage_id = document.getElementById('selStage').value;
  const fb = document.getElementById('assignFeedback');

  if (!teacher_id || !section_code || !stage_id) {
    fb.style.color = '#f59e0b';
    fb.textContent = '⚠️ Please fill all fields';
    return;
  }

  const btn = document.getElementById('btnAssign');
  btn.disabled = true;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Assigning...';
  fb.textContent = '';

  try {
    await apiFetch('/api/admin/assign-teacher', {
      method: 'POST',
      body: { teacher_id, section_code, stage_id }
    });
    fb.style.color = '#10b981';
    fb.textContent = '✅ Teacher assigned successfully!';
    document.getElementById('selTeacher').value = '';
    document.getElementById('selSection').value = '';
    document.getElementById('selStage').value = '';
    await loadMappings();
    setTimeout(() => { fb.textContent = ''; }, 3000);
  } catch (err) {
    fb.style.color = '#ef4444';
    fb.textContent = `❌ ${err.message}`;
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-link"></i> Assign Teacher to Section';
  }
}

async function removeMapping(id, btn) {
  if (!confirm('Remove this teacher-section assignment?')) return;
  btn.disabled = true;
  try {
    await apiFetch(`/api/admin/teacher-sections/${id}`, { method: 'DELETE' });
    showToast('Assignment removed', 'success');
    await loadMappings();
  } catch (err) {
    showToast(err.message, 'error');
    btn.disabled = false;
  }
}

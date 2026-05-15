// ── admin_assign_groups.js ─────────────────────────────────────────────────
let allGroups = [];
let stages    = [];
let domains   = [];
let activeStage = '';
let searchTimer = null;

document.addEventListener('DOMContentLoaded', async () => {
  const user = await getCurrentUser();
  if (user) {
    document.getElementById('userName').textContent = user.full_name;
    document.getElementById('userAvatar').textContent = getInitials(user.full_name);
  }
  await Promise.all([loadDropdowns(), loadGroups()]);
});

async function loadDropdowns() {
  try {
    const [sData, stData] = await Promise.all([
      apiFetch('/api/admin/sections'),
      apiFetch('/api/admin/stages')
    ]);
    stages = stData.stages;

    const sel = document.getElementById('secFilter');
    sData.sections.forEach(s => {
      const o = document.createElement('option');
      o.value = s; o.textContent = `Section: ${s}`;
      sel.appendChild(o);
    });
  } catch (e) { /* silent */ }
}

async function loadGroups() {
  const grid = document.getElementById('groupGrid');
  grid.innerHTML = '<div class="empty-state" style="grid-column:1/-1;"><i class="fas fa-spinner fa-spin"></i><p>Loading...</p></div>';
  try {
    const search  = document.getElementById('searchInput').value;
    const section = document.getElementById('secFilter').value;
    let url = `/api/admin/groups?limit=200`;
    if (activeStage) url += `&stage=${encodeURIComponent(activeStage)}`;
    if (search)      url += `&search=${encodeURIComponent(search)}`;
    if (section)     url += `&section=${encodeURIComponent(section)}`;

    const data = await apiFetch(url);
    allGroups = data.groups || [];
    renderGroups(allGroups);
    updateStageCounts();
  } catch (err) {
    grid.innerHTML = `<div class="empty-state" style="grid-column:1/-1;color:#ef4444;"><i class="fas fa-exclamation-triangle"></i><p>${err.message}</p></div>`;
  }
}

function renderGroups(groups) {
  const grid = document.getElementById('groupGrid');
  document.getElementById('totalPill').textContent = `${groups.length} Groups`;

  if (!groups.length) {
    grid.innerHTML = '<div class="empty-state" style="grid-column:1/-1;"><i class="fas fa-layer-group"></i><p>No groups found</p></div>';
    return;
  }

  const stageColors = { 'FYDP-1': '#818cf8', 'FYDP-2': '#f59e0b', 'FYDP-3': '#10b981' };
  const stageBg     = { 'FYDP-1': 'rgba(99,102,241,0.1)', 'FYDP-2': 'rgba(245,158,11,0.1)', 'FYDP-3': 'rgba(16,185,129,0.1)' };

  grid.innerHTML = groups.map(g => {
    const col = stageColors[g.stage_name] || '#818cf8';
    const bg  = stageBg[g.stage_name]    || 'rgba(99,102,241,0.1)';
    const nextStage = getNextStage(g.stage_name);

    return `
    <div class="grp-card" id="gc-${g.group_id}">
      <div class="grp-head">
        <div>
          <div class="grp-code-big">${escapeHtml(g.group_code)}</div>
          <div class="grp-domain">${escapeHtml(g.domain_name || '')}</div>
        </div>
        <span style="padding:3px 10px;border-radius:20px;font-size:0.68rem;font-weight:800;background:${bg};color:${col};border:1px solid ${col}33;">
          ${g.stage_name}
        </span>
      </div>
      <div class="grp-info-row">
        <span class="ab ab-indigo"><i class="fas fa-users" style="font-size:0.65rem;"></i> ${g.member_count} members</span>
        ${g.section_code ? `<span class="ab ab-blue">§ ${escapeHtml(g.section_code)}</span>` : ''}
        <span class="ab ${g.project_status === 'ACTIVE' ? 'ab-green' : 'ab-amber'}">${g.project_status}</span>
      </div>
      <div class="grp-sup">
        <i class="fas fa-user-tie" style="color:#10b981;font-size:0.75rem;"></i>
        ${g.supervisor_name ? escapeHtml(g.supervisor_name) : '<span style="color:#475569;font-style:italic;">No supervisor</span>'}
      </div>
      <div class="grp-actions">
        <button class="btn-view" onclick="viewGroup(${g.group_id})">
          <i class="fas fa-eye"></i> View
        </button>
        ${nextStage ? `
        <button class="btn-promote" onclick="openPromote(${g.group_id}, '${escapeHtml(g.group_code)}', '${g.stage_name}')">
          <i class="fas fa-arrow-up"></i> Promote to ${nextStage}
        </button>` : `
        <button class="btn-promote" disabled>
          <i class="fas fa-check"></i> Final Stage
        </button>`}
      </div>
    </div>`;
  }).join('');
}

function getNextStage(current) {
  const order = ['FYDP-1', 'FYDP-2', 'FYDP-3'];
  const idx = order.indexOf(current);
  return idx >= 0 && idx < order.length - 1 ? order[idx + 1] : null;
}

function updateStageCounts() {
  const counts = { 'FYDP-1': 0, 'FYDP-2': 0, 'FYDP-3': 0 };
  allGroups.forEach(g => { if (counts[g.stage_name] !== undefined) counts[g.stage_name]++; });
  document.getElementById('cnt-1').textContent = counts['FYDP-1'] ? `(${counts['FYDP-1']})` : '';
  document.getElementById('cnt-2').textContent = counts['FYDP-2'] ? `(${counts['FYDP-2']})` : '';
  document.getElementById('cnt-3').textContent = counts['FYDP-3'] ? `(${counts['FYDP-3']})` : '';
}

function switchStage(stage) {
  activeStage = stage;
  document.querySelectorAll('.stage-tab').forEach(t => t.classList.remove('active-tab'));
  const tabId = stage ? `tab-${stage.split('-')[1]}` : 'tab-all';
  document.getElementById(tabId)?.classList.add('active-tab');
  loadGroups();
}

function debounce() {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(loadGroups, 300);
}

// ── View Group Modal ─────────────────────────────────────────────────────────
async function viewGroup(groupId) {
  document.getElementById('groupModal').classList.add('open');
  document.getElementById('modalGroupCode').textContent = 'Loading...';
  document.getElementById('modalContent').innerHTML = '<div style="text-align:center;padding:30px;color:#475569;"><i class="fas fa-spinner fa-spin"></i></div>';
  try {
    const data = await apiFetch(`/api/admin/group-full/${groupId}`);
    const g = data.group;
    document.getElementById('modalGroupCode').textContent = g.group_code;
    document.getElementById('modalContent').innerHTML = `
      <div style="margin-bottom:16px;">
        <div style="font-size:0.7rem;font-weight:700;color:#475569;text-transform:uppercase;margin-bottom:6px;">Project Title</div>
        <div style="font-size:0.9rem;font-weight:700;color:#fff;">${escapeHtml(g.project_title || 'Untitled')}</div>
      </div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px;">
        <div><div class="promote-label">Stage</div><span class="ab ab-indigo">${g.stage_name}</span></div>
        <div><div class="promote-label">Domain</div><span class="ab ab-purple">${escapeHtml(g.domain_name || '—')}</span></div>
        <div><div class="promote-label">Section</div><span style="color:#94a3b8;font-size:0.8rem;">${escapeHtml(g.section_code || '—')}</span></div>
        <div><div class="promote-label">Status</div><span class="ab ${g.project_status === 'ACTIVE' ? 'ab-green' : 'ab-amber'}">${g.project_status}</span></div>
      </div>
      <div style="margin-bottom:16px;">
        <div class="promote-label">Supervisor</div>
        <div style="font-size:0.85rem;color:${g.supervisor_name ? '#10b981' : '#475569'};">
          <i class="fas fa-user-tie"></i> ${g.supervisor_name ? escapeHtml(g.supervisor_name) : 'Not assigned'}
        </div>
      </div>
      <div>
        <div class="promote-label" style="margin-bottom:8px;">Members (${data.members.length})</div>
        ${data.members.map(m => `
          <div class="member-row">
            <div class="mem-av">${getInitials(m.full_name)}</div>
            <div style="flex:1;">
              <div style="font-size:0.82rem;font-weight:700;color:#e2e8f0;">${escapeHtml(m.full_name)}</div>
              <div style="font-size:0.68rem;color:#475569;">${escapeHtml(m.university_id)}</div>
            </div>
            <span class="ab ${m.member_role === 'LEADER' ? 'ab-amber' : 'ab-blue'}">${m.member_role}</span>
          </div>`).join('') || '<div style="color:#475569;font-size:0.8rem;">No members</div>'}
      </div>`;
  } catch (err) {
    document.getElementById('modalContent').innerHTML = `<div style="color:#ef4444;">${err.message}</div>`;
  }
}

// ── Promote Modal ────────────────────────────────────────────────────────────
async function openPromote(groupId, groupCode, currentStage) {
  document.getElementById('groupModal').classList.add('open');
  document.getElementById('modalGroupCode').textContent = `Promote ${groupCode}`;

  const nextStage = getNextStage(currentStage);
  const nextStageObj = stages.find(s => s.stage_name === nextStage);

  let domainsHtml = '';
  try {
    const dData = await apiFetch('/api/admin/domains');
    domainsHtml = dData.domains.map(d =>
      `<option value="${d.domain_id}">${escapeHtml(d.domain_name)}</option>`
    ).join('');
  } catch(e) { /* silent */ }

  document.getElementById('modalContent').innerHTML = `
    <div style="margin-bottom:14px;padding:12px;border-radius:10px;background:rgba(99,102,241,0.08);border:1px solid rgba(99,102,241,0.2);">
      <div style="font-size:0.72rem;color:#818cf8;font-weight:700;">Promoting</div>
      <div style="font-size:0.9rem;font-weight:800;color:#fff;margin-top:4px;">
        ${currentStage} → <span style="color:#10b981;">${nextStage}</span>
      </div>
    </div>
    <div style="margin-bottom:12px;">
      <div class="promote-label">New Project Domain (optional)</div>
      <select class="promote-select" id="promDomain">
        <option value="">— Keep current domain —</option>
        ${domainsHtml}
      </select>
    </div>
    <div style="margin-bottom:12px;">
      <div class="promote-label">New Project Title (optional)</div>
      <input type="text" class="promote-select" id="promTitle" placeholder="Leave blank to keep current title">
    </div>
    <div style="margin-bottom:16px;">
      <div class="promote-label">Reason *</div>
      <input type="text" class="promote-select" id="promReason" placeholder="e.g. Completed FYDP-1 requirements" required>
    </div>
    <div style="display:flex;gap:10px;">
      <button onclick="closeModal()" style="flex:1;padding:10px;border-radius:8px;background:var(--card2);border:1px solid var(--border);color:var(--text2);cursor:pointer;font-weight:700;">Cancel</button>
      <button onclick="doPromote(${groupId}, ${nextStageObj?.stage_id})" style="flex:2;padding:10px;border-radius:8px;background:linear-gradient(135deg,#6366f1,#4f46e5);color:#fff;border:none;cursor:pointer;font-weight:800;">
        <i class="fas fa-arrow-up"></i> Confirm Promote
      </button>
    </div>`;
}

async function doPromote(groupId, newStageId) {
  const reason = document.getElementById('promReason')?.value?.trim();
  if (!reason) { showToast('Please enter a reason for promotion', 'warning'); return; }

  const domain = document.getElementById('promDomain')?.value;
  const title  = document.getElementById('promTitle')?.value?.trim();

  try {
    await apiFetch('/api/admin/promote-group', {
      method: 'POST',
      body: {
        group_id: groupId,
        new_stage_id: newStageId,
        new_domain_id: domain || null,
        new_project_title: title || null,
        change_reason: reason
      }
    });
    showToast('Group promoted successfully!', 'success');
    closeModal();
    loadGroups();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function closeModal() {
  document.getElementById('groupModal').classList.remove('open');
}

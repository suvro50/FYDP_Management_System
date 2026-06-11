/* ═══════════════════════════════════════════════════════════════════════════
   FYDP Management System — Shared JavaScript Utilities
   ═══════════════════════════════════════════════════════════════════════════ */

// ── Toast Notification System ──────────────────────────────────────────────
function showToast(message, type = 'info') {
  let container = document.querySelector('.toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'toast-container';
    document.body.appendChild(container);
  }

  const icons = {
    success: '✅', error: '❌', warning: '⚠️', info: 'ℹ️'
  };

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `<span>${icons[type] || ''}</span><span>${message}</span>`;
  container.appendChild(toast);

  toast.addEventListener('click', () => removeToast(toast));
  setTimeout(() => removeToast(toast), 3000);
}

function removeToast(toast) {
  toast.classList.add('removing');
  setTimeout(() => toast.remove(), 300);
}

// ── Fetch Wrapper (with loading & error handling) ──────────────────────────
async function apiFetch(url, options = {}) {
  const defaults = {
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin'
  };
  const config = { ...defaults, ...options };
  if (options.body && typeof options.body === 'object' && !(options.body instanceof FormData)) {
    config.body = JSON.stringify(options.body);
  }
  if (options.body instanceof FormData) {
    delete config.headers['Content-Type'];
  }

  try {
    const res = await fetch(url, config);
    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || `Request failed (${res.status})`);
    }
    return data;
  } catch (err) {
    if (err.message === 'Not authenticated') {
      window.location.href = '/login';
      return;
    }
    throw err;
  }
}

// ── Loading Spinner ────────────────────────────────────────────────────────
function showLoading() {
  let overlay = document.querySelector('.spinner-overlay');
  if (!overlay) {
    overlay = document.createElement('div');
    overlay.className = 'spinner-overlay';
    overlay.innerHTML = '<div class="spinner"></div>';
    document.body.appendChild(overlay);
  }
  overlay.classList.add('active');
}

function hideLoading() {
  const overlay = document.querySelector('.spinner-overlay');
  if (overlay) overlay.classList.remove('active');
}

// ── Logout ─────────────────────────────────────────────────────────────────
async function logout() {
  try {
    await apiFetch('/auth/logout', { method: 'POST' });
    window.location.href = '/login';
  } catch (e) {
    window.location.href = '/login';
  }
}

// ── Format Date ────────────────────────────────────────────────────────────
function formatDate(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', {
    year: 'numeric', month: 'short', day: 'numeric'
  });
}

function formatDateTime(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit'
  });
}

// ── Get Current User ───────────────────────────────────────────────────────
async function getCurrentUser() {
  // Never redirect to /login if we are already on the login page
  const onLoginPage = window.location.pathname === '/login' ||
                      document.body.classList.contains('login-page') ||
                      !!document.querySelector('.login-wrapper');
  try {
    const data = await apiFetch('/auth/me');
    return data.user;
  } catch (e) {
    if (!onLoginPage) window.location.href = '/login';
    return null;
  }
}

// ── Get User Initials ──────────────────────────────────────────────────────
function getInitials(name) {
  return name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
}

// ── Role Badge Color ───────────────────────────────────────────────────────
function getRoleBadgeClass(role) {
  const map = {
    'ADMIN': 'badge-purple',
    'SUPERVISOR': 'badge-blue',
    'COURSE_TEACHER': 'badge-green',
    'STUDENT': 'badge-yellow'
  };
  return map[role] || 'badge-gray';
}

// ── Status Badge ───────────────────────────────────────────────────────────
function getStatusBadge(status) {
  const map = {
    'ACTIVE': '<span class="badge badge-green">Active</span>',
    'SUSPENDED': '<span class="badge badge-red">Suspended</span>',
    'DEACTIVATED': '<span class="badge badge-gray">Deactivated</span>',
    'APPROVED': '<span class="badge badge-green">Approved</span>',
    'PENDING': '<span class="badge badge-yellow">Pending</span>',
    'REJECTED': '<span class="badge badge-red">Rejected</span>',
    'COMPLETED': '<span class="badge badge-green">Completed</span>',
    'DROPPED': '<span class="badge badge-red">Dropped</span>',
    'ON_HOLD': '<span class="badge badge-yellow">On Hold</span>',
    'PENDING_REVIEW': '<span class="badge badge-yellow">Pending Review</span>',
    'REVIEWED': '<span class="badge badge-green">Reviewed</span>',
    'FLAGGED': '<span class="badge badge-red">Flagged</span>',
    'LOOKING': '<span class="badge badge-blue">Looking</span>',
    'IN_TEAM': '<span class="badge badge-green">In Team</span>',
    'NOT_AVAILABLE': '<span class="badge badge-gray">Not Available</span>',
    'ACCEPTED': '<span class="badge badge-green">Accepted</span>',
    'CANCELLED': '<span class="badge badge-gray">Cancelled</span>'
  };
  return map[status] || `<span class="badge badge-gray">${status}</span>`;
}

// ── Notification Badge (Global Bell) ─────────────────────────────────────
async function updateNotificationBadge() {
  return loadNavUnreadBadges(await getCurrentUser().catch(() => null));
}
// Backward-compat alias
async function updateNotificationCount() {
  try {
    const user = await getCurrentUser();
    let total = 0;
    const promises = [apiFetch('/api/notifications/count')];
    if (user && user.role === 'SUPERVISOR') {
      promises.push(apiFetch('/api/chat/unread-count').catch(() => ({ unread_count: 0 })));
      promises.push(apiFetch('/api/chat/group-unread-count').catch(() => ({ unread_count: 0 })));
      promises.push(apiFetch('/api/supervisor/stats').catch(() => null));
    } else if (user && user.role === 'STUDENT') {
      promises.push(apiFetch('/api/chat/unread-count').catch(() => ({ unread_count: 0 })));
      promises.push(apiFetch('/api/chat/group-unread-count').catch(() => ({ unread_count: 0 })));
    }
    const results = await Promise.allSettled(promises);
    results.forEach((r, i) => {
      if (r.status === 'fulfilled' && r.value) {
        if (i === 3 && user && user.role === 'SUPERVISOR') {
          total += (r.value.pendingReports || 0); // stats
        } else {
          total += (r.value.unread_count || 0);
        }
      }
    });
    const badges = document.querySelectorAll('.notification-bell .badge');
    badges.forEach(b => {
      if (total > 0) { b.textContent = total > 99 ? '99+' : total; b.style.display = 'flex'; }
      else { b.style.display = 'none'; }
    });
  } catch (e) { /* silent */ }
}

// ── Format time ago ────────────────────────────────────────────────────────
function formatTimeAgo(dateStr) {
  if (!dateStr) return '';
  const diff = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000);
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
  return new Date(dateStr).toLocaleDateString();
}

// ── Escape HTML ────────────────────────────────────────────────────────────
function escapeHtml(str) {
  if (!str) return '';
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// ═══════════════════════════════════════════════════════════════════════════
// STRICT BROWSER CLOSE LOGOUT (Defeats Chrome Session Restore)
// ═══════════════════════════════════════════════════════════════════════════
const bc = new BroadcastChannel('fydp_session');

if (!sessionStorage.getItem('tab_initialized')) {
  sessionStorage.setItem('tab_initialized', 'true');
  let hasOtherTabs = false;
  
  bc.onmessage = (e) => { 
    if (e.data === 'ping') bc.postMessage('pong'); 
    else if (e.data === 'pong') hasOtherTabs = true; 
  };
  
  bc.postMessage('ping');
  
  // Wait to see if any other tab responds
  setTimeout(() => {
    const onLoginPage = window.location.pathname === '/login' ||
                        document.body.classList.contains('login-page') ||
                        !!document.querySelector('.login-wrapper');
    if (!hasOtherTabs && !onLoginPage) {
      // No other tabs and not on login page: this is a fresh browser session (even if cookie survived)
      fetch('/auth/logout', { method: 'POST' }).then(() => {
        window.location.href = '/login';
      });
    }
  }, 200);
} else {
  // Tab already initialized, just listen for pings from new tabs
  bc.onmessage = (e) => { 
    if (e.data === 'ping') bc.postMessage('pong'); 
  };
}

// DARK MODE — Scoped to Pre-FYDP pages only (pages with #darkModeToggle button).
// Other dashboards are dark-only and should never get light-mode applied.
function initDarkMode() {
  const isLoginPage = document.body.classList.contains('login-page') ||
                      window.location.pathname === '/login' ||
                      document.querySelector('.login-wrapper') !== null;
  if (isLoginPage) {
    document.body.classList.remove('dark-mode', 'light-mode');
    return;
  }

  // Only apply light/dark toggle on pages that actually have the toggle button
  const toggleBtn = document.querySelector('#darkModeToggle');
  if (!toggleBtn) {
    // No toggle button = this page does NOT support light mode.
    // Ensure dark-mode is on and light-mode is off, regardless of stored pref.
    document.body.classList.remove('light-mode');
    document.body.classList.add('dark-mode');
    return;
  }

  // Migrate old global 'theme' key to scoped 'pf_theme' key (one-time)
  const oldTheme = localStorage.getItem('theme');
  if (oldTheme && !localStorage.getItem('pf_theme')) {
    localStorage.setItem('pf_theme', oldTheme);
    localStorage.removeItem('theme');
  } else if (oldTheme) {
    localStorage.removeItem('theme');
  }
  
  const savedTheme = localStorage.getItem('pf_theme');
  if (savedTheme === 'light') {
    document.body.classList.remove('dark-mode');
    document.body.classList.add('light-mode');
  } else {
    document.body.classList.add('dark-mode');
    document.body.classList.remove('light-mode');
  }
  
  // Update toggle icon
  const icon = toggleBtn.querySelector('i');
  if (icon) {
    icon.className = document.body.classList.contains('dark-mode') ? 'fas fa-sun' : 'fas fa-moon';
  }
}

function toggleDarkMode() {
  const isDark = document.body.classList.toggle('dark-mode');
  if (isDark) {
    document.body.classList.remove('light-mode');
  } else {
    document.body.classList.add('light-mode');
  }
  // Save under scoped key so other dashboards are not affected
  localStorage.setItem('pf_theme', isDark ? 'dark' : 'light');
  
  const icon = document.querySelector('#darkModeToggle i');
  if (icon) {
    icon.className = isDark ? 'fas fa-sun' : 'fas fa-moon';
  }
}
document.addEventListener('DOMContentLoaded', initDarkMode);

// ═══════════════════════════════════════════════════════════════════════════
// READ RECEIPTS — Helper for DM chats (not group chat)
// Returns tick HTML based on is_read flag (WhatsApp style)
// ═══════════════════════════════════════════════════════════════════════════
function getTickHtml(isRead, isSent) {
  if (!isSent) return ''; // Only show ticks for sent messages
  if (isRead) {
    return '<span class="msg-tick double" title="Seen" style="color:#1976d2;font-size:0.7rem;margin-left:3px;">✓✓</span>';
  }
  return '<span class="msg-tick single" title="Delivered" style="color:rgba(0,0,0,0.4);font-size:0.7rem;margin-left:3px;">✓</span>';
}

// ═══════════════════════════════════════════════════════════════════════════
// NAV UNREAD BADGES — Show unread counts on sidebar links
// Fetches per-category counts and injects number badges into nav links
// ═══════════════════════════════════════════════════════════════════════════
async function loadNavUnreadBadges(user) {
  if (!user) return;
  try {
    let totalUnread = 0;

    // 1. Top-right bell badge (all system notifications)
    const notifData = await apiFetch('/api/notifications/count').catch(() => ({ unread_count: 0 }));
    totalUnread += (notifData.unread_count || 0);

    if (user.role === 'SUPERVISOR') {
      // 2a. Student Messages unread count
      const dmData = await apiFetch('/api/chat/unread-count').catch(() => ({ unread_count: 0 }));
      _setNavBadge('/supervisor/student-inbox', dmData.unread_count);
      totalUnread += (dmData.unread_count || 0);

      // 2b. Pending approvals count
      const statsData = await apiFetch('/api/supervisor/stats').catch(() => null);
      if (statsData) {
        _setNavBadge('/supervisor/approvals', statsData.pendingReports);
        totalUnread += (statsData.pendingReports || 0);
      }
      
      // 2c. Group Chat unread count
      const grpData = await apiFetch('/api/chat/group-unread-count').catch(() => ({ unread_count: 0 }));
      _setNavBadge('/supervisor/groups', grpData.unread_count);
      totalUnread += (grpData.unread_count || 0);

      // 2d. Pending FYDP-1 group requests
      const reqData = await apiFetch('/api/supervisor/fydp1-request-stats').catch(() => ({ pending_count: 0 }));
      _setNavBadge('/supervisor/requests', reqData.pending_count);
      totalUnread += (reqData.pending_count || 0);

    } else if (user.role === 'STUDENT' || user.role === 'PRE_FYDP_STUDENT') {
      // Supervisor & Teacher DM unread
      const dmStats = await apiFetch('/api/chat/unread-count').catch(() => ({ supervisor_unread: 0, teacher_unread: 0, unread_count: 0 }));
      
      _setNavBadge('/student/supervisor-chat', dmStats.supervisor_unread);
      _setNavBadge('/student/teacher-chat', dmStats.teacher_unread);
      
      totalUnread += (dmStats.unread_count || 0); // Total unread DMs
      
      // Group Chat unread count
      const grpDm = await apiFetch('/api/chat/group-unread-count').catch(() => ({ unread_count: 0 }));
      _setNavBadge('/student/my-group-chat', grpDm.unread_count);
      totalUnread += (grpDm.unread_count || 0);
      
      // Pre-FYDP requests
      const pfData = await apiFetch('/api/pre-fydp/dashboard-stats').catch(() => null);
      if (pfData) {
        _setNavBadge('/pre-fydp/my-requests', pfData.incoming_requests);
        totalUnread += (pfData.incoming_requests || 0);
      }
    } else if (user.role === 'COURSE_TEACHER') {
      // 2a. Escalated Inbox
      const tStats = await apiFetch('/api/teacher/stats').catch(() => null);
      if (tStats) {
        _setNavBadge('/teacher/inbox', tStats.pendingInbox);
        totalUnread += (tStats.pendingInbox || 0);
      }

      // 2b. Student DMs
      const tDm = await apiFetch('/api/chat/unread-count').catch(() => ({ unread_count: 0 }));
      _setNavBadge('/teacher/student-inbox', tDm.unread_count);
      totalUnread += (tDm.unread_count || 0);

      // 2c. Group Chat
      const tGrp = await apiFetch('/api/chat/group-unread-count').catch(() => ({ unread_count: 0 }));
      _setNavBadge('/teacher/groups', tGrp.unread_count);
      totalUnread += (tGrp.unread_count || 0);
    }

    // Update the global bell badge with the total sum
    const badges = document.querySelectorAll('.notification-bell .badge, #notifBadge');
    badges.forEach(b => {
      if (totalUnread > 0) {
        b.textContent = totalUnread > 99 ? '99+' : totalUnread;
        b.style.display = 'flex';
      } else {
        b.style.display = 'none';
      }
    });

    const pfDots = document.querySelectorAll('.pf-notif-dot, #notifDot');
    pfDots.forEach(d => {
      if (totalUnread > 0) {
        d.style.display = 'block';
      } else {
        d.style.display = 'none';
      }
    });

  } catch (e) { /* silent */ }
}

function _setNavBadge(href, count) {
  if (!count || count <= 0) { _clearNavBadge(href); return; }
  const link = document.querySelector(`a[href="${href}"]`);
  if (!link) return;
  let badge = link.querySelector('.nav-unread-badge');
  if (!badge) {
    badge = document.createElement('span');
    badge.className = 'nav-unread-badge';
    badge.style.cssText = 'background:#e53935;color:#fff;font-size:0.6rem;font-weight:700;padding:1px 6px;border-radius:10px;margin-left:auto;min-width:18px;text-align:center;';
    link.style.display = 'flex';
    link.style.alignItems = 'center';
    link.appendChild(badge);
  }
  badge.textContent = count > 99 ? '99+' : count;
}

function _clearNavBadge(href) {
  const link = document.querySelector(`a[href="${href}"]`);
  if (!link) return;
  link.querySelector('.nav-unread-badge')?.remove();
}

// ── Notification Dropdown ─────────────────────────────────────────────────
function toggleNotifDropdown() {
  const dropdown = document.getElementById('notifDropdown');
  const bell = document.getElementById('notifBell');
  if (!dropdown) return;

  const isShow = dropdown.classList.toggle('show');
  if (isShow) {
    if (bell && getComputedStyle(dropdown).position === 'fixed') {
      const rect = bell.getBoundingClientRect();
      const dropW = parseInt(getComputedStyle(dropdown).width) || 380;
      const vw = window.innerWidth;
      // Position below the bell with 8px gap
      dropdown.style.top  = (rect.bottom + 8) + 'px';
      dropdown.style.left = 'auto';
      // Align right edge of dropdown with right edge of bell, clamped to viewport
      let rightPos = vw - rect.right;
      if (rightPos + dropW > vw - 8) rightPos = 8;
      dropdown.style.right = Math.max(8, rightPos) + 'px';
    }
    loadNotifDropdown();
  }
}

async function markAllNotifRead() {
  try {
    await apiFetch('/api/notifications/read-all', { method: 'PUT' });
    updateNotificationBadge();
    const dropdownBtn = document.getElementById('notifBell');
    if (dropdownBtn) dropdownBtn.click();
    showToast('All notifications marked as read', 'success');
  } catch (e) {
    showToast('Failed to mark all as read', 'error');
  }
}

async function loadNotifDropdown() {
  const el = document.getElementById('notifDropdownBody');
  if (!el) return;
  el.innerHTML = '<div style="padding:30px;text-align:center;color:#999;"><i class="fas fa-spinner fa-spin"></i> Loading...</div>';
  try {
    const user = await getCurrentUser();
    if (!user) return;
    const [nd, dm, grp, st, pf] = await Promise.allSettled([
      user.role === 'PRE_FYDP_STUDENT' ? Promise.resolve({ notifications: [] }) : apiFetch('/api/notifications?limit=8'),
      user.role === 'PRE_FYDP_STUDENT' ? Promise.resolve(null) : apiFetch('/api/chat/unread-count'),
      user.role === 'PRE_FYDP_STUDENT' ? Promise.resolve(null) : apiFetch('/api/chat/group-unread-count'),
      user.role === 'SUPERVISOR' ? apiFetch('/api/supervisor/stats') : 
      user.role === 'COURSE_TEACHER' ? apiFetch('/api/teacher/stats') : Promise.resolve(null),
      (user.role === 'STUDENT' || user.role === 'PRE_FYDP_STUDENT') ? apiFetch('/api/pre-fydp/dashboard-stats') : Promise.resolve(null)
    ]);

    // PRE_FYDP_STUDENT: always start with empty list — old FYDP notifications are not relevant here
    let notifs = user.role === 'PRE_FYDP_STUDENT' ? [] : ((nd.status === 'fulfilled' && nd.value && nd.value.notifications) ? nd.value.notifications : []);

    // Inject dynamic summary items at the top
    // PRE_FYDP_STUDENT users do not have chat routes — skip group/DM virtual items to avoid 403 blank pages
    if (user.role !== 'PRE_FYDP_STUDENT') {
      if (grp.status === 'fulfilled' && grp.value && grp.value.unread_count > 0) {
        const link = (user.role === 'SUPERVISOR' || user.role === 'COURSE_TEACHER') ? (user.role === 'SUPERVISOR' ? '/supervisor/groups' : '/teacher/groups') : '/student/my-group-chat';
        notifs.unshift({ notification_id: 'grp', is_read: 0, title: '👥 Group Chats', message: `You have ${grp.value.unread_count} unread group message(s).`, created_at: new Date().toISOString(), link });
      }
      if (dm.status === 'fulfilled' && dm.value && dm.value.unread_count > 0) {
        const link = user.role === 'SUPERVISOR' ? '/supervisor/student-inbox' : user.role === 'COURSE_TEACHER' ? '/teacher/student-inbox' : '/student/supervisor-chat';
        notifs.unshift({ notification_id: 'dm', is_read: 0, title: '💬 Direct Messages', message: `You have ${dm.value.unread_count} unread direct message(s).`, created_at: new Date().toISOString(), link });
      }
    }
    if (user.role === 'SUPERVISOR' && st.status === 'fulfilled' && st.value && st.value.pendingReports > 0) {
      notifs.unshift({ notification_id: 'appr', is_read: 0, title: '⏳ Pending Reports', message: `You have ${st.value.pendingReports} report(s) waiting for review.`, created_at: new Date().toISOString(), link: '/supervisor/approvals' });
    }
    if (user.role === 'SUPERVISOR') {
      try {
        const reqStats = await apiFetch('/api/supervisor/fydp1-request-stats');
        if (reqStats && reqStats.pending_count > 0) {
          notifs.unshift({ notification_id: 'fydp1req', is_read: 0, title: '📋 Group Requests', message: `You have ${reqStats.pending_count} pending FYDP-1 group request(s) from Pre-FYDP students.`, created_at: new Date().toISOString(), link: '/supervisor/requests' });
        }
      } catch(e) { /* silent */ }
    }
    if (user.role === 'COURSE_TEACHER' && st.status === 'fulfilled' && st.value && st.value.pendingInbox > 0) {
      notifs.unshift({ notification_id: 'inbox', is_read: 0, title: '📥 Escalated Inbox', message: `You have ${st.value.pendingInbox} escalated package(s) waiting for review.`, created_at: new Date().toISOString(), link: '/teacher/inbox' });
    }
    if ((user.role === 'STUDENT' || user.role === 'PRE_FYDP_STUDENT') && pf.status === 'fulfilled' && pf.value && pf.value.incoming_requests > 0) {
      notifs.unshift({ notification_id: 'pf', is_read: 0, title: '🤝 Join Requests', message: `You have ${pf.value.incoming_requests} pending join request(s) for your group.`, created_at: new Date().toISOString(), link: '/pre-fydp/my-requests' });
    }

    if (notifs.length === 0) {
      el.innerHTML = '<div style="padding:40px 20px;text-align:center;color:#999;font-size:0.9rem;">\uD83D\uDD14 No new notifications</div>';
      return;
    }

    el.innerHTML = notifs.map(n => {
      const timeAgo = formatTimeAgo(n.created_at);
      const parts = (n.title || '').split(' ');
      const icon = parts.length > 1 && /^[\u{1F000}-\u{1FFFF}\u2600-\u27BF]/u.test(parts[0]) ? parts[0] : '\uD83D\uDD14';
      const cleanTitle = escapeHtml(n.title || '').replace(/^\S+\s/, '');
      const safeLink = escapeHtml(n.link || '/notifications');
      const safeType = escapeHtml(n.notification_type || '');
      const encTitle = encodeURIComponent(cleanTitle);
      const encMsg = encodeURIComponent(n.message || '');
      return `
        <div class="notif-item ${n.is_read ? '' : 'unread'}" onclick="readAndGoNotif('${n.notification_id}', '${safeLink}', '${safeType}', '${encTitle}', '${encMsg}')" style="cursor:pointer;">
          <div class="notif-item-icon">${icon}</div>
          <div class="notif-item-text">
            <h5>${cleanTitle}</h5>
            <p>${escapeHtml(n.message || '')}</p>
            <span class="notif-item-time">${timeAgo}</span>
          </div>
          ${!n.is_read ? '<div class="notif-unread-dot"></div>' : ''}
        </div>`;
    }).join('');
  } catch (e) {
    el.innerHTML = '<div style="padding:20px;text-align:center;color:#f44336;">Failed to load notifications</div>';
  }
}

async function readAndGoNotif(id, link, type, encTitle, encMsg) {
  if (id && !isNaN(parseInt(id, 10))) {
    try { await apiFetch(`/api/notifications/${id}/read`, { method: 'PUT' }); } catch (e) { /* silent */ }
  }
  
  const requiresModal = ['REPORT_REJECTED', 'REPORT_APPROVED', 'STAGE_PROMOTED'].includes(type) || 
                        (encMsg && decodeURIComponent(encMsg).length > 60);

  if (requiresModal && encMsg) {
    showGlobalDetailModal(decodeURIComponent(encTitle || ''), decodeURIComponent(encMsg), link);
  } else {
    window.location.href = link;
  }
}

function showGlobalDetailModal(title, message, link) {
  let modal = document.getElementById('detailModal');
  if (!modal) {
    document.body.insertAdjacentHTML('beforeend', `
      <div class="modal-overlay" id="detailModal">
        <div class="modal" style="max-width:500px;">
          <div class="modal-header">
            <h3 id="detailTitle">Notification</h3>
            <button class="modal-close" onclick="document.getElementById('detailModal').classList.remove('active'); event.stopPropagation();">&times;</button>
          </div>
          <div class="modal-body" id="detailBody"></div>
        </div>
      </div>
    `);
    modal = document.getElementById('detailModal');
  }
  
  const dTitle = document.getElementById('detailTitle');
  if(dTitle) dTitle.textContent = title || 'Notification';
  
  const dBody = document.getElementById('detailBody');
  if(dBody) {
    dBody.innerHTML = `<p style="line-height:1.6; margin:0; color:var(--pf-text, var(--text-color, #333));">${(message || '').replace(/\n/g, '<br>')}</p>`;
    if (link && link !== '#' && link !== '/notifications') {
      dBody.innerHTML += `<div style="margin-top:20px; text-align:right;"><a href="${link}" class="btn btn-primary" style="text-decoration:none; display:inline-block; padding:8px 16px; border-radius:6px; color:#fff;">View Action</a></div>`;
    }
  }
  
  modal.classList.add('active');
}

async function markAllNotifRead() {
  try {
    await apiFetch('/api/notifications/read-all', { method: 'PUT' });
    showToast('All notifications marked as read', 'success');
    loadNotifDropdown();
    updateNotificationBadge();
  } catch (e) {
    showToast('Failed to mark all as read', 'error');
  }
}

// ── Initialize Application ────────────────────────────────────────────────
// Auto-load nav badges when page loads with user info
// Skip entirely on the login page to avoid redirect loops
document.addEventListener('DOMContentLoaded', async () => {
  const onLoginPage = window.location.pathname === '/login' ||
                      document.body.classList.contains('login-page') ||
                      !!document.querySelector('.login-wrapper');
  if (onLoginPage) return;

  // Load badges after a short delay (ensures auth cookie is readable)
  setTimeout(async () => {
    try {
      const u = await apiFetch('/auth/me').then(d => d.user).catch(() => null);
      if (u) {
        loadNavUnreadBadges(u);
        // Start real-time polling every 30 seconds
        setInterval(() => loadNavUnreadBadges(u), 30000);
      }
    } catch (e) { /* silent */ }
  }, 800);

  // Close dropdown when clicking outside
  document.addEventListener('click', (e) => {
    const isBell = e.target.closest('.notification-bell') || e.target.closest('#notifBell');
    const isDropdown = e.target.closest('.notif-dropdown');
    if (!isBell && !isDropdown) {
      document.getElementById('notifDropdown')?.classList.remove('show');
    }
  });

  // Socket.IO real-time badge refresh
  if (window.socket) {
    window.socket.on('new_notification', updateNotificationBadge);
    window.socket.on('notification', updateNotificationBadge);
    window.socket.on('new_message', updateNotificationBadge);
  }
});

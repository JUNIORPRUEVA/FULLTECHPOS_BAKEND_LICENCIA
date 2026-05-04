/*
  Admin common helpers (session, fetch wrapper, UI messages)
  Uses x-session-id stored in localStorage as "sessionId".
*/

(function () {
  const isLocal = window.location.hostname === '127.0.0.1' || window.location.hostname === 'localhost';
  // Default: same-origin. This avoids "session expired" issues when deploying
  // to a new domain (e.g. EasyPanel) because sessions are bound to the backend.
  // Local dev keeps the historical localhost:3000 default.
  const BACKEND_API_BASE = isLocal ? 'http://127.0.0.1:3000' : window.location.origin;

  function getReturnTo() {
    const params = new URLSearchParams(window.location.search);
    return params.get('returnTo') || localStorage.getItem('returnTo') || '';
  }

  function getSessionIdFromUrl() {
    const params = new URLSearchParams(window.location.search);
    return params.get('sessionId');
  }

  function getSessionId() {
    return localStorage.getItem('sessionId');
  }

  function setSessionId(sessionId) {
    if (sessionId) localStorage.setItem('sessionId', sessionId);
  }

  async function verifySession(sessionId) {
    const response = await fetch(`${BACKEND_API_BASE}/api/verify-session`, {
      cache: 'no-store',
      headers: {
        'x-session-id': sessionId
      }
    });
    const data = await response.json().catch(() => ({}));
    return { response, data };
  }

  function redirectToLogin() {
    const returnTo = getReturnTo() || window.location.href;
    const url = `/admin/login.html?returnTo=${encodeURIComponent(returnTo)}`;
    window.location.href = url;
  }

  async function ensureAuth({ userNameElId = 'userName' } = {}) {
    let sessionId = getSessionId();
    const urlSessionId = getSessionIdFromUrl();
    if (urlSessionId) {
      sessionId = urlSessionId;
      setSessionId(urlSessionId);
    }

    const params = new URLSearchParams(window.location.search);
    const returnTo = params.get('returnTo');
    if (returnTo) localStorage.setItem('returnTo', returnTo);

    if (!sessionId) {
      redirectToLogin();
      return null;
    }

    try {
      const { data } = await verifySession(sessionId);
      if (!data.success) {
        logout();
        return null;
      }

      const el = document.getElementById(userNameElId);
      if (el) el.textContent = data.username || 'Admin';
      return sessionId;
    } catch (_) {
      // No forzar logout en errores transitorios (red/proxy).
      // Mantener la sesión local y permitir reintentos.
      console.warn('[adminCommon] verifySession failed (transient).');
      return sessionId;
    }
  }

  async function adminFetchJson(path, { method = 'GET', body, headers = {}, sessionId } = {}) {
    const sid = sessionId || getSessionId();
    if (!sid) {
      redirectToLogin();
      throw new Error('No autenticado');
    }

    const init = {
      method,
      cache: 'no-store',
      headers: {
        'x-session-id': sid,
        ...headers
      }
    };

    if (body !== undefined) {
      init.headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(body);
    }

    const response = await fetch(`${BACKEND_API_BASE}${path}`, init);
    const data = await response.json().catch(() => ({}));

    if (!response.ok || data.ok === false || data.success === false) {
      const msg = data.message || data.error || response.statusText || 'Error';
      const err = new Error(msg);
      err.status = response.status;
      err.data = data;
      throw err;
    }

    return { response, data };
  }

  function showMessage(containerId, text, type) {
    const el = document.getElementById(containerId);
    if (!el) return;

    el.textContent = text;
    el.classList.remove('show', 'success', 'error');
    if (type) el.classList.add(type);
    el.classList.add('show');
  }

  function hideMessage(containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;
    el.classList.remove('show', 'success', 'error');
    el.textContent = '';
  }

  function parseJsonTextarea(value, { fieldName = 'JSON' } = {}) {
    const raw = String(value || '').trim();
    if (!raw) return null;
    try {
      return JSON.parse(raw);
    } catch (e) {
      const err = new Error(`${fieldName} inválido: ${e.message}`);
      err.code = 'INVALID_JSON';
      throw err;
    }
  }

  async function logout() {
    const sid = getSessionId();
    try {
      if (sid) {
        await fetch(`${BACKEND_API_BASE}/api/logout`, {
          method: 'POST',
          headers: {
            'x-session-id': sid,
            'Content-Type': 'application/json'
          }
        });
      }
    } catch (_) {}

    localStorage.removeItem('sessionId');
    window.location.href = '/';
  }

  // ─── Shared Sidebar ───────────────────────────────────────────────────────

  const SIDEBAR_ITEMS = [
    { key: 'dashboard',     icon: '🏠', label: 'Panel',              href: 'admin-hub.html' },
    { key: 'customers',     icon: '👥', label: 'Clientes',            href: 'customers.html' },
    { key: 'products',      icon: '🧩', label: 'Productos',           href: 'products.html' },
    { key: 'plans',         icon: '🧾', label: 'Planes',              href: 'product-plans.html' },
    { key: 'subscriptions', icon: '🔄', label: 'Suscripciones',       href: 'subscriptions.html' },
    { key: 'payments',      icon: '💳', label: 'Pagos',               href: 'payments.html' },
    { key: 'licenses',      icon: '📜', label: 'Licencias',           href: 'licenses.html' },
    { key: 'tokens',        icon: '🔐', label: 'Tokens de acceso',    href: 'license-config.html' },
    { key: 'audit',         icon: '🧷', label: 'Registros de auditoría', href: 'audit-logs.html' },
    { key: 'users',         icon: '🛡️', label: 'Usuarios del sistema', href: 'platform-users.html' },
    { key: 'settings',      icon: '🏷️', label: 'Configuración tienda', href: 'store-settings.html' },
  ];

  function renderSidebar(activeKey) {
    const logoSrc = '../assets/img/logo/logo.png';

    const linksHTML = SIDEBAR_ITEMS.map((item) => {
      const cls = item.key === activeKey ? ' class="active"' : '';
      return `<li><a href="${item.href}"${cls}><span class="icon" aria-hidden="true">${item.icon}</span><span>${item.label}</span></a></li>`;
    }).join('');

    const sidebarHTML = `
<aside class="admin-sidebar" id="adminSidebar" aria-label="Navegacion principal">
  <div class="sidebar-header">
    <div class="sidebar-brand">
      <img class="sidebar-logo-img" src="${logoSrc}" alt="Logo" onerror="this.style.display='none'" />
      <div class="sidebar-title">
        <strong id="sidebarBrandName">Appyra</strong>
        <span>Gestor de licencias</span>
      </div>
    </div>
  </div>
  <ul class="sidebar-nav">${linksHTML}</ul>
  <div class="sidebar-footer">
    <button class="logout-btn" type="button" onclick="AdminCommon.logout()">Cerrar sesión</button>
  </div>
</aside>
<div class="sidebar-overlay" id="sidebarOverlay" onclick="AdminCommon.closeSidebar()"></div>`;

    const container = document.getElementById('adminSidebarContainer');
    if (container) {
      container.innerHTML = sidebarHTML;
    }

    _applySidebarActiveByUrl(activeKey);
  }

  function _applySidebarActiveByUrl(activeKey) {
    if (activeKey) return; // explicit key wins
    const path = window.location.pathname.split('/').pop();
    const navLinks = document.querySelectorAll('.admin-sidebar .sidebar-nav a');
    navLinks.forEach((link) => {
      const href = String(link.getAttribute('href') || '').split('/').pop();
      link.classList.toggle('active', href === path);
    });
  }

  function toggleSidebar() {
    document.body.classList.toggle('sidebar-open');
  }

  function closeSidebar() {
    document.body.classList.remove('sidebar-open');
  }

  let _sidebarReady = false;

  function initSidebarLayout(activeKey) {
    renderSidebar(activeKey);
    if (!_sidebarReady) {
      _sidebarReady = true;
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeSidebar();
      });
      // Use document-level delegation so listener survives sidebar re-renders.
      document.addEventListener('click', (e) => {
        const sidebar = document.getElementById('adminSidebar');
        if (sidebar && sidebar.contains(e.target) && e.target.closest('a')) {
          closeSidebar();
        }
      });
    }
  }

  // Auto-init: any page that declares #adminSidebarContainer gets the sidebar
  // without needing an explicit initSidebarLayout() call in page-level JS.
  document.addEventListener('DOMContentLoaded', function () {
    if (document.getElementById('adminSidebarContainer') && !document.getElementById('adminSidebar')) {
      AdminCommon.initSidebarLayout(null);
    }
  });

  window.AdminCommon = {
    BACKEND_API_BASE,
    getSessionId,
    setSessionId,
    ensureAuth,
    adminFetchJson,
    showMessage,
    hideMessage,
    parseJsonTextarea,
    logout,
    renderSidebar,
    initSidebarLayout,
    toggleSidebar,
    closeSidebar,
  };
})();

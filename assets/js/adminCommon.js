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
    { key: 'dashboard',     label: 'Panel',                 href: 'admin-hub.html' },
    { key: 'customers',     label: 'Clientes',              href: 'customers.html' },
    { key: 'products',      label: 'Productos',             href: 'products.html' },
    { key: 'plans',         label: 'Planes',                href: 'product-plans.html' },
    { key: 'subscriptions', label: 'Suscripciones',         href: 'subscriptions.html' },
    { key: 'payments',      label: 'Pagos',                 href: 'payments.html' },
    { key: 'licenses',      label: 'Licencias',             href: 'licenses.html' },
    { key: 'tokens',        label: 'Tokens de acceso',      href: 'license-config.html' },
    { key: 'users',         label: 'Usuarios del sistema',  href: 'platform-users.html' },
    { key: 'settings',      label: 'Configuración tienda',  href: 'store-settings.html' },
  ];

  const SIDEBAR_SVG = {
    dashboard: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 11.5 12 4l9 7.5"></path><path d="M5 10.5V20h14v-9.5"></path><path d="M9.5 20v-5h5v5"></path></svg>',
    customers: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.5 19.5v-1.2a3.8 3.8 0 0 0-3.8-3.8H8.8A3.8 3.8 0 0 0 5 18.3v1.2"></path><circle cx="10.8" cy="8.2" r="3.2"></circle><path d="M19 19.5v-1a3.2 3.2 0 0 0-2.2-3"></path><path d="M15.5 5.5a3 3 0 0 1 0 5.8"></path></svg>',
    products: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.8 7.5 12 3l8.2 4.5L12 12z"></path><path d="M3.8 7.5V16.5L12 21l8.2-4.5V7.5"></path><path d="M12 12v9"></path></svg>',
    plans: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="3.5" width="16" height="17" rx="2"></rect><path d="M8 8h8M8 12h8M8 16h5"></path></svg>',
    subscriptions: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 7.8A8 8 0 0 0 6.2 5.5"></path><path d="M6.2 5.5V9.2H2.5"></path><path d="M4 16.2A8 8 0 0 0 17.8 18.5"></path><path d="M17.8 18.5v-3.7h3.7"></path></svg>',
    payments: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="M3 10h18"></path><path d="M7 15h4"></path></svg>',
    licenses: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="3.5" width="16" height="17" rx="2"></rect><path d="M8 8h8M8 12h8M8 16h6"></path></svg>',
    tokens: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="12" r="3.5"></circle><path d="M11.5 12H21"></path><path d="M17 12v2.5M14 12v2.5"></path></svg>',
    users: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.5 5 6.5V12c0 4.5 3 7.6 7 8.5 4-1 7-4 7-8.5V6.5z"></path><path d="M9 12.8 11 14.8 15 10.8"></path></svg>',
    settings: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10.8 3h2.4l.6 2.2a7 7 0 0 1 1.7.7l2-1.1 1.7 1.7-1.1 2c.3.5.5 1.1.7 1.7L21 11v2l-2.2.6a7 7 0 0 1-.7 1.7l1.1 2-1.7 1.7-2-1.1c-.5.3-1.1.5-1.7.7L13.2 21h-2.4l-.6-2.2a7 7 0 0 1-1.7-.7l-2 1.1-1.7-1.7 1.1-2a7 7 0 0 1-.7-1.7L3 13v-2l2.2-.6c.1-.6.4-1.2.7-1.7l-1.1-2 1.7-1.7 2 1.1c.5-.3 1.1-.5 1.7-.7z"></path><circle cx="12" cy="12" r="2.7"></circle></svg>'
  };

  function iconForKey(key) {
    return SIDEBAR_SVG[key] || SIDEBAR_SVG.dashboard;
  }

  function renderSidebar(activeKey) {
    const logoSrc = '../assets/img/logo/logo.png';

    const linksHTML = SIDEBAR_ITEMS.map((item) => {
      const cls = item.key === activeKey ? ' class="active"' : '';
      return `<li><a href="${item.href}"${cls} title="${item.label}" aria-label="${item.label}"><span class="icon" aria-hidden="true">${iconForKey(item.key)}</span><span class="nav-label">${item.label}</span></a></li>`;
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
      <button class="sidebar-expand-btn" type="button" title="Expandir o contraer" aria-label="Expandir o contraer" onclick="AdminCommon.toggleSidebarExpanded()">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6l6 6-6 6"></path></svg>
      </button>
    </div>
  </div>
  <ul class="sidebar-nav">${linksHTML}</ul>
  <div class="sidebar-footer">
    <button class="logout-btn" type="button" title="Cerrar sesión" aria-label="Cerrar sesión" onclick="AdminCommon.logout()">Cerrar sesión</button>
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

  function isDesktop() {
    return window.matchMedia('(min-width: 861px)').matches;
  }

  function toggleSidebarExpanded(force) {
    const next = typeof force === 'boolean'
      ? force
      : !document.body.classList.contains('sidebar-expanded');

    if (next) {
      document.body.classList.add('sidebar-expanded');
    } else {
      document.body.classList.remove('sidebar-expanded');
    }

    try {
      localStorage.setItem('adminSidebarExpanded', next ? '1' : '0');
    } catch (_) {}
  }

  function initSidebarExpandState() {
    try {
      const stored = localStorage.getItem('adminSidebarExpanded');
      if (isDesktop()) {
        // Default desktop state: collapsed (not expanded)
        toggleSidebarExpanded(stored === '1');
      } else {
        document.body.classList.remove('sidebar-expanded');
      }
    } catch (_) {
      if (!isDesktop()) {
        document.body.classList.remove('sidebar-expanded');
      }
    }

    window.addEventListener('resize', () => {
      if (!isDesktop()) {
        document.body.classList.remove('sidebar-expanded');
      }
    });
  }

  let _sidebarReady = false;

  function initSidebarLayout(activeKey) {
    renderSidebar(activeKey);
    initSidebarExpandState();
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

  const DesignSystem = {
    tokens: {
      color: {
        bgApp: '#F6F8FC',
        surfaceBase: '#FFFFFF',
        surfaceSoft: '#F9FBFE',
        surfaceTech: '#F5F7FA',
        borderMain: '#E4EAF2',
        borderSoft: '#EAF0F7',
        textPrimary: '#1A2235',
        textSecondary: '#6B7494',
        textMuted: '#8893AA',
        primaryAction: '#1F4B99',
        primarySoft: '#EAF0FF',
        dataBlue: '#1565C0',
        success: '#2E7D32',
        warning: '#E67E00',
        error: '#C62828',
        violet: '#6A1B9A',
        teal: '#00897B',
        magenta: '#AD1457'
      },
      spacing: [4, 6, 8, 10, 12, 14, 16, 20, 24],
      radius: {
        sm: 8,
        md: 10,
        lg: 12,
        xl: 14,
        dialog: 16
      },
      motionMs: {
        fast: 120,
        base: 150,
        slow: 180
      }
    },
    guidelines: {
      hierarchy: [
        'Screen title: 20px semibold',
        'Block title: 13-14px bold',
        'Field label: 10-11px semibold muted',
        'Primary value: 12-16px bold',
        'Support text: 11-12px medium'
      ],
      layout: [
        'Desktop-first with right detail panel',
        'Compact topbar and dense rows',
        'No heavy shadows; separate by border and tone',
        'Grids collapse 3->2->1 without horizontal overflow'
      ],
      interaction: [
        'Hover, press and focus states are required',
        'AA contrast minimum for functional text',
        'Motion duration between 120ms and 180ms'
      ]
    },
    utils: {
      formatMoney(value, currency = 'DOP', locale = 'es-DO') {
        const n = Number(value || 0);
        return new Intl.NumberFormat(locale, {
          style: 'currency',
          currency,
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        }).format(Number.isFinite(n) ? n : 0);
      },
      clampText(text, max = 48) {
        const s = String(text || '');
        return s.length > max ? `${s.slice(0, max - 1)}…` : s;
      }
    }
  };

  window.AppyraDesignSystem = DesignSystem;

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
    toggleSidebarExpanded,
  };
})();

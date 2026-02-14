/*
  Admin common helpers (session, fetch wrapper, UI messages)
  Uses x-session-id stored in localStorage as "sessionId".
*/

(function () {
  const isLocal = window.location.hostname === '127.0.0.1' || window.location.hostname === 'localhost';
  // Prefer a stable API origin in production to avoid mismatches between
  // where the static admin is hosted vs where the API lives.
  const BACKEND_API_BASE = isLocal
    ? 'http://127.0.0.1:3000'
    : (window.location.origin.includes('api.fulltechrd.com')
        ? window.location.origin
        : 'https://api.fulltechrd.com');

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
    const url = `${BACKEND_API_BASE}/admin/login.html?returnTo=${encodeURIComponent(returnTo)}`;
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
      logout();
      return null;
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

  window.AdminCommon = {
    BACKEND_API_BASE,
    getSessionId,
    setSessionId,
    ensureAuth,
    adminFetchJson,
    showMessage,
    hideMessage,
    parseJsonTextarea,
    logout
  };
})();

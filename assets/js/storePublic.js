(function () {
  const isLocal = window.location.hostname === '127.0.0.1' || window.location.hostname === 'localhost';
  const API_BASE = isLocal ? 'http://127.0.0.1:3000' : window.location.origin;

  async function fetchJson(path) {
    const res = await fetch(`${API_BASE}${path}`, { cache: 'no-store' });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.ok === false || data.success === false) {
      const msg = data.message || data.error || res.statusText || 'Error';
      const err = new Error(msg);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  function setCssVars(theme) {
    if (!theme || typeof theme !== 'object') return;
    const root = document.documentElement;
    if (theme.primary) root.style.setProperty('--color-primary', String(theme.primary));
    if (theme.accent) root.style.setProperty('--color-accent', String(theme.accent));
    if (theme.light) root.style.setProperty('--color-light', String(theme.light));
    if (theme.dark) root.style.setProperty('--color-dark', String(theme.dark));
  }

  function e164ToWaLink(raw, text) {
    const digits = String(raw || '').replace(/[^0-9]/g, '');
    if (!digits) return '#';
    const base = `https://wa.me/${digits}`;
    if (!text) return base;
    return `${base}?text=${encodeURIComponent(text)}`;
  }

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function moneyText(p) {
    if (p.price_text) return String(p.price_text);
    if (p.price_amount != null && Number.isFinite(Number(p.price_amount))) {
      const cur = p.currency || 'DOP';
      return `${cur} ${Number(p.price_amount).toLocaleString('es-DO', { maximumFractionDigits: 2 })}`;
    }
    return '';
  }

  window.StorePublic = {
    API_BASE,
    fetchJson,
    setCssVars,
    e164ToWaLink,
    esc,
    moneyText
  };
})();

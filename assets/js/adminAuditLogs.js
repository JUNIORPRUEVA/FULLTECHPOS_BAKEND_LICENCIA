(function () {
  const state = { sessionId: null };
  const msgId = 'message';

  window.addEventListener('DOMContentLoaded', init);

  async function init() {
    bindUi();
    state.sessionId = await AdminCommon.ensureAuth({ userNameElId: 'userName' });
    if (!state.sessionId) return;
    await loadLogs();
  }

  function bindUi() {
    document.getElementById('filterBtn').addEventListener('click', loadLogs);
  }

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function showLoading(show) {
    document.getElementById('loading').style.display = show ? 'block' : 'none';
  }

  function showError(error) {
    AdminCommon.showMessage(msgId, String(error?.message || error || 'Error interno'), 'error');
  }

  function buildQuery() {
    const params = new URLSearchParams();
    const company = document.getElementById('filterCompany').value.trim();
    const action = document.getElementById('filterAction').value.trim();
    const targetType = document.getElementById('filterTargetType').value.trim();
    const from = document.getElementById('filterDateFrom').value;
    const to = document.getElementById('filterDateTo').value;

    if (company) params.set('company_id', company);
    if (action) params.set('action', action);
    if (targetType) params.set('target_type', targetType);
    if (from) params.set('date_from', new Date(`${from}T00:00:00`).toISOString());
    if (to) params.set('date_to', new Date(`${to}T23:59:59`).toISOString());
    params.set('limit', '200');
    params.set('offset', '0');

    return params;
  }

  async function loadLogs() {
    AdminCommon.hideMessage(msgId);
    showLoading(true);
    try {
      const { data } = await AdminCommon.adminFetchJson(`/api/admin/audit-logs?${buildQuery().toString()}`, {
        sessionId: state.sessionId
      });
      renderLogs(Array.isArray(data?.logs) ? data.logs : []);
    } catch (error) {
      showError(error);
      renderLogs([]);
    } finally {
      showLoading(false);
    }
  }

  function renderLogs(logs) {
    const wrap = document.getElementById('tableWrap');
    if (!logs.length) {
      wrap.innerHTML = '<div class="empty">No hay logs para los filtros seleccionados.</div>';
      return;
    }

    wrap.innerHTML = `
      <table>
        <thead>
          <tr>
            <th>Fecha</th>
            <th>Actor</th>
            <th>Action</th>
            <th>Target</th>
            <th>Company</th>
          </tr>
        </thead>
        <tbody>
          ${logs.map((log) => `
            <tr>
              <td>${formatDate(log.created_at)}</td>
              <td>
                <div>${esc(log.actor_type || 'system')}</div>
                <div class="muted mono">${esc(log.actor_email || log.actor_user_id || '-')}</div>
              </td>
              <td>
                <div class="chip">${esc(log.action || '-')}</div>
              </td>
              <td>
                <div>${esc(log.target_type || '-')}</div>
                <div class="muted mono">${esc(log.target_id || '-')}</div>
              </td>
              <td>
                <div>${esc(log.company_name || '-')}</div>
                <div class="muted mono">${esc(log.company_id || '-')}</div>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;
  }

  function formatDate(value) {
    if (!value) return '-';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleString('es-DO');
  }
})();

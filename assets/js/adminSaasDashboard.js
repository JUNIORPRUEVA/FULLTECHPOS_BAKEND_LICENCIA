(function () {
  const state = { sessionId: null };
  const msgId = 'message';

  window.addEventListener('DOMContentLoaded', init);

  async function init() {
    document.getElementById('refreshBtn').addEventListener('click', loadDashboard);
    document.getElementById('maintenanceBtn').addEventListener('click', runMaintenance);

    state.sessionId = await AdminCommon.ensureAuth({ userNameElId: 'userName' });
    if (!state.sessionId) return;

    await loadDashboard();
  }

  function showError(error) {
    AdminCommon.showMessage(msgId, String(error?.message || error || 'Error interno'), 'error');
  }

  function showSuccess(message) {
    AdminCommon.showMessage(msgId, message, 'success');
  }

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])
    );
  }

  // ─── Dashboard load ────────────────────────────────────────────────────────

  async function loadDashboard() {
    AdminCommon.hideMessage(msgId);
    const btn = document.getElementById('refreshBtn');
    if (btn) btn.disabled = true;

    try {
      const res = await AdminCommon.adminFetchJson('/api/admin/saas-dashboard', {
        sessionId: state.sessionId
      });

      if (!res?.ok) throw new Error(res?.error || 'Error al cargar dashboard');
      const d = res.data;

      setText('metricCompanies', formatNumber(d.total_companies));
      setText('metricActive', formatNumber(d.active_subscriptions));
      setText('metricExpired', formatNumber(d.expired_subscriptions));
      setText('metricSuspended', formatNumber(d.suspended_subscriptions));
      setText('metricPendingPayments', formatNumber(d.pending_payments));
      setText('metricMonthlyEstimate', formatCurrency(d.monthly_revenue_estimate));
      setText('metricCollectedMonth', formatCurrency(d.payments_collected_this_month));
      setText('metricNearExpiration', formatNumber((d.clients_near_expiration || []).length));

      renderNearExpiration(d.clients_near_expiration || []);
      renderRevenueByOwnership(d.revenue_by_product_or_project || []);

      showSuccess('Dashboard actualizado.');
    } catch (error) {
      showError(error);
      renderNearExpiration([]);
      renderRevenueByOwnership([]);
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  // ─── Maintenance ───────────────────────────────────────────────────────────

  async function runMaintenance() {
    AdminCommon.hideMessage(msgId);
    const btn = document.getElementById('maintenanceBtn');
    if (btn) { btn.disabled = true; btn.textContent = 'Ejecutando...'; }
    setMaintenanceResult(null);

    try {
      const res = await AdminCommon.adminFetchJson('/api/admin/subscriptions/run-maintenance', {
        sessionId: state.sessionId,
        method: 'POST'
      });

      if (!res?.ok) throw new Error(res?.error || 'Error al ejecutar mantenimiento');

      const d = res.data;
      setMaintenanceResult(d);
      showSuccess(res.message || 'Mantenimiento completado.');

      // Reload metrics to reflect new statuses.
      await loadDashboard();
    } catch (error) {
      showError(error);
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = 'Ejecutar mantenimiento'; }
    }
  }

  function setMaintenanceResult(data) {
    const wrap = document.getElementById('maintenanceResult');
    if (!wrap) return;

    if (!data) { wrap.innerHTML = ''; wrap.hidden = true; return; }

    wrap.hidden = false;
    wrap.innerHTML = `
      <div class="maintenance-summary">
        <span class="chip expired">${esc(data.expired_count || 0)} expiradas</span>
        <span class="chip past_due">${esc(data.past_due_count || 0)} en mora</span>
        <span class="chip">${esc(data.skipped_count || 0)} omitidas</span>
        <span class="chip suspended">${esc(data.licenses_blocked_count || 0)} licencias bloqueadas</span>
        <span class="muted" style="font-size:.75rem;">de ${esc(data.candidates_checked || 0)} candidatas</span>
      </div>
    `;
  }

  // ─── Render helpers ────────────────────────────────────────────────────────

  function setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function formatNumber(value) {
    return new Intl.NumberFormat('es-DO').format(Number(value || 0));
  }

  function formatCurrency(value) {
    return `DOP ${new Intl.NumberFormat('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(
      Number(value || 0)
    )}`;
  }

  function formatDate(value) {
    if (!value) return '-';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleDateString('es-DO');
  }

  function renderNearExpiration(rows) {
    const wrap = document.getElementById('nearExpWrap');
    if (!rows.length) {
      wrap.innerHTML = '<div class="empty">No hay clientes cerca de expiracion en los proximos 15 dias.</div>';
      return;
    }

    wrap.innerHTML = `
      <table>
        <thead>
          <tr>
            <th>Company</th>
            <th>Plan</th>
            <th>Status</th>
            <th>Fin</th>
          </tr>
        </thead>
        <tbody>
          ${rows
            .map(
              (sub) => `
            <tr>
              <td>
                <div>${esc(sub.company_name || '-')}</div>
                <div class="muted mono">${esc(sub.company_id || '')}</div>
              </td>
              <td>
                <div>${esc(sub.plan_name || '-')}</div>
                <div class="muted">${esc(sub.product_name || sub.project_name || '')}</div>
              </td>
              <td><span class="chip ${esc(String(sub.status || '').toLowerCase())}">${esc(sub.status || '-')}</span></td>
              <td>${formatDate(sub.end_date)}</td>
            </tr>`
            )
            .join('')}
        </tbody>
      </table>
    `;
  }

  function renderRevenueByOwnership(rows) {
    const wrap = document.getElementById('revenueByOwnershipWrap');
    if (!wrap) return;

    if (!rows.length) {
      wrap.innerHTML = '<div class="empty">Sin datos de ingresos por producto/proyecto.</div>';
      return;
    }

    wrap.innerHTML = `
      <table>
        <thead>
          <tr>
            <th>Producto / Proyecto</th>
            <th>Tipo</th>
            <th>Suscripciones</th>
            <th>Estimado mensual</th>
          </tr>
        </thead>
        <tbody>
          ${rows
            .map(
              (row) => `
            <tr>
              <td>${esc(row.label || '-')}</td>
              <td><span class="chip">${esc(row.type || '-')}</span></td>
              <td>${formatNumber(row.subscriptions)}</td>
              <td>${formatCurrency(row.monthly_estimate)}</td>
            </tr>`
            )
            .join('')}
        </tbody>
      </table>
    `;
  }
})();

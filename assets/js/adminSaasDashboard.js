(function () {
  const state = {
    sessionId: null,
    plansById: new Map(),
    subscriptions: [],
    payments: []
  };

  const msgId = 'message';

  window.addEventListener('DOMContentLoaded', init);

  async function init() {
    document.getElementById('refreshBtn').addEventListener('click', loadDashboard);

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
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  async function loadDashboard() {
    AdminCommon.hideMessage(msgId);

    try {
      const [plansRes, subscriptionsRes, paymentsRes, activeCountRes, expiredCountRes, suspendedCountRes, pendingPaymentsRes] = await Promise.all([
        AdminCommon.adminFetchJson('/api/admin/product-plans?limit=300&offset=0', { sessionId: state.sessionId }),
        AdminCommon.adminFetchJson('/api/admin/subscriptions?limit=300&offset=0', { sessionId: state.sessionId }),
        AdminCommon.adminFetchJson('/api/admin/payments?limit=300&offset=0', { sessionId: state.sessionId }),
        AdminCommon.adminFetchJson('/api/admin/subscriptions?status=active&limit=1&offset=0', { sessionId: state.sessionId }),
        AdminCommon.adminFetchJson('/api/admin/subscriptions?status=expired&limit=1&offset=0', { sessionId: state.sessionId }),
        AdminCommon.adminFetchJson('/api/admin/subscriptions?status=suspended&limit=1&offset=0', { sessionId: state.sessionId }),
        AdminCommon.adminFetchJson('/api/admin/payments?status=pending&limit=1&offset=0', { sessionId: state.sessionId })
      ]);

      const plans = Array.isArray(plansRes?.data?.plans) ? plansRes.data.plans : [];
      const subscriptions = Array.isArray(subscriptionsRes?.data?.subscriptions) ? subscriptionsRes.data.subscriptions : [];
      const payments = Array.isArray(paymentsRes?.data?.payments) ? paymentsRes.data.payments : [];

      state.subscriptions = subscriptions;
      state.payments = payments;
      state.plansById = new Map(plans.map((plan) => [String(plan.id), plan]));

      const totalCompanies = new Set(subscriptions.map((sub) => sub.company_id).filter(Boolean)).size;
      const activeSubscriptions = Number(activeCountRes?.data?.total || 0);
      const expiredSubscriptions = Number(expiredCountRes?.data?.total || 0);
      const suspendedSubscriptions = Number(suspendedCountRes?.data?.total || 0);
      const pendingPayments = Number(pendingPaymentsRes?.data?.total || 0);

      const monthlyRevenueEstimate = estimateMonthlyRevenue(subscriptions);
      const paymentsCollectedThisMonth = collectedThisMonth(payments);
      const nearExpiration = collectNearExpiration(subscriptions, 15);

      setText('metricCompanies', formatNumber(totalCompanies));
      setText('metricActive', formatNumber(activeSubscriptions));
      setText('metricExpired', formatNumber(expiredSubscriptions));
      setText('metricSuspended', formatNumber(suspendedSubscriptions));
      setText('metricPendingPayments', formatNumber(pendingPayments));
      setText('metricMonthlyEstimate', formatCurrency(monthlyRevenueEstimate));
      setText('metricCollectedMonth', formatCurrency(paymentsCollectedThisMonth));
      setText('metricNearExpiration', formatNumber(nearExpiration.length));

      renderNearExpiration(nearExpiration);
      showSuccess('Dashboard actualizado.');
    } catch (error) {
      showError(error);
      renderNearExpiration([]);
    }
  }

  function setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function formatNumber(value) {
    return new Intl.NumberFormat('es-DO').format(Number(value || 0));
  }

  function formatCurrency(value) {
    return `DOP ${new Intl.NumberFormat('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value || 0))}`;
  }

  function estimateMonthlyRevenue(subscriptions) {
    let total = 0;

    subscriptions.forEach((sub) => {
      const status = String(sub.status || '').toLowerCase();
      if (!['active', 'trial', 'lifetime', 'past_due'].includes(status)) return;

      const plan = state.plansById.get(String(sub.plan_id));
      if (!plan) return;
      const amount = Number(plan.price_amount || 0);
      if (!Number.isFinite(amount) || amount <= 0) return;

      const period = String(plan.billing_period || 'monthly').toLowerCase();
      if (period === 'annual') {
        total += amount / 12;
      } else if (period === 'lifetime') {
        total += amount / 24;
      } else {
        total += amount;
      }
    });

    return total;
  }

  function collectedThisMonth(payments) {
    const now = new Date();
    const month = now.getMonth();
    const year = now.getFullYear();

    return payments.reduce((acc, payment) => {
      if (String(payment.status || '').toLowerCase() !== 'paid') return acc;
      const paidDate = new Date(payment.paid_at || payment.recorded_at || payment.created_at);
      if (Number.isNaN(paidDate.getTime())) return acc;
      if (paidDate.getMonth() === month && paidDate.getFullYear() === year) {
        return acc + Number(payment.amount || 0);
      }
      return acc;
    }, 0);
  }

  function collectNearExpiration(subscriptions, days) {
    const now = new Date();
    const max = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);

    return subscriptions
      .filter((sub) => {
        const status = String(sub.status || '').toLowerCase();
        if (!['active', 'trial', 'past_due'].includes(status)) return false;
        if (!sub.end_date) return false;

        const end = new Date(sub.end_date);
        if (Number.isNaN(end.getTime())) return false;
        return end >= now && end <= max;
      })
      .sort((a, b) => new Date(a.end_date).getTime() - new Date(b.end_date).getTime());
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
            <th>Renovacion</th>
            <th>Fin</th>
          </tr>
        </thead>
        <tbody>
          ${rows.map((sub) => `
            <tr>
              <td>
                <div class="mono">${esc(sub.company_id || '-')}</div>
                <div class="muted">${esc(sub.company_name || '')}</div>
              </td>
              <td>
                <div>${esc(sub.plan_name || '-')}</div>
                <div class="muted mono">${esc(sub.plan_code || '-')}</div>
              </td>
              <td><span class="chip ${esc(String(sub.status || '').toLowerCase())}">${esc(sub.status || '-')}</span></td>
              <td>${formatDate(sub.renewal_date)}</td>
              <td>${formatDate(sub.end_date)}</td>
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
    return date.toLocaleDateString('es-DO');
  }
})();

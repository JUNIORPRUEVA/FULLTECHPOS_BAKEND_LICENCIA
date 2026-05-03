(function () {
  const state = { sessionId: null };
  const msgId = 'message';

  window.addEventListener('DOMContentLoaded', init);

  async function init() {
    bindUi();
    state.sessionId = await AdminCommon.ensureAuth({ userNameElId: 'userName' });
    if (!state.sessionId) return;
    await loadPayments();
  }

  function bindUi() {
    document.getElementById('filterBtn').addEventListener('click', loadPayments);
    document.getElementById('newPaymentBtn').addEventListener('click', () => openModal('paymentModal'));
    document.getElementById('paymentForm').addEventListener('submit', onSubmitPayment);

    document.addEventListener('click', (event) => {
      const closeId = event.target.getAttribute('data-close-modal');
      if (closeId) closeModal(closeId);
    });
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

  function showSuccess(message) {
    AdminCommon.showMessage(msgId, message, 'success');
  }

  function fmtMoney(amount, currency) {
    const value = Number(amount || 0);
    const curr = String(currency || 'DOP').toUpperCase();
    return `${curr} ${new Intl.NumberFormat('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)}`;
  }

  function fmtDateTime(value) {
    if (!value) return '-';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleString('es-DO');
  }

  function chip(status) {
    const s = String(status || '').toLowerCase();
    return `<span class="chip ${esc(s)}">${esc(s || 'unknown')}</span>`;
  }

  function queryFilters() {
    const params = new URLSearchParams();
    const company = document.getElementById('filterCompany').value.trim();
    const subscription = document.getElementById('filterSubscription').value.trim();
    const status = document.getElementById('filterStatus').value;

    if (company) params.set('company_id', company);
    if (subscription) params.set('subscription_id', subscription);
    if (status) params.set('status', status);
    params.set('limit', '200');
    params.set('offset', '0');
    return params;
  }

  async function loadPayments() {
    AdminCommon.hideMessage(msgId);
    showLoading(true);
    try {
      const { data } = await AdminCommon.adminFetchJson(`/api/admin/payments?${queryFilters().toString()}`, {
        sessionId: state.sessionId
      });
      renderRows(Array.isArray(data?.payments) ? data.payments : []);
    } catch (error) {
      showError(error);
      renderRows([]);
    } finally {
      showLoading(false);
    }
  }

  function renderRows(rows) {
    const wrap = document.getElementById('tableWrap');
    if (!rows.length) {
      wrap.innerHTML = '<div class="empty">No hay pagos en este momento.</div>';
      return;
    }

    wrap.innerHTML = `
      <table>
        <thead>
          <tr>
            <th>Status</th>
            <th>Monto</th>
            <th>Metodo</th>
            <th>Referencia</th>
            <th>Subscription</th>
            <th>Company</th>
            <th>Fecha</th>
          </tr>
        </thead>
        <tbody>
          ${rows.map((row) => `
            <tr>
              <td>${chip(row.status)}</td>
              <td>${fmtMoney(row.amount, row.currency)}</td>
              <td>${esc(row.payment_method || '-')}</td>
              <td class="mono">${esc(row.reference || '-')}</td>
              <td class="mono">${esc(row.subscription_id || '-')}</td>
              <td>
                <div class="mono">${esc(row.company_id || '-')}</div>
                <div class="muted">${esc(row.company_name || '')}</div>
              </td>
              <td>${fmtDateTime(row.paid_at || row.recorded_at || row.created_at)}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;
  }

  async function onSubmitPayment(event) {
    event.preventDefault();
    const amount = Number(document.getElementById('paymentAmount').value);
    if (!Number.isFinite(amount) || amount < 0) {
      showError(new Error('El monto no puede ser negativo.'));
      return;
    }

    const payload = {
      subscription_id: document.getElementById('paymentSubscriptionId').value.trim(),
      amount,
      status: document.getElementById('paymentStatus').value,
      payment_method: document.getElementById('paymentMethod').value,
      currency: document.getElementById('paymentCurrency').value.trim() || 'DOP',
      reference: document.getElementById('paymentReference').value.trim() || undefined,
      company_id: document.getElementById('paymentCompanyId').value.trim() || undefined,
      license_id: document.getElementById('paymentLicenseId').value.trim() || undefined,
      notes: document.getElementById('paymentNotes').value.trim() || undefined
    };

    const paidAtRaw = document.getElementById('paymentPaidAt').value;
    if (paidAtRaw) payload.paid_at = new Date(paidAtRaw).toISOString();

    try {
      const { data } = await AdminCommon.adminFetchJson('/api/admin/payments', {
        method: 'POST',
        body: payload,
        sessionId: state.sessionId
      });

      const updatedEndDate = data?.subscription?.end_date;
      const updateMsg = payload.status === 'paid' && updatedEndDate
        ? ` Pago aplicado. Nueva fecha fin: ${new Date(updatedEndDate).toLocaleDateString('es-DO')}`
        : '';

      showSuccess(`Pago registrado correctamente.${updateMsg}`);
      closeModal('paymentModal');
      document.getElementById('paymentForm').reset();
      document.getElementById('paymentCurrency').value = 'DOP';
      document.getElementById('paymentStatus').value = 'paid';
      document.getElementById('paymentMethod').value = 'manual';
      await loadPayments();
    } catch (error) {
      showError(error);
    }
  }

  function openModal(id) {
    document.getElementById(id).classList.add('is-open');
    document.body.style.overflow = 'hidden';
  }

  function closeModal(id) {
    document.getElementById(id).classList.remove('is-open');
    if (!document.querySelector('.modal.is-open')) {
      document.body.style.overflow = '';
    }
  }
})();

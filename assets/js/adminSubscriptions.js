(function () {
  const state = {
    sessionId: null,
    plans: [],
    products: [],
    projects: []
  };

  const msgId = 'message';

  window.addEventListener('DOMContentLoaded', init);

  async function init() {
    bindUi();
    state.sessionId = await AdminCommon.ensureAuth({ userNameElId: 'userName' });
    if (!state.sessionId) return;

    try {
      await Promise.all([loadPlans(), loadProducts(), loadProjects()]);
      await loadSubscriptions();
    } catch (error) {
      showError(error);
    }
  }

  function bindUi() {
    document.getElementById('filterBtn').addEventListener('click', loadSubscriptions);
    document.getElementById('newSubscriptionBtn').addEventListener('click', () => openModal('subscriptionModal'));
    document.getElementById('subscriptionForm').addEventListener('submit', onCreateSubscription);
    document.getElementById('extendForm').addEventListener('submit', onExtendSubscription);

    document.addEventListener('click', (event) => {
      const closeId = event.target.getAttribute('data-close-modal');
      if (closeId) closeModal(closeId);
    });
  }

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function fmtDate(value) {
    if (!value) return '-';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleDateString('es-DO');
  }

  function showError(error) {
    AdminCommon.showMessage(msgId, String(error?.message || error || 'Error interno'), 'error');
  }

  function showSuccess(message) {
    AdminCommon.showMessage(msgId, message, 'success');
  }

  function showLoading(show) {
    document.getElementById('loading').style.display = show ? 'block' : 'none';
  }

  function chip(status) {
    const s = String(status || '').toLowerCase();
    return `<span class="chip ${esc(s)}">${esc(s || 'unknown')}</span>`;
  }

  async function loadPlans() {
    const { data } = await AdminCommon.adminFetchJson('/api/admin/product-plans?limit=200&offset=0', { sessionId: state.sessionId });
    state.plans = Array.isArray(data?.plans) ? data.plans : [];
    const options = ['<option value="">Seleccionar plan</option>']
      .concat(state.plans.map((plan) => `<option value="${esc(plan.id)}">${esc(plan.name)} (${esc(plan.code)})</option>`))
      .join('');
    document.getElementById('subPlanId').innerHTML = options;
  }

  async function loadProducts() {
    const { data } = await AdminCommon.adminFetchJson('/api/admin/products?limit=200&offset=0', { sessionId: state.sessionId });
    state.products = Array.isArray(data?.products) ? data.products : [];
    const options = ['<option value="">Todos</option>']
      .concat(state.products.map((item) => `<option value="${esc(item.id)}">${esc(item.name || item.slug || item.id)}</option>`))
      .join('');
    document.getElementById('filterProduct').innerHTML = options;
  }

  async function loadProjects() {
    const { data } = await AdminCommon.adminFetchJson('/api/admin/projects?limit=200&page=1', { sessionId: state.sessionId });
    state.projects = Array.isArray(data?.projects) ? data.projects : [];
    const options = ['<option value="">Todos</option>']
      .concat(state.projects.map((item) => `<option value="${esc(item.id)}">${esc(item.name || item.code || item.id)}</option>`))
      .join('');
    document.getElementById('filterProject').innerHTML = options;
  }

  function buildQuery() {
    const params = new URLSearchParams();
    const company = document.getElementById('filterCompany').value.trim();
    const status = document.getElementById('filterStatus').value.trim();
    const product = document.getElementById('filterProduct').value.trim();
    const project = document.getElementById('filterProject').value.trim();

    if (company) params.set('company_id', company);
    if (status) params.set('status', status);
    if (product) params.set('product_id', product);
    if (project) params.set('project_id', project);

    params.set('limit', '200');
    params.set('offset', '0');
    return params;
  }

  async function loadSubscriptions() {
    AdminCommon.hideMessage(msgId);
    showLoading(true);
    try {
      const { data } = await AdminCommon.adminFetchJson(`/api/admin/subscriptions?${buildQuery().toString()}`, {
        sessionId: state.sessionId
      });
      const rows = Array.isArray(data?.subscriptions) ? data.subscriptions : [];
      renderRows(rows);
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
      wrap.innerHTML = '<div class="empty">No hay suscripciones para los filtros actuales.</div>';
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
            <th>Producto/Proyecto</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          ${rows.map((row) => {
            const owner = row.product_name || row.product_slug
              ? `Producto: ${esc(row.product_name || row.product_slug)}`
              : `Proyecto: ${esc(row.project_name || row.project_code || '-')}`;
            return `
              <tr>
                <td>
                  <div class="mono">${esc(row.company_id)}</div>
                  <div class="muted">${esc(row.company_name || '')}</div>
                </td>
                <td>
                  <strong>${esc(row.plan_name || '-')}</strong>
                  <div class="muted mono">${esc(row.plan_code || '-')}</div>
                </td>
                <td>${chip(row.status)}</td>
                <td>${fmtDate(row.renewal_date)}</td>
                <td>${fmtDate(row.end_date)}</td>
                <td>${owner}</td>
                <td>
                  <div class="row-actions">
                    <button class="btn btn-secondary" type="button" data-extend="${esc(row.id)}">Extender</button>
                    <button class="btn btn-warning" type="button" data-suspend="${esc(row.id)}">Suspender</button>
                    <button class="btn btn-danger" type="button" data-cancel="${esc(row.id)}">Cancelar</button>
                  </div>
                </td>
              </tr>
            `;
          }).join('')}
        </tbody>
      </table>
    `;

    wrap.querySelectorAll('[data-extend]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const id = btn.getAttribute('data-extend');
        document.getElementById('extendSubscriptionId').value = id;
        document.getElementById('extendModalRef').textContent = `Suscripcion: ${id}`;
        openModal('extendModal');
      });
    });

    wrap.querySelectorAll('[data-suspend]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const id = btn.getAttribute('data-suspend');
        await changeStatus(id, 'suspend');
      });
    });

    wrap.querySelectorAll('[data-cancel]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const id = btn.getAttribute('data-cancel');
        await changeStatus(id, 'cancel');
      });
    });
  }

  async function onCreateSubscription(event) {
    event.preventDefault();
    const payload = {
      company_id: document.getElementById('subCompanyId').value.trim(),
      plan_id: document.getElementById('subPlanId').value,
      notes: document.getElementById('subNotes').value.trim() || undefined
    };

    const status = document.getElementById('subStatus').value;
    const startDate = document.getElementById('subStartDate').value;
    if (status) payload.status = status;
    if (startDate) payload.start_date = startDate;

    try {
      await AdminCommon.adminFetchJson('/api/admin/subscriptions', {
        method: 'POST',
        body: payload,
        sessionId: state.sessionId
      });
      showSuccess('Suscripcion creada correctamente.');
      closeModal('subscriptionModal');
      document.getElementById('subscriptionForm').reset();
      await loadSubscriptions();
    } catch (error) {
      showError(error);
    }
  }

  async function onExtendSubscription(event) {
    event.preventDefault();
    const id = document.getElementById('extendSubscriptionId').value.trim();
    const days = Number(document.getElementById('extendDays').value);
    if (!Number.isFinite(days) || days <= 0) {
      showError(new Error('Days debe ser mayor que 0.'));
      return;
    }

    const payload = { days };
    const grace = document.getElementById('extendGraceUntil').value;
    const notes = document.getElementById('extendNotes').value.trim();
    if (grace) payload.grace_until = grace;
    if (notes) payload.notes = notes;

    try {
      await AdminCommon.adminFetchJson(`/api/admin/subscriptions/${encodeURIComponent(id)}/extend`, {
        method: 'PATCH',
        body: payload,
        sessionId: state.sessionId
      });
      showSuccess('Suscripcion extendida.');
      closeModal('extendModal');
      document.getElementById('extendForm').reset();
      await loadSubscriptions();
    } catch (error) {
      showError(error);
    }
  }

  async function changeStatus(subscriptionId, mode) {
    const endpoint = mode === 'suspend' ? 'suspend' : 'cancel';
    try {
      await AdminCommon.adminFetchJson(`/api/admin/subscriptions/${encodeURIComponent(subscriptionId)}/${endpoint}`, {
        method: 'PATCH',
        body: {},
        sessionId: state.sessionId
      });
      showSuccess(mode === 'suspend' ? 'Suscripcion suspendida.' : 'Suscripcion cancelada.');
      await loadSubscriptions();
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

(function () {
  const state = {
    sessionId: null,
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
      await Promise.all([loadProducts(), loadProjects()]);
      await loadPlans();
    } catch (error) {
      showError(error);
    }
  }

  function bindUi() {
    document.getElementById('filterBtn').addEventListener('click', loadPlans);
    document.getElementById('newPlanBtn').addEventListener('click', () => openPlanModal());
    document.getElementById('planForm').addEventListener('submit', onSubmitPlan);

    document.addEventListener('click', (event) => {
      const closeId = event.target.getAttribute('data-close-modal');
      if (closeId) closeModal(closeId);
    });
  }

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function fmtMoney(amount, currency) {
    const value = Number(amount || 0);
    const curr = String(currency || 'DOP').toUpperCase();
    return `${curr} ${new Intl.NumberFormat('es-DO', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value)}`;
  }

  function chipForActive(isActive) {
    return `<span class="chip ${isActive ? 'active enabled' : 'disabled'}">${isActive ? 'active' : 'inactive'}</span>`;
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

  async function loadProducts() {
    const { data } = await AdminCommon.adminFetchJson('/api/admin/products?limit=200&offset=0', { sessionId: state.sessionId });
    state.products = Array.isArray(data?.products) ? data.products : [];
    populateOwnershipSelects();
  }

  async function loadProjects() {
    const { data } = await AdminCommon.adminFetchJson('/api/admin/projects?limit=200&page=1', { sessionId: state.sessionId });
    state.projects = Array.isArray(data?.projects) ? data.projects : [];
    populateOwnershipSelects();
  }

  function populateOwnershipSelects() {
    const productOptions = ['<option value="">Todos</option>']
      .concat(state.products.map((item) => `<option value="${esc(item.id)}">${esc(item.name || item.slug || item.id)}</option>`))
      .join('');

    const projectOptions = ['<option value="">Todos</option>']
      .concat(state.projects.map((item) => `<option value="${esc(item.id)}">${esc(item.name || item.code || item.id)}</option>`))
      .join('');

    const filterProduct = document.getElementById('filterProduct');
    const filterProject = document.getElementById('filterProject');
    const formProduct = document.getElementById('planProductId');
    const formProject = document.getElementById('planProjectId');

    const selectedFilterProduct = filterProduct.value;
    const selectedFilterProject = filterProject.value;
    const selectedFormProduct = formProduct.value;
    const selectedFormProject = formProject.value;

    filterProduct.innerHTML = productOptions;
    filterProject.innerHTML = projectOptions;

    formProduct.innerHTML = productOptions.replace('Todos', 'Ninguno');
    formProject.innerHTML = projectOptions.replace('Todos', 'Ninguno');

    filterProduct.value = selectedFilterProduct;
    filterProject.value = selectedFilterProject;
    formProduct.value = selectedFormProduct;
    formProject.value = selectedFormProject;
  }

  function buildPlanQuery() {
    const params = new URLSearchParams();
    const productId = document.getElementById('filterProduct').value.trim();
    const projectId = document.getElementById('filterProject').value.trim();
    const isActive = document.getElementById('filterIsActive').value.trim();

    if (productId) params.set('product_id', productId);
    if (projectId) params.set('project_id', projectId);
    if (isActive) params.set('is_active', isActive);
    params.set('limit', '200');
    params.set('offset', '0');
    return params;
  }

  async function loadPlans() {
    AdminCommon.hideMessage(msgId);
    showLoading(true);

    try {
      const { data } = await AdminCommon.adminFetchJson(`/api/admin/product-plans?${buildPlanQuery().toString()}`, {
        sessionId: state.sessionId
      });
      renderPlans(Array.isArray(data?.plans) ? data.plans : []);
    } catch (error) {
      showError(error);
      renderPlans([]);
    } finally {
      showLoading(false);
    }
  }

  function renderPlans(plans) {
    const wrap = document.getElementById('tableWrap');
    if (!plans.length) {
      wrap.innerHTML = '<div class="empty">No hay planes para los filtros seleccionados.</div>';
      return;
    }

    wrap.innerHTML = `
      <table>
        <thead>
          <tr>
            <th>Plan</th>
            <th>Producto/Proyecto</th>
            <th>Precio</th>
            <th>Periodo</th>
            <th>Device limit</th>
            <th>Grace days</th>
            <th>Estado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          ${plans.map((plan) => {
            const owner = plan.product_name || plan.product_slug
              ? `Producto: ${esc(plan.product_name || plan.product_slug)}`
              : `Proyecto: ${esc(plan.project_name || plan.project_code || '-')}`;
            return `
              <tr>
                <td>
                  <strong>${esc(plan.name)}</strong>
                  <div class="muted mono">${esc(plan.code)}</div>
                </td>
                <td>${owner}</td>
                <td>${fmtMoney(plan.price_amount, plan.currency)}</td>
                <td><span class="chip">${esc(plan.billing_period)}</span></td>
                <td>${esc(plan.device_limit)}</td>
                <td>${esc(plan.default_grace_days)}</td>
                <td>${chipForActive(Boolean(plan.is_active))}</td>
                <td>
                  <div class="row-actions">
                    <button class="btn btn-secondary" type="button" data-edit-plan="${esc(plan.id)}">Editar</button>
                    <button class="btn ${plan.is_active ? 'btn-warning' : 'btn-success'}" type="button" data-toggle-plan="${esc(plan.id)}" data-enable="${plan.is_active ? 'false' : 'true'}">${plan.is_active ? 'Disable' : 'Enable'}</button>
                  </div>
                </td>
              </tr>
            `;
          }).join('')}
        </tbody>
      </table>
    `;

    wrap.querySelectorAll('[data-edit-plan]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const planId = btn.getAttribute('data-edit-plan');
        await openPlanModal(planId);
      });
    });

    wrap.querySelectorAll('[data-toggle-plan]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const planId = btn.getAttribute('data-toggle-plan');
        const enable = btn.getAttribute('data-enable') === 'true';
        await togglePlan(planId, enable);
      });
    });
  }

  async function openPlanModal(planId) {
    AdminCommon.hideMessage(msgId);
    const form = document.getElementById('planForm');
    form.reset();
    document.getElementById('planId').value = '';
    document.getElementById('planCurrency').value = 'DOP';
    document.getElementById('planDeviceLimit').value = '1';
    document.getElementById('planGraceDays').value = '0';
    document.getElementById('planCompanyLimit').value = '1';
    document.getElementById('planModalTitle').textContent = 'Nuevo plan';

    if (planId) {
      const { data } = await AdminCommon.adminFetchJson(`/api/admin/product-plans/${encodeURIComponent(planId)}`, {
        sessionId: state.sessionId
      });
      const plan = data?.plan || {};
      document.getElementById('planModalTitle').textContent = 'Editar plan';
      document.getElementById('planId').value = plan.id || '';
      document.getElementById('planProductId').value = plan.product_id || '';
      document.getElementById('planProjectId').value = plan.project_id || '';
      document.getElementById('planCode').value = plan.code || '';
      document.getElementById('planName').value = plan.name || '';
      document.getElementById('planBilling').value = plan.billing_period || 'monthly';
      document.getElementById('planPrice').value = Number(plan.price_amount || 0);
      document.getElementById('planCurrency').value = plan.currency || 'DOP';
      document.getElementById('planDeviceLimit').value = Number(plan.device_limit || 0);
      document.getElementById('planGraceDays').value = Number(plan.default_grace_days || 0);
      document.getElementById('planTrialDays').value = plan.trial_days == null ? '' : Number(plan.trial_days);
      document.getElementById('planCompanyLimit').value = Number(plan.company_limit || 1);
      document.getElementById('planMetadata').value = JSON.stringify(plan.metadata || {}, null, 2);
    }

    openModal('planModal');
  }

  async function onSubmitPlan(event) {
    event.preventDefault();
    const planId = document.getElementById('planId').value.trim();
    const productId = document.getElementById('planProductId').value.trim();
    const projectId = document.getElementById('planProjectId').value.trim();

    if ((productId ? 1 : 0) === (projectId ? 1 : 0)) {
      showError(new Error('Debes seleccionar exactamente uno entre producto o proyecto.'));
      return;
    }

    const payload = {
      product_id: productId || undefined,
      project_id: projectId || undefined,
      code: document.getElementById('planCode').value.trim(),
      name: document.getElementById('planName').value.trim(),
      billing_period: document.getElementById('planBilling').value,
      price_amount: Number(document.getElementById('planPrice').value),
      currency: document.getElementById('planCurrency').value.trim() || 'DOP',
      device_limit: Number(document.getElementById('planDeviceLimit').value),
      default_grace_days: Number(document.getElementById('planGraceDays').value),
      trial_days: document.getElementById('planTrialDays').value === '' ? null : Number(document.getElementById('planTrialDays').value),
      company_limit: Number(document.getElementById('planCompanyLimit').value)
    };

    const metadataRaw = document.getElementById('planMetadata').value.trim();
    if (metadataRaw) {
      try {
        payload.metadata = JSON.parse(metadataRaw);
      } catch (error) {
        showError(new Error(`Metadata JSON invalido: ${error.message}`));
        return;
      }
    }

    try {
      if (planId) {
        await AdminCommon.adminFetchJson(`/api/admin/product-plans/${encodeURIComponent(planId)}`, {
          method: 'PATCH',
          body: payload,
          sessionId: state.sessionId
        });
        showSuccess('Plan actualizado correctamente.');
      } else {
        await AdminCommon.adminFetchJson('/api/admin/product-plans', {
          method: 'POST',
          body: payload,
          sessionId: state.sessionId
        });
        showSuccess('Plan creado correctamente.');
      }

      closeModal('planModal');
      await loadPlans();
    } catch (error) {
      showError(error);
    }
  }

  async function togglePlan(planId, enable) {
    try {
      await AdminCommon.adminFetchJson(`/api/admin/product-plans/${encodeURIComponent(planId)}/${enable ? 'enable' : 'disable'}`, {
        method: 'PATCH',
        sessionId: state.sessionId
      });
      showSuccess(enable ? 'Plan habilitado.' : 'Plan deshabilitado.');
      await loadPlans();
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

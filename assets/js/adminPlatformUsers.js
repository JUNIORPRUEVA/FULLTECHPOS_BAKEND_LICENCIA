(function () {
  const state = {
    sessionId: null,
    users: [],
    roles: []
  };

  const msgId = 'message';

  window.addEventListener('DOMContentLoaded', init);

  async function init() {
    bindUi();
    state.sessionId = await AdminCommon.ensureAuth({ userNameElId: 'userName' });
    if (!state.sessionId) return;

    await Promise.all([loadRoles(), loadUsers()]);
  }

  function bindUi() {
    document.getElementById('filterBtn').addEventListener('click', loadUsers);
    document.getElementById('newUserBtn').addEventListener('click', () => openModal('userModal'));
    document.getElementById('userForm').addEventListener('submit', onCreateUser);
    document.getElementById('roleForm').addEventListener('submit', onAssignRole);

    document.addEventListener('click', (event) => {
      const closeId = event.target.getAttribute('data-close-modal');
      if (closeId) closeModal(closeId);
    });
  }

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
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

  async function loadRoles() {
    try {
      const { data } = await AdminCommon.adminFetchJson('/api/admin/roles', { sessionId: state.sessionId });
      state.roles = Array.isArray(data?.roles) ? data.roles : [];
      document.getElementById('roleId').innerHTML = ['<option value="">Seleccionar rol</option>']
        .concat(state.roles.map((role) => `<option value="${esc(role.id)}">${esc(role.code)} (${esc(role.scope_type || '-')})</option>`))
        .join('');
    } catch (error) {
      showError(error);
    }
  }

  function buildUserQuery() {
    const params = new URLSearchParams();
    const status = document.getElementById('filterStatus').value;
    const userType = document.getElementById('filterType').value;
    const q = document.getElementById('filterQ').value.trim();

    if (status) params.set('status', status);
    if (userType) params.set('user_type', userType);
    if (q) params.set('q', q);
    params.set('limit', '200');
    params.set('offset', '0');
    return params;
  }

  async function loadUsers() {
    AdminCommon.hideMessage(msgId);
    showLoading(true);

    try {
      const { data } = await AdminCommon.adminFetchJson(`/api/admin/platform-users?${buildUserQuery().toString()}`, {
        sessionId: state.sessionId
      });
      state.users = Array.isArray(data?.users) ? data.users : [];
      renderUsers();
    } catch (error) {
      showError(error);
      state.users = [];
      renderUsers();
    } finally {
      showLoading(false);
    }
  }

  function renderUsers() {
    const wrap = document.getElementById('tableWrap');
    if (!state.users.length) {
      wrap.innerHTML = '<div class="empty">No hay usuarios para mostrar.</div>';
      return;
    }

    wrap.innerHTML = `
      <table>
        <thead>
          <tr>
            <th>Email</th>
            <th>Display name</th>
            <th>User type</th>
            <th>Status</th>
            <th>Creado</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          ${state.users.map((user) => `
            <tr>
              <td>
                <div>${esc(user.email || '-')}</div>
                <div class="muted mono">${esc(user.id || '-')}</div>
              </td>
              <td>${esc(user.display_name || '-')}</td>
              <td>${chip(user.user_type)}</td>
              <td>${chip(user.status)}</td>
              <td>${formatDate(user.created_at)}</td>
              <td>
                <div class="row-actions">
                  <button class="btn btn-secondary" type="button" data-assign-role="${esc(user.id)}" data-user-email="${esc(user.email || user.id)}">Asignar rol</button>
                </div>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;

    wrap.querySelectorAll('[data-assign-role]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const userId = btn.getAttribute('data-assign-role');
        const userEmail = btn.getAttribute('data-user-email');
        document.getElementById('roleUserId').value = userId;
        document.getElementById('roleModalUser').textContent = `Usuario: ${userEmail}`;
        openModal('roleModal');
      });
    });
  }

  async function onCreateUser(event) {
    event.preventDefault();
    const payload = {
      email: document.getElementById('userEmail').value.trim(),
      display_name: document.getElementById('userDisplayName').value.trim() || undefined,
      phone: document.getElementById('userPhone').value.trim() || undefined,
      status: document.getElementById('userStatus').value,
      user_type: document.getElementById('userType').value
    };

    try {
      await AdminCommon.adminFetchJson('/api/admin/platform-users', {
        method: 'POST',
        body: payload,
        sessionId: state.sessionId
      });
      showSuccess('Usuario creado correctamente.');
      closeModal('userModal');
      document.getElementById('userForm').reset();
      document.getElementById('userStatus').value = 'active';
      document.getElementById('userType').value = 'admin';
      await loadUsers();
    } catch (error) {
      showError(error);
    }
  }

  async function onAssignRole(event) {
    event.preventDefault();
    const userId = document.getElementById('roleUserId').value;
    const roleId = document.getElementById('roleId').value;
    const companyId = document.getElementById('roleCompanyId').value.trim();

    if (!userId || !roleId) {
      showError(new Error('Usuario y rol son requeridos.'));
      return;
    }

    try {
      await AdminCommon.adminFetchJson(`/api/admin/platform-users/${encodeURIComponent(userId)}/roles`, {
        method: 'POST',
        body: {
          role_id: roleId,
          company_id: companyId || undefined
        },
        sessionId: state.sessionId
      });
      showSuccess('Rol asignado correctamente.');
      closeModal('roleModal');
      document.getElementById('roleForm').reset();
    } catch (error) {
      showError(error);
    }
  }

  function formatDate(value) {
    if (!value) return '-';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '-';
    return date.toLocaleDateString('es-DO');
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

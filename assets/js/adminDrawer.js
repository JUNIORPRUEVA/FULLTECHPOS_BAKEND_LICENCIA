/* Appyra - Admin mobile drawer (UI only)
   Injects a drawer menu on admin pages that DO NOT already have a sidebar.
*/

(function () {
  const LINKS = [
    { href: '/admin/admin-hub.html', label: 'Panel Principal', icon: '🏠' },
    { href: '/admin/customers.html', label: 'Gestionar Clientes', icon: '👥' },
    { href: '/admin/licenses.html', label: 'Gestionar Licencias', icon: '📜' },
    { href: '/admin/license-config.html', label: 'Tokens Reset', icon: '🔐' },
    { href: '/admin/products.html', label: 'Productos', icon: '🧩' },
    { href: '/admin/store-settings.html', label: 'Store Settings', icon: '🏷️' }
  ];

  function hasSidebarLayout() {
    return Boolean(document.querySelector('.sidebar'));
  }

  function buildDrawer() {
    const overlay = document.createElement('div');
    overlay.className = 'jr-adminDrawerOverlay';
    // On mobile, pointerdown is more reliable than click.
    overlay.addEventListener('pointerdown', close);
    overlay.addEventListener('click', close);

    const drawer = document.createElement('nav');
    drawer.className = 'jr-adminDrawer';
    drawer.setAttribute('aria-label', 'Menú administrativo');

    const header = document.createElement('div');
    header.className = 'jr-adminDrawerHeader';
    header.innerHTML = `
      <img src="../assets/img/logo/logoprincipal.png" alt="Appyra" />
      <div class="jr-adminDrawerTitle">
        <strong>Appyra</strong>
        <span>Administración</span>
      </div>
    `;

    const nav = document.createElement('div');
    nav.className = 'jr-adminDrawerNav';

    const pathname = String(window.location.pathname || '').toLowerCase();

    nav.innerHTML = LINKS.map((l) => {
      const isCurrent = pathname.endsWith(String(l.href).toLowerCase());
      return `
        <a href="${l.href}" ${isCurrent ? 'aria-current="page"' : ''}>
          <span aria-hidden="true">${l.icon}</span>
          <span>${l.label}</span>
        </a>
      `;
    }).join('');

    // Auto-close on navigation click
    nav.addEventListener('click', (e) => {
      const a = e.target && e.target.closest ? e.target.closest('a') : null;
      if (!a) return;
      close();
    });

    const footer = document.createElement('div');
    footer.className = 'jr-adminDrawerFooter';
    footer.innerHTML = `<button type="button" class="jr-adminDrawerClose">Cerrar menú</button>`;
    footer.querySelector('button').addEventListener('click', close);

    drawer.appendChild(header);
    drawer.appendChild(nav);
    drawer.appendChild(footer);

    document.body.appendChild(overlay);
    document.body.appendChild(drawer);
  }

  function open() {
    document.body.classList.add('jr-admin-drawer-open');
  }

  function close() {
    document.body.classList.remove('jr-admin-drawer-open');
  }

  function toggle() {
    document.body.classList.toggle('jr-admin-drawer-open');
  }

  function bindButtons() {
    const buttons = document.querySelectorAll('[data-jr-admin-drawer-open]');
    buttons.forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        toggle();
      });
    });
  }

  function bindKeyboard() {
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') close();
    });
  }

  function bindLifecycleClose() {
    // Ensure drawer never stays stuck open (BFCache/back/forward)
    window.addEventListener('pageshow', close);
    window.addEventListener('pagehide', close);
    window.addEventListener('hashchange', close);
  }

  window.JrAdminDrawer = { open, close, toggle };

  window.addEventListener('DOMContentLoaded', () => {
    // Always start closed.
    close();

    // Don't inject if the page already uses a sidebar/drawer layout.
    if (hasSidebarLayout()) {
      bindButtons();
      bindKeyboard();
      bindLifecycleClose();
      return;
    }

    buildDrawer();
    bindButtons();
    bindKeyboard();
    bindLifecycleClose();
  });
})();

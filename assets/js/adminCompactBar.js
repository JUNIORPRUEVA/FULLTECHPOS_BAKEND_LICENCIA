(function () {
  function closeAll() {
    document.querySelectorAll('.admin-compactBarMenu.is-open').forEach((menu) => {
      menu.classList.remove('is-open');
    });

    document.querySelectorAll('.admin-compactBarBtn.is-active').forEach((button) => {
      button.classList.remove('is-active');
    });
  }

  function toggle(menuId, event) {
    if (event) event.stopPropagation();
    const menu = document.getElementById(menuId);
    if (!menu) return;

    const button = document.querySelector(`[data-admin-compact-toggle="${menuId}"]`);
    const willOpen = !menu.classList.contains('is-open');

    closeAll();

    if (willOpen) {
      menu.classList.add('is-open');
      if (button) button.classList.add('is-active');
    }
  }

  document.addEventListener('click', (event) => {
    if (!event.target.closest('.admin-compactBarActions')) {
      closeAll();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeAll();
  });

  window.AdminCompactBar = {
    toggle,
    closeAll
  };
})();
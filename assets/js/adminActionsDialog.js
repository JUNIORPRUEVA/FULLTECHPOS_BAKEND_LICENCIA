(function () {
  function ensureDialog() {
    let overlay = document.getElementById('jrActionsOverlay');
    if (overlay) return overlay;

    overlay = document.createElement('div');
    overlay.id = 'jrActionsOverlay';
    overlay.className = 'jr-actionsOverlay';
    overlay.innerHTML = `
      <div class="jr-actionsDialog" role="dialog" aria-modal="true" aria-labelledby="jrActionsTitle">
        <div class="jr-actionsHeader">
          <div style="min-width:0;">
            <div class="jr-actionsTitle" id="jrActionsTitle"></div>
            <div class="jr-actionsSubtitle" id="jrActionsSubtitle" style="display:none;"></div>
          </div>
          <button class="jr-actionsClose" type="button" aria-label="Cerrar">✕</button>
        </div>
        <div class="jr-actionsBody">
          <div class="jr-actionsList" id="jrActionsList"></div>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) {
        window.JrAdminActionsDialog?.close();
      }
    });

    overlay.querySelector('.jr-actionsClose')?.addEventListener('click', () => {
      window.JrAdminActionsDialog?.close();
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        window.JrAdminActionsDialog?.close();
      }
    });

    return overlay;
  }

  function setText(el, value) {
    if (!el) return;
    el.textContent = String(value ?? '');
  }

  function open({ title = 'Acciones', subtitle = '', actions = [] } = {}) {
    const overlay = ensureDialog();
    const titleEl = overlay.querySelector('#jrActionsTitle');
    const subtitleEl = overlay.querySelector('#jrActionsSubtitle');
    const listEl = overlay.querySelector('#jrActionsList');

    setText(titleEl, title);

    const subtitleText = String(subtitle ?? '').trim();
    if (subtitleEl) {
      if (subtitleText) {
        subtitleEl.style.display = 'block';
        setText(subtitleEl, subtitleText);
      } else {
        subtitleEl.style.display = 'none';
        setText(subtitleEl, '');
      }
    }

    if (listEl) {
      listEl.innerHTML = '';
      const safeActions = Array.isArray(actions) ? actions : [];
      for (const action of safeActions) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'jr-actionsBtn';

        if (action?.kind === 'token' || action?.className === 'token') btn.classList.add('is-token');
        if (action?.kind === 'danger' || action?.className === 'danger') btn.classList.add('is-danger');

        btn.disabled = Boolean(action?.disabled);
        setText(btn, action?.label || 'Acción');

        btn.addEventListener('click', async () => {
          if (btn.disabled) return;
          window.JrAdminActionsDialog?.close();
          try {
            const fn = action?.onClick;
            if (typeof fn === 'function') {
              await fn();
            }
          } catch (e) {
            // UI-only component: do not swallow app errors silently in console
            console.error('ActionsDialog action failed:', e);
          }
        });

        listEl.appendChild(btn);
      }
    }

    overlay.classList.add('show');
    document.documentElement.style.overflow = 'hidden';

    // focus close button for accessibility
    overlay.querySelector('.jr-actionsClose')?.focus();
  }

  function close() {
    const overlay = document.getElementById('jrActionsOverlay');
    if (!overlay) return;
    overlay.classList.remove('show');
    document.documentElement.style.overflow = '';
  }

  window.JrAdminActionsDialog = {
    open,
    close,
  };
})();

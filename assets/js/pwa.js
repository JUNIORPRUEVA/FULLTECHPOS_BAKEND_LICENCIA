(function () {
  const isAdmin = /^\/admin\//.test(window.location.pathname || '');
  const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  const isIos = () => /iphone|ipad|ipod/i.test(window.navigator.userAgent || '');

  let deferredPrompt = null;
  let installButton = null;
  let installHint = null;

  function injectInstallUi() {
    if (isAdmin || document.getElementById('pwaInstallButton')) return;

    const style = document.createElement('style');
    style.id = 'pwaInstallStyles';
    style.textContent = [
      '.pwa-install-btn{position:fixed;right:16px;bottom:16px;z-index:1600;display:none;align-items:center;gap:8px;padding:10px 14px;border-radius:999px;border:1px solid rgba(255,255,255,.14);background:linear-gradient(135deg,#3B82F6 0%,#06B6D4 48%,#9333EA 100%);color:#fff;font:800 13px/1 Inter,Segoe UI,sans-serif;box-shadow:0 18px 40px rgba(59,130,246,.28);cursor:pointer;transition:transform .22s ease,box-shadow .22s ease,opacity .22s ease;}',
      '.pwa-install-btn:hover{transform:translateY(-2px);box-shadow:0 24px 54px rgba(59,130,246,.34);}',
      '.pwa-install-btn.is-visible{display:inline-flex;}',
      '.pwa-install-hint{position:fixed;right:16px;bottom:72px;z-index:1600;display:none;max-width:280px;padding:14px 16px;border-radius:18px;background:rgba(15,23,42,.92);border:1px solid rgba(148,163,184,.16);box-shadow:0 24px 60px rgba(2,6,23,.28);backdrop-filter:blur(18px);color:#E2E8F0;font:600 13px/1.65 Inter,Segoe UI,sans-serif;}',
      '.pwa-install-hint.is-visible{display:block;}',
      '.pwa-install-hint strong{display:block;margin-bottom:6px;color:#fff;font-size:13px;}',
      '.pwa-install-close{position:absolute;top:8px;right:10px;border:none;background:transparent;color:#94A3B8;font:800 16px/1 Inter,Segoe UI,sans-serif;cursor:pointer;}',
      '.pwa-install-close:hover{color:#fff;}',
      '@media (max-width:768px){.pwa-install-btn{right:12px;left:12px;bottom:12px;justify-content:center;}.pwa-install-hint{right:12px;left:12px;bottom:68px;max-width:none;}}'
    ].join('');
    document.head.appendChild(style);

    installButton = document.createElement('button');
    installButton.id = 'pwaInstallButton';
    installButton.className = 'pwa-install-btn';
    installButton.type = 'button';
    installButton.innerHTML = '<span aria-hidden="true">⬇</span><span>Descargar app</span>';
    installButton.addEventListener('click', onInstallClick);

    installHint = document.createElement('div');
    installHint.id = 'pwaInstallHint';
    installHint.className = 'pwa-install-hint';
    installHint.innerHTML = '<button type="button" class="pwa-install-close" aria-label="Cerrar">×</button><strong>Instala Appyra</strong><span>En iPhone o iPad usa Compartir y luego Agregar a pantalla de inicio.</span>';
    installHint.querySelector('.pwa-install-close').addEventListener('click', () => {
      installHint.classList.remove('is-visible');
      try { localStorage.setItem('appyra-pwa-ios-hint-dismissed', '1'); } catch (_) {}
    });

    document.body.appendChild(installButton);
    document.body.appendChild(installHint);
  }

  function showInstallButton() {
    if (!installButton || isStandalone()) return;
    installButton.classList.add('is-visible');
  }

  function hideInstallButton() {
    if (!installButton) return;
    installButton.classList.remove('is-visible');
  }

  async function onInstallClick() {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      try {
        await deferredPrompt.userChoice;
      } catch (_) {
        // Ignore prompt resolution errors.
      }
      deferredPrompt = null;
      hideInstallButton();
      return;
    }

    if (isIos() && !isStandalone() && installHint) {
      installHint.classList.add('is-visible');
    }
  }

  function maybeShowIosHint() {
    if (isAdmin || !isIos() || isStandalone() || deferredPrompt || !installHint) return;
    try {
      if (localStorage.getItem('appyra-pwa-ios-hint-dismissed') === '1') return;
    } catch (_) {
      // Ignore storage read errors.
    }
    showInstallButton();
  }

  function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) return;
    window.addEventListener('load', function () {
      navigator.serviceWorker
        .register('/sw.js', { scope: '/', updateViaCache: 'none' })
        .then(function (registration) {
          registration.update().catch(() => undefined);

          document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible') {
              registration.update().catch(() => undefined);
            }
          });

          window.addEventListener('focus', function () {
            registration.update().catch(() => undefined);
          });
        })
        .catch(function () {
          // Silent: PWA is optional.
        });
    });
  }

  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    deferredPrompt = event;
    showInstallButton();
  });

  window.addEventListener('appinstalled', function () {
    deferredPrompt = null;
    hideInstallButton();
    if (installHint) installHint.classList.remove('is-visible');
  });

  window.addEventListener('load', function () {
    injectInstallUi();
    maybeShowIosHint();
  });

  registerServiceWorker();
})();

(function () {
  if (!('serviceWorker' in navigator)) return;

  window.addEventListener('load', function () {
    navigator.serviceWorker
      .register('/sw.js')
      .catch(function () {
        // Silent: PWA is optional.
      });
  });
})();

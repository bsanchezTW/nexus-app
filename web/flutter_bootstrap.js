{{flutter_js}}
{{flutter_build_config}}

// Flutter's service worker (and the auto-unregister stub that calls
// client.navigate) can interrupt mid-load and leave the navy boot screen
// stuck. Clear any old SW/caches, then boot without registering a new one.
(async function bootstrap() {
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map((r) => r.unregister()));
    }
  } catch (e) {
    console.warn('Failed to unregister service workers:', e);
  }

  try {
    if (window.caches) {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    }
  } catch (e) {
    console.warn('Failed to clear caches:', e);
  }

  _flutter.loader.load({
    onEntrypointLoaded: async function (engineInitializer) {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
        const splash = document.getElementById('app-boot-splash');
        if (splash) splash.remove();
      } catch (e) {
        console.error('Flutter bootstrap failed:', e);
        const splash = document.getElementById('app-boot-splash');
        if (splash) {
          splash.classList.add('slow');
          const hint = splash.querySelector('.hint');
          if (hint) {
            hint.textContent =
              'Error al iniciar. Recarga la pagina o limpia la cache del sitio.';
          }
        }
      }
    },
  });
})();

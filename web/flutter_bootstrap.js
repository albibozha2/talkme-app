{{flutter_js}}
{{flutter_build_config}}

// Older builds installed a service worker that could keep serving an old version: remove it.
// (The notifications worker, firebase-messaging-sw.js, has its own scope and stays.)
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function (regs) {
    regs.forEach(function (r) {
      if (/\/app\/$/.test(r.scope)) r.unregister();
    });
  }).catch(function () {});
}

// Same as Flutter's default start-up, plus removing the loading screen once the app is ready.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const loading = document.getElementById('loading');
    if (loading) loading.remove();
  },
});

(function(window, document) {
  'use strict';

  window.addEventListener('load', function() {
    let loaded = false;
    const events = ['click', 'scroll', 'touchstart', 'keydown', 'mousemove'];
    const timer = window.setTimeout(loadOnce, 3000);

    function loadOnce() {
      if (loaded) return;
      loaded = true;
      window.clearTimeout(timer);
      events.forEach(function(event) { window.removeEventListener(event, loadOnce); });

      window.fbAsyncInit = function() {
        window.FB.init({
          appId: document.body.dataset.facebookAppId,
          autoLogAppEvents: true,
          xfbml: true,
          version: 'v26.0'
        });
      };
      window.AdSense.load();
    }

    events.forEach(function(event) {
      window.addEventListener(event, loadOnce, { once: true, passive: true });
    });
  });
})(window, document);

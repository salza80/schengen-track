(function(window, document) {
  'use strict';

  let loading = false;

  function initializeSlots() {
    const pending = new Set(document.querySelectorAll('ins.adsense-slot'));
    let observer;

    function requestVisibleAds() {
      pending.forEach(function(slot) {
        if (slot.getBoundingClientRect().width <= 0 || window.getComputedStyle(slot).visibility !== 'visible') return;

        pending.delete(slot);
        if (observer) observer.unobserve(slot);
        // Only eligible slots carry Google's class, so a request cannot pick
        // an earlier hidden slot elsewhere in the document.
        slot.classList.add('adsbygoogle');
        (window.adsbygoogle = window.adsbygoogle || []).push({});
      });

      if (pending.size === 0) {
        if (observer) observer.disconnect();
        window.removeEventListener('resize', requestVisibleAds);
      }
    }

    if (typeof window.ResizeObserver !== 'undefined') {
      observer = new window.ResizeObserver(requestVisibleAds);
      pending.forEach(function(slot) { observer.observe(slot); });
    }
    // Also handles visibility changes at breakpoints and older browsers.
    window.addEventListener('resize', requestVisibleAds);
    requestVisibleAds();
  }

  window.AdSense = {
    load: function() {
      if (loading) return;
      loading = true;

      const script = document.createElement('script');
      script.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-8290979932488448';
      script.async = true;
      script.crossOrigin = 'anonymous';
      script.onload = initializeSlots;
      document.body.appendChild(script);
    }
  };
})(window, document);

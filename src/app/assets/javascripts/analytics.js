// The live Google loader has no immutable release/hash contract. Keep this
// dependency explicit; CSP does not provide integrity protection for its bytes.
(function(window, document) {
  'use strict';
  window.dataLayer = window.dataLayer || [];
  window.gtag = function() { window.dataLayer.push(arguments); };
  window.gtag('js', new Date());
  window.gtag('config', 'G-E9CCZDHLJF');
  var script = document.createElement('script');
  script.async = true;
  script.src = 'https://www.googletagmanager.com/gtag/js?id=G-E9CCZDHLJF';
  document.head.appendChild(script);
})(window, document);

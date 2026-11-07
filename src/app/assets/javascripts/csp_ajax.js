// jquery_ujs executes same-origin Rails script responses in the private
// document's nonce context. Public cached documents deliberately have no nonce.
(function(window, document, $) {
  'use strict';
  $.ajaxPrefilter(function(options) {
    if (options.crossDomain) return;
    options.converters = options.converters || {};
    options.converters['text script'] = function(text) {
      var meta = document.querySelector('meta[name="csp-nonce"]');
      if (!meta || !meta.content) throw new Error('Script responses require a private document');
      $.globalEval(text, { nonce: meta.content });
      return text;
    };
  });
})(window, document, window.jQuery);

// Shared detection and browser-local date helpers for cached public pages.
(function(window, document) {
  'use strict';

  function isCalculatorPage() {
    if (!document.body) return false;

    var datasetValue = document.body.dataset && document.body.dataset.publicCalculatorPage;
    var attributeValue = document.body.getAttribute &&
      document.body.getAttribute('data-public-calculator-page');
    return datasetValue === 'true' || attributeValue === 'true';
  }

  function hasCookie(name, value) {
    var expected = name + '=' + value;
    return document.cookie.split(';').some(function(cookie) {
      return cookie.trim() === expected;
    });
  }

  function localDateKey(date) {
    return [
      date.getFullYear(),
      String(date.getMonth() + 1).padStart(2, '0'),
      String(date.getDate()).padStart(2, '0')
    ].join('-');
  }

  window.PublicPageHydration = {
    isCalculatorPage: isCalculatorPage,
    hasCookie: hasCookie,
    localDateKey: localDateKey
  };
})(window, document);

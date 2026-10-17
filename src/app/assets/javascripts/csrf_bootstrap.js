// Adds a fresh per-session CSRF token immediately before a cached public form
// performs its first state-changing request.
(function(window, document) {
  'use strict';

  var tokenRequests = {};

  function installMeta(name, content) {
    var meta = document.querySelector('meta[name="' + name + '"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = name;
      document.head.appendChild(meta);
    }
    meta.content = content;
  }

  function installToken(data, form) {
    var param = data.param || 'authenticity_token';
    var token = data.token || data.csrf_token;
    if (!token) return false;

    installMeta('csrf-param', param);
    installMeta('csrf-token', token);

    if (form) {
      var input = form.querySelector('input[name="' + param + '"]');
      if (!input) {
        input = document.createElement('input');
        input.type = 'hidden';
        input.name = param;
        form.appendChild(input);
      }
      input.value = token;
      form.dataset.csrfReady = 'true';
    }

    return true;
  }

  function tokenFor(form) {
    var url = form.dataset.csrfBootstrapUrl;
    if (!url) return Promise.reject(new Error('Missing CSRF bootstrap URL'));

    if (!tokenRequests[url]) {
      tokenRequests[url] = fetch(url, {
        method: 'GET',
        credentials: 'same-origin',
        cache: 'no-store',
        headers: { 'Accept': 'application/json' }
      }).then(function(response) {
        if (!response.ok) throw new Error('CSRF bootstrap failed');
        return response.json();
      }).catch(function(error) {
        delete tokenRequests[url];
        throw error;
      });
    }

    return tokenRequests[url];
  }

  function resumeSubmission(form) {
    if (typeof form.requestSubmit === 'function') form.requestSubmit();
    else HTMLFormElement.prototype.submit.call(form);
  }

  document.addEventListener('submit', function(event) {
    var form = event.target;
    if (!form.dataset || !form.dataset.csrfBootstrapUrl || form.dataset.csrfReady === 'true') return;

    event.preventDefault();
    event.stopImmediatePropagation();
    if (form.dataset.csrfBootstrapping === 'true') return;
    form.dataset.csrfBootstrapping = 'true';

    tokenFor(form).then(function(data) {
      if (!installToken(data, form)) throw new Error('CSRF bootstrap returned no token');
      delete form.dataset.csrfBootstrapping;
      resumeSubmission(form);
    }).catch(function(error) {
      delete form.dataset.csrfBootstrapping;
      if (window.console) console.error(error);
      document.querySelectorAll('#saveVisitButton, #saveVisaButton').forEach(function(button) {
        button.disabled = false;
      });
      window.alert('Unable to start a secure session. Please try again.');
    });
  }, true);

  window.addEventListener('pageshow', function(event) {
    if (!event.persisted || !window.PublicPageHydration.isCalculatorPage()) return;
    var hasCalculatorSession = window.PublicPageHydration.hasCookie('has_calculator_session', '1');
    if (hasCalculatorSession) window.location.reload();
  });

  window.CsrfBootstrap = { installToken: installToken };
})(window, document);

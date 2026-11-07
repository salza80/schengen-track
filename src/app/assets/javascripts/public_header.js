(function () {
  function renderMessages(container, messages) {
    if (!container || !Array.isArray(messages)) return;

    var fragment = document.createDocumentFragment();
    messages.forEach(function (message) {
      if (!message || typeof message.text !== 'string' ||
          (message.type !== 'notice' && message.type !== 'alert')) return;

      var notice = document.createElement('div');
      notice.className = 'alert alert-' + (message.type === 'notice' ? 'success' : 'warning') +
        ' alert-dismissible fade show';
      notice.id = message.type === 'notice' ? 'success' : 'notice';
      notice.setAttribute('role', 'alert');
      notice.textContent = message.text;

      var close = document.createElement('button');
      close.className = 'btn-close';
      close.type = 'button';
      close.setAttribute('data-bs-dismiss', 'alert');
      close.setAttribute('aria-label', 'Close');
      notice.appendChild(close);
      fragment.appendChild(notice);
    });
    container.replaceChildren(fragment);
  }

  function menuUrlAllowed(value, prefix, paths) {
    try {
      var url = new URL(value, window.location.href);
      return url.origin === window.location.origin && !url.username && !url.password && !url.search && !url.hash &&
        url.pathname.indexOf(prefix + '/') === 0 && paths.test(url.pathname.slice(prefix.length));
    } catch (error) {
      return false;
    }
  }

  function sanitizedMenu(html, headerUrl) {
    if (!window.DOMPurify || !window.DOMPurify.isSupported) return null;

    var fragment = window.DOMPurify.sanitize(html, {
      ALLOWED_TAGS: ['li', 'a', 'span', 'small', 'div', 'i', 'form', 'input', 'button'],
      ALLOWED_ATTR: ['id', 'class', 'dir', 'href', 'action', 'method', 'type', 'name', 'value',
        'aria-label', 'aria-labelledby', 'aria-haspopup', 'aria-expanded', 'aria-hidden',
        'data-bs-toggle', 'data-turbo'],
      ALLOW_DATA_ATTR: false,
      ALLOW_ARIA_ATTR: false,
      RETURN_DOM_FRAGMENT: true
    });

    // Keep only the routes and identifiers used by this menu. Process the
    // sanitized nodes directly so the fragment is never reparsed as HTML.
    var prefix = new URL(headerUrl, window.location.href).pathname.replace(/\/session_header$/, '');
    fragment.querySelectorAll('a').forEach(function (link) {
      var href = link.getAttribute('href');
      if (href === '#' && link.id === 'personDropdown') return;
      if (!menuUrlAllowed(href, prefix, /^\/(?:people(?:\/(?:new|\d+\/edit))?|my_details|users\/(?:sign_in|sign_up))$/)) {
        link.removeAttribute('href');
      }
    });
    fragment.querySelectorAll('form').forEach(function (form) {
      if (form.getAttribute('method') !== 'post' ||
          !menuUrlAllowed(form.getAttribute('action'), prefix, /^\/(?:people\/\d+\/set_current|users\/sign_out)$/)) {
        form.remove();
      }
    });
    fragment.querySelectorAll('[id]').forEach(function (element) {
      if (element.id !== 'personDropdown' && element.id !== 'logout-form') element.removeAttribute('id');
    });
    fragment.querySelectorAll('[name], input').forEach(function (element) {
      if (element.tagName !== 'INPUT' || element.getAttribute('type') !== 'hidden' ||
          (element.name !== 'authenticity_token' && element.name !== '_method')) element.remove();
    });
    return fragment;
  }

  function hydratePublicHeader() {
    var container = document.getElementById('public-user-menu');
    if (!container) return;

    var hasSession = window.PublicPageHydration.hasCookie('has_calculator_session', '1');
    var hasFlash = window.PublicPageHydration.hasCookie('has_flash_message', '1');
    if (!hasSession && !hasFlash) return;

    var headerUrl = new URL(container.dataset.sessionHeaderUrl, window.location.href);
    var calculatorPage = window.PublicPageHydration.isCalculatorPage() &&
      window.location.pathname.match(/\/(visits|days)$/);
    if (calculatorPage) headerUrl.searchParams.set('calculator_page', calculatorPage[1]);
    fetch(headerUrl.pathname + headerUrl.search, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (response) {
        if (response.status === 204) return null;
        if (!response.ok) return null;
        return response.json();
      })
      .then(function (data) {
        if (!data) return;
        if (calculatorPage && window.PublicPageHydration.isCalculatorPage() && typeof data.calculator_path === 'string') {
          var prefix = headerUrl.pathname.replace(/\/session_header$/, '');
          if (menuUrlAllowed(data.calculator_path, prefix, /^\/my\/(?:visits|days)$/)) {
            var destination = new URL(data.calculator_path, window.location.href);
            var presentation = new URLSearchParams(window.location.search);
            ['year', 'month', 'day', 'open'].forEach(function (name) {
              if (presentation.has(name)) destination.searchParams.set(name, presentation.get(name));
            });
            destination.hash = window.location.hash;
            window.location.replace(destination.toString());
            return;
          }
        }
        renderMessages(document.getElementById('public-notices'), data.messages);
        if (typeof data.html === 'string' && data.html) {
          var menu = sanitizedMenu(data.html, container.dataset.sessionHeaderUrl);
          if (menu) container.replaceChildren(menu);
        }
        if (data.csrf_token && window.CsrfBootstrap) {
          window.CsrfBootstrap.installToken({
            param: 'authenticity_token',
            token: data.csrf_token
          });
        }
      })
      .catch(function () { /* Keep the public navigation usable on failure. */ });
  }
  window.PublicHeader = { refresh: hydratePublicHeader };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', hydratePublicHeader);
  else hydratePublicHeader();
})();

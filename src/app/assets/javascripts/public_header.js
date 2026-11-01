(function () {
  function hydratePublicHeader() {
    var container = document.getElementById('public-user-menu');
    if (!container) return;

    var hasSession = window.PublicPageHydration.hasCookie('has_calculator_session', '1');
    var hasFlash = window.PublicPageHydration.hasCookie('has_flash_message', '1');
    if (!hasSession && !hasFlash) return;

    fetch(container.dataset.sessionHeaderUrl, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (response) {
        if (response.status === 204) return null;
        if (!response.ok) return null;
        return response.json();
      })
      .then(function (data) {
        if (!data) return;
        var notices = document.getElementById('public-notices');
        if (notices && data.notice_html) notices.innerHTML = data.notice_html;
        if (data.html) container.innerHTML = data.html;
        if (data.csrf_token && window.CsrfBootstrap) {
          window.CsrfBootstrap.installToken({
            param: 'authenticity_token',
            token: data.csrf_token
          });
        }
      })
      .catch(function () { /* Keep the public navigation usable on failure. */ });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', hydratePublicHeader);
  else hydratePublicHeader();
})();

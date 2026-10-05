(function () {
  function loadHeader() {
    var container = document.getElementById('public-user-menu');
    if (!container) return;

    var hasSession = document.cookie.split(';').some(function (cookie) {
      return cookie.trim() === 'has_calculator_session=1';
    });
    var hasFlash = document.cookie.split(';').some(function (cookie) {
      return cookie.trim() === 'has_flash_message=1';
    });
    // Probe once per tab for sessions created before the hint cookie existed.
    // A visitor without a session receives 204 and never creates a guest.
    try {
      if (!hasSession && !hasFlash && sessionStorage.getItem('session-header-probed')) return;
    } catch (_) {}

    fetch(container.dataset.sessionHeaderUrl, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (response) {
        if (response.status === 204) {
          try { sessionStorage.setItem('session-header-probed', '1'); } catch (_) {}
          return null;
        }
        if (!response.ok) return null;
        return response.json();
      })
      .then(function (data) {
        if (!data) return;
        var notices = document.getElementById('public-notices');
        if (notices && data.notice_html) notices.innerHTML = data.notice_html;
        if (data.html) container.innerHTML = data.html;
        if (!data.csrf_token) return;
        [['csrf-param', 'authenticity_token'], ['csrf-token', data.csrf_token]].forEach(function (entry) {
          var meta = document.querySelector('meta[name="' + entry[0] + '"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = entry[0];
            document.head.appendChild(meta);
          }
          meta.content = entry[1];
        });
      })
      .catch(function () { /* Keep the public navigation usable on failure. */ });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', loadHeader);
  else loadHeader();
})();

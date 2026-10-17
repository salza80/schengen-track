// Hydrate date-dependent controls omitted from cached public calculator HTML.
document.addEventListener('DOMContentLoaded', function() {
  if (!window.PublicPageHydration.isCalculatorPage()) return;

  function hydratePublicCalculatorDateControls() {
    var today = new Date();
    var pageLocale = document.documentElement.getAttribute('lang') || undefined;
    var formatter = new Intl.DateTimeFormat(pageLocale, {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });

    document.querySelectorAll('.calendar-current-date').forEach(function(label) {
      label.textContent = formatter.format(today);
      var container = label.closest('.calendar-current-date-container');
      if (container) container.classList.remove('d-none');
    });

    document.querySelectorAll('.calendar-jump-today').forEach(function(link) {
      var jumpUrl = new URL(link.href, window.location.origin);
      jumpUrl.searchParams.set('year', String(today.getFullYear()));
      jumpUrl.searchParams.set('month', String(today.getMonth() + 1));
      jumpUrl.searchParams.set('day', String(today.getDate()));
      link.href = jumpUrl.pathname + jumpUrl.search;
    });
  }

  hydratePublicCalculatorDateControls();
});

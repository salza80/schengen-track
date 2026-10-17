// Keep the footer year accurate on long-lived cached pages.
document.addEventListener('DOMContentLoaded', function() {
  var currentYear = String(new Date().getFullYear());
  document.querySelectorAll('.current-year').forEach(function(label) {
    label.textContent = currentYear;
  });
});

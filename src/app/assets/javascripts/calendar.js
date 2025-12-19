// Calendar enhancements

document.addEventListener('DOMContentLoaded', function() {
  // Initialize Bootstrap tooltips on day cells
  var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-toggle="tooltip"]'));
  tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl, {
      html: true,
      boundary: 'window'
    });
  });
  
  // Smooth scroll to top on page load (after year change)
  if (document.querySelector('.calendar-container')) {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }
  
  // Keyboard navigation for year controls
  document.addEventListener('keydown', function(e) {
    // Only activate if we're on calendar view
    if (!document.querySelector('.calendar-container')) return;
    
    // Prevent default if input/textarea focused
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    
    if (e.key === 'ArrowLeft') {
      var prevButton = document.querySelector('.btn-prev-year');
      if (prevButton && !prevButton.disabled) {
        prevButton.click();
      }
    } else if (e.key === 'ArrowRight') {
      var nextButton = document.querySelector('.btn-next-year');
      if (nextButton && !nextButton.disabled) {
        nextButton.click();
      }
    }
  });
  
  // Highlight current day
  var today = new Date().toISOString().split('T')[0];
  var currentDayCell = document.querySelector('[data-date="' + today + '"]');
  
  if (currentDayCell) {
    currentDayCell.classList.add('current-day');
    
    // Optional: Scroll to current day after a brief delay
    setTimeout(function() {
      var yOffset = -150; // Offset for sticky header
      var y = currentDayCell.getBoundingClientRect().top + window.pageYOffset + yOffset;
      
      // Only scroll if current day is not visible
      var rect = currentDayCell.getBoundingClientRect();
      if (rect.top < 0 || rect.bottom > window.innerHeight) {
        window.scrollTo({ top: y, behavior: 'smooth' });
      }
    }, 500);
  }
});

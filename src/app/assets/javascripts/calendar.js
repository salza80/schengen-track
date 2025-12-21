// Calendar enhancements

document.addEventListener('DOMContentLoaded', function() {
  // Scroll to specific month if parameter is present (do this FIRST, before tooltips)
  var scrollTarget = document.querySelector('#calendar-scroll-target');
  
  if (scrollTarget) {
    var targetMonth = scrollTarget.getAttribute('data-month');
    
    if (targetMonth) {
      // Try to find month element
      var monthElement = document.querySelector('.calendar-month[data-month="' + targetMonth + '"]');
      
      if (monthElement) {
        // Wait for page to fully render
        setTimeout(function() {
          // Offset for sticky header (year nav is ~80-100px)
          var offset = 100;
          var elementPosition = monthElement.getBoundingClientRect().top + window.pageYOffset;
          var offsetPosition = elementPosition - offset;
                    
          window.scrollTo({
            top: offsetPosition,
            behavior: 'smooth'
          });
        }, 500); // Increased delay to 500ms
      } else {
        console.warn('Month element not found for month:', targetMonth);
      }
    }
  } else {
    console.log('No scroll target found - will use default behavior');
  }
  
  // Initialize Bootstrap tooltips on day cells (only if Bootstrap is available)
  if (typeof bootstrap !== 'undefined' && bootstrap.Tooltip) {
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
      try {
        return new bootstrap.Tooltip(tooltipTriggerEl, {
          html: true,
          boundary: 'window'
        });
      } catch(e) {
        console.warn('Tooltip initialization failed:', e);
        return null;
      }
    });
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
    
    // Only scroll to current day if we're NOT scrolling to a specific month
    if (!scrollTarget) {
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
  }
});

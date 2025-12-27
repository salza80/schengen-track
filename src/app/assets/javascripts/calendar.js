// Calendar enhancements

document.addEventListener('DOMContentLoaded', function() {
  // Check for newly created or updated visits (handle FIRST)
  var newVisitDate = sessionStorage.getItem('newVisitDate');
  var updatedVisitDate = sessionStorage.getItem('updatedVisitDate');
  var savedScrollPosition = sessionStorage.getItem('scrollPosition');
  
  // Handle newly created visit highlight
  if (newVisitDate) {
    setTimeout(function() {
      var visitCell = document.querySelector('[data-date="' + newVisitDate + '"]');
      if (visitCell) {
        visitCell.classList.add('newly-created-visit');
        // Remove highlight after 3 seconds
        setTimeout(function() {
          visitCell.classList.remove('newly-created-visit');
        }, 3000);
      }
    }, 600);
    sessionStorage.removeItem('newVisitDate');
  }
  
  // Handle updated visit highlight
  if (updatedVisitDate) {
    setTimeout(function() {
      var visitCell = document.querySelector('[data-date="' + updatedVisitDate + '"]');
      if (visitCell) {
        visitCell.classList.add('newly-updated-visit');
        // Remove highlight after 3 seconds
        setTimeout(function() {
          visitCell.classList.remove('newly-updated-visit');
        }, 3000);
      }
    }, 600);
    sessionStorage.removeItem('updatedVisitDate');
  }
  
  // Restore scroll position for edits (only if not creating new visit)
  if (savedScrollPosition && !newVisitDate) {
    setTimeout(function() {
      window.scrollTo({
        top: parseInt(savedScrollPosition),
        behavior: 'smooth'
      });
    }, 100);
    sessionStorage.removeItem('scrollPosition');
  }
  
  // Scroll to specific month if parameter is present (do this FIRST, before tooltips)
  var scrollTarget = document.querySelector('#calendar-scroll-target');
  
  if (scrollTarget) {
    var targetMonth = scrollTarget.getAttribute('data-month');
    var targetDay = scrollTarget.getAttribute('data-day');
    
    if (targetMonth) {
      // If specific day is provided, scroll to and highlight it
      if (targetDay) {
        var year = new URL(window.location.href).searchParams.get('year') || new Date().getFullYear();
        var month = targetMonth.padStart(2, '0');
        var day = targetDay.padStart(2, '0');
        var targetDate = year + '-' + month + '-' + day;
        var targetDayCell = document.querySelector('[data-date="' + targetDate + '"]');
        
        if (targetDayCell) {
          setTimeout(function() {
            // Scroll to the day cell
            var offset = 150;
            var elementPosition = targetDayCell.getBoundingClientRect().top + window.pageYOffset;
            var offsetPosition = elementPosition - offset;
            
            window.scrollTo({
              top: offsetPosition,
              behavior: 'smooth'
            });
            
            // Add flashing animation
            targetDayCell.classList.add('highlight-day');
            setTimeout(function() {
              targetDayCell.classList.remove('highlight-day');
            }, 3000);
          }, 500);
        }
      } else {
        // Just scroll to month
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
      // Use requestAnimationFrame to batch layout reads and avoid forced reflow
      requestAnimationFrame(function() {
        setTimeout(function() {
          // Batch all layout reads together
          var rect = currentDayCell.getBoundingClientRect();
          var yOffset = -150; // Offset for sticky header
          var y = rect.top + window.pageYOffset + yOffset;
          
          // Only scroll if current day is not visible
          if (rect.top < 0 || rect.bottom > window.innerHeight) {
            window.scrollTo({ top: y, behavior: 'smooth' });
          }
        }, 500);
      });
    }
  }
});

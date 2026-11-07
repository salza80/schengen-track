// Tooltips remain a hover convenience; touch and keyboard users get details in the dialog.
window.CalendarPresentation = {
  activeDate: null,

  setActiveDay: function(cell) {
    document.querySelectorAll('.day-cell[tabindex="0"]').forEach(function(previous) {
      if (previous !== cell) previous.tabIndex = -1;
    });
    cell.tabIndex = 0;
    this.activeDate = cell.dataset.date;
  },

  initializeDayNavigation: function() {
    var cells = Array.from(document.querySelectorAll('.day-cell[data-date]'));
    if (!cells.length) return;
    var viewer = new URLSearchParams(window.location.search);
    var root = document.querySelector('.calendar-view-container');
    var target = root.dataset.selectedYear + '-' + (viewer.get('month') || '').padStart(2, '0') + '-' + (viewer.get('day') || '').padStart(2, '0');
    var active = cells.find(function(cell) { return cell.dataset.date === window.CalendarPresentation.activeDate; }) ||
      cells.find(function(cell) { return cell.dataset.date === target; }) ||
      cells.find(function(cell) { return cell.classList.contains('current-day'); }) || cells[0];
    this.setActiveDay(active);
  },

  moveDay: function(cell, event) {
    var offsets = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };
    if (!Object.prototype.hasOwnProperty.call(offsets, event.key) && event.key !== 'Home' && event.key !== 'End') return false;
    event.preventDefault();
    event.stopPropagation();
    var cells = Array.from(document.querySelectorAll('.day-cell[data-date]'));
    var index = cells.indexOf(cell);
    var dayOfWeek = new Date(cell.dataset.date + 'T00:00:00Z').getUTCDay();
    var offset = event.key === 'Home' ? -dayOfWeek : event.key === 'End' ? 6 - dayOfWeek : offsets[event.key];
    var target = cells[Math.max(0, Math.min(cells.length - 1, index + offset))];
    this.setActiveDay(target);
    target.focus({ preventScroll: true });
    target.scrollIntoView({ block: 'nearest', behavior: 'instant' });
    return true;
  },

  initializeTooltips: function() {
    if (typeof bootstrap === 'undefined' || !bootstrap.Tooltip) return;
    if (window.matchMedia && !window.matchMedia('(hover: hover) and (pointer: fine)').matches) return;
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function(element) {
      bootstrap.Tooltip.getOrCreateInstance(element, { html: true, boundary: document.body, trigger: 'hover' });
    });
  }
};

// Calendar enhancements

document.addEventListener('DOMContentLoaded', function() {
  var initialScrollCancelled = false;
  document.addEventListener('pointerdown', function() { initialScrollCancelled = true; }, { once: true });
  document.addEventListener('touchstart', function() { initialScrollCancelled = true; }, { once: true, passive: true });
  document.addEventListener('wheel', function() { initialScrollCancelled = true; }, { once: true, passive: true });
  document.addEventListener('show.bs.modal', function() { initialScrollCancelled = true; });

  // Scroll to specific month if parameter is present (do this FIRST, before tooltips)
  var scrollTarget = document.querySelector('#calendar-scroll-target');
  var calendarRoot = document.querySelector('.calendar-view-container');
  var viewerParams = new URL(window.location.href).searchParams;
  var isPublicCalculator = window.PublicPageHydration.isCalculatorPage();

  function normalizeCalendarPart(value, minimum, maximum) {
    if (!/^\d{1,2}$/.test(value || '')) return null;

    var number = parseInt(value, 10);
    return number >= minimum && number <= maximum ? String(number) : null;
  }

  var viewerMonth = normalizeCalendarPart(viewerParams.get('month'), 1, 12);
  var browserToday = new Date();
  var selectedYear = calendarRoot && calendarRoot.getAttribute('data-selected-year');
  function publicCurrentMonth() {
    if (!isPublicCalculator || selectedYear !== String(browserToday.getFullYear())) return null;
    return String(browserToday.getMonth() + 1);
  }

  var currentMonth = publicCurrentMonth();
  var targetMonth = viewerMonth || currentMonth || normalizeCalendarPart(
    scrollTarget && scrollTarget.getAttribute('data-month'),
    1,
    12
  );
  var targetDay = viewerMonth
    ? normalizeCalendarPart(viewerParams.get('day'), 1, 31)
    : normalizeCalendarPart(scrollTarget && scrollTarget.getAttribute('data-day'), 1, 31);
  
  if (targetMonth) {
      // If specific day is provided, scroll to and highlight it
      if (targetDay) {
        var year = (calendarRoot && calendarRoot.getAttribute('data-selected-year')) || new Date().getFullYear();
        var month = targetMonth.padStart(2, '0');
        var day = targetDay.padStart(2, '0');
        var targetDate = year + '-' + month + '-' + day;
        var targetDayCell = document.querySelector('[data-date="' + targetDate + '"]');
        
        if (targetDayCell) {
          setTimeout(function() {
            if (initialScrollCancelled) return;
            // Scroll to the day cell
            var offset = 150;
            var elementPosition = targetDayCell.getBoundingClientRect().top + window.pageYOffset;
            var offsetPosition = elementPosition - offset;
            
            window.scrollTo({
              top: offsetPosition,
              behavior: 'instant'
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
            if (initialScrollCancelled) return;
            // Offset for sticky header (year nav is ~80-100px)
            var offset = 100;
            var elementPosition = monthElement.getBoundingClientRect().top + window.pageYOffset;
            var offsetPosition = elementPosition - offset;
                      
            window.scrollTo({
              top: offsetPosition,
              behavior: 'instant'
            });
          }, 500); // Increased delay to 500ms
        }
      }
  }
  
  window.CalendarPresentation.initializeTooltips();

  // Keyboard navigation for year controls
  document.addEventListener('keydown', function(e) {
    // Only activate if we're on calendar view
    if (!document.querySelector('.calendar-container')) return;
    
    // Date selects and other dialog controls own their arrow keys.
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || (e.target.closest && e.target.closest('.modal, .day-cell'))) return;
    
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
  
  function hydratePublicCurrentDay() {
    // Cached HTML must not retain the day that was current at render time.
    document.querySelectorAll('.day-cell.current-day').forEach(function(cell) {
      cell.classList.remove('current-day');
    });
    return window.PublicPageHydration.localDateKey(browserToday);
  }

  function currentDayKey() {
    return isPublicCalculator
      ? hydratePublicCurrentDay()
      : browserToday.toISOString().split('T')[0];
  }

  // Highlight current day
  var currentDayCell = document.querySelector('[data-date="' + currentDayKey() + '"]');
  
  if (currentDayCell) {
    currentDayCell.classList.add('current-day');
    
    // Only scroll to current day if we're NOT scrolling to a specific month
    if (!targetMonth) {
      // Use requestAnimationFrame to batch layout reads and avoid forced reflow
      requestAnimationFrame(function() {
        setTimeout(function() {
          if (initialScrollCancelled) return;
          // Batch all layout reads together
          var rect = currentDayCell.getBoundingClientRect();
          var yOffset = -150; // Offset for sticky header
          var y = rect.top + window.pageYOffset + yOffset;
          
          // Only scroll if current day is not visible
          if (rect.top < 0 || rect.bottom > window.innerHeight) {
            window.scrollTo({ top: y, behavior: 'instant' });
          }
        }, 500);
      });
    }
  }
  window.CalendarPresentation.initializeDayNavigation();
});

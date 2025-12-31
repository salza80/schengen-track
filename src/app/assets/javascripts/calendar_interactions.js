// Calendar Interaction Handler
// Handles click-to-add/edit visits on calendar

(function() {
  'use strict';
  
  var CalendarInteractions = {
    // State management
    state: {
      isSelecting: false,
      startDate: null,
      endDate: null,
      selectedCells: [],
      longPressTimer: null,
      longPressTriggered: false,
      isMobileDevice: 'ontouchstart' in window || navigator.maxTouchPoints > 0
    },
    
    // Store current visit ID for edit mode
    currentVisitId: null,
    
    // Initialize on page load
    init: function() {
      var self = this;
      
      // Only run on calendar view
      if (!$('.calendar-view-container').length) {
        return;
      }
      
      // Bind click handlers to day cells
      self.bindDayCellClicks();
      
      // Bind mobile touch handlers for long press
      if (self.state.isMobileDevice) {
        self.bindMobileTouchHandlers();
      } else {
        // Bind drag-to-select handlers (desktop only)
        self.bindDragToSelect();
      }
      
      // Close context menu when clicking outside
      $(document).on('click', function(e) {
        if (!$(e.target).closest('#visitContextMenu').length && !$(e.target).closest('.day-cell').length) {
          $('#visitContextMenu').hide();
        }
      });
      
      // Close modal cleanup
      $('#visitModal').on('hidden.bs.modal', function() {
        self.resetSelection();
      });
      
      // Bind modal Save button
      $('#saveVisitButton').on('click', function(e) {
        e.preventDefault();
        self.submitVisitForm();
      });
      
      // Bind modal Delete button
      $('#deleteVisitButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visits/' + self.currentVisitId;
        $('#visitModal').modal('hide');
        self.openDeleteModal(deleteUrl);
      });
    },
    
    // Bind click handlers to day cells
    bindDayCellClicks: function() {
      var self = this;
      
      $(document).on('click', '.day-cell', function(e) {
        // Skip if long press was triggered
        if (self.state.longPressTriggered) {
          self.state.longPressTriggered = false;
          return;
        }
        
        var $cell = $(this);
        
        // On mobile, first click shows tooltip, second click opens modal
        if (self.state.isMobileDevice) {
          var $tooltip = $cell.data('bs.tooltip');
          
          // Safely check if tooltip is shown
          var isTooltipShown = false;
          try {
            isTooltipShown = $tooltip && $tooltip.tip && $tooltip.tip.classList.contains('show');
          } catch (e) {
            // Tooltip not initialized or structure changed
            isTooltipShown = false;
          }
          
          // If tooltip is not shown, show it
          if (!isTooltipShown) {
            e.preventDefault();
            e.stopPropagation();
            
            // Hide all other tooltips
            $('.day-cell').tooltip('hide');
            
            // Show this tooltip
            $cell.tooltip('show');
            
            // Auto-hide after 3 seconds
            setTimeout(function() {
              $cell.tooltip('hide');
            }, 3000);
            
            return;
          }
          
          // If tooltip is already shown, proceed to open modal
          $cell.tooltip('hide');
        }
        
        e.preventDefault();
        e.stopPropagation();
        
        var date = $cell.data('date');
        
        if (!date) return;
        
        // Check if this day has visits
        self.checkVisitsForDate(date, function(visits) {
          if (visits.length === 0) {
            // No visits - open ADD modal
            self.openAddModal(date, date);
          } else if (visits.length === 1) {
            // Single visit - open EDIT modal
            self.openEditModal(visits[0].id);
          } else {
            // Multiple visits - show context menu
            self.showContextMenu($cell, visits);
          }
        });
      });
    },
    
    // Bind mobile touch handlers for long press
    bindMobileTouchHandlers: function() {
      var self = this;
      var longPressDuration = 500; // milliseconds
      
      $(document).on('touchstart', '.day-cell', function(e) {
        var $cell = $(this);
        self.state.longPressTriggered = false;
        
        // Start long press timer
        self.state.longPressTimer = setTimeout(function() {
          self.state.longPressTriggered = true;
          
          // Vibrate if supported
          if (navigator.vibrate) {
            navigator.vibrate(50);
          }
          
          // Hide tooltip if shown
          $cell.tooltip('hide');
          
          // Trigger add/edit visit
          var date = $cell.data('date');
          if (!date) return;
          
          self.checkVisitsForDate(date, function(visits) {
            if (visits.length === 0) {
              self.openAddModal(date, date);
            } else if (visits.length === 1) {
              self.openEditModal(visits[0].id);
            } else {
              self.showContextMenu($cell, visits);
            }
          });
        }, longPressDuration);
        
        // Visual feedback - add pressing class
        $cell.addClass('long-pressing');
      });
      
      $(document).on('touchend touchcancel', '.day-cell', function(e) {
        // Clear timer
        if (self.state.longPressTimer) {
          clearTimeout(self.state.longPressTimer);
          self.state.longPressTimer = null;
        }
        
        // Remove visual feedback
        $(this).removeClass('long-pressing');
      });
      
      // Prevent default touch behavior on cells
      $(document).on('touchmove', '.day-cell', function(e) {
        if (self.state.longPressTimer) {
          clearTimeout(self.state.longPressTimer);
          self.state.longPressTimer = null;
          $(this).removeClass('long-pressing');
        }
      });
    },
    
    // Bind drag-to-select functionality
    bindDragToSelect: function() {
      var self = this;
      var isMouseDown = false;
      
      $(document).on('mousedown', '.day-cell', function(e) {
        if (e.which !== 1) return; // Only left mouse button
        
        isMouseDown = true;
        self.state.isSelecting = true;
        self.state.startDate = $(this).data('date');
        self.state.selectedCells = [this];
        
        $(this).addClass('selecting');
        e.preventDefault();
      });
      
      $(document).on('mouseover', '.day-cell', function() {
        if (!isMouseDown || !self.state.isSelecting) return;
        
        var currentDate = $(this).data('date');
        if (!currentDate) return;
        
        // Update selection
        self.updateSelection(self.state.startDate, currentDate);
      });
      
      $(document).on('mouseup', function() {
        if (!isMouseDown) return;
        
        isMouseDown = false;
        
        if (self.state.isSelecting && self.state.selectedCells.length > 1) {
          // Multi-day selection completed
          var dates = self.getSelectedDateRange();
          self.openAddModal(dates.start, dates.end);
        }
        
        self.resetSelection();
      });
    },
    
    // Update visual selection during drag
    updateSelection: function(startDate, currentDate) {
      var self = this;
      var start = new Date(startDate);
      var current = new Date(currentDate);
      var isReverse = current < start;
      
      // Clear previous selection
      $('.day-cell').removeClass('selecting selected');
      self.state.selectedCells = [];
      
      // Select all cells in range
      $('.day-cell').each(function() {
        var cellDate = new Date($(this).data('date'));
        var inRange = isReverse 
          ? (cellDate >= current && cellDate <= start)
          : (cellDate >= start && cellDate <= current);
        
        if (inRange) {
          $(this).addClass('selecting');
          self.state.selectedCells.push(this);
        }
      });
      
      self.state.endDate = currentDate;
    },
    
    // Get selected date range
    getSelectedDateRange: function() {
      var start = new Date(this.state.startDate);
      var end = new Date(this.state.endDate || this.state.startDate);
      
      return {
        start: start <= end ? this.state.startDate : this.state.endDate,
        end: start <= end ? this.state.endDate : this.state.startDate
      };
    },
    
    // Reset selection state
    resetSelection: function() {
      this.state.isSelecting = false;
      this.state.startDate = null;
      this.state.endDate = null;
      this.state.selectedCells = [];
      $('.day-cell').removeClass('selecting selected');
    },
    
    // Check if date has visits (AJAX call)
    checkVisitsForDate: function(date, callback) {
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visits/for_date.json',
        method: 'GET',
        data: { date: date },
        dataType: 'json',
        success: function(visits) {
          callback(visits);
        },
        error: function() {
          console.error('Failed to fetch visits for date:', date);
          callback([]);
        }
      });
    },
    
    // Submit the visit form
    submitVisitForm: function() {
      var $form = $('#visitModal form');
      if ($form.length) {
        $form.submit();
      }
    },
    
    // Open ADD modal
    openAddModal: function(entryDate, exitDate) {
      var self = this;
      self.currentVisitId = null; // Clear current visit ID
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visits/new.js',
        method: 'GET',
        data: { 
          entry_date: entryDate,
          exit_date: exitDate
        },
        dataType: 'script',
        success: function() {
          // Hide delete button for new visits
          $('#deleteVisitButton').hide();
        },
        error: function() {
          alert('Failed to open visit form. Please try again.');
        }
      });
    },
    
    // Open EDIT modal
    openEditModal: function(visitId) {
      var self = this;
      self.currentVisitId = visitId; // Store current visit ID
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visits/' + visitId + '/edit.js',
        method: 'GET',
        dataType: 'script',
        success: function() {
          // Show delete button for existing visits
          $('#deleteVisitButton').show();
        },
        error: function() {
          alert('Failed to open visit form. Please try again.');
        }
      });
    },
    
    // Open delete confirmation modal
    openDeleteModal: function(deleteUrl) {
      var $modal = $('#deleteModal');
      var $confirmButton = $('#deleteConfirmButton');
      
      // Update the confirmation button with the delete URL
      $confirmButton.attr('href', deleteUrl);
      $confirmButton.attr('data-method', 'delete');
      $confirmButton.attr('rel', 'nofollow');
      
      // Show the modal
      $modal.modal('show');
      
      // Handle delete confirmation click
      $confirmButton.off('click').on('click', function(e) {
        e.preventDefault();
        
        // Create a form to submit the DELETE request
        var $form = $('<form>', {
          'method': 'POST',
          'action': deleteUrl
        });
        
        // Add CSRF token
        var csrfToken = $('meta[name="csrf-token"]').attr('content');
        $form.append($('<input>', {
          'type': 'hidden',
          'name': '_method',
          'value': 'delete'
        }));
        $form.append($('<input>', {
          'type': 'hidden',
          'name': 'authenticity_token',
          'value': csrfToken
        }));
        
        // Add return_to parameter with current URL to preserve calendar state
        $form.append($('<input>', {
          'type': 'hidden',
          'name': 'return_to',
          'value': window.location.pathname + window.location.search
        }));
        
        // Submit the form
        $('body').append($form);
        $form.submit();
      });
    },
    
    // Show context menu for multiple visits
    showContextMenu: function($cell, visits) {
      var $menu = $('#visitContextMenu');
      var $list = $menu.find('ul');
      
      // Clear existing items
      $list.empty();
      
      // Add menu items for each visit
      visits.forEach(function(visit, index) {
        var $item = $('<li></li>');
        $item.html(
          '<div class="visit-country">' + visit.country_name + '</div>' +
          '<div class="visit-dates">' + visit.entry_date + ' - ' + visit.exit_date + '</div>'
        );
        
        $item.on('click', function(e) {
          e.stopPropagation();
          $menu.hide();
          CalendarInteractions.openEditModal(visit.id);
        });
        
        $list.append($item);
        
        // Add divider between items (except last)
        if (index < visits.length - 1) {
          $list.append('<li class="divider"></li>');
        }
      });
      
      // Show menu to get its dimensions
      $menu.show();
      
      // Get cell position relative to viewport
      var cellRect = $cell[0].getBoundingClientRect();
      var menuWidth = $menu.outerWidth();
      var menuHeight = $menu.outerHeight();
      
      // Calculate initial position (below cell, centered)
      var menuLeft = cellRect.left + (cellRect.width / 2) - (menuWidth / 2);
      var menuTop = cellRect.bottom + 5;
      
      // Adjust horizontal position if menu would go off screen
      if (menuLeft + menuWidth > $(window).width()) {
        menuLeft = $(window).width() - menuWidth - 10;
      }
      if (menuLeft < 10) {
        menuLeft = 10;
      }
      
      // Adjust vertical position if menu would go off bottom of screen
      if (menuTop + menuHeight > $(window).height()) {
        // Position above the cell instead
        menuTop = cellRect.top - menuHeight - 5;
        
        // If still off screen, position at top of viewport
        if (menuTop < 10) {
          menuTop = 10;
        }
      }
      
      // Apply position
      $menu.css({
        left: menuLeft + 'px',
        top: menuTop + 'px'
      });
    }
  };
  
  // Initialize when document is ready
  $(document).ready(function() {
    CalendarInteractions.init();
  });
  
  // Also initialize on turbolinks page load (if using turbolinks)
  $(document).on('turbolinks:load', function() {
    CalendarInteractions.init();
  });
  
})();

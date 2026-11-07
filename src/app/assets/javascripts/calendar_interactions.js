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
      isMobileDevice: 'ontouchstart' in window || navigator.maxTouchPoints > 0
    },
    
    // Store current visit ID for edit mode
    currentVisitId: null,
    
    // Initialize on page load
    init: function() {
      var self = this;
      
      // Only bind once; refreshed calendar cells use delegated handlers.
      if (self.initialized || !$('.calendar-view-container').length) {
        return;
      }

      self.initialized = true;
      ModalInteractions.bindFocusGuard('#visitModal');
      
      // Bind click handlers to day cells
      self.bindDayCellClicks();
      
      if (!self.state.isMobileDevice) self.bindDragToSelect();
      
      // Close modal cleanup
      $('#visitModal').on('hidden.bs.modal', function() {
        self.resetSelection();
      });
      
      // Bind modal Save button
      $('#saveVisitButton').on('click', function(e) {
        e.preventDefault();
        ModalInteractions.submitForm('#visitModal form', '#saveVisitButton');
      });

      ModalInteractions.bindSubmissionReset('#visitModal form', '#saveVisitButton');
      
      // Bind modal Delete button
      $('#deleteVisitButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visits/' + self.currentVisitId;
        var focusReturn = $('#visitModal').data('focus-return');
        $('#visitModal').removeData('focus-return');
        $('#visitModal').modal('hide');
        ModalInteractions.openDeleteModal(deleteUrl, { trigger: focusReturn });
      });

      var continuation = new URLSearchParams(window.location.search);
      if (continuation.get('open') === 'trip') {
        var entryDate = continuation.get('entry_date');
        var exitDate = continuation.get('exit_date');
        continuation.delete('open');
        continuation.delete('entry_date');
        continuation.delete('exit_date');
        window.history.replaceState({}, '', window.location.pathname + (continuation.toString() ? '?' + continuation.toString() : ''));
        self.openAddModal(entryDate, exitDate);
      }
    },
    
    // Bind click handlers to day cells
    bindDayCellClicks: function() {
      var self = this;
      
      $(document).on('click keydown', '.day-cell', function(e) {
        if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
        if (self.suppressNextClick && e.type === 'click') {
          self.suppressNextClick = false;
          return;
        }
        var $cell = $(this);
        $('#visitModal').data('focus-return', this);
        self.showDayInfo($cell.data('date'));
        $('.day-cell').each(function() {
          var tooltip = bootstrap.Tooltip.getInstance(this);
          if (tooltip) tooltip.hide();
        });
        if (!$('#visitModal').is('[data-nationality-required]')) self.showLoading();
        $('#visitModal').modal('show');

        e.preventDefault();
        e.stopPropagation();
        
        var date = $cell.data('date');
        
        if (!date) return;
        
        if ($('#visitModal').is('[data-nationality-required]')) {
          self.openAddModal(date, date);
          return;
        }
        // Check if this day has visits
        self.checkVisitsForDate(date, function(visits) {
          var modal = bootstrap.Modal.getInstance(document.getElementById('visitModal'));
          if (self.selectedDate !== date || !modal || !modal._isShown) return;
          if (visits.length === 0) {
            // No visits - open ADD modal
            self.openAddModal(date, date);
          } else if (visits.length === 1) {
            // Single visit - open EDIT modal
            self.openEditModal(visits[0].id);
          } else {
            // Multiple visits - show context menu
            self.showVisitChoices(visits);
          }
        });
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
          $('#visitModal').data('focus-return', self.state.selectedCells[0]);
          self.suppressNextClick = true;
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
    
    showDayInfo: function(date) {
      this.selectedDate = date;
      var cell = /^\d{4}-\d{2}-\d{2}$/.test(date || '') && document.querySelector('.day-cell[data-date="' + date + '"]');
      var summary = document.getElementById('calendar-day-info');
      summary.hidden = !cell;
      if (!cell) return;
      var parts = date.split('-').map(Number);
      document.getElementById('calendar-day-info-date').textContent = new Intl.DateTimeFormat(
        document.documentElement.lang, { dateStyle: 'long' }
      ).format(new Date(parts[0], parts[1] - 1, parts[2]));
      document.getElementById('calendar-day-info-content').replaceChildren(window.DOMPurify.sanitize(
        cell.getAttribute('data-bs-title'), {
          ALLOWED_TAGS: ['strong', 'span', 'br'], ALLOWED_ATTR: ['class'], RETURN_DOM_FRAGMENT: true
        }
      ));
    },

    showLoading: function() {
      $('#calendar-visit-form').text($('#calendar-content').data('loading'));
      $('#saveVisitButton').prop('disabled', true);
      $('#deleteVisitButton').hide();
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
    
    // Open ADD modal
    openAddModal: function(entryDate, exitDate) {
      var self = this;
      self.currentVisitId = null; // Clear current visit ID
      self.showDayInfo(entryDate);
      if ($('#visitModal').is('[data-nationality-required]')) {
        var $preferenceForm = $('#visitModal .calculator-nationality-form');
        $preferenceForm.find('input[name="entry_date"], input[name="exit_date"], input[data-viewer-continuation="true"]').remove();
        var viewerParams = new URLSearchParams(window.location.search);
        ['year', 'month', 'day'].forEach(function(name) {
          var value = viewerParams.get(name);
          if (!value) return;

          var $input = $preferenceForm.find('input[name="' + name + '"]');
          if ($input.length) {
            $input.val(value);
          } else {
            $preferenceForm.append($('<input>', { type: 'hidden', name: name, value: value, 'data-viewer-continuation': 'true' }));
          }
        });
        if (entryDate) {
          $preferenceForm.append($('<input>', { type: 'hidden', name: 'entry_date', value: entryDate }));
        }
        if (exitDate) {
          $preferenceForm.append($('<input>', { type: 'hidden', name: 'exit_date', value: exitDate }));
        }
        $('#deleteVisitButton').hide();
        $('#visitModal').modal('show');
        return;
      }
      $('#saveVisitButton').show();
      self.showLoading();
      $('#visitModal').modal('show');
      var locale = $('html').attr('lang') || 'en';
      ModalInteractions.loadForm({
        url: '/' + locale + '/visits/new.json',
        dataType: 'json',
        data: { 
          entry_date: entryDate,
          exit_date: exitDate
        },
        deleteButtonSelector: '#deleteVisitButton',
        showDeleteButton: false,
        errorMessage: 'Failed to open visit form. Please try again.'
      });
    },
    
    // Open EDIT modal
    openEditModal: function(visitId) {
      var self = this;
      self.currentVisitId = visitId; // Store current visit ID
      $('#saveVisitButton').show();
      self.showLoading();
      $('#visitModal').modal('show');
      var locale = $('html').attr('lang') || 'en';
      ModalInteractions.loadForm({
        url: '/' + locale + '/visits/' + visitId + '/edit.json',
        dataType: 'json',
        deleteButtonSelector: '#deleteVisitButton',
        showDeleteButton: true,
        errorMessage: 'Failed to open visit form. Please try again.'
      });
    },
    
    // Border days can belong to more than one visit. Keep the choice in the dialog.
    showVisitChoices: function(visits) {
      var $list = $('<div>', { class: 'list-group' });
      visits.forEach(function(visit) {
        $('<button>', { type: 'button', class: 'list-group-item list-group-item-action' })
          .text(visit.country_name + ' · ' + visit.entry_date + ' – ' + visit.exit_date)
          .on('click', function() { CalendarInteractions.openEditModal(visit.id); })
          .appendTo($list);
      });
      $('#calendar-visit-form').empty().append($list);
      $('#deleteVisitButton, #saveVisitButton').hide();
      $('#visitModal').modal('show');
    }
  };
  
  window.CalendarInteractions = CalendarInteractions;

  // Initialize when document is ready
  $(document).ready(function() {
    CalendarInteractions.init();
  });
  
  // Also initialize on turbolinks page load (if using turbolinks)
  $(document).on('turbolinks:load', function() {
    CalendarInteractions.init();
  });
  
})();

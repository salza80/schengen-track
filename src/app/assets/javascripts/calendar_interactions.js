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
      selectedCells: []
    },
    
    // Store current visit ID for edit mode
    currentVisitId: null,
    dialogVersion: 0,
    
    // Initialize on page load
    init: function() {
      var self = this;
      
      // Only bind once; refreshed calendar cells use delegated handlers.
      if (self.initialized || !$('.calendar-view-container').length) {
        return;
      }

      self.initialized = true;
      ModalInteractions.bindFocusGuard('#visitModal');
      $('#visitModal').on('modal:form-rendered', function() {
        document.getElementById('calendar-day-info').hidden = true;
      });
      
      // Bind click handlers to day cells
      self.bindDayCellClicks();
      
      self.bindDragToSelect();
      
      $('#visitModal').on('hide.bs.modal', function() {
        self.dialogVersion += 1;
        self.cancelFormRequest();
      });

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
        if (e.type === 'keydown' && window.CalendarPresentation.moveDay(this, e)) return;
        if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
        if (self.suppressNextClick && e.type === 'click') {
          self.suppressNextClick = false;
          return;
        }
        var $cell = $(this);
        var version = ++self.dialogVersion;
        window.CalendarPresentation.setActiveDay(this);
        $('#visitModal').data('focus-return', this);
        if (!$('#visitModal').is('[data-nationality-required]')) self.showLoading();
        self.showDayInfo($cell.data('date'));
        $('.day-cell').each(function() {
          var tooltip = bootstrap.Tooltip.getInstance(this);
          if (tooltip) tooltip.hide();
        });
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
        self.checkVisitsForDate(date, function(visits, error) {
          var modal = bootstrap.Modal.getInstance(document.getElementById('visitModal'));
          if (self.dialogVersion !== version || self.selectedDate !== date || !modal || !modal._isShown) return;
          if (error) {
            self.showLoadError(function() {
              document.querySelector('.day-cell[data-date="' + date + '"]').click();
            });
            return;
          }
          if (visits.length === 0) {
            // No visits - open ADD modal
            self.openAddModal(date, date);
          } else if (visits.length === 1) {
            // Single visit - open EDIT modal
            self.openEditModal(visits[0].id);
          } else {
            // Border day - choose a visit in the dialog
            self.showVisitChoices(visits);
          }
        });
      });
      $(document).on('focusin', '.day-cell', function() {
        window.CalendarPresentation.setActiveDay(this);
      });
    },
    
    // Bind drag-to-select functionality
    bindDragToSelect: function() {
      var self = this;

      $(document).on('pointerdown', '.day-cell', function(e) {
        var pointer = e.originalEvent || e;
        if (pointer.pointerType !== 'mouse' || pointer.button !== 0) return;
        self.suppressNextClick = false;
        
        self.state.isSelecting = true;
        self.state.startDate = $(this).data('date');
        self.state.selectedCells = [this];
        
        $(this).addClass('selecting');
        e.preventDefault();
      });
      
      $(document).on('pointerover', '.day-cell', function(e) {
        if (!self.state.isSelecting || (e.originalEvent || e).pointerType !== 'mouse') return;
        
        var currentDate = $(this).data('date');
        if (!currentDate) return;
        
        // Update selection
        self.updateSelection(self.state.startDate, currentDate);
      });
      
      $(document).on('pointerup', function(e) {
        if (!self.state.isSelecting || (e.originalEvent || e).pointerType !== 'mouse') return;
        
        if (self.state.isSelecting && self.state.selectedCells.length > 1) {
          // Multi-day selection completed
          var dates = self.getSelectedDateRange();
          $('#visitModal').data('focus-return', self.state.selectedCells[0]);
          // A drag's click may target the grid rather than either day cell.
          self.suppressNextClick = true;
          setTimeout(function() { self.suppressNextClick = false; }, 0);
          self.openAddModal(dates.start, dates.end);
        }
        
        self.resetSelection();
      });

      function cancelDrag() {
        if (self.state.isSelecting) self.resetSelection();
      }
      $(document).on('pointercancel', function(e) {
        if ((e.originalEvent || e).pointerType === 'mouse') cancelDrag();
      });
      $(window).on('blur', cancelDrag);
    },
    
    // Update visual selection during drag
    updateSelection: function(startDate, currentDate) {
      var self = this;
      var start = new Date(startDate);
      var current = new Date(currentDate);
      var isReverse = current < start;
      
      // Clear previous selection
      $('.day-cell').removeClass('selecting');
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
      $('.day-cell').removeClass('selecting');
    },
    
    showDayInfo: function(date, activateDay) {
      this.selectedDate = date;
      var cell = /^\d{4}-\d{2}-\d{2}$/.test(date || '') && document.querySelector('.day-cell[data-date="' + date + '"]');
      var summary = document.getElementById('calendar-day-info');
      summary.hidden = !cell || !!document.querySelector('#calendar-visit-form form[data-visit-form], #calendar-visit-form form[data-inline-visa-form]');
      summary.querySelector('[data-day-add-visa]').hidden = !cell || !cell.hasAttribute('data-visa-missing');
      if (!cell) return;
      if (activateDay !== false) window.CalendarPresentation.setActiveDay(cell);
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
        error: function() { callback(null, true); }
      });
    },
    
    // Open ADD modal
    openAddModal: function(entryDate, exitDate) {
      var self = this;
      self.currentVisitId = null; // Clear current visit ID
      self.showDayInfo(entryDate);
      if ($('#visitModal').is('[data-nationality-required]')) {
        self.dialogVersion += 1;
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
            var input = document.createElement('input');
            input.type = 'hidden';
            input.name = name;
            input.value = value;
            input.dataset.viewerContinuation = 'true';
            $preferenceForm.get(0).appendChild(input);
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
      var locale = $('html').attr('lang') || 'en';
      self.loadVisitForm('/' + locale + '/visits/new.json', { entry_date: entryDate, exit_date: exitDate }, false);
    },
    
    // Open EDIT modal
    openEditModal: function(visitId) {
      var self = this;
      self.currentVisitId = visitId; // Store current visit ID
      var locale = $('html').attr('lang') || 'en';
      self.loadVisitForm('/' + locale + '/visits/' + visitId + '/edit.json', {}, true);
    },

    loadVisitForm: function(url, data, showDelete) {
      var self = this;
      var version = ++self.dialogVersion;
      self.cancelFormRequest();
      $('#saveVisitButton').show();
      self.showLoading();
      $('#visitModal').modal('show');
      self.formRequest = ModalInteractions.loadForm({
        url: url,
        data: data,
        dataType: 'json',
        isCurrent: function() { return self.isDialogCurrent(version); },
        onSuccess: window.CalendarRefresh.showForm,
        onError: function() { self.showLoadError(function() { self.loadVisitForm(url, data, showDelete); }); },
        deleteButtonSelector: '#deleteVisitButton',
        showDeleteButton: showDelete
      });
    },

    cancelFormRequest: function() {
      if (this.formRequest) this.formRequest.abort();
      this.formRequest = null;
    },

    showLoadError: function(retry) {
      var messages = document.getElementById('calendar-content').dataset;
      var container = document.getElementById('calendar-visit-form');
      var error = document.createElement('p');
      error.setAttribute('role', 'alert');
      error.textContent = messages.formError;
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'btn btn-outline-primary';
      button.textContent = messages.retry;
      button.addEventListener('click', retry, { once: true });
      container.replaceChildren(error, button);
      $('#saveVisitButton').prop('disabled', true);
      $('#deleteVisitButton').hide();
    },

    isDialogCurrent: function(version) {
      var modal = bootstrap.Modal.getInstance(document.getElementById('visitModal'));
      return this.dialogVersion === version && modal && modal._isShown;
    },
    
    // Border days can belong to more than one visit. Keep the choice in the dialog.
    showVisitChoices: function(visits) {
      var $list = $('<div>', { class: 'list-group' });
      visits.forEach(function(visit) {
        $('<button>', { type: 'button', class: 'list-group-item list-group-item-action' })
          .text(visit.country_name + ' · ' + visit.date_range_label)
          .on('click', function() { CalendarInteractions.openEditModal(visit.id); })
          .appendTo($list);
      });
      $('#calendar-visit-form').empty().append($list);
      this.showDayInfo(this.selectedDate, false);
      $('#deleteVisitButton, #saveVisitButton').hide();
      $('#visitModal').modal('show');
    }
  };
  
  window.CalendarInteractions = CalendarInteractions;

  // Initialize when document is ready
  $(document).ready(function() {
    CalendarInteractions.init();
  });
})();

// Visits Page Modal Interactions
// Handles add/edit for visits and visas on the visits index page

(function() {
  'use strict';
  
  var VisitsPageModals = {
    // Store current visit/visa ID for edit mode
    currentVisitId: null,
    currentVisaId: null,
    
    // Initialize on page load
    init: function() {
      var self = this;
      
      // Only run on visits page
      if (!$('body').data('controller') || $('body').data('controller') !== 'visits') {
        // Fallback: check if we're on visits page by presence of modals
        if (!$('#visitModal').length || !$('#visaModal').length) {
          return;
        }
      }

      // Bootstrap applies aria-hidden while hiding a modal. Move focus out first so
      // the focused close/cancel button is never hidden from assistive technology.
      $('#visitModal, #visaModal')
        .off('hide.bs.modal.focusGuard')
        .on('hide.bs.modal.focusGuard', function() {
          if (this.contains(document.activeElement)) {
            document.activeElement.blur();
          }
        })
        .off('hidden.bs.modal.focusGuard')
        .on('hidden.bs.modal.focusGuard', function() {
          var trigger = $(this).data('focus-return');
          $(this).removeData('focus-return');
          if (trigger && document.documentElement.contains(trigger)) {
            window.setTimeout(function() {
              trigger.focus();
            }, 0);
          }
        })
        .off('click.modalFocusGuard', '[data-dismiss="modal"]')
        .on('click.modalFocusGuard', '[data-dismiss="modal"]', function(e) {
          var $modal = $(this).closest('.modal');
          var modalInstance = $modal.data('bs.modal');
          this.blur();
          if (modalInstance && modalInstance._isTransitioning) {
            e.preventDefault();
            e.stopPropagation();
            $modal.one('shown.bs.modal.focusGuard', function() {
              $modal.modal('hide');
            });
          }
        });
      
      // Bind add visit button
      $('[data-action="add-visit"]').on('click', function(e) {
        e.preventDefault();
        $('#visitModal').data('focus-return', e.currentTarget);
        self.openAddVisitModal();
      });
      
      // Bind add visa button
      $('[data-action="add-visa"]').on('click', function(e) {
        e.preventDefault();
        $('#visaModal').data('focus-return', e.currentTarget);
        self.openAddVisaModal();
      });
      
      // Bind edit visit links
      $(document).on('click', '.edit-visit-link', function(e) {
        e.preventDefault();
        var visitId = $(this).data('visit-id');
        $('#visitModal').data('focus-return', e.currentTarget);
        self.openEditVisitModal(visitId);
      });
      
      // Bind edit visa links
      $(document).on('click', '.edit-visa-link', function(e) {
        e.preventDefault();
        var visaId = $(this).data('visa-id');
        $('#visaModal').data('focus-return', e.currentTarget);
        self.openEditVisaModal(visaId);
      });
      
      // Bind delete visit links
      $(document).on('click', '.delete-visit-link', function(e) {
        e.preventDefault();
        var deleteUrl = $(this).data('delete-url');
        self.openDeleteModal(deleteUrl, 'visit');
      });
      
      // Bind delete visa links
      $(document).on('click', '.delete-visa-link', function(e) {
        e.preventDefault();
        var deleteUrl = $(this).data('delete-url');
        self.openDeleteModal(deleteUrl, 'visa');
      });
      
      // Bind modal Save button (visits)
      $('#saveVisitButton').on('click', function(e) {
        e.preventDefault();
        self.submitVisitForm();
      });
      
      // Bind modal Delete button (visits)
      $('#deleteVisitButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visits/' + self.currentVisitId;
        $('#visitModal').removeData('focus-return');
        $('#visitModal').modal('hide');
        self.openDeleteModal(deleteUrl, 'visit');
      });
      
      // Bind modal Save button (visas)
      $('#saveVisaButton').on('click', function(e) {
        e.preventDefault();
        self.submitVisaForm();
      });

      $(document).on('ajax:complete', '#visitModal form, #visaModal form', function() {
        $('#saveVisitButton, #saveVisaButton').prop('disabled', false);
      });
      
      // Bind modal Delete button (visas)
      $('#deleteVisaButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visas/' + self.currentVisaId;
        $('#visaModal').removeData('focus-return');
        $('#visaModal').modal('hide');
        self.openDeleteModal(deleteUrl, 'visa');
      });
      
      // Bind clickable visit rows (navigate to calendar)
      $(document).on('click', 'tr[data-clickable-row="true"]', function(e) {
        // Don't navigate if clicking edit/delete links or any anchor tag
        if ($(e.target).is('a') || $(e.target).closest('a').length) {
          return;
        }
        
        var year = $(this).data('entry-year');
        var month = $(this).data('entry-month');
        var day = $(this).data('entry-day');
        var locale = $('html').attr('lang') || 'en';
        
        // Navigate to calendar page with year and month
        window.location.href = '/' + locale + '/days?year=' + year + '&month=' + month + '&day=' + day;
      });

    },
    
    // Submit the visit form
    submitVisitForm: function() {
      var $form = $('#visitModal form');
      var $button = $('#saveVisitButton');
      if ($form.length && !$button.prop('disabled')) {
        $button.prop('disabled', true);
        $form.submit();
      }
    },
    
    // Submit the visa form
    submitVisaForm: function() {
      var $form = $('#visaModal form');
      var $button = $('#saveVisaButton');
      if ($form.length && !$button.prop('disabled')) {
        $button.prop('disabled', true);
        $form.submit();
      }
    },
    
    // Open ADD visit modal
    openAddVisitModal: function() {
      var self = this;
      self.currentVisitId = null; // Clear current visit ID
      if ($('#visitModal').is('[data-nationality-required]')) {
        $('#deleteVisitButton').hide();
        $('#visitModal').modal('show');
        return;
      }
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visits/new.js',
        method: 'GET',
        dataType: 'script',
        success: function() {
          // Hide delete button for new visits
          $('#deleteVisitButton').hide();
        },
        error: function(xhr, status, error) {
          console.error('Failed to load visit form:', status, error);
          console.error('Response:', xhr.responseText);
          alert('Failed to open visit form. Please try again.');
        }
      });
    },
    
    // Open EDIT visit modal
    openEditVisitModal: function(visitId) {
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
        error: function(xhr, status, error) {
          console.error('Failed to load visit form:', status, error);
          console.error('Response:', xhr.responseText);
          alert('Failed to open visit form. Please try again.');
        }
      });
    },
    
    // Open ADD visa modal
    openAddVisaModal: function() {
      var self = this;
      self.currentVisaId = null; // Clear current visa ID
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visas/new.js',
        method: 'GET',
        dataType: 'script',
        success: function() {
          // Hide delete button for new visas
          $('#deleteVisaButton').hide();
        },
        error: function(xhr, status, error) {
          console.error('Failed to load visa form:', status, error);
          console.error('Response:', xhr.responseText);
          alert('Failed to open visa form. Please try again.');
        }
      });
    },
    
    // Open EDIT visa modal
    openEditVisaModal: function(visaId) {
      var self = this;
      self.currentVisaId = visaId; // Store current visa ID
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visas/' + visaId + '/edit.js',
        method: 'GET',
        dataType: 'script',
        success: function() {
          // Show delete button for existing visas
          $('#deleteVisaButton').show();
        },
        error: function(xhr, status, error) {
          console.error('Failed to load visa form:', status, error);
          console.error('Response:', xhr.responseText);
          alert('Failed to open visa form. Please try again.');
        }
      });
    },
    
    // Open delete confirmation modal
    openDeleteModal: function(deleteUrl, itemType) {
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
        
        // Submit the form
        $('body').append($form);
        $form.submit();
      });
    }
  };
  
  // Initialize when document is ready
  $(document).ready(function() {
    VisitsPageModals.init();
  });
  
  // Also initialize on turbolinks page load (if using turbolinks)
  $(document).on('turbolinks:load', function() {
    VisitsPageModals.init();
  });
  
})();

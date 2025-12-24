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
      
      // Bind add visit button
      $('[data-action="add-visit"]').on('click', function(e) {
        e.preventDefault();
        self.openAddVisitModal();
      });
      
      // Bind add visa button
      $('[data-action="add-visa"]').on('click', function(e) {
        e.preventDefault();
        self.openAddVisaModal();
      });
      
      // Bind edit visit links
      $(document).on('click', '.edit-visit-link', function(e) {
        e.preventDefault();
        var visitId = $(this).data('visit-id');
        self.openEditVisitModal(visitId);
      });
      
      // Bind edit visa links
      $(document).on('click', '.edit-visa-link', function(e) {
        e.preventDefault();
        var visaId = $(this).data('visa-id');
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
        $('#visitModal').modal('hide');
        self.openDeleteModal(deleteUrl, 'visit');
      });
      
      // Bind modal Save button (visas)
      $('#saveVisaButton').on('click', function(e) {
        e.preventDefault();
        self.submitVisaForm();
      });
      
      // Bind modal Delete button (visas)
      $('#deleteVisaButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visas/' + self.currentVisaId;
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
        var locale = $('html').attr('lang') || 'en';
        
        // Navigate to calendar page with year and month
        window.location.href = '/' + locale + '/days?year=' + year + '&month=' + month;
      });
    },
    
    // Submit the visit form
    submitVisitForm: function() {
      var $form = $('#visitModal form');
      if ($form.length) {
        $form.submit();
      }
    },
    
    // Submit the visa form
    submitVisaForm: function() {
      var $form = $('#visaModal form');
      if ($form.length) {
        $form.submit();
      }
    },
    
    // Open ADD visit modal
    openAddVisitModal: function() {
      var self = this;
      self.currentVisitId = null; // Clear current visit ID
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

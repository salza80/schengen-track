// Visits Page Modal Interactions
// Handles add/edit for visits and visas on the visits index page

(function() {
  'use strict';
  
  var VisitsPageModals = {
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
    },
    
    // Open ADD visit modal
    openAddVisitModal: function() {
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visits/new',
        method: 'GET',
        dataType: 'script',
        error: function() {
          alert('Failed to open visit form. Please try again.');
        }
      });
    },
    
    // Open EDIT visit modal
    openEditVisitModal: function(visitId) {
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visits/' + visitId + '/edit',
        method: 'GET',
        dataType: 'script',
        error: function() {
          alert('Failed to open visit form. Please try again.');
        }
      });
    },
    
    // Open ADD visa modal
    openAddVisaModal: function() {
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visas/new',
        method: 'GET',
        dataType: 'script',
        error: function() {
          alert('Failed to open visa form. Please try again.');
        }
      });
    },
    
    // Open EDIT visa modal
    openEditVisaModal: function(visaId) {
      var locale = $('html').attr('lang') || 'en';
      $.ajax({
        url: '/' + locale + '/visas/' + visaId + '/edit',
        method: 'GET',
        dataType: 'script',
        error: function() {
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

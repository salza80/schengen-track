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

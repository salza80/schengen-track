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

      ModalInteractions.bindFocusGuard('#visitModal, #visaModal');
      
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
        ModalInteractions.openDeleteModal(deleteUrl, { trigger: e.currentTarget });
      });
      
      // Bind delete visa links
      $(document).on('click', '.delete-visa-link', function(e) {
        e.preventDefault();
        var deleteUrl = $(this).data('delete-url');
        ModalInteractions.openDeleteModal(deleteUrl, { trigger: e.currentTarget });
      });
      
      // Bind modal Save button (visits)
      $('#saveVisitButton').on('click', function(e) {
        e.preventDefault();
        ModalInteractions.submitForm('#visitModal form', '#saveVisitButton');
      });
      
      // Bind modal Delete button (visits)
      $('#deleteVisitButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visits/' + self.currentVisitId;
        var focusReturn = $('#visitModal').data('focus-return');
        $('#visitModal').removeData('focus-return');
        $('#visitModal').modal('hide');
        ModalInteractions.openDeleteModal(deleteUrl, { trigger: focusReturn });
      });
      
      // Bind modal Save button (visas)
      $('#saveVisaButton').on('click', function(e) {
        e.preventDefault();
        ModalInteractions.submitForm('#visaModal form', '#saveVisaButton');
      });

      ModalInteractions.bindSubmissionReset(
        '#visitModal form, #visaModal form',
        '#saveVisitButton, #saveVisaButton'
      );
      
      // Bind modal Delete button (visas)
      $('#deleteVisaButton').on('click', function(e) {
        e.preventDefault();
        var locale = $('html').attr('lang') || 'en';
        var deleteUrl = '/' + locale + '/visas/' + self.currentVisaId;
        var focusReturn = $('#visaModal').data('focus-return');
        $('#visaModal').removeData('focus-return');
        $('#visaModal').modal('hide');
        ModalInteractions.openDeleteModal(deleteUrl, { trigger: focusReturn });
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
      ModalInteractions.loadForm({
        url: '/' + locale + '/visits/new.js',
        deleteButtonSelector: '#deleteVisitButton',
        showDeleteButton: false,
        errorMessage: 'Failed to open visit form. Please try again.'
      });
    },
    
    // Open EDIT visit modal
    openEditVisitModal: function(visitId) {
      var self = this;
      self.currentVisitId = visitId; // Store current visit ID
      var locale = $('html').attr('lang') || 'en';
      ModalInteractions.loadForm({
        url: '/' + locale + '/visits/' + visitId + '/edit.js',
        deleteButtonSelector: '#deleteVisitButton',
        showDeleteButton: true,
        errorMessage: 'Failed to open visit form. Please try again.'
      });
    },
    
    // Open ADD visa modal
    openAddVisaModal: function() {
      var self = this;
      self.currentVisaId = null; // Clear current visa ID
      var locale = $('html').attr('lang') || 'en';
      ModalInteractions.loadForm({
        url: '/' + locale + '/visas/new.js',
        deleteButtonSelector: '#deleteVisaButton',
        showDeleteButton: false,
        errorMessage: 'Failed to open visa form. Please try again.'
      });
    },
    
    // Open EDIT visa modal
    openEditVisaModal: function(visaId) {
      var self = this;
      self.currentVisaId = visaId; // Store current visa ID
      var locale = $('html').attr('lang') || 'en';
      ModalInteractions.loadForm({
        url: '/' + locale + '/visas/' + visaId + '/edit.js',
        deleteButtonSelector: '#deleteVisaButton',
        showDeleteButton: true,
        errorMessage: 'Failed to open visa form. Please try again.'
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

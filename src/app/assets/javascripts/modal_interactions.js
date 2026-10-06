// Shared form, deletion, and focus behavior for Bootstrap modals.
(function(window, $) {
  'use strict';

  function canReceiveFocus(element) {
    return element.matches('a[href], button, input, select, textarea, [tabindex]');
  }

  window.ModalInteractions = {
    bindFocusGuard: function(modalSelector) {
      $(modalSelector)
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
          if (!trigger || !document.documentElement.contains(trigger)) return;

          if (!canReceiveFocus(trigger)) {
            trigger.setAttribute('tabindex', '-1');
          }
          window.setTimeout(function() {
            trigger.focus();
          }, 0);
        })
        .off('click.modalFocusGuard', '[data-dismiss="modal"]')
        .on('click.modalFocusGuard', '[data-dismiss="modal"]', function(event) {
          var $modal = $(this).closest('.modal');
          var modalInstance = $modal.data('bs.modal');
          this.blur();
          if (modalInstance && modalInstance._isTransitioning) {
            event.preventDefault();
            event.stopPropagation();
            var hideAfterShown = function() {
              $modal.modal('hide');
            };
            $modal.one('shown.bs.modal.focusGuard', hideAfterShown);

            // The transition can finish between the state check and listener
            // registration. In that case, hide immediately instead of waiting
            // for an event that has already fired.
            if (!modalInstance._isTransitioning) {
              $modal.off('shown.bs.modal.focusGuard', hideAfterShown);
              $modal.modal('hide');
            }
          }
        });
    },

    submitForm: function(formSelector, buttonSelector) {
      var $form = $(formSelector);
      var $button = $(buttonSelector);
      if (!$form.length || $button.prop('disabled')) return;

      $button.prop('disabled', true);
      $form.submit();
    },

    bindSubmissionReset: function(formSelector, buttonSelector) {
      $(document)
        .off('ajax:complete.modalSubmission', formSelector)
        .on('ajax:complete.modalSubmission', formSelector, function() {
          $(buttonSelector).prop('disabled', false);
        });
    },

    loadForm: function(options) {
      $.ajax({
        url: options.url,
        method: 'GET',
        data: options.data,
        dataType: 'script',
        success: function() {
          $(options.deleteButtonSelector).toggle(!!options.showDeleteButton);
        },
        error: function(xhr, status, error) {
          console.error(options.errorMessage, status, error);
          if (xhr && xhr.responseText) console.error('Response:', xhr.responseText);
          alert(options.errorMessage);
        }
      });
    },

    openDeleteModal: function(deleteUrl, options) {
      options = options || {};
      var $modal = $('#deleteModal');
      var $confirmButton = $('#deleteConfirmButton');

      window.ModalInteractions.bindFocusGuard('#deleteModal');
      if (options.trigger) $modal.data('focus-return', options.trigger);
      if (options.message !== undefined) $('#deleteModalMessage').text(options.message);
      $confirmButton.attr('href', deleteUrl);
      $confirmButton.attr('data-method', 'delete');
      $confirmButton.attr('rel', 'nofollow');
      $modal.modal('show');

      $confirmButton.off('click').on('click', function(event) {
        event.preventDefault();
        var $form = $('<form>', { method: 'POST', action: deleteUrl });
        var csrfToken = $('meta[name="csrf-token"]').attr('content');

        $form.append($('<input>', { type: 'hidden', name: '_method', value: 'delete' }));
        $form.append($('<input>', {
          type: 'hidden',
          name: 'authenticity_token',
          value: csrfToken
        }));
        $('body').append($form);
        $form.submit();
      });
    }
  };
})(window, window.jQuery);

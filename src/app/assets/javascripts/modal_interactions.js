// Shared form, deletion, and focus behavior for Bootstrap modals.
(function(window, $) {
  'use strict';

  function canReceiveFocus(element) {
    return element.matches('a[href], button, input, select, textarea, [tabindex]');
  }

  function hideAfterOpening($modal, modalInstance) {
    var hide = function() { $modal.modal('hide'); };
    $modal.one('shown.bs.modal.focusGuard', hide);
    // The transition may have completed while registering the listener.
    if (!modalInstance._isTransitioning) {
      $modal.off('shown.bs.modal.focusGuard', hide);
      hide();
    }
  }

  window.ModalInteractions = {
    bindFocusGuard: function(modalSelector) {
      $(modalSelector)
        .off('show.bs.modal.focusGuard')
        .on('show.bs.modal.focusGuard', function() { $(this).removeData('opening-focus'); })
        .off('focusin.modalFocusGuard')
        .on('focusin.modalFocusGuard', function(event) {
          var modal = bootstrap.Modal.getInstance(this);
          if (modal && modal._isShown && modal._isTransitioning && event.target !== this) {
            $(this).data('opening-focus', event.target);
          }
        })
        .off('shown.bs.modal.focusGuard')
        .on('shown.bs.modal.focusGuard', function() {
          // Bootstrap focuses the dialog when the animation finishes. Preserve
          // input a user already started while it was opening.
          var control = $(this).data('opening-focus');
          $(this).removeData('opening-focus');
          if (control && this.contains(control)) control.focus({ preventScroll: true });
        })
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
            trigger.focus({ preventScroll: true });
          }, 0);
        })
        .off('click.modalFocusGuard', '[data-bs-dismiss="modal"]')
        .on('click.modalFocusGuard', '[data-bs-dismiss="modal"]', function(event) {
          var $modal = $(this).closest('.modal');
          var modalInstance = bootstrap.Modal.getInstance($modal.get(0));
          this.blur();
          if (modalInstance && modalInstance._isShown && modalInstance._isTransitioning) {
            event.preventDefault();
            event.stopPropagation();
            hideAfterOpening($modal, modalInstance);
          }
        })
        .off('keydown.modalFocusGuard')
        .on('keydown.modalFocusGuard', function(event) {
          if (event.key !== 'Escape' || event.isDefaultPrevented()) return;
          var modalInstance = bootstrap.Modal.getInstance(this);
          if (modalInstance && modalInstance._isShown && modalInstance._isTransitioning) {
            event.preventDefault();
            event.stopPropagation();
            hideAfterOpening($(this), modalInstance);
          }
        });
    },

    submitForm: function(formSelector, buttonSelector) {
      var $form = $(formSelector);
      var $button = $(buttonSelector);
      if (!$form.length || $button.prop('disabled')) return;

      var form = $form.get(0);
      if (typeof form.checkValidity === 'function' && !form.checkValidity()) {
        if (typeof form.reportValidity === 'function') form.reportValidity();
        return;
      }

      $button.prop('disabled', true);
      if (typeof form.requestSubmit === 'function') form.requestSubmit();
      else {
        var submitEvent = document.createEvent('Event');
        submitEvent.initEvent('submit', true, true);
        if (form.dispatchEvent(submitEvent)) form.submit();
      }
    },

    bindSubmissionReset: function(formSelector, buttonSelector) {
      $(document)
        .off('ajax:complete.modalSubmission', formSelector)
        .on('ajax:complete.modalSubmission', formSelector, function() {
          $(buttonSelector).prop('disabled', false);
        })
        .off('ajax:error.calculatorLimits', formSelector)
        .on('ajax:error.calculatorLimits', formSelector, function(event, xhr) {
          if (this.dataset.calendarVisitForm === 'true') return;
          if (!xhr || (xhr.status !== 429 && xhr.status !== 503)) return;
          try {
            var error = JSON.parse(xhr.responseText).error;
            if (error && ['rate_limited', 'calculator_capacity_reached', 'service_unavailable'].indexOf(error.code) !== -1) {
              window.alert(error.message);
            }
          } catch (ignored) {}
        });
    },

    loadForm: function(options) {
      return $.ajax({
        url: options.url,
        method: 'GET',
        data: options.data,
        dataType: options.dataType || 'script',
        success: function(data) {
          if (options.isCurrent && !options.isCurrent()) return;
          if (options.onSuccess) options.onSuccess(data);
          $(options.deleteButtonSelector).toggle(!!options.showDeleteButton);
        },
        error: function(xhr, status, error) {
          if (status === 'abort') return;
          if (options.isCurrent && !options.isCurrent()) return;
          if (options.onError) {
            options.onError(xhr);
            return;
          }
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

// Add a visa without losing the visit being edited. Each page owns its refresh.
(function(window, document, $) {
  'use strict';

  var draft = null;
  var version = 0;
  var request;
  var slot = '#visitModal .modal-body';

  function current(intent) {
    var modal = bootstrap.Modal.getInstance(document.getElementById('visitModal'));
    return draft && version === intent && modal && modal._isShown;
  }

  function visitForm() {
    return draft ? draft.form : document.querySelector('#visitModal form[data-visit-form]');
  }

  function refreshInfo() {
    var form = visitForm();
    if (form) $(form).trigger('visit:refresh-info');
  }

  function render(data) {
    window.ModalInteractions.renderForm('#visitModal', slot, '#saveVisitButton', data);
    var form = document.querySelector(slot + ' form');
    window.ModalInteractions.focusForm(form);
    form.addEventListener('submit', function(event) {
      if (form.getAttribute('aria-busy') !== 'true') return;
      event.preventDefault();
      event.stopPropagation();
    });
  }

  function restore() {
    if (!draft) return;
    version += 1;
    if (request) request.abort();
    request = null;
    var previous = draft;
    draft = null;
    document.querySelector(slot).replaceChildren(previous.content);
    $('#visitModal .modal-title').text(previous.title);
    $('#saveVisitButton').data('save-label', previous.saveLabel).text(previous.saveLabel)
      .attr('aria-label', previous.saveLabel).prop('disabled', false);
    $('#deleteVisitButton').toggle(previous.showDelete);
    var cancel = document.querySelector('#visitModal .modal-footer [data-bs-dismiss="modal"]');
    cancel.textContent = previous.cancelLabel;
    cancel.setAttribute('aria-label', previous.cancelLabel);
    $(slot).trigger('modal:form-rendered');
    document.querySelector('#visitModal .modal-body').scrollTop = previous.scrollTop;
    // Other modal hide guards finish before focus returns to the visit input.
    window.setTimeout(function() {
      if (document.documentElement.contains(previous.form)) {
        previous.form.querySelector('[data-country-search]').focus({ preventScroll: true });
      }
    }, 0);
  }

  function load(intent) {
    document.querySelector(slot).textContent = draft.form.dataset.loadingLabel;
    $('#saveVisitButton').prop('disabled', true);
    request = window.ModalInteractions.loadForm({
      url: '/' + document.documentElement.lang + '/visas/new.json',
      data: { start_date: draft.entryDate, end_date: draft.exitDate },
      dataType: 'json', isCurrent: function() { return current(intent); },
      deleteButtonSelector: '#deleteVisitButton', showDeleteButton: false,
      onSuccess: render,
      onError: function() {
        var error = document.createElement('p');
        error.setAttribute('role', 'alert');
        error.textContent = draft.form.dataset.formError;
        var retry = document.createElement('button');
        retry.type = 'button';
        retry.className = 'btn btn-outline-primary';
        retry.textContent = draft.form.dataset.retryLabel;
        retry.addEventListener('click', function() { load(intent); }, { once: true });
        document.querySelector(slot).replaceChildren(error, retry);
        retry.focus({ preventScroll: true });
      }
    });
  }

  $(document).on('click', '#visitModal [data-visit-add-visa]', function(event) {
    event.preventDefault();
    var form = this.closest('form[data-visit-form]');
    if (!form || form.getAttribute('aria-busy') === 'true' || draft) return;
    slot = document.getElementById('calendar-visit-form') ? '#calendar-visit-form' : '#visitModal .modal-body';
    var container = document.querySelector(slot);
    var content = document.createDocumentFragment();
    var cancel = document.querySelector('#visitModal .modal-footer [data-bs-dismiss="modal"]');
    draft = {
      content: content, form: form,
      title: $('#visitModal .modal-title').text(), saveLabel: $('#saveVisitButton').data('save-label') || $('#saveVisitButton').text().trim(),
      showDelete: $('#deleteVisitButton').is(':visible'), cancelLabel: cancel.textContent,
      scrollTop: document.querySelector('#visitModal .modal-body').scrollTop, entryDate: form.querySelector('#visit_entry_date').value,
      exitDate: form.querySelector('#visit_exit_date').value
    };
    while (container.firstChild) content.appendChild(container.firstChild);
    cancel.textContent = form.dataset.backLabel;
    cancel.setAttribute('aria-label', form.dataset.backLabel);
    $('#deleteVisitButton').hide();
    load(++version);
  });

  $(document).on('hide.bs.modal.visitVisa', '#visitModal', function(event) {
    if (!draft) return;
    event.preventDefault();
    restore();
  });

  $(document).on('ajax:beforeSend', '#visitModal form[data-inline-visa-form="true"]', function(event, xhr) {
    var form = this;
    var intent = version;
    form.setAttribute('aria-busy', 'true');
    $('#saveVisitButton').prop('disabled', true).text(form.dataset.savingLabel).attr('aria-label', form.dataset.savingLabel);
    $(form).find('.visa-save-error').remove();
    xhr.done(function(data) {
      if (!data.saved) return;
      if (current(intent)) restore();
      var form = visitForm();
      var info = form && form.querySelector('#entry-date-info');
      if (info) info.hidden = true;
      $('#visitModal').trigger('visit:visa-saved', [refreshInfo]);
    }).fail(function(response) {
      if (!current(intent)) return;
      if (response.status === 422 && response.responseJSON && response.responseJSON.html) {
        render(response.responseJSON);
      } else {
        var error = document.createElement('div');
        error.className = 'visa-save-error alert alert-danger';
        error.setAttribute('role', 'alert');
        error.textContent = response.responseJSON && response.responseJSON.error && response.responseJSON.error.message || form.dataset.saveError;
        form.prepend(error);
      }
    }).always(function() {
      form.removeAttribute('aria-busy');
      if (!document.documentElement.contains(form)) return;
      var button = $('#saveVisitButton');
      button.text(button.data('save-label')).attr('aria-label', button.data('save-label')).prop('disabled', false);
    });
  });
})(window, document, window.jQuery);

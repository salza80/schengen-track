// Keep the calendar document, modal and viewport while Rails recalculates a year.
(function(window, document, $) {
  'use strict';

  var feedbackTimer;
  var refreshVersion = 0;

  function fragment(html) {
    return window.DOMPurify.sanitize(html, { USE_PROFILES: { html: true }, RETURN_DOM_FRAGMENT: true });
  }

  function feedback(message, retry, keepVisible) {
    window.clearTimeout(feedbackTimer);
    var container = document.getElementById('calendar-feedback');
    container.replaceChildren();
    var notice = document.createElement('div');
    notice.className = 'alert mb-0 ' + (retry ? 'alert-warning' : 'alert-success');
    notice.textContent = message;
    if (retry) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'btn btn-outline-primary btn-sm ms-2';
      button.textContent = document.getElementById('calendar-content').dataset.retry;
      button.addEventListener('click', retry, { once: true });
      notice.appendChild(button);
    }
    container.appendChild(notice);
    if (!retry && !keepVisible) feedbackTimer = window.setTimeout(function() { container.replaceChildren(); }, 4000);
  }

  function refresh(afterRefresh, options) {
    var version = ++refreshVersion;
    options = options || {};
    var content = document.getElementById('calendar-content');
    content.setAttribute('aria-busy', 'true');
    if (options.savedVisit) feedback(content.dataset.updating, null, true);
    var root = document.querySelector('.calendar-view-container');
    var url = '/' + document.documentElement.lang + '/my/days';
    return $.ajax({
      url: url + '.json',
      data: { year: root.dataset.selectedYear },
      dataType: 'json',
      cache: false
    }).then(function(data) {
      if (version !== refreshVersion) return;
      if (!data || typeof data.html !== 'string') throw new Error('Missing calendar');
      var content = document.getElementById('calendar-content');
      // Read at response time so a user who scrolls while waiting keeps that position.
      var header = document.querySelector('nav.navbar');
      var headerBottom = header ? header.getBoundingClientRect().bottom : 0;
      var anchor = Array.from(content.querySelectorAll('.day-cell')).find(function(cell) {
        var rect = cell.getBoundingClientRect();
        return rect.top >= headerBottom && rect.top < window.innerHeight;
      });
      var date = anchor && anchor.dataset.date;
      var top = anchor && anchor.getBoundingClientRect().top;
      var scrollY = window.scrollY;
      var returnElement = $('#visitModal').data('focus-return');
      var returnDate = returnElement && returnElement.getAttribute('data-date');
      var focusedDate = document.activeElement && document.activeElement.getAttribute('data-date');
      var html = fragment(data.html);

      content.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function(element) {
        var tooltip = bootstrap.Tooltip.getInstance(element);
        if (tooltip) tooltip.dispose();
      });
      content.replaceChildren(html);
      window.CalendarPresentation.initializeDayNavigation();
      var replacement = date && content.querySelector('[data-date="' + date + '"]');
      window.scrollTo({
        top: replacement ? window.scrollY + replacement.getBoundingClientRect().top - top : scrollY,
        behavior: 'instant'
      });
      if (returnDate) $('#visitModal').data('focus-return', content.querySelector('[data-date="' + returnDate + '"]'));
      if (focusedDate) {
        var focusedCell = content.querySelector('[data-date="' + focusedDate + '"]');
        if (focusedCell) focusedCell.focus({ preventScroll: true });
      }

      document.body.removeAttribute('data-public-calculator-page');
      document.body.dataset.privateCalendar = 'true';
      var destination = new URL(url, window.location.origin);
      var viewer = new URLSearchParams(window.location.search);
      ['year', 'month', 'day'].forEach(function(name) {
        if (viewer.has(name)) destination.searchParams.set(name, viewer.get(name));
      });
      window.history.replaceState({}, '', destination.pathname + destination.search);
      window.CsrfBootstrap.installToken({ token: data.csrf_token });
      window.CalendarPresentation.initializeTooltips();
      window.CalendarInteractions.showDayInfo(window.CalendarInteractions.selectedDate, false);
      window.PublicHeader.refresh();
      content.removeAttribute('aria-busy');
      if (options.savedVisit) feedback(content.dataset.saved);
      else document.getElementById('calendar-feedback').replaceChildren();
      if (afterRefresh) afterRefresh();
    }).fail(function() {
      if (version !== refreshVersion) return;
      content.removeAttribute('aria-busy');
      feedback(options.savedVisit ? content.dataset.savedRefreshError : content.dataset.refreshError, function() { refresh(afterRefresh, options); });
    });
  }

  function showForm(data) {
    document.getElementById('calendar-visit-form').replaceChildren(fragment(data.html));
    document.querySelector('#visitModal .modal-body').scrollTop = 0;
    $('#visitModal .modal-title').text(data.title);
    $('#saveVisitButton').data('save-label', data.save_label).text(data.save_label).attr('aria-label', data.save_label).prop('disabled', false).show();
    $('#calendar-visit-form').trigger('calendar:form-loaded');
  }

  $(document).on('ajax:beforeSend', '#calendar-visit-form form[data-calendar-visit-form="true"]', function(event, xhr) {
    var form = this;
    var version = window.CalendarInteractions.dialogVersion;
    beforeSave.call(form);
    // Follow the request: replacing a dialog cleans up the old form's events.
    xhr.done(function(data) { saved.call(form, data, version); })
      .fail(function(response) { saveFailed.call(form, response, version); })
      .always(function() { completeSave.call(form); });
  });

  function beforeSave() {
    this.setAttribute('aria-busy', 'true');
    $(this).find('.calendar-save-error').remove();
    var label = document.getElementById('calendar-content').dataset.saving;
    $('#saveVisitButton').text(label).attr('aria-label', label).prop('disabled', true);
  }

  function completeSave() {
    this.removeAttribute('aria-busy');
    if (!document.documentElement.contains(this)) return;
    var $button = $('#saveVisitButton');
    $button.text($button.data('save-label')).attr('aria-label', $button.data('save-label')).prop('disabled', false);
  }

  function saved(data, version) {
    if (!data.saved) return;
    // Close the keyboard and modal before measuring the background's viewport.
    var $modal = $('#visitModal');
    var modal = bootstrap.Modal.getInstance($modal.get(0));
    var afterHide = function() {
      refresh(null, { savedVisit: true });
    };
    if (!window.CalendarInteractions.isDialogCurrent(version)) {
      afterHide();
      return;
    }
    $modal.one('hidden.bs.modal.calendarRefresh', afterHide);
    // Fast saves can finish during the opening animation; Bootstrap ignores hide then.
    if (modal._isShown && modal._isTransitioning) {
      $modal.one('shown.bs.modal.calendarRefresh', function() { $modal.modal('hide'); });
    } else {
      $modal.modal('hide');
    }
  }

  function saveFailed(xhr, version) {
    if (!window.CalendarInteractions.isDialogCurrent(version)) return;
    if (xhr.status === 422 && xhr.responseJSON && xhr.responseJSON.html) {
      showForm(xhr.responseJSON);
      return;
    }
    var error = document.createElement('div');
    error.className = 'calendar-save-error alert alert-danger';
    error.setAttribute('role', 'alert');
    var detail = xhr.responseJSON && xhr.responseJSON.error;
    error.textContent = detail && typeof detail.message === 'string' ? detail.message : document.getElementById('calendar-content').dataset.saveError;
    this.prepend(error);
    error.scrollIntoView({ block: 'nearest' });
  }

  $(document).on('ajax:beforeSend', '#calendar-visit-form .nationality-step-form', function() {
    $(this).data('continuation', {
      version: window.CalendarInteractions.dialogVersion,
      entryDate: $(this).find('[name="entry_date"]').val(),
      exitDate: $(this).find('[name="exit_date"]').val()
    });
  });

  $(document).on('ajax:success', '#calendar-visit-form .nationality-step-form', function(event, data) {
    if (!data.selected) return;
    var continuation = $(this).data('continuation');
    $('#visitModal').removeAttr('data-nationality-required');
    if (window.CalendarInteractions.isDialogCurrent(continuation.version)) window.CalendarInteractions.showLoading();
    refresh(function() {
      if (window.CalendarInteractions.isDialogCurrent(continuation.version)) {
        window.CalendarInteractions.openAddModal(continuation.entryDate, continuation.exitDate);
      }
    });
  });

  $(document).on('ajax:error', '#calendar-visit-form .nationality-step-form', function(event, xhr) {
    var continuation = $(this).data('continuation');
    if (!continuation || !window.CalendarInteractions.isDialogCurrent(continuation.version)) return;
    if (xhr.responseJSON && typeof xhr.responseJSON.error === 'string') {
      var error = document.createElement('div');
      error.className = 'alert alert-danger';
      error.setAttribute('role', 'alert');
      error.textContent = xhr.responseJSON.error;
      this.prepend(error);
    }
  });

  window.CalendarRefresh = { refresh: refresh, showForm: showForm };
})(window, document, window.jQuery);

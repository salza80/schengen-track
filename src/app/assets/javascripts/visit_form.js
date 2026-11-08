//= require country_picker
//= require visit_visa_flow
// Initialize server-rendered modal forms without embedding executable code in HTML.
(function(window, document, $) {
  'use strict';

  function initializeForms() {
    document.querySelectorAll('form[data-visit-form]').forEach(function(form) {
      if (form.dataset.visitFormInitialized) return;
      form.dataset.visitFormInitialized = 'true';
      var $form = $(form);
      new App.CountryPicker(form.querySelector('[data-country-picker]'));
      var entry = form.querySelector('#visit_entry_date');
      var exit = form.querySelector('#visit_exit_date');
      var locale = document.documentElement.lang;
      var numbers = new Intl.NumberFormat(locale);
      var plurals = new Intl.PluralRules(locale);
      var units = JSON.parse(form.dataset.durationUnits);
      function updateDuration() {
        exit.min = entry.value || exit.dataset.firstDate;
        var duration = form.querySelector('.visit-duration');
        var start = Date.parse(entry.value + 'T00:00:00Z');
        var finish = Date.parse(exit.value + 'T00:00:00Z');
        if (!Number.isFinite(start) || !Number.isFinite(finish) || finish < start) {
          duration.textContent = '';
          return;
        }
        var days = Math.round((finish - start) / 86400000) + 1;
        var plural = plurals.select(days);
        duration.textContent = form.dataset.durationLabel
          .replace('__DAYS__', numbers.format(days))
          .replace('__UNIT__', units[plural] || units.other);
      }
      $(entry).add(exit).on('input change', updateDuration);
      updateDuration();
      var maxStayRequest;
      var info = form.querySelector('#entry-date-info');
      if (!info) return;

      function updateEntryInfo(result) {
        var details = result.entry_info;
        var daysUsed = info.querySelector('[data-entry-days-used]');
        var visa = info.querySelector('[data-entry-visa]');
        var entries = info.querySelector('[data-entry-visa-entries]');
        daysUsed.textContent = details ? details.days_used : '';
        daysUsed.classList.toggle('text-danger-emphasis', !!(details && details.overstay));
        visa.hidden = !details || !details.visa_status;
        info.querySelector('[data-entry-visa-status]').textContent = details ? details.visa_status || '' : '';
        visa.classList.toggle('text-danger-emphasis', !!(details && details.visa_missing));
        info.querySelector('[data-visit-add-visa]').hidden = !details || !details.visa_missing;
        entries.hidden = !details || !details.visa_entries;
        entries.textContent = details ? details.visa_entries || '' : '';
        entries.classList.toggle('text-danger-emphasis', !!(details && details.visa_entries_exceeded));
        ['overstay', 'wait'].forEach(function(kind) {
          var warning = info.querySelector('[data-entry-' + kind + ']');
          warning.textContent = details ? details[kind] || '' : '';
          warning.hidden = !details || !details[kind];
        });
        var departure = result.departure_info;
        info.querySelector('[data-departure-info]').hidden = !departure;
        info.querySelector('[data-departure-days-used]').textContent = departure ? departure.days_used : '';
        info.querySelector('[data-departure-remaining]').textContent = departure ? departure.remaining : '';
        var departureWarning = info.querySelector('[data-departure-overstay]');
        departureWarning.textContent = departure ? departure.overstay || '' : '';
        departureWarning.hidden = !departure || !departure.overstay;
        info.querySelector('[data-entry-allowance]').hidden = !result.show || result.max_days <= 0;
        info.hidden = !details && (!result.show || result.max_days <= 0);
      }

      function updateMaxStayInfo() {
        var countryCode = $form.find('#visit_country_code').val();
        if (maxStayRequest) maxStayRequest.abort();
        info.hidden = true;
        if (!entry.value || !entry.validity.valid) return;
        var data = { date: entry.value };
        if (exit.value && exit.validity.valid) data.exit_date = exit.value;
        if (countryCode) data.country_code = countryCode;
        if (form.dataset.visitId) data.visit_id = form.dataset.visitId;
        maxStayRequest = $.ajax({
          url: '/' + document.documentElement.lang + '/visits/max_stay_info',
          data: data,
          dataType: 'json',
          success: function(result) {
            updateEntryInfo(result);
            if (!result.show || result.max_days <= 0) return;
            var parts = form.dataset.daysUntil.replace('__DAYS__', numbers.format(result.max_days)).split('__DATE__');
            var $message = $form.find('#max-stay-info').empty();
            $message.append(document.createTextNode(parts[0]));
            var $link = $('<a>', { href: '#', class: 'exit-date-link' }).text(result.exit_date);
            $link.css({ textDecoration: 'underline', color: 'inherit', cursor: 'pointer' });
            $link.on('click', function(event) {
              event.preventDefault();
              $form.find('#visit_exit_date').val(result.exit_date_iso).trigger('change');
            });
            $message.append($link, document.createTextNode(parts.slice(1).join('__DATE__')));
            if (result.constrained) {
              if (result.constraint_type === 'schengen') {
                $message.append(document.createTextNode(' ' + form.dataset.schengenConstraint));
              } else if (result.constraint_type === 'next_visit') {
                $message.append(document.createTextNode(' ' + form.dataset.nextVisitConstraint.replace('__DATE__', result.next_entry_date)));
              }
            }
          },
          error: function() { info.hidden = true; }
        });
      }

      $form.find('#visit_entry_date, #visit_exit_date, #visit_country_code')
        .on('change', updateMaxStayInfo);
      $form.on('visit:refresh-info', updateMaxStayInfo);
      updateMaxStayInfo();
    });
  }

  document.addEventListener('DOMContentLoaded', initializeForms);
  $(document).ajaxSuccess(initializeForms);
  $(document).on('modal:form-rendered', initializeForms);
})(window, document, window.jQuery);

//= require country_picker
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

      function updateMaxStayInfo() {
        var countryCode = $form.find('#visit_country_code').val();
        if (maxStayRequest) maxStayRequest.abort();
        $form.find('#entry-date-info').hide();
        if (!entry.value || !entry.validity.valid) return;
        var data = { date: entry.value };
        if (countryCode) data.country_code = countryCode;
        if (form.dataset.visitId) data.visit_id = form.dataset.visitId;
        maxStayRequest = $.ajax({
          url: '/' + document.documentElement.lang + '/visits/max_stay_info',
          data: data,
          dataType: 'json',
          success: function(result) {
            if (!result.show || result.max_days <= 0) {
              $form.find('#entry-date-info').hide();
              return;
            }
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
            $form.find('#entry-date-info').show();
          },
          error: function() { $form.find('#entry-date-info').hide(); }
        });
      }

      $form.find('#visit_entry_date, #visit_country_code')
        .on('change', updateMaxStayInfo);
      updateMaxStayInfo();
    });
  }

  document.addEventListener('DOMContentLoaded', initializeForms);
  $(document).ajaxSuccess(initializeForms);
  $(document).on('calendar:form-loaded', initializeForms);
})(window, document, window.jQuery);

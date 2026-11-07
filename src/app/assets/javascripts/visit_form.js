// Initialize server-rendered modal forms without embedding executable code in HTML.
(function(window, document, $) {
  'use strict';

  function initializeForms() {
    document.querySelectorAll('form[data-visit-form]').forEach(function(form) {
      if (form.dataset.visitFormInitialized) return;
      form.dataset.visitFormInitialized = 'true';
      var $form = $(form);
      new App.Cascade($form.find('[data-continent-selector]'), $form.find('#visit_country_id'),
        JSON.parse(form.dataset.countryOptions), 'country_code', 'name', 'continent_code');

      function updateMaxStayInfo() {
        var year = $form.find('#visit_entry_date_1i').val();
        var month = $form.find('#visit_entry_date_2i').val();
        var day = $form.find('#visit_entry_date_3i').val();
        var countryCode = $form.find('#visit_country_id').val();
        if (!year || !month || !day) return;
        var data = { date: year + '-' + month.padStart(2, '0') + '-' + day.padStart(2, '0') };
        if (countryCode) data.country_code = countryCode;
        if (form.dataset.visitId) data.visit_id = form.dataset.visitId;
        $.ajax({
          url: '/' + document.documentElement.lang + '/visits/max_stay_info',
          data: data,
          dataType: 'json',
          success: function(result) {
            if (!result.show || result.max_days <= 0) {
              $form.find('#entry-date-info').hide();
              return;
            }
            var parts = form.dataset.daysUntil.replace('__DAYS__', result.max_days).split('__DATE__');
            var $message = $form.find('#max-stay-info').empty();
            $message.append(document.createTextNode(parts[0]));
            var $link = $('<a>', { href: '#', class: 'exit-date-link' }).text(result.exit_date);
            $link.css({ textDecoration: 'underline', color: 'inherit', cursor: 'pointer' });
            $link.on('click', function(event) {
              event.preventDefault();
              var date = result.exit_date_iso.split('-');
              $form.find('#visit_exit_date_1i').val(date[0]);
              $form.find('#visit_exit_date_2i').val(parseInt(date[1], 10));
              $form.find('#visit_exit_date_3i').val(parseInt(date[2], 10));
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

      $form.find('#visit_entry_date_1i, #visit_entry_date_2i, #visit_entry_date_3i, #visit_country_id')
        .on('change', updateMaxStayInfo);
      updateMaxStayInfo();
    });
  }

  document.addEventListener('DOMContentLoaded', initializeForms);
  $(document).ajaxSuccess(initializeForms);
  $(document).on('calendar:form-loaded', initializeForms);
})(window, document, window.jQuery);

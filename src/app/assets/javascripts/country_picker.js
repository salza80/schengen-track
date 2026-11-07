// Searchable country control; only a catalogue country code is submitted.
(function(window) {
  'use strict';

  window.App.CountryPicker = function(form, countries) {
    var input = form.querySelector('#visit_country_search');
    var code = form.querySelector('#visit_country_id');
    var list = form.querySelector('#visit_country_results');
    var status = form.querySelector('#visit_country_status');
    var locale = document.documentElement.lang;
    var active = -1;
    var matches = [];

    function normalized(value) {
      return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase(locale).trim();
    }

    function close() {
      list.hidden = true;
      input.setAttribute('aria-expanded', 'false');
      input.removeAttribute('aria-activedescendant');
      status.textContent = '';
      active = -1;
    }

    function setCode(country) {
      var next = country ? country.country_code : '';
      var changed = code.value !== next;
      code.value = next;
      input.setCustomValidity(next ? '' : form.dataset.countryRequired);
      if (changed) code.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function choose(country) {
      input.value = country.name;
      setCode(country);
      close();
    }

    function highlight(index) {
      active = Math.max(0, Math.min(matches.length - 1, index));
      Array.from(list.children).forEach(function(option, position) {
        option.classList.toggle('active', position === active);
        option.setAttribute('aria-selected', position === active ? 'true' : 'false');
      });
      var option = list.children[active];
      if (!option) return;
      input.setAttribute('aria-activedescendant', option.id);
      if (option.offsetTop < list.scrollTop) list.scrollTop = option.offsetTop;
      if (option.offsetTop + option.offsetHeight > list.scrollTop + list.clientHeight) {
        list.scrollTop = option.offsetTop + option.offsetHeight - list.clientHeight;
      }
    }

    function search() {
      var query = normalized(input.value);
      matches = countries.filter(function(country) { return normalized(country.name).includes(query); });
      var nodes = document.createDocumentFragment();
      matches.forEach(function(country) {
        var option = document.createElement('div');
        option.id = 'visit-country-option-' + country.country_code;
        option.className = 'list-group-item list-group-item-action';
        option.setAttribute('role', 'option');
        option.setAttribute('aria-selected', 'false');
        option.textContent = country.name;
        // Keep focus on the combobox through touch, pen and mouse selection.
        option.addEventListener('pointerdown', function(event) { event.preventDefault(); });
        option.addEventListener('mousedown', function(event) { event.preventDefault(); });
        option.addEventListener('click', function() { choose(country); });
        nodes.appendChild(option);
      });
      list.replaceChildren(nodes);
      list.hidden = false;
      input.setAttribute('aria-expanded', 'true');
      status.textContent = matches.length ? form.dataset.countryResults.replace('__COUNT__', String(matches.length)) : form.dataset.countryNoMatches;
      active = -1;
      input.removeAttribute('aria-activedescendant');
    }

    var selected = countries.find(function(country) { return country.country_code === code.value; });
    if (selected) input.value = selected.name;
    setCode(selected);
    input.addEventListener('focus', search);
    input.addEventListener('input', function() {
      var exact = countries.find(function(country) { return normalized(country.name) === normalized(input.value); });
      setCode(exact);
      search();
    });
    input.addEventListener('blur', close);
    input.addEventListener('keydown', function(event) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        event.stopPropagation();
        if (list.hidden) search();
        if (matches.length) highlight(active < 0 ? (event.key === 'ArrowDown' ? 0 : matches.length - 1) : active + (event.key === 'ArrowDown' ? 1 : -1));
      } else if (event.key === 'Enter' && !list.hidden) {
        event.preventDefault();
        if (matches.length) choose(matches[active < 0 ? 0 : active]);
      } else if (event.key === 'Escape' && !list.hidden) {
        event.preventDefault();
        event.stopPropagation();
        close();
      }
    });
  };
})(window);

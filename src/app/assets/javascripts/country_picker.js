// Searchable country control; only a catalogue country code is submitted.
(function(window) {
  'use strict';

  window.App.CountryPicker = function(root) {
    var countries = JSON.parse(root.dataset.countryOptions);
    var input = root.querySelector('[data-country-search]');
    var code = root.querySelector('[data-country-value]');
    var list = root.querySelector('[data-country-results]');
    var status = root.querySelector('[data-country-status]');
    var clear = root.querySelector('[data-country-clear]');
    var locale = document.documentElement.lang;
    var active = -1;
    var matches = [];
    var dismissed = false;

    function updateClearButton() {
      clear.hidden = !input.value;
    }

    function normalized(value) {
      return value.toLocaleLowerCase(locale).normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
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
      input.setCustomValidity(next ? '' : root.dataset.requiredMessage);
      if (changed) code.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function choose(country) {
      input.value = country.name;
      updateClearButton();
      setCode(country);
      close();
      dismissed = true;
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
      dismissed = false;
      var query = normalized(input.value);
      var codeQuery = input.value.trim().toUpperCase();
      matches = countries.map(function(country) {
        var name = normalized(country.name);
        var rank = country.country_code === codeQuery ? 0 : name.startsWith(query) ? 1 : name.includes(query) ? 2 : -1;
        return { country: country, rank: rank };
      }).filter(function(match) { return match.rank >= 0; })
        .sort(function(left, right) { return left.rank - right.rank; })
        .map(function(match) { return match.country; });
      var nodes = document.createDocumentFragment();
      matches.forEach(function(country) {
        var option = document.createElement('div');
        option.id = list.id + '-option-' + country.country_code;
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
      list.scrollTop = 0;
      list.hidden = false;
      input.setAttribute('aria-expanded', 'true');
      status.textContent = matches.length ? root.dataset.resultsLabel.replace('__COUNT__', new Intl.NumberFormat(locale).format(matches.length)) : root.dataset.noMatches;
      active = -1;
      input.removeAttribute('aria-activedescendant');
    }

    var selected = countries.find(function(country) { return country.country_code === code.value; });
    if (selected) input.value = selected.name;
    setCode(selected);
    updateClearButton();
    input.addEventListener('focus', function() { if (!dismissed) search(); });
    input.addEventListener('click', function() { if (list.hidden) search(); });
    input.addEventListener('input', function() {
      updateClearButton();
      var exact = countries.find(function(country) { return normalized(country.name) === normalized(input.value); });
      setCode(exact);
      search();
    });
    input.addEventListener('blur', close);
    clear.addEventListener('click', function() {
      input.value = '';
      updateClearButton();
      setCode(null);
      input.focus({ preventScroll: true });
      search();
    });
    input.addEventListener('keydown', function(event) {
      if (event.isComposing || event.keyCode === 229) return;
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        event.stopPropagation();
        if (list.hidden) search();
        if (matches.length) highlight(active < 0 ? (event.key === 'ArrowDown' ? 0 : matches.length - 1) : active + (event.key === 'ArrowDown' ? 1 : -1));
      } else if (event.key === 'Enter' && !list.hidden) {
        event.preventDefault();
        if (active >= 0) choose(matches[active]);
        else if (code.value) {
          choose(countries.find(function(country) { return country.country_code === code.value; }));
        }
      } else if (event.key === 'Escape' && !list.hidden) {
        event.preventDefault();
        event.stopPropagation();
        close();
        dismissed = true;
      }
    });
  };
})(window);

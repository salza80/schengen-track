// Pure matching rules shared by suggestion filtering and exact-name validation.
(function(window) {
  'use strict';

  window.App.CountrySearch = function(countries, locale) {
    var collator = new Intl.Collator(locale, { sensitivity: 'base' });

    function normalize(value) {
      return value.toLocaleLowerCase(locale).normalize('NFD')
        // Fold Latin accents and Arabic vowel/hamza marks, preserving Indic vowels.
        .replace(/[\u0300-\u036f\u0640\u064b-\u065f\u0670]/g, '')
        .replace(/[\u2018\u2019\u02bc]/g, "'")
        .replace(/[\u2010-\u2015\u2212]/g, '-')
        .replace(/\s+/g, ' ').trim();
    }

    var entries = countries.map(function(country) {
      var names = [normalize(country.name)];
      if (locale.split('-')[0] === 'de') {
        var substitutions = { 'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss' };
        var expanded = country.name.toLocaleLowerCase(locale).replace(/[äöüß]/g, function(letter) {
          return substitutions[letter];
        });
        var alternative = normalize(expanded);
        if (alternative !== names[0]) names.push(alternative);
      }
      return { country: country, names: names };
    }).sort(function(left, right) { return collator.compare(left.country.name, right.country.name); });

    this.exact = function(value) {
      var query = normalize(value);
      var entry = entries.find(function(candidate) { return candidate.names.includes(query); });
      return entry && entry.country;
    };

    this.matches = function(value) {
      var query = normalize(value);
      var code = value.trim().toUpperCase();
      return entries.map(function(entry) {
        var rank = -1;
        if (entry.country.country_code === code) rank = 0;
        else if (entry.names.some(function(name) { return name.startsWith(query); })) rank = 1;
        else if (entry.names.some(function(name) { return name.includes(query); })) rank = 2;
        return { country: entry.country, rank: rank };
      }).filter(function(match) { return match.rank >= 0; })
        .sort(function(left, right) { return left.rank - right.rank; })
        .map(function(match) { return match.country; });
    };
  };
})(window);

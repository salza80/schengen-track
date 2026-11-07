import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = fs.readFileSync(path.join(__dirname, '../../src/app/assets/javascripts/country_picker/search.js'), 'utf8');
type Country = { country_code: string; name: string };
function matcher(countries: Country[], locale: string) {
  const window: any = { App: {} };
  vm.runInNewContext(script, { window, Intl });
  return new window.App.CountrySearch(countries, locale);
}

test.each([
  ['en', 'United States', 'United\u00a0States', 'US'],
  ['de', 'Österreich', 'Oesterreich', 'AT'],
  ['de', 'Türkei', 'Tuerkei', 'TR'],
  ['de', 'Weißrussland', 'Weissrussland', 'BY'],
  ['fr', "Côte d'Ivoire", 'cote d’ivoire', 'CI'],
  ['fr', 'États-Unis', 'Etats‑Unis', 'US'],
  ['es', 'España', 'espana', 'ES'],
  ['pt-BR', 'São Tomé e Príncipe', 'sao tome e principe', 'ST'],
  ['tr', 'İrlanda', 'irlanda', 'IE'],
  ['hi', 'भारत', 'भारत', 'IN'],
  ['ar', 'ألمانيا', 'المانيا', 'DE'],
  ['ar', 'الإمارات العربية المتحدة', 'الامارات العربية المتحدة', 'AE'],
  ['ar', 'ألمانيا', 'أَلْمَانِيَا', 'DE'],
  ['zh-CN', '美国', '美国', 'US']
])('%s accepts %s typed as %s without changing its label or code', (locale, name, query, code) => {
  const country = { country_code: code, name };
  const search = matcher([country], locale);
  expect(search.matches(query)).toEqual([country]);
  expect(search.exact(query)).toBe(country);
  expect(country).toEqual({ country_code: code, name });
});

test('Hindi vowel signs are preserved rather than broadly stripping Unicode marks', () => {
  const search = matcher([{ country_code: 'IN', name: 'भारत' }], 'hi');
  expect(search.matches('भरत')).toEqual([]);
  expect(search.exact('भरत')).toBeUndefined();
});

test('suggestions use locale collation without reordering the source catalogue', () => {
  const countries = [
    { country_code: 'ES', name: 'Spanien' },
    { country_code: 'AT', name: 'Österreich' },
    { country_code: 'AU', name: 'Australien' }
  ];
  expect(matcher(countries, 'de').matches('').map((country: Country) => country.country_code)).toEqual(['AU', 'AT', 'ES']);
  expect(countries.map(country => country.country_code)).toEqual(['ES', 'AT', 'AU']);
});

test('ISO matches and prefixes outrank substrings while partial input remains invalid', () => {
  const search = matcher([
    { country_code: 'DZ', name: 'Algeria' },
    { country_code: 'DE', name: 'Germany' },
    { country_code: 'AU', name: 'Australia' },
    { country_code: 'US', name: 'United States' }
  ], 'en');
  expect(search.matches('ger').map((country: Country) => country.country_code)).toEqual(['DE', 'DZ']);
  expect(search.matches('us')[0].country_code).toBe('US');
  expect(search.exact('ger')).toBeUndefined();
  expect(search.exact('US')).toBeUndefined();
});

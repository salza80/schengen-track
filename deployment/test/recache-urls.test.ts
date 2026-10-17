import * as path from 'path';
import * as fs from 'fs';

const { buildUrls } = require('../scripts/recache_urls.cjs');

test.each(['prod', 'staging'])('warm-up covers public pages and eligible nationalities for %s', environment => {
  const origin = environment === 'prod' ? 'https://schengen-calculator.com' : 'https://test.schengen-calculator.com';
  const profile = environment === 'prod' ? 'full' : 'sample';
  const urls: string[] = buildUrls(path.join(__dirname, `../scripts/urls-${environment}.txt`), { profile });
  expect(new Set(urls).size).toBe(urls.length);
  expect(urls.every(url => new URL(url).origin === origin)).toBe(true);
  expect(urls).toContain(`${origin}/api/docs`);
  expect(urls).toContain(`${origin}/`);
  expect(urls).toContain(`${origin}/visits`);
  expect(urls).toContain(`${origin}/days`);
  expect(urls).toContain(`${origin}/blog/extended-schengen-stay`);
  expect(urls).toContain(`${origin}/about/American`);
  expect(urls).toContain(`${origin}/en/about/American`);
  if (profile === 'sample') {
    expect(urls.filter(url => url.includes('/about/')).every(url => url.endsWith('/American'))).toBe(true);
  }

  const catalogDirectory = path.join(__dirname, '../../src/config/country_catalog');
  for (const file of fs.readdirSync(catalogDirectory)) {
    const { locale } = JSON.parse(fs.readFileSync(path.join(catalogDirectory, file), 'utf8'));
    expect(urls).toContain(`${origin}/sitemap-${locale}.xml`);
    expect(urls).toContain(`${origin}/${locale}`);
    for (const page of ['privacy', 'disclaimer', 'datadeletion', 'visits', 'days', 'about', 'blog/extended-schengen-stay']) {
      expect(urls).toContain(`${origin}/${locale}/${page}`);
    }
    expect(urls).toContain(`${origin}/${locale}/about/American`);
    if (profile === 'full') {
      expect(urls).toContain(`${origin}/${locale}/about/Brazilian`);
      expect(urls).toContain(`${origin}/${locale}/about/Sri_Lankan`);
    }
    expect(urls).not.toContain(`${origin}/${locale}/about/Portuguese`);
    expect(urls).not.toContain(`${origin}/${locale}/about/German`);
    expect(urls).not.toContain(`${origin}/${locale}/about/`);
  }
});

test('warm-up rejects misspelled profiles', () => {
  expect(() => buildUrls('', { profile: 'sampl' })).toThrow('Unknown warm-up profile');
});

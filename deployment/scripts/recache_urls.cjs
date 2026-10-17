const fs = require('node:fs');
const path = require('node:path');

// Declare each route once; catalogue locales supply all language variants.
const PUBLIC_PAGE_PATHS = [
  '', '/visits', '/days', '/about', '/blog/extended-schengen-stay',
  '/privacy', '/disclaimer', '/datadeletion'
];
const PUBLIC_DOCUMENT_PATHS = [
  '/sitemap.xml', '/favicon.ico', '/robots.txt', '/llms.txt',
  '/llms-full.txt', '/openapi.json', '/ads.txt', '/api/docs'
];

// Use the same generated presentation data and English nationality slugs as
// AboutController. Translated country names are labels, not URL slugs.
function buildUrls(listFile, { profile = 'full', catalogDirectory = path.resolve(__dirname, '../../src/config/country_catalog') } = {}) {
  if (!['full', 'sample'].includes(profile)) throw new Error(`Unknown warm-up profile: ${profile}`);
  const hostname = fs.readFileSync(listFile, 'utf8').trim();
  if (!/^[a-z0-9.-]+$/i.test(hostname)) throw new Error('Warm-up target must contain one hostname');
  const origin = `https://${hostname}`;
  const urls = new Set(PUBLIC_DOCUMENT_PATHS.map(route => `${origin}${route}`));
  const files = fs.readdirSync(catalogDirectory).filter(file => file.endsWith('.json')).sort();
  if (!files.length) throw new Error('No country catalogues found');

  for (const file of files) {
    const { locale, countries } = JSON.parse(fs.readFileSync(path.join(catalogDirectory, file), 'utf8'));
    urls.add(`${origin}/sitemap-${locale}.xml`);
    // Both /about/... and /en/about/... are independently cached routes.
    const prefixes = locale === 'en' ? ['', '/en'] : [`/${locale}`];
    for (const prefix of prefixes) {
      for (const route of PUBLIC_PAGE_PATHS) {
        const pathname = `${prefix}${route}` || '/';
        urls.add(`${origin}${pathname}`);
      }
      for (const country of countries) {
        if (country.visa_required === 'F' || !country.base_nationality.trim()) continue;
        if (profile === 'sample' && country.country_code !== 'US') continue;
        const slug = encodeURIComponent(country.base_nationality.replaceAll(' ', '_'));
        urls.add(`${origin}${prefix}/about/${slug}`);
      }
    }
  }
  return [...urls];
}

if (require.main === module) {
  process.stdout.write(buildUrls(process.argv[2], { profile: process.argv[3] || 'full' }).join('\n') + '\n');
}

module.exports = { buildUrls };

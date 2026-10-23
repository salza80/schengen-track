# Font Awesome Free 7.3.1

Source: the official `@fortawesome/fontawesome-free@7.3.1` npm package.
https://www.npmjs.com/package/@fortawesome/fontawesome-free/v/7.3.1

The upstream Sass files are included here, with the solid, regular and brands
WOFF2 files in `../../fonts/font-awesome/`. See LICENSE.txt for the font, icon
and code licenses. No CDN, Kit or Node build step is required.

Local integration: only the `src` declarations in solid.scss, regular.scss and
brands.scss are patched to use Sprockets' `font-url` helper. This ensures font
URLs include their content fingerprints. The application wrapper configures
`font-display: swap` and imports these Sass modules with Dart Sass.

To update, download the pinned official npm tarball, verify its SHA-512 against
the registry's `dist.integrity`, replace the Sass files and the three WOFF2
files, and reapply those three `font-url` changes. Update this version and the
license, compile production assets, and verify the fonts, icon aliases and
spacing on desktop and mobile. Keep Font Awesome 7's fixed icon canvas unless
a specific component needs its `fa-width-auto` utility.

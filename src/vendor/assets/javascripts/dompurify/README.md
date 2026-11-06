# DOMPurify 3.4.17

Source: https://github.com/cure53/DOMPurify/tree/3.4.17

The signed upstream tag resolves to commit
`a77a3e78b59f72fa4d1c83f22e121ad9cc7d3575`. `purify.js` is the upstream
`dist/purify.js`, with the source-map directive removed because the map is not
shipped. The Apache 2.0 license is included in `LICENSE`.

Local SHA-256 for `purify.js`:
`28169f99ccbf663f59d4ba77b7fff2176e77cfd0f5855ed981804d7a21d0edeb`.

Sprockets includes this local copy in `core.js` before `public_header.js`;
there is no CDN dependency or Node build step. The header sanitizer permits
only its required tags and attributes, then restricts links and forms to its
localized application routes. Flash messages bypass HTML parsing entirely.

To update, select a maintained upstream release, verify its tag and commit in
the official repository, replace `dist/purify.js` and the license, remove the
source-map directive, and update the version, commit and checksum here. Run the
header JavaScript tests, Rails header integration tests, header security browser
tests, and production asset compilation. These vendored files require manual
security updates; Dependabot does not update this copy.

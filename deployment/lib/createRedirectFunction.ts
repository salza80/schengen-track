// a CloudFront function to rewrite from altDomain to targetDomain
export function createRedirectFunction(altDomain: string, targetDomain: string): string {
  return `
    function querySuffix(querystring) {
      var parts = [];
      var names = Object.keys(querystring);

      for (var i = 0; i < names.length; i++) {
        var name = names[i];
        var parameter = querystring[name];
        var values = parameter.multiValue || [{ value: parameter.value }];

        for (var j = 0; j < values.length; j++) {
          parts.push(encodeURIComponent(name) + '=' + encodeURIComponent(values[j].value || ''));
        }
      }

      return parts.length ? '?' + parts.join('&') : '';
    }

    function handler(event) {
      var request = event.request;
      var headers = request.headers;
      var host = headers.host.value;
      if (event.viewer && event.viewer.ip) {
        headers['x-schengen-client-ip'] = { value: event.viewer.ip };
      }

      // Navigate to the private confirmation before any cached HTML renders.
      // A URI rewrite alone keeps the bearer in the browser's address bar and
      // does not select the calculation-link cache behavior.
      if (/^\\/(?:[^\\/]+\\/)?(?:days|visits)$/.test(request.uri) &&
          (request.method === 'GET' || request.method === 'HEAD')) {
        var guestCalculation = request.querystring.guest_calculation;
        if (guestCalculation) {
          var token = guestCalculation.value;
          if (guestCalculation.multiValue) {
            token = guestCalculation.multiValue.length === 1 ? guestCalculation.multiValue[0].value : '';
          }
          if (typeof token !== 'string' || token.length > 2048) token = '';
          return {
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
              'location': { value: 'https://${targetDomain}/calculations/' + encodeURIComponent(token || 'invalid-token') },
              'cache-control': { value: 'private, no-store' },
              'referrer-policy': { value: 'no-referrer' }
            }
          };
        }
      }

      // Redirect the alternate hostname and the retired generic Portuguese
      // locale directly to their canonical replacement in a single hop.
      var targetUri = request.uri;
      if (/^\\/pt(?:\\/|$)/.test(targetUri)) {
        var portuguesePath = targetUri.substring(3);
        targetUri = '/pt-BR' + (portuguesePath === '/' ? '' : portuguesePath);
      }

      if (host === '${altDomain}' || targetUri !== request.uri) {
        return {
          statusCode: 301,
          statusDescription: 'Permanently Moved',
          headers: 
          { "location": { "value": 'https://${targetDomain}' + targetUri + querySuffix(request.querystring) }}
        };
      }

      // Public calculator cache keys must never vary with session cookies.
      // Private calculator pages have separate explicitly uncached behaviors.
      if ((request.method === 'GET' || request.method === 'HEAD') &&
          /^\\/(?:en\\/|de\\/|es\\/|fr\\/|ar\\/|hi\\/|pt-BR\\/|tr\\/|zh-CN\\/)?(?:visits|days)$/.test(request.uri)) {
        request.cookies = {};
      }

      // Calendar presentation parameters stay in the viewer URL for the
      // browser, but only one normalized year reaches the cache key/origin.
      if (/^\\/(?:en\\/|de\\/|es\\/|fr\\/|ar\\/|hi\\/|pt-BR\\/|tr\\/|zh-CN\\/)?days$/.test(request.uri)) {
        var currentYear = new Date().getUTCFullYear();
        var yearValue = request.querystring.year && request.querystring.year.value;
        var year = /^\\d{4}$/.test(yearValue || '') ? parseInt(yearValue, 10) : currentYear;
        year = Math.max(currentYear - 20, Math.min(currentYear + 20, year));
        request.querystring = { year: { value: String(year) } };
      }

      // Continue with the request as is
      return request;
    }
  `;
}

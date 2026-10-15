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

      // Calendar presentation parameters stay in the viewer URL for the
      // browser, but only one normalized year reaches the cache key/origin.
      if (/^\\/(?:[^\\/]+\\/)?days$/.test(request.uri)) {
        var guestCalculation = request.querystring.guest_calculation;
        if (guestCalculation && guestCalculation.value) {
          request.uri = '/calculations/' + encodeURIComponent(guestCalculation.value);
          request.querystring = {};
          return request;
        }

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

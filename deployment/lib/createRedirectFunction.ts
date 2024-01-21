// a couldfront function to rewrite from altDomain to targetDomain
export function createRedirectFunction(altDomain: string, targetDomain: string): string {
  return `
    function handler(event) {
      var request = event.request;
      var headers = request.headers;
      var host = request.headers.host.value;

      // Check if the request is coming from altDomain
      if (host === '${altDomain}') {
        // Redirect to targetDomain
        return {
          status: 302,
          statusDescription: 'Found',
          headers: 
          { "location": { "value": 'https://${targetDomain}' }}
        };
      }

      // Continue with the request as is
      return request;
    }
  `;
}

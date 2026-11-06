// Auth routes need verified viewer identity without host or locale redirects.
export function createClientIpFunction(): string {
  return `function handler(event) {
    var request = event.request;
    request.headers['x-schengen-client-ip'] = { value: event.viewer.ip };
    return request;
  }`;
}

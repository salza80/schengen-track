// a couldfront function to rewrite from altDomain to targetDomain
export function createRedirectFunction(altDomain: string, targetDomain: string): string {
    return `
        function handler(event) {
            const request = event.request;
            const headers = request.headers;

            // Check if the request is coming from altDomain
            if (headers.host && headers.host[0].value === '${altDomain}') {
                // Redirect to targetDomain
                return {
                    status: '301',
                    statusDescription: 'Moved Permanently',
                    headers: {
                        location: [{
                            key: 'Location',
                            value: 'https://${targetDomain}' + request.uri,
                        }],
                    },
                };
            }

            // Continue with the request as is
            return request;
        }
    `;
}


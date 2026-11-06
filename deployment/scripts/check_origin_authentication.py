"""Read-only deployment gate: both direct API origins must reject forged identity."""
import json
import re
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check(outputs):
    opener = urllib.request.build_opener(NoRedirect())
    values = {item['OutputKey']: item['OutputValue'] for item in outputs}
    for key, path in [('RailsOriginUrl', 'openapi.json'), ('McpOriginUrl', 'mcp')]:
        origin = values[key]
        if not re.fullmatch(r'https://[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com/?', origin):
            raise ValueError(f'Unexpected {key} endpoint')
        data = b'{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' if key == 'McpOriginUrl' else None
        request = urllib.request.Request(origin.rstrip('/') + '/' + path, data=data, headers={
            'X-Schengen-Origin-Auth': 'retired-bearer',
            'X-Schengen-Client-Ip': '192.0.2.99',
            'Content-Type': 'application/json',
        })
        try:
            with opener.open(request, timeout=30) as response:
                status = response.status
        except urllib.error.HTTPError as error:
            with error:
                status = error.code
        if status != 403:
            raise RuntimeError(f'{key} accepted an unsigned request: HTTP {status}')
        print(f'{key}: unsigned forged-identity request rejected (403)')


if __name__ == '__main__':
    with open(sys.argv[1]) as source:
        check(json.load(source))

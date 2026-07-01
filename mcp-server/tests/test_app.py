import importlib
import json
import os
import sys
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import app


class AppTest(unittest.TestCase):
    def setUp(self):
        os.environ.pop("SCHENGEN_API_BASE_URL", None)
        os.environ.pop("SCHENGEN_MCP_UPSTREAM_TIMEOUT_SECONDS", None)
        self.app = importlib.reload(app)

    def test_tools_list_exposes_create_calculation(self):
        response = self.app.lambda_handler(json_rpc_event("tools/list", {}), None)
        body = json.loads(response["body"])

        tools = body["result"]["tools"]
        self.assertEqual("create_schengen_calculation", tools[0]["name"])
        self.assertIn("inputSchema", tools[0])

    def test_create_schengen_calculation_posts_to_rails_api(self):
        os.environ["SCHENGEN_API_BASE_URL"] = "https://example.test"
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, _type, _value, _traceback):
                return None

            def read(self):
                return json.dumps({"status": "ok", "web_url": "https://example.test/en/days"}).encode("utf-8")

        def fake_urlopen(request, timeout):
            captured["url"] = request.full_url
            captured["timeout"] = timeout
            captured["body"] = json.loads(request.data.decode("utf-8"))
            return FakeResponse()

        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            result = self.app.create_schengen_calculation(
                user={"first_name": "Sam"},
                trips=[{"country": "France", "entry_date": "2026-01-01", "exit_date": "2026-01-10"}],
            )

        self.assertEqual("ok", result["status"])
        self.assertEqual("https://example.test/api/v1/calculations", captured["url"])
        self.assertEqual(10, captured["timeout"])
        self.assertEqual([], captured["body"]["visas"])

    def test_create_schengen_calculation_returns_clear_upstream_error(self):
        def fake_urlopen(_request, timeout):
            raise urllib.error.HTTPError(
                url="https://example.test/api/v1/calculations",
                code=413,
                msg="Payload Too Large",
                hdrs={},
                fp=Body(b'{"error":{"code":"too_many_trips","limit":50}}'),
            )

        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            result = self.app.create_schengen_calculation(user={"first_name": "Sam"}, trips=[])

        self.assertEqual("error", result["status"])
        self.assertEqual(413, result["http_status"])
        self.assertEqual("too_many_trips", result["error"]["error"]["code"])


def json_rpc_event(method, params):
    return {
        "requestContext": {"http": {"method": "POST"}},
        "body": json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}),
    }


class Body:
    def __init__(self, value):
        self.value = value

    def read(self):
        return self.value

    def close(self):
        return None


if __name__ == "__main__":
    unittest.main()

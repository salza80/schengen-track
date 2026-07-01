import importlib
import json
import os
import sys
import types
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
        os.environ.pop("SCHENGEN_AGENT_AUTH_HEADER", None)
        os.environ.pop("SCHENGEN_MCP_UPSTREAM_TIMEOUT_SECONDS", None)
        os.environ.pop("GA_MEASUREMENT_ID", None)
        os.environ.pop("GA_API_SECRET", None)
        os.environ.pop("GA_API_SECRET_PARAM", None)
        self.app = importlib.reload(app)

    def test_tools_list_exposes_create_calculation(self):
        response = self.app.lambda_handler(json_rpc_event("tools/list", {}), None)
        body = json.loads(response["body"])

        tools = body["result"]["tools"]
        tools_by_name = {tool["name"]: tool for tool in tools}
        tool = tools_by_name["create_schengen_calculation"]
        schema = tool["inputSchema"]

        self.assertIn("website link", tool["description"])
        self.assertIn("show the returned website link to the user", tool["description"])
        self.assertIn("list_supported_countries", tools_by_name)
        self.assertEqual(["user", "trips"], schema["required"])
        self.assertEqual("array", schema["properties"]["visas"]["type"])
        self.assertNotIn("visas", schema["required"])
        self.assertIn("US, GB, AU", schema["properties"]["user"]["properties"]["nationality"]["description"])
        self.assertIn("FR, DE", schema["properties"]["trips"]["items"]["properties"]["country_code"]["description"])
        self.assertIn("Entry and exit", schema["properties"]["trips"]["description"])
        self.assertIn("do not pass country names", schema["properties"]["trips"]["description"])
        self.assertEqual("^[A-Z]{2}$", schema["properties"]["trips"]["items"]["properties"]["country_code"]["pattern"])

    def test_tools_list_tracks_ga_event_when_configured(self):
        os.environ["GA_MEASUREMENT_ID"] = "G-TEST"
        os.environ["GA_API_SECRET"] = "secret"
        ga_payloads = []

        class FakeGaResponse:
            def close(self):
                return None

        def fake_urlopen(request, timeout):
            ga_payloads.append(json.loads(request.data.decode("utf-8")))
            return FakeGaResponse()

        event = json_rpc_event(
            "tools/list",
            {},
            headers={"User-Agent": "ExampleAgent/1.0", "X-Forwarded-For": "203.0.113.7"},
            source_ip="198.51.100.9",
        )
        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            response = self.app.lambda_handler(event, None)
            self.app.lambda_handler(event, None)

        self.assertEqual(200, response["statusCode"])
        event = ga_payloads[0]["events"][0]
        self.assertEqual("mcp_tools_list_called", event["name"])
        self.assertEqual(2, event["params"]["tool_count"])
        self.assertEqual(200, event["params"]["status_code"])
        self.assertEqual("mcp", event["params"]["source"])
        self.assertEqual(ga_payloads[0]["client_id"], ga_payloads[1]["client_id"])

    def test_list_supported_countries_tool_returns_lookup_data(self):
        result = self.app.list_supported_countries()
        body = json.loads(result)
        countries = body["countries"]

        us = next(country for country in countries if country["code"] == "US")
        france = next(country for country in countries if country["code"] == "FR")

        self.assertEqual("United States", us["name"])
        self.assertEqual("American", us["nationality"])
        self.assertFalse(us["schengen"])
        self.assertEqual("France", france["name"])
        self.assertTrue(france["schengen"])

    def test_list_supported_countries_tracks_ga_event_when_configured(self):
        os.environ["GA_MEASUREMENT_ID"] = "G-TEST"
        os.environ["GA_API_SECRET"] = "secret"
        ga_payloads = []

        class FakeGaResponse:
            def close(self):
                return None

        def fake_urlopen(request, timeout):
            ga_payloads.append(json.loads(request.data.decode("utf-8")))
            return FakeGaResponse()

        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            result = self.app.list_supported_countries()

        countries = json.loads(result)["countries"]
        event = ga_payloads[0]["events"][0]
        self.assertEqual("mcp_list_supported_countries_called", event["name"])
        self.assertEqual(len(countries), event["params"]["country_count"])
        self.assertGreater(event["params"]["schengen_country_count"], 0)
        self.assertEqual("mcp", event["params"]["source"])

    def test_supported_countries_resource_returns_lookup_data(self):
        response = self.app.lambda_handler(
            json_rpc_event("resources/read", {"uri": "schengen://supported-countries"}),
            None,
        )

        content = json.loads(response["body"])["result"]["contents"][0]
        body = json.loads(content["text"])

        self.assertEqual("application/json", content["mimeType"])
        self.assertTrue(any(country["code"] == "DE" and country["schengen"] for country in body["countries"]))

    def test_supported_countries_payload_is_memoized(self):
        with mock.patch.object(self.app.ET, "parse", wraps=self.app.ET.parse) as parse:
            self.app.supported_countries_payload()
            self.app.supported_countries_payload()

        self.assertEqual(1, parse.call_count)

    def test_create_schengen_calculation_posts_to_rails_api(self):
        os.environ["SCHENGEN_API_BASE_URL"] = "https://example.test"
        os.environ["SCHENGEN_AGENT_AUTH_HEADER"] = "agent-secret"
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, _type, _value, _traceback):
                return None

            def read(self):
                return json.dumps({
                    "status": "safe",
                    "days_used": 10,
                    "days_remaining": 80,
                    "summary": "The planned trips use 10 Schengen days, with 80 days remaining.",
                    "web_url": "https://example.test/en/days",
                    "trips": [
                        {
                            "country_code": "FR",
                            "country_name": "France",
                            "entry_date": "2026-01-01",
                            "exit_date": "2026-01-10",
                            "days": 10,
                        }
                    ],
                }).encode("utf-8")

        def fake_urlopen(request, timeout):
            captured["url"] = request.full_url
            captured["timeout"] = timeout
            captured["body"] = json.loads(request.data.decode("utf-8"))
            captured["headers"] = {key.lower(): value for key, value in request.header_items()}
            return FakeResponse()

        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            result = self.app.create_schengen_calculation(
                user={"first_name": "Sam", "nationality": "US"},
                trips=[{"country_code": "FR", "entry_date": "2026-01-01", "exit_date": "2026-01-10"}],
            )

        self.assertIn("The planned trips use 10 Schengen days, with 80 days remaining.", result)
        self.assertIn("Show this website link to the user", result)
        self.assertIn("https://example.test/en/days", result)
        self.assertIn("France: 2026-01-01 to 2026-01-10, 10 days", result)
        self.assertIn('"web_url": "https://example.test/en/days"', result)
        self.assertEqual("https://example.test/api/v1/calculations", captured["url"])
        self.assertEqual(10, captured["timeout"])
        self.assertEqual([], captured["body"]["visas"])
        self.assertEqual("mcp", captured["headers"]["x-schengen-agent-source"])
        self.assertEqual("agent-secret", captured["headers"]["x-schengen-agent-auth"])
        self.assertTrue(captured["headers"]["x-schengen-agent-client-id"])

    def test_tool_call_forwards_original_mcp_client_id_to_rails(self):
        os.environ["SCHENGEN_API_BASE_URL"] = "https://example.test"
        os.environ["SCHENGEN_AGENT_AUTH_HEADER"] = "agent-secret"
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, _type, _value, _traceback):
                return None

            def read(self):
                return json.dumps({
                    "status": "safe",
                    "summary": "Created.",
                    "web_url": "https://example.test/en/days",
                    "trips": [],
                }).encode("utf-8")

        def fake_urlopen(request, timeout):
            captured["headers"] = {key.lower(): value for key, value in request.header_items()}
            return FakeResponse()

        event = json_rpc_event(
            "tools/call",
            {
                "name": "create_schengen_calculation",
                "arguments": {
                    "user": {"nationality": "US"},
                    "trips": [{"country_code": "FR", "entry_date": "2026-01-01", "exit_date": "2026-01-10"}],
                },
            },
            headers={"User-Agent": "ExampleAgent/1.0", "X-Forwarded-For": "203.0.113.7"},
            source_ip="198.51.100.9",
        )

        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            response = self.app.lambda_handler(event, None)

        self.assertEqual(200, response["statusCode"])
        self.assertEqual("mcp", captured["headers"]["x-schengen-agent-source"])
        self.assertEqual("agent-secret", captured["headers"]["x-schengen-agent-auth"])
        self.assertEqual(self.app.client_id_for_event(event), captured["headers"]["x-schengen-agent-client-id"])

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
            result = self.app.create_schengen_calculation(
                user={"first_name": "Sam", "nationality": "US"},
                trips=[{"country_code": "FR", "entry_date": "2026-01-01", "exit_date": "2026-01-10"}],
            )

        self.assertIn("The Schengen calculation could not be created.", result)
        self.assertIn("API status: 413.", result)
        self.assertIn("too_many_trips", result)

    def test_create_schengen_calculation_tracks_ga_event_when_configured(self):
        os.environ["SCHENGEN_API_BASE_URL"] = "https://example.test"
        os.environ["GA_MEASUREMENT_ID"] = "G-TEST"
        os.environ["GA_API_SECRET"] = "secret"
        ga_payloads = []

        class FakeApiResponse:
            def __enter__(self):
                return self

            def __exit__(self, _type, _value, _traceback):
                return None

            def read(self):
                return json.dumps({
                    "status": "safe",
                    "summary": "Created.",
                    "web_url": "https://example.test/en/days",
                    "trips": [],
                }).encode("utf-8")

        class FakeGaResponse:
            def close(self):
                return None

        def fake_urlopen(request, timeout):
            if "google-analytics.com" in request.full_url:
                ga_payloads.append(json.loads(request.data.decode("utf-8")))
                return FakeGaResponse()
            return FakeApiResponse()

        with mock.patch.object(self.app.urllib.request, "urlopen", fake_urlopen):
            self.app.create_schengen_calculation(
                user={"first_name": "Sam", "nationality": "US"},
                trips=[{"country_code": "FR", "entry_date": "2026-01-01", "exit_date": "2026-01-10"}],
            )

        event = ga_payloads[0]["events"][0]
        self.assertEqual("mcp_create_schengen_calculation_called", event["name"])
        self.assertEqual("safe", event["params"]["upstream_status"])
        self.assertEqual(1, event["params"]["trip_count"])
        self.assertEqual("mcp", event["params"]["source"])

    def test_ga_api_secret_reads_configured_ssm_parameter(self):
        os.environ["GA_API_SECRET_PARAM"] = "/scheng/test/ga_api_secret"

        class FakeSsmClient:
            def get_parameter(self, Name, WithDecryption):
                self.request = {"Name": Name, "WithDecryption": WithDecryption}
                return {"Parameter": {"Value": "ssm-secret"}}

        fake_client = FakeSsmClient()
        fake_boto3 = types.SimpleNamespace(client=lambda service_name: fake_client)

        with mock.patch.dict(sys.modules, {"boto3": fake_boto3}):
            self.assertEqual("ssm-secret", self.app.ga_api_secret())

        self.assertEqual({"Name": "/scheng/test/ga_api_secret", "WithDecryption": True}, fake_client.request)

    def test_tools_call_returns_assistant_ready_text_without_json_string_escaping(self):
        os.environ["SCHENGEN_API_BASE_URL"] = "https://example.test"

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, _type, _value, _traceback):
                return None

            def read(self):
                return json.dumps({
                    "status": "warning",
                    "days_used": 90,
                    "days_remaining": 0,
                    "summary": "The planned trips use all 90 Schengen days.",
                    "web_url": "https://example.test/en/days",
                    "trips": [],
                }).encode("utf-8")

        with mock.patch.object(self.app.urllib.request, "urlopen", lambda _request, timeout: FakeResponse()):
            response = self.app.lambda_handler(
                json_rpc_event(
                    "tools/call",
                    {
                        "name": "create_schengen_calculation",
                        "arguments": {
                            "user": {"nationality": "US"},
                            "trips": [{"country_code": "FR", "entry_date": "2026-01-01", "exit_date": "2026-03-31"}],
                        },
                    },
                ),
                None,
            )

        text = json.loads(response["body"])["result"]["content"][0]["text"]
        self.assertIn("The planned trips use all 90 Schengen days.", text)
        self.assertIn("Show this website link to the user", text)
        self.assertIn("https://example.test/en/days", text)
        self.assertNotIn("\\n", text)


def json_rpc_event(method, params, headers=None, source_ip="203.0.113.9"):
    return {
        "headers": headers or {"User-Agent": "MCP test agent"},
        "requestContext": {"http": {"method": "POST", "sourceIp": source_ip}},
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

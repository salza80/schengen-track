from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any

try:
    from awslabs.mcp_lambda_handler import MCPLambdaHandler
except ImportError:
    from local_mcp import MCPLambdaHandler


SERVER_VERSION = "0.1.0"
DEFAULT_API_BASE_URL = "https://schengen-calculator.com"

mcp = MCPLambdaHandler(name="schengen-calculator-mcp", version=SERVER_VERSION)


@mcp.tool()
def create_schengen_calculation(
    user: dict[str, Any],
    trips: list[dict[str, Any]],
    visas: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Create a guest Schengen calculation and return the result plus a website URL."""
    payload = {
        "user": user,
        "trips": trips,
        "visas": visas or [],
    }
    return post_calculation(payload)


def post_calculation(payload: dict[str, Any]) -> dict[str, Any]:
    api_base_url = os.environ.get("SCHENGEN_API_BASE_URL", DEFAULT_API_BASE_URL).rstrip("/")
    timeout = float(os.environ.get("SCHENGEN_MCP_UPSTREAM_TIMEOUT_SECONDS", "10"))
    request = urllib.request.Request(
        f"{api_base_url}/api/v1/calculations",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "content-type": "application/json",
            "accept": "application/json",
            "user-agent": f"schengen-calculator-mcp/{SERVER_VERSION}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        try:
            details = json.loads(body)
        except json.JSONDecodeError:
            details = {"message": body}

        return {
            "status": "error",
            "http_status": error.code,
            "error": details,
        }


def lambda_handler(event, context):
    return mcp.handle_request(event, context)

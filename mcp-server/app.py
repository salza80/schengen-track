from contextvars import ContextVar
import hashlib
import json
import logging
import os
from pathlib import Path
import xml.etree.ElementTree as ET
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any, Optional

try:
    from awslabs.mcp_lambda_handler import MCPLambdaHandler
except ImportError:
    from local_mcp import MCPLambdaHandler


SERVER_VERSION = "0.1.0"
DEFAULT_API_BASE_URL = "https://schengen-calculator.com"
AGENT_SOURCE = "mcp"
AGENT_SOURCE_HEADER = "x-schengen-agent-source"
GA_EVENT_CREATE_CALCULATION = "mcp_create_schengen_calculation_called"
GA_EVENT_LIST_SUPPORTED_COUNTRIES = "mcp_list_supported_countries_called"
GA_EVENT_TOOLS_LIST = "mcp_tools_list_called"
_GA_API_SECRET_CACHE = None
_GA_CLIENT_ID: ContextVar[Optional[str]] = ContextVar("ga_client_id", default=None)
logger = logging.getLogger(__name__)

# Rails owns the canonical country dataset at src/db/data/countries.xml.
# The MCP Lambda Docker build copies that file into /var/task/countries.xml,
# while local tests/dev read the Rails file directly when no packaged copy exists.
PACKAGED_COUNTRIES_XML_PATH = Path(__file__).with_name("countries.xml")
LOCAL_CANONICAL_COUNTRIES_XML_PATH = Path(__file__).resolve().parents[1] / "src" / "db" / "data" / "countries.xml"

CREATE_CALCULATION_SCHEMA = {
    "name": "create_schengen_calculation",
    "description": (
        "Create a guest Schengen 90/180-day calculation from ISO country codes and YYYY-MM-DD dates. "
        "Returns assistant-ready text plus a website link the user can open to review, edit, or save the calculation. "
        "After calling this tool, show the returned website link to the user so they can check the calculation."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "user": {
                "type": "object",
                "description": "Traveler details. Use country codes only; do not pass country names, cities, or demonyms.",
                "properties": {
                    "first_name": {
                        "type": "string",
                        "description": "Optional traveler first name. Use Guest if unknown.",
                        "examples": ["Sam"],
                    },
                    "last_name": {
                        "type": "string",
                        "description": "Optional traveler last name. Use Traveler if unknown.",
                        "examples": ["Traveler"],
                    },
                    "nationality": {
                        "type": "string",
                        "description": (
                            "Uppercase ISO 3166-1 alpha-2 country code for the traveler's nationality, "
                            "e.g. US, GB, AU. Do not pass demonyms such as American or British."
                        ),
                        "pattern": "^[A-Z]{2}$",
                        "examples": ["US", "GB", "AU"],
                    },
                },
                "required": ["nationality"],
                "additionalProperties": False,
            },
            "trips": {
                "type": "array",
                "description": (
                    "Schengen and non-Schengen visits. Entry and exit dates both count as days present. "
                    "Use uppercase ISO country codes only; do not pass country names, cities, or demonyms."
                ),
                "minItems": 1,
                "maxItems": 50,
                "items": {
                    "type": "object",
                    "properties": {
                        "country_code": {
                            "type": "string",
                            "description": (
                                "Uppercase ISO 3166-1 alpha-2 visited-country code, e.g. FR, DE. "
                                "Do not pass country names like France, cities like Paris, or demonyms like French."
                            ),
                            "pattern": "^[A-Z]{2}$",
                            "examples": ["FR", "DE"],
                        },
                        "entry_date": {
                            "type": "string",
                            "description": "Entry date in YYYY-MM-DD format. The entry date counts as a Schengen day.",
                            "format": "date",
                            "examples": ["2026-07-01"],
                        },
                        "exit_date": {
                            "type": "string",
                            "description": "Exit date in YYYY-MM-DD format. The exit date counts as a Schengen day.",
                            "format": "date",
                            "examples": ["2026-07-20"],
                        },
                    },
                    "required": ["country_code", "entry_date", "exit_date"],
                    "additionalProperties": False,
                },
            },
            "visas": {
                "type": "array",
                "description": "Optional short-stay visa records. Dates are YYYY-MM-DD.",
                "maxItems": 20,
                "items": {
                    "type": "object",
                    "properties": {
                        "visa_type": {
                            "type": "string",
                            "description": "Visa type. Usually S for short-stay.",
                            "examples": ["S"],
                        },
                        "start_date": {
                            "type": "string",
                            "description": "Visa validity start date in YYYY-MM-DD format.",
                            "format": "date",
                            "examples": ["2026-01-01"],
                        },
                        "end_date": {
                            "type": "string",
                            "description": "Visa validity end date in YYYY-MM-DD format.",
                            "format": "date",
                            "examples": ["2026-12-31"],
                        },
                        "no_entries": {
                            "type": "integer",
                            "description": "Number of entries allowed by the visa. Use 0 if unknown.",
                            "examples": [0],
                        },
                    },
                    "required": ["start_date", "end_date"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["user", "trips"],
        "additionalProperties": False,
        "examples": [
            {
                "user": {"first_name": "Sam", "last_name": "Traveler", "nationality": "US"},
                "trips": [
                    {"country_code": "FR", "entry_date": "2026-07-01", "exit_date": "2026-07-10"},
                    {"country_code": "DE", "entry_date": "2026-08-01", "exit_date": "2026-08-15"},
                ],
            }
        ],
    },
}

LIST_COUNTRIES_SCHEMA = {
    "name": "list_supported_countries",
    "description": (
        "Return the supported country-code lookup table as JSON. Use this before create_schengen_calculation "
        "to map nationalities and visited countries to uppercase ISO 3166-1 alpha-2 codes."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {},
        "required": [],
        "additionalProperties": False,
    },
}

mcp = MCPLambdaHandler(name="schengen-calculator-mcp", version=SERVER_VERSION)


@mcp.tool()
def create_schengen_calculation(
    user: dict[str, Any],
    trips: list[dict[str, Any]],
    visas: list[dict[str, Any]] = None,
) -> str:
    """Create a guest Schengen calculation. Include the returned website link in user-facing answers.

    Args:
        user: Object with nationality as an uppercase ISO 3166-1 alpha-2 country code, e.g. US, GB, AU. Do not pass country names, cities, or demonyms.
        trips: Array of visits. trips[].country_code must be an uppercase ISO 3166-1 alpha-2 visited-country code, e.g. FR, DE. Dates must be YYYY-MM-DD. Entry and exit both count.
        visas: Optional array of visa records. Dates must be YYYY-MM-DD.
    """
    payload = {
        "user": user,
        "trips": trips,
        "visas": visas or [],
    }
    result = post_calculation(payload)
    track_ga_event(
        GA_EVENT_CREATE_CALCULATION,
        {
            "upstream_status": result.get("status"),
            "http_status": result.get("http_status", 201 if result.get("status") != "error" else None),
            "trip_count": len(trips or []),
            "visa_count": len(visas or []),
        },
    )
    return format_tool_response(result)


@mcp.tool()
def list_supported_countries() -> str:
    """Return supported countries as JSON with code, name, nationality, and schengen fields."""
    payload = supported_countries_payload()
    countries = payload["countries"]
    track_ga_event(
        GA_EVENT_LIST_SUPPORTED_COUNTRIES,
        {
            "country_count": len(countries),
            "schengen_country_count": sum(1 for country in countries if country["schengen"]),
        },
    )
    return json.dumps(payload, ensure_ascii=False, sort_keys=True)


@mcp.resource(
    "schengen://supported-countries",
    name="Supported countries",
    description="JSON country lookup table with code, name, nationality, and schengen fields.",
    mime_type="application/json",
)
def supported_countries_resource() -> str:
    return json.dumps(supported_countries_payload(), ensure_ascii=False, sort_keys=True)


def apply_explicit_tool_schemas() -> None:
    if hasattr(mcp, "tools"):
        mcp.tools["create_schengen_calculation"] = CREATE_CALCULATION_SCHEMA
        mcp.tools["list_supported_countries"] = LIST_COUNTRIES_SCHEMA

    if hasattr(mcp, "_tools"):
        if "create_schengen_calculation" in mcp._tools:
            mcp._tools["create_schengen_calculation"].description = CREATE_CALCULATION_SCHEMA["description"]
            mcp._tools["create_schengen_calculation"].input_schema = CREATE_CALCULATION_SCHEMA["inputSchema"]
        if "list_supported_countries" in mcp._tools:
            mcp._tools["list_supported_countries"].description = LIST_COUNTRIES_SCHEMA["description"]
            mcp._tools["list_supported_countries"].input_schema = LIST_COUNTRIES_SCHEMA["inputSchema"]


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
            AGENT_SOURCE_HEADER: AGENT_SOURCE,
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
    except Exception as error:
        return {
            "status": "error",
            "error": {"message": str(error), "type": error.__class__.__name__},
        }


def supported_countries_payload() -> dict[str, Any]:
    countries = []
    root = ET.parse(countries_xml_path()).getroot()
    for record in root.findall("record"):
        code = xml_text(record, "country_code")
        if not code:
            continue

        countries.append({
            "code": code,
            "name": xml_text(record, "name"),
            "nationality": xml_text(record, "nationality"),
            "schengen": bool(xml_text(record, "schengen_start_date")),
        })

    countries.sort(key=lambda country: country["code"])
    return {"countries": countries}


def countries_xml_path() -> Path:
    configured_path = os.environ.get("MCP_COUNTRIES_XML_PATH")
    if configured_path:
        return Path(configured_path)

    if PACKAGED_COUNTRIES_XML_PATH.exists():
        return PACKAGED_COUNTRIES_XML_PATH

    return LOCAL_CANONICAL_COUNTRIES_XML_PATH


def xml_text(record: ET.Element, tag: str) -> str:
    node = record.find(tag)
    return (node.text or "").strip() if node is not None else ""


def track_ga_event(event_name: str, params: dict[str, Any]) -> None:
    measurement_id = os.environ.get("GA_MEASUREMENT_ID", "G-E9CCZDHLJF")
    api_secret = ga_api_secret()
    if not measurement_id or not api_secret:
        return

    payload = {
        "client_id": ga_client_id(),
        "events": [
            {
                "name": event_name,
                "params": {
                    "engagement_time_msec": 1,
                    "source": AGENT_SOURCE,
                    **{key: value for key, value in params.items() if value is not None},
                },
            }
        ],
    }
    query = urllib.parse.urlencode({"measurement_id": measurement_id, "api_secret": api_secret})
    request = urllib.request.Request(
        f"https://www.google-analytics.com/mp/collect?{query}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )

    try:
        urllib.request.urlopen(request, timeout=ga_timeout_seconds()).close()
    except Exception as error:
        logger.info(
            "Google Analytics Measurement Protocol event failed for %s: %s: %s",
            event_name,
            error.__class__.__name__,
            error,
        )
        return


def ga_client_id() -> str:
    return _GA_CLIENT_ID.get() or str(uuid.uuid4())


def ga_timeout_seconds() -> float:
    return float(os.environ.get("SCHENGEN_MCP_GA_TIMEOUT_SECONDS", "1"))


def ga_api_secret() -> Optional[str]:
    global _GA_API_SECRET_CACHE

    direct_secret = os.environ.get("GA_API_SECRET")
    if direct_secret:
        return direct_secret

    if _GA_API_SECRET_CACHE is not None:
        return _GA_API_SECRET_CACHE

    param_name = os.environ.get("GA_API_SECRET_PARAM")
    if not param_name:
        return None

    try:
        import boto3

        response = boto3.client("ssm").get_parameter(Name=param_name, WithDecryption=True)
        _GA_API_SECRET_CACHE = response["Parameter"]["Value"]
        return _GA_API_SECRET_CACHE
    except Exception as error:
        logger.warning(
            "Unable to load GA API secret from SSM parameter %s: %s: %s",
            param_name,
            error.__class__.__name__,
            error,
        )
        return None


def format_tool_response(result: dict[str, Any]) -> str:
    if result.get("status") == "error":
        return format_error_response(result)

    summary = result.get("summary") or "The Schengen calculation has been created."
    web_url = result.get("web_url") or result.get("claim_url")
    status = result.get("status")
    days_used = result.get("days_used")
    days_remaining = result.get("days_remaining")
    overstay_days = result.get("overstay_days")
    next_allowed_entry_date = result.get("next_allowed_entry_date")

    lines = [
        summary,
    ]

    if isinstance(days_used, int) and isinstance(days_remaining, int):
        lines.append(f"Days used: {days_used}. Days remaining: {days_remaining}.")

    if status == "overstay" and isinstance(overstay_days, int):
        lines.append(f"Overstay: yes, by {overstay_days} day{'s' if overstay_days != 1 else ''}.")
    elif status:
        lines.append(f"Status: {status}.")

    if next_allowed_entry_date:
        lines.append(f"Next allowed entry date: {next_allowed_entry_date}.")

    if web_url:
        lines.extend(
            [
                "",
                "Show this website link to the user so they can check, review, edit, or save the calculation themselves:",
                web_url,
            ]
        )

    trips = result.get("trips")
    if isinstance(trips, list) and trips:
        lines.extend(["", "Trips included:"])
        for trip in trips:
            if not isinstance(trip, dict):
                continue
            country = trip.get("country_name") or trip.get("country_code") or "Unknown country"
            entry_date = trip.get("entry_date") or "unknown entry"
            exit_date = trip.get("exit_date") or "unknown exit"
            days = trip.get("days")
            day_text = f", {days} day{'s' if days != 1 else ''}" if isinstance(days, int) else ""
            lines.append(f"- {country}: {entry_date} to {exit_date}{day_text}")

    lines.extend(["", "Raw calculation data:", json.dumps(result, ensure_ascii=False, sort_keys=True)])
    return "\n".join(lines)


def format_error_response(result: dict[str, Any]) -> str:
    http_status = result.get("http_status")
    error = result.get("error")
    lines = ["The Schengen calculation could not be created."]
    if http_status:
        lines.append(f"API status: {http_status}.")
    lines.extend(["Details:", json.dumps(error or result, ensure_ascii=False, sort_keys=True)])
    return "\n".join(lines)


def lambda_handler(event, context):
    rpc_method = json_rpc_method(event)
    client_id_token = _GA_CLIENT_ID.set(client_id_for_event(event))
    try:
        response = mcp.handle_request(event, context)

        if rpc_method == "tools/list":
            track_ga_event(
                GA_EVENT_TOOLS_LIST,
                {
                    "tool_count": mcp_tool_count(),
                    "status_code": response.get("statusCode") if isinstance(response, dict) else None,
                },
            )

        return response
    finally:
        _GA_CLIENT_ID.reset(client_id_token)


def json_rpc_method(event: dict[str, Any]) -> Optional[str]:
    try:
        body = event.get("body") or "{}"
        request = json.loads(body) if isinstance(body, str) else body
        return request.get("method") if isinstance(request, dict) else None
    except (json.JSONDecodeError, AttributeError, TypeError):
        return None


def mcp_tool_count() -> Optional[int]:
    tools = getattr(mcp, "_tools", None) or getattr(mcp, "tools", None)
    return len(tools) if hasattr(tools, "__len__") else None


def client_id_for_event(event: dict[str, Any]) -> Optional[str]:
    headers = event_headers(event)
    http_context = event.get("requestContext", {}).get("http", {}) if isinstance(event, dict) else {}
    parts = [
        http_context.get("sourceIp"),
        header_value(headers, "x-forwarded-for"),
        header_value(headers, "cf-connecting-ip"),
        header_value(headers, "user-agent"),
    ]
    seed = "|".join(part for part in parts if part)
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:32] if seed else None


def event_headers(event: dict[str, Any]) -> dict[str, Any]:
    headers = event.get("headers", {}) if isinstance(event, dict) else {}
    return headers if isinstance(headers, dict) else {}


def header_value(headers: dict[str, Any], name: str) -> Optional[str]:
    target = name.lower()
    for key, value in headers.items():
        if str(key).lower() == target and value:
            return str(value)
    return None


apply_explicit_tool_schemas()

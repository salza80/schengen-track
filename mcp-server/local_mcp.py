import inspect
import json
from dataclasses import dataclass
from typing import Any, Callable


@dataclass
class ToolDefinition:
    name: str
    description: str
    input_schema: dict[str, Any]
    function: Callable[..., Any]


class MCPLambdaHandler:
    """Small local fallback compatible with the AWS Labs decorator API.

    Production should use awslabs.mcp_lambda_handler.MCPLambdaHandler. This
    fallback exists so unit tests and local iteration do not need a network
    install of the AWS Labs package.
    """

    def __init__(self, name: str, version: str):
        self.name = name
        self.version = version
        self._tools: dict[str, ToolDefinition] = {}

    def tool(self):
        def decorator(function: Callable[..., Any]):
            self._tools[function.__name__] = ToolDefinition(
                name=function.__name__,
                description=inspect.getdoc(function) or "",
                input_schema=self._input_schema(function),
                function=function,
            )
            return function

        return decorator

    def handle_request(self, event: dict[str, Any], context: Any):
        method = event.get("requestContext", {}).get("http", {}).get("method", event.get("httpMethod", "POST"))
        if method == "GET":
            return self._response(200, {"name": self.name, "version": self.version})

        request = self._body(event)
        rpc_method = request.get("method")
        request_id = request.get("id")

        if rpc_method == "initialize":
            return self._rpc_response(request_id, {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": self.name, "version": self.version},
                "capabilities": {"tools": {}},
            })

        if rpc_method == "tools/list":
            return self._rpc_response(request_id, {
                "tools": [
                    {
                        "name": tool.name,
                        "description": tool.description,
                        "inputSchema": tool.input_schema,
                    }
                    for tool in self._tools.values()
                ]
            })

        if rpc_method == "tools/call":
            params = request.get("params", {})
            tool = self._tools.get(params.get("name"))
            if tool is None:
                return self._rpc_error(request_id, -32602, "Unknown tool")

            try:
                result = tool.function(**params.get("arguments", {}))
            except Exception as error:
                return self._rpc_response(request_id, {
                    "isError": True,
                    "content": [{"type": "text", "text": str(error)}],
                })

            return self._rpc_response(request_id, {
                "content": [{"type": "text", "text": json.dumps(result)}],
            })

        return self._rpc_error(request_id, -32601, "Method not found")

    def _input_schema(self, function: Callable[..., Any]):
        properties = {}
        required = []

        for name, parameter in inspect.signature(function).parameters.items():
            properties[name] = self._schema_for_annotation(parameter.annotation)
            if parameter.default is inspect.Parameter.empty:
                required.append(name)

        return {
            "type": "object",
            "properties": properties,
            "required": required,
        }

    def _schema_for_annotation(self, annotation: Any):
        if annotation is int:
            return {"type": "integer"}
        if annotation is float:
            return {"type": "number"}
        if annotation is bool:
            return {"type": "boolean"}
        if annotation is list or getattr(annotation, "__origin__", None) is list:
            return {"type": "array"}
        if annotation is dict or getattr(annotation, "__origin__", None) is dict:
            return {"type": "object"}
        return {"type": "string"}

    def _body(self, event: dict[str, Any]):
        body = event.get("body") or "{}"
        return json.loads(body) if isinstance(body, str) else body

    def _rpc_response(self, request_id: Any, result: dict[str, Any]):
        return self._response(200, {"jsonrpc": "2.0", "id": request_id, "result": result})

    def _rpc_error(self, request_id: Any, code: int, message: str):
        return self._response(200, {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}})

    def _response(self, status_code: int, body: dict[str, Any]):
        return {
            "statusCode": status_code,
            "headers": {
                "content-type": "application/json",
                "cache-control": "no-store",
            },
            "body": json.dumps(body),
        }

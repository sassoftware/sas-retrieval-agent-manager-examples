import json
from typing import Any, Dict

from sasram.agent import Client

TOOL_TIMEOUT = 30.0

HELP_TEXT = (
    "Which tool would you like to call? Reply with the tool name followed by any "
    "arguments as comma-separated key=value pairs.\n"
    "Format: <tool_name>, <arg1>=<value1>, <arg2>=<value2>, ...\n"
    "Ask 'list tools' to see all available tools, or 'args <tool_name>' to see a tool's arguments.\n\n"
    "Available tools: {tool_names}"
)


def exec(text: str, ram_client: Client) -> str:
    # Tools registered for this agent carry the tool_server_id needed for invoke_tool
    tools = ram_client.get_langchain_tools()
    tool_names = ", ".join(sorted(t.name for t in tools))

    # First turn (empty history): ask the user which tool to call and with what args
    if not ram_client.get_session_history_as_langchain():
        return HELP_TEXT.format(tool_names=tool_names)

    lower_text = text.strip().lower()

    if "tool" in lower_text and any(w in lower_text for w in ("list", "available", "all", "what")):
        return "Available tools:\n" + "\n".join(f"- {name}" for name in sorted(t.name for t in tools))

    if "arg" in lower_text:
        # Prefer the longest matching name, since a shorter tool name can be a substring
        # of a more specific one (e.g. "team" vs. "teamMember")
        matches = [t for t in tools if t.name.lower() in lower_text]
        tool = max(matches, key=lambda t: len(t.name), default=None)
        if tool is None:
            return f"Which tool's arguments? Available tools: {tool_names}"
        return _describe_tool_args(tool, ram_client)

    tool_name, *raw_args = [p.strip() for p in text.split(",") if p.strip()]

    tool = next((t for t in tools if t.name == tool_name), None)
    if tool is None:
        return HELP_TEXT.format(tool_names=tool_names)

    args: Dict[str, Any] = {}
    for raw_arg in raw_args:
        if "=" not in raw_arg:
            return f"Could not parse argument '{raw_arg}'. Expected format: key=value."
        key, value = raw_arg.split("=", 1)
        args[key.strip()] = value.strip()

    result = ram_client.invoke_tool(
        tool_server_id=tool.tool_server_id,
        tool_name=tool_name,
        args=args,
        timeout=TOOL_TIMEOUT,
    )

    return _extract_text(result)


def _describe_tool_args(tool, ram_client: Client) -> str:
    header = f"'{tool.name}'"
    if tool.description:
        header += f": {tool.description.strip()}"

    # The client-side tool schema here is a generic args/kwargs stub, not the real
    # per-parameter schema, so probe the server directly: calling with no arguments
    # will either succeed (no args required) or return a validation error naming them
    try:
        result = ram_client.invoke_tool(
            tool_server_id=tool.tool_server_id,
            tool_name=tool.name,
            args={},
            timeout=TOOL_TIMEOUT,
        )
        extracted = _extract_text(result)
        # Some MCP servers report failures as error text in the result instead of raising
        if "error" in extracted.lower():
            return (
                f"{header}\n\nCalling it with no arguments returned an error, which usually reveals "
                f"the required arguments:\n{extracted}"
            )
        return (
            f"{header}\n\nCalling it with no arguments succeeded, so no arguments appear to be "
            f"required:\n{extracted}"
        )
    except Exception as e:
        return (
            f"{header}\n\nCalling it with no arguments failed, which usually reveals the required "
            f"arguments:\n{e}"
        )


def _extract_text(result: dict) -> str:
    # MCP tool results carry their payload as a list of typed content parts
    parts = [c["text"] for c in result.get("content", []) if c.get("type") == "text"]
    raw = "\n".join(parts) if parts else str(result)

    # Pretty-print JSON payloads so nested tool results are readable
    try:
        return f"```json\n{json.dumps(json.loads(raw), indent=2)}\n```"
    except (json.JSONDecodeError, TypeError):
        return raw

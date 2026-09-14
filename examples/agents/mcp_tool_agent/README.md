# MCP Tool Agent

This folder contains a minimal agent example that calls a single, specific MCP tool directly using
`ram_client.invoke_tool(...)`, instead of delegating tool selection to the LangGraph agent as the
[default tool calling agent](../default_tool_calling_agent/) does. This is useful when you always want a
deterministic call to one known tool rather than letting an LLM decide whether/when to call it.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

No system prompt is required. This template never calls an LLM — it parses the user's message directly
and invokes the tool.

### Tools

Configure the tools you want available from any MCP Tool Server — any tool registered on the server(s)
can be called by name.

You still need to add the MCP Tool Server to this agent experiment in RAM; only tools from servers
attached to the experiment are discoverable via `ram_client.get_langchain_tools()` and callable by
prompting.

### Collections

No collections are required for this example.

### Environment Variables (required)

None. The tool server ID is derived automatically from the tool name you provide, using
`ram_client.get_langchain_tools()`.

## Agent-specific Configuration

Edit [run.py](run.py) to set:

- `TOOL_TIMEOUT`: The timeout, in seconds, passed to `invoke_tool` (defaults to `30.0`).

## Runtime Behavior

1. On the first message of a session, the template replies with instructions asking the user for a tool
   name and its arguments.
2. On subsequent messages, the template recognizes a few commands:
   - `list tools` (or any message mentioning "tool" plus "list"/"available"/"all"/"what"): returns a
     bulleted list of all available tool names.
   - `args <tool_name>` (or any message mentioning "arg" plus a tool name): calls that tool with no
     arguments and returns the result (or the server's error), since that's the most reliable way to
     reveal a tool's required parameters — the client-side tool schema only exposes a generic args/kwargs
     stub, not real per-parameter info. If multiple tool names appear to match, the longest (most specific)
     one wins, e.g. a tool named `getTeamsTeamId` over `getTeams`. The response also inspects the result
     text for error indicators, since some MCP servers report failures as text in the result instead of
     raising.
   - `<tool_name>, <arg1>=<value1>, <arg2>=<value2>, ...`: invokes the named tool with the given args.
   - Anything else (including a message on the first turn, or one that doesn't match a known tool) returns
     the help text.
3. For a tool call, it looks up the matching tool's `tool_server_id` from `ram_client.get_langchain_tools()`
   and calls `ram_client.invoke_tool(tool_server_id=tool_server_id, tool_name=tool_name, args=args, timeout=TOOL_TIMEOUT)`.
4. The template extracts the text content from the tool result, pretty-printing it if it's JSON, and
   returns it.

## Automation Hook (Optional)

There are no automations for this agent.

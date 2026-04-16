# Financial Agent (MCP + RAM)

This folder contains a financial agent example built with RAM. It combines structured data (database + market tools)
and unstructured retrieval (financial news collection) to generate client-specific daily updates.

## Input to this agent experiment

### Retrieval Settings - System Prompt

Use the Retrieval Settings page to configure a system prompt for this agent. Use the
system prompt content from `SYSTEM_PROMPT.txt`

### Tools

Configure these tools in the agent experiment:

- Database tools (Container MCP server connected to the financial client database):
	- `execute_sql`
	- `list_schemas`
	- `list_tables`
- Finance market tools (Code MCP server):
	- `fetch_current_price`
	- `fetch_price_history`
- Chart tools (Container MCP server):
	- `generate_bar_chart`
	- `generate_line_chart`
	- `generate_pie_chart`

### Collections

Configure these collections:

- Minimum recommendation: a daily financial news collection.
- Recommended setting: turn ON agentic retrieval.

### Environment Variables (optional)

None required for this example.

## Agent-specific configuration

Edit [run.py](run.py) to set the target client values:

- `CLIENT_NAME`
- `CLIENT_ID`

These values are used by the daily summary flow. Update them to match your target environment and client data.

## Runtime commands

This agent supports the following commands:

- `#help`: Show available commands.
- `#displayupdate`: Return the latest stored daily summary.
- `#generateupdate`: Generate a new daily summary and store it.

For normal user prompts, the agent delegates to the RAM LangGraph agent and returns the model response.

## Automation Hook (Optional)

The `init(client)` function in [run.py](run.py) is intended for scheduled RAM automation.
When triggered, it generates and stores the daily summary.

# Financial Agent (MCP + RAM)

This folder contains a financial agent example built with SAS Retrieval Agent Manager (RAM). It combines structured data (the database and market tools)
and unstructured retrieval (from the financial news collection) to generate client-specific daily updates.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Use the Retrieval Settings page to configure a system prompt for this agent. Use the
system prompt content from `SYSTEM_PROMPT.txt`

### Tools

Configure these tools in the agent experiment:

- Database tools (Container MCP server connected to the financial client database):
	- See [postgres_db_connection_template](../../container_mcp_servers/postgres_db_connection_template/) for the container MCP server used by this agent.
	- `execute_sql`
	- `list_schemas`
	- `list_tables`
- Finance market tools (Code MCP server):
	- See [finance_tools Code MCP server](../../code_mcp_servers/finance_tools/)
	- `fetch_current_price`
	- `fetch_price_history`
- Chart tools (Container MCP server):
	- See [chart_generator](../../container_mcp_servers/chart_generator/) for the container MCP server used by this agent.
	- `generate_bar_chart`
	- `generate_line_chart`
	- `generate_pie_chart`

### Collections

Configure these collections:

- Minimum recommendation: a daily financial news collection.
	- See [financial_news_fetcher custom source](../../custom_sources/financial_news_fetcher/) for an example of generating daily financial news documents for the collection.
- Recommended setting: turn on agentic retrieval.

### Environment Variables (optional)

No environment variables are required for this example.

## Agent-specific Configuration

Edit [run.py](run.py) to set the target client values:

- `CLIENT_NAME`
- `CLIENT_ID`

These values are used by the daily summary flow. Update the values to match your target environment and client data.

## Runtime Commands

This agent supports the following commands:

- `#help`: Show available commands.
- `#displayupdate`: Return the latest stored daily summary.
- `#generateupdate`: Generate a new daily summary and store it.

For normal user prompts, the agent delegates to the RAM LangGraph agent and returns the model response.

## Automation Hook (Optional)

The `init(client)` function in [run.py](run.py) is intended for scheduled RAM automation.
When triggered, it generates and stores the daily summary.

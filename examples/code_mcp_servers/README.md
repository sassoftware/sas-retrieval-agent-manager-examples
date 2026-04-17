# Code MCP Servers

This folder contains examples of Code MCP tool servers built with RAM. Code MCP servers
let you write Python code that exposes tools (functions) your agents can call at runtime.

A Code MCP server in RAM is a lightweight Python project made up of:

- `run.py`: tool implementations and tool definitions.
- `requirements.txt`: optional third-party Python packages used by the tools.
- Environment variables (optional): runtime configuration values used by the server.

## Creating a Code MCP Server

1. On the `Code Templates` pane, click `Code MCP Server`.
2. Copy the example `run.py` into the template's `run.py`.
3. If needed, copy the example `requirements.txt` into the template's `requirements.txt`.
4. Configure any required environment variables (see the example's README).
5. Save and publish the template.

## What to include in run.py

At minimum, `run.py` should include:

- A definition for each exposed tool (name, description, and expected inputs/outputs).
- The Python implementation for each tool.

## requirements.txt (optional)

Additional packages that are required by your tool implementations.

## Environment Variables (optional)

Use environment variables for configuration that should not be hardcoded, such as:

- API endpoints
- API keys or tokens
- Feature flags or runtime options

## Testing and usage

After publishing the Code MCP server template, you will need to create a new
"MCP Tool Server" that uses the template in the "MCP Tools" page of RAM. After
creating and starting the tool server successfully, you can then register the tools
with your agent.

## Examples

| Example | Description |
| ------- | ----------- |
| [Finance Tools](./finance_tools/) | Finance and quantitative analysis tools, including market data lookup, regression, summary statistics, and arithmetic helpers |
| [News Search Tools](./news_search_tools/) | Web search tools for finding news from NYT, Reddit, DuckDuckGo, and Yahoo Finance |
| [Simple Calculator](./simple_calculator/) | Minimal single-tool MCP server example that adds two integers |
| [Web Search](./web_search/) | Lightweight web search tool example built on DuckDuckGo search via the `ddgs` package |

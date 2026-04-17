# Code MCP Servers

This folder contains examples of Code MCP tool servers built with RAM. Code MCP servers
let you write Python code that exposes tools (functions) your agents can call at runtime.
Each example includes the code needed (`run.py`/`requirements.txt`) and details on the
tools it provides.

## Creating a Code MCP Server

1. On the `Code Templates` pane, click `Code MCP Server`.
2. Add `run.py` and `requirements.txt` from the example.
3. Add any environment variables the example requires (see the example's README).
4. Save and publish the tool server.

Once published, you can assign the MCP server to any agent experiment's **MCP Tools**
configuration. The agent will then be able to call the tools defined in the server.

## Examples

| Example | Description |
| ------- | ----------- |
| [News Search Tools](./news_search_tools/) | Web search tools for finding news from NYT, Reddit, DuckDuckGo, and Yahoo Finance |

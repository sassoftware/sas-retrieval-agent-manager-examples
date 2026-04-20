# Web Search Code MCP Server

This folder contains a Code MCP server template for lightweight web search in SAS Retrieval Agent Manager (RAM).

The server exposes a single tool that performs a web search and returns a small set of search results that an agent can use as additional context.

## Template Files

- `run.py`: MCP tool implementation and definition
- `requirements.txt`: third-party dependency for this server template

## Tools

### `search_web(search_str: str) -> list[dict]`

Searches the web for a text query and returns up to 5 results.

- Input: search query string
- Output: list of search result objects
- Current behavior: uses the `ddgs` package to perform DuckDuckGo text search with `max_results=5`

This tool is useful when an agent needs recent or general web context that is not available in the configured document collections.

## Environment Variables (optional)

No environment variables are required for this example.

## Notes

- This template depends on the `ddgs` package listed in [requirements.txt](requirements.txt).
- Web search results depend on external network access and third-party search availability.

# News Search Tools (Code MCP Server)

This folder contains a Code MCP server that provides web search tools for finding news
from multiple sources. These tools are used by the news agent examples and the news
orchestrator example.

## Tools Provided

| Tool | Description |
| ---- | ----------- |
| `search_nyt_headlines` | Search the New York Times article archive for headlines using the NYT Article Search API. |
| `search_reddit` | Search Reddit for posts and discussions on a topic via RSS feeds. Extracts post content and follows external links. |
| `search_internet` | Search the internet using DuckDuckGo and extract full article content from results. |
| `search_yahoo_finance_news` | Search Yahoo Finance for news articles related to a query or stock ticker. |

## Setup

1. On the `Code Templates` pane, click `Code MCP Server`.
2. Add [run.py](./run.py) and [requirements.txt](./requirements.txt)
3. Save and publish the tool server.

## Environment Variables

| Variable | Required | Description |
| -------- | -------- | ----------- |
| `NYT_API_KEY` | Yes (for `search_nyt_headlines`) | New York Times API key. Get one at [developer.nytimes.com](https://developer.nytimes.com/). |

Set this as a secret environment variable on the MCP tool server in RAM.

## Dependencies

The `requirements.txt` lists all Python packages needed by the tools:

- `httpx` — async HTTP client (NYT API)
- `requests` — HTTP client (Reddit RSS)
- `feedparser` — RSS/Atom feed parsing
- `beautifulsoup4` — HTML parsing
- `trafilatura` — web content extraction
- `ddgs` — DuckDuckGo search API
- `yfinance` — Yahoo Finance data

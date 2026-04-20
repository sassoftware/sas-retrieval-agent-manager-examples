# News Search Tools Code MCP Server

This folder contains a Code MCP server that provides web search tools for finding news
from multiple sources. These tools are used by the news agent examples and the news
orchestrator example.

## Tools

| Tool | Description |
| ---- | ----------- |
| `search_nyt_headlines` | Searches the New York Times article archive for headlines using the NYT Article Search API. |
| `search_reddit` | Searches Reddit for posts and discussions on a topic via RSS feeds. Extracts post content and follows external links. |
| `search_internet` | Searches the internet using DuckDuckGo and extract full article content from results. |
| `search_yahoo_finance_news` | Searches Yahoo Finance for news articles related to a query or stock ticker. |

## Environment Variables

Follow the [general Code MCP server instructions](../README.md) with the following specifics.

Add `NYT_API_KEY` as a secret environment variable, set the variable to
your NYT API key. You can get an API key at [developer.nytimes.com](https://developer.nytimes.com/).

## Dependencies

- `httpx` — async HTTP client (NYT API)
- `requests` — HTTP client (Reddit RSS)
- `feedparser` — RSS/Atom feed parsing
- `beautifulsoup4` — HTML parsing
- `trafilatura` — web content extraction
- `ddgs` — DuckDuckGo search API
- `yfinance` — Yahoo Finance data

# Business News Agent

This folder contains a no-code agent specialized in business and financial news. This agent has access to a
business news document collection and web search tools to answer questions about markets,
corporate news, mergers and acquisitions, and economic trends.

This agent is designed to be used as a **sub-agent** of the
[News Orchestrator](../../agent_orchestrators/news_orchestrator/), but can also be used as a
standalone agent.

> **Note:** Before configuring this agent, you must set up:
> 1. The [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server.
> 2. A **Business News** custom source and collection. See the
>    [News Custom Source](../../custom_sources/news_source/) example (use `CATEGORY = 'business'`).
>    Make sure to set up an automation to re-vectorize the collection on the source's schedule.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Any system prompt works. This is a no-code agent, so the LLM uses the agent card
and tools to determine how to respond.

### Tools

From the [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server, add:

- `search_nyt_headlines`
- `search_reddit`
- `search_internet`
- `search_yahoo_finance_news`

### Collections

Add the **Business News** collection that you created from the
[News Custom Source](../../custom_sources/news_source/) (with `CATEGORY = 'business'`).
Use alias `default`. Enable **agentic retrieval**.

### Environment Variables (optional)

No environment variables are required for this example.

## Agent Card

The agent card is important when this agent is used as a sub-agent. It tells the
orchestrator what this agent can do. Configure the agent card with the following skills:

```yaml
skills:
  - name: Give business news
    description: >
      This agent has access to several up-to-date business news sources
      and can search for information on anything business related
    examples:
      - tell me about what's going on with tech companies
      - how is the strait of hormuz closure affecting the economy?
      - What is the current stock price of NVIDIA
      - How did the S&P 500 perform in the last trading session
      - List the latest merger and acquisition news in the fintech sector
      - What are the key takeaways from the most recent Federal Reserve meeting
      - Which retail companies reported earnings this morning

  - name: What's going on in the business news world lately?
    description: >
      This agent knows the latest business news and can give you an overview
      of the recent top stories
    examples:
      - What's going on in the business news world lately?
```

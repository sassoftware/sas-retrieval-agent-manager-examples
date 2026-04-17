# Health News Agent

A no-code agent specialized in health and medical news. This agent has access to a health
news document collection and web search tools to answer questions about medical research,
public health, FDA approvals, and health policy.

This agent is designed to be used as a **sub-agent** of the
[News Orchestrator](../../agent_orchestrators/news_orchestrator/), but can also be used
standalone.

> **Note:** Before configuring this agent, you must set up:
> 1. The [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server.
> 2. A **Health News** custom source and collection. See the
>    [News Custom Source](../../custom_sources/news_source/) example (use `CATEGORY = 'health'`).
>    Make sure to set up an automation to re-vectorize the collection on the source's schedule.

## Input to this agent experiment

### Retrieval Settings - System Prompt

Any system prompt will work. This is a no-code agent, so the LLM uses the agent card
and tools to determine how to respond.

### Tools

From the [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server, add:

- `search_nyt_headlines`
- `search_reddit`
- `search_internet`
- `search_yahoo_finance_news`

### Collections

Add the **Health News** collection you created from the
[News Custom Source](../../custom_sources/news_source/) (with `CATEGORY = 'health'`).
Use alias `default`. Enable **agentic retrieval**.

### Environment Variables (optional)

None required for this example.

## Agent Card

Configure the agent card with the following skills:

```yaml
skills:
  - name: Give Health news
    description: ""
    examples:
      - What are the most recent FDA approvals for oncology treatments
      - Summarize the latest findings on the benefits of intermittent fasting
      - What are the current CDC guidelines for the upcoming flu season
      - List new breakthroughs in Alzheimers disease research from this year
      - What are the top rated mental health apps according to clinical reviews

  - name: What's going on in the Health news world lately?
    description: ""
    examples:
      - What's going on in the Health news world lately?
```

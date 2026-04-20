# Science and Technology News Agent

This folder contains a no-code agent that is specialized in science and technology news. This agent has access to a
science and tech news document collection and web search tools to answer questions about
AI, space exploration, software, quantum computing, and scientific research.

This agent is designed to be used as a **sub-agent** of the
[News Orchestrator](../../agent_orchestrators/news_orchestrator/), but it can also be used as a
standalone agent.

> **Note:** Before configuring this agent, you must set up:
> 1. The [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server.
> 2. A **Science and Tech News** custom source and collection. See the
>    [News Custom Source](../../custom_sources/news_source/) example (use `CATEGORY = 'tech'`).
>    Make sure to set up an automation to re-vectorize the collection on the source's schedule.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Any system prompt works with this agent. This is a no-code agent, so the LLM uses the agent card
and tools to determine how to respond.

### Tools

From the [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server, add:

- `search_nyt_headlines`
- `search_reddit`
- `search_internet`
- `search_yahoo_finance_news`

### Collections

Add the **Science and Tech News** collection that you created from the
[News Custom Source](../../custom_sources/news_source/) (with `CATEGORY = 'tech'`).
Use alias `default`. Enable **agentic retrieval**.

### Environment Variables (optional)

No environment variables are required for this example.

## Agent Card

Configure the agent card with the following skills:

```yaml
skills:
  - name: Give Science and Technology news
    description: ""
    examples:
      - What are the latest updates regarding the James Webb Space Telescope missions
      - Summarize the newest features released in the latest version of Python
      - How is generative AI being integrated into enterprise software this year
      - What are the most recent milestones achieved in quantum computing hardware
      - List the upcoming satellite launches scheduled for the next two weeks

  - name: What's going on in the Science and Technology news world lately?
    description: ""
    examples:
      - What's going on in the Science and Technology news world lately?
```

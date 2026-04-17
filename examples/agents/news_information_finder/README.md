# News Information Finder

A no-code agent that acts as a general-purpose news research tool. Unlike the domain-specific
news agents, this agent has access to **all** news collections and all web search tools,
making it useful for cross-domain queries or topics that don't fall neatly into one category.

This agent is designed to be used as a **sub-agent** of the
[News Orchestrator](../../agent_orchestrators/news_orchestrator/), but can also be used
standalone.

> **Note:** Before configuring this agent, you must set up:
> 1. The [News Search Tools](../../code_mcp_servers/news_search_tools/) MCP server.
> 2. News custom sources and collections for each domain. See the
>    [News Custom Source](../../custom_sources/news_source/) example (create one source per
>    category: `business`, `health`, `tech`, etc.).
> 3. An **NYT front pages** custom source and collection. See the
>    [NYT Front Page Custom Source](../../custom_sources/nyt_front_page_source/) example.
> 4. Make sure to set up automations to re-vectorize each collection on its source's schedule.

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

Add **all** of your news collections. These should include collections created from
the [News Custom Source](../../custom_sources/news_source/) (Business, Health, Science
and Tech, etc.) as well as the [NYT Front Page](../../custom_sources/nyt_front_page_source/)
collection. Enable **agentic retrieval** on each.

### Environment Variables (optional)

None required for this example.

## Agent Card

Configure the agent card with the following skills:

```yaml
skills:
  - name: Find information about a topic
    description: ""
    examples:
      - Tell me what's going on in Iran
      - How are robotics technologies coming along?
      - Who is Alysa Liu?

  - name: Search reddit
    description: ""
    examples:
      - Find info on reddit about nuclear energy news
      - What are people on reddit saying about the AI bubble lately?

  - name: Search the internet
    description: ""
    examples:
      - Search the internet for information about the Davos Economic Forum
      - Can you find info on the internet about sportswashing
      - Look up the latest news on renewable energy investments

  - name: Search NYT headlines
    description: ""
    examples:
      - What are the latest NYT headlines related to what's going on in Iran?
      - What is the NYT saying about the winter olympics?
      - What are the latest NYT headlines about OpenAI?
```

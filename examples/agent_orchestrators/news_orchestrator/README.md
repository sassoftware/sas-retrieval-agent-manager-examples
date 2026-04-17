# News Orchestrator

An advanced news analysis orchestrator that coordinates a team of domain-specific news
sub-agents to produce insightful, cross-domain news briefings. Rather than simply
summarizing what sub-agents return, this orchestrator synthesizes findings into compelling,
insight-driven narratives that connect stories across domains.

## Prerequisites

> **Important:** You must set up ALL sub-agents and the MCP tool server before creating
> this orchestrator. Each sub-agent must be fully configured with a running server. The
> orchestrator cannot function until its sub-agents are available and responding.

### Required Custom Sources and Collections

Before setting up the sub-agents, create the news sources and collections they depend on:

- **Domain news sources** — Create one source per news domain using the
  [News Custom Source](../../custom_sources/news_source/) template. Set `CATEGORY` to
  `business`, `health`, `tech`, etc. Create a collection for each source and set up an
  automation to re-vectorize on the source's schedule.
- **NYT front pages source** — Create using the
  [NYT Front Page Custom Source](../../custom_sources/nyt_front_page_source/) template.
  Create a collection and automation for it as well.

### Required MCP Tool Server

- **[News Search Tools](../../code_mcp_servers/news_search_tools/)** — provides web
  search tools (`search_nyt_headlines`, `search_reddit`, `search_internet`,
  `search_yahoo_finance_news`). Set this up first since the sub-agents depend on it.

### Required Sub-Agents

Set up each of the following agents. Each is a no-code agent with its own news collection,
the search tools from the News Search Tools MCP server, and agentic retrieval enabled.
See each agent's README for detailed setup instructions.

| Sub-Agent | Description | Collection Needed |
| --------- | ----------- | ----------------- |
| [Business News Agent](../../agents/business_news_agent/) | Business, markets, economics | Business news articles |
| [Health News Agent](../../agents/health_news_agent/) | Medical research, public health, FDA | Health news articles |
| [Science and Technology News Agent](../../agents/science_tech_news_agent/) | AI, space, computing, research | Science and tech news articles |
| [News Information Finder](../../agents/news_information_finder/) | General-purpose cross-domain search | All news collections |

You can also add more domain-specific sub-agents (e.g., Culture, Global Affairs, Industrial)
following the same pattern as the agents above. The orchestrator will automatically discover
and use any sub-agents assigned to it.

### Setup Order

1. Create and publish the **News Search Tools** MCP server.
2. Create **custom sources** for each news domain and an NYT front page source (see above).
3. Create **collections** for each source, vectorize them, and set up **automations** to
   re-vectorize whenever the source updates.
4. Create and start each **sub-agent** (Business, Health, Science/Tech, Information Finder).
5. Verify each sub-agent is running and responsive.
6. Create the **orchestrator** (this agent).

## Setting Up the Orchestrator

1. Create a **code template** by clicking `Code Orchestrator Agent` on the `Code Templates` page
2. Add [run.py](./run.py)
3. On the `Agents` pane, click **Create an Agent Orchestrator**.
4. Create a new experiment. Everything can be left as default except for the following:
5. **Details:** Set `Experiment Type` to `Code template experiment` and select the code template you just made.
6. **Agents:** Add all the agents listed above.
7. Click `Create`.
8. Start the orchestrator's server.

## How It Works

The orchestrator operates in two phases:

1. **Research phase** — The orchestrator queries its sub-agents to gather information
   relevant to the user's question. It asks targeted, specific questions rather than broad
   "tell me everything" requests. It queries multiple sub-agents when the question spans
   domains and follows up with additional queries when initial findings raise new questions.

2. **Composition phase** — The orchestrator synthesizes all research into a compelling
   narrative. Its system prompt instructs it to lead with surprising or counterintuitive
   findings, connect stories across domains, ground claims in concrete examples, and cite
   sources.

## Runtime Commands

- `#help` — Show available commands.
- `#story` — Generate a cross-domain news analysis. The orchestrator will look for
  interesting collisions between stories in different domains and produce a narrative
  connecting them.
- Any other input is treated as a news query and routed through the research and
  composition pipeline.

## Environment Variables

None required on the orchestrator itself. Environment variables (like `NYT_API_KEY`) are
configured on the sub-agents' MCP tool server.

## Files

| File | Description |
| ---- | ----------- |
| `run.py` | Orchestrator code template |

# Simple Orchestrator

A minimal orchestrator example that demonstrates the basic pattern for coordinating
sub-agents. This is a good starting point if you want to understand how orchestrators
work before building something more complex like the
[News Orchestrator](../news_orchestrator/).

## Prerequisites

> **Important:** You must set up at least two sub-agents before creating this orchestrator.
> Each sub-agent must be a fully configured agent with a running server. The orchestrator
> cannot function until its sub-agents are available.

This example works with **any** sub-agents you have available. You just need at least two
agents that the orchestrator can delegate to. For example, you could use two of the news
agents from the [agents examples](../../agents/), or any other agents you have set up.

## Setting Up the Orchestrator

1. Create a new agent in RAM and set its type to **Orchestrator**.
2. Add your sub-agents (at least two recommended).
3. Create a **no-code** experiment. No code template is needed for this example since it
   uses the built-in orchestrator behavior.
4. **System prompt:** Use the content from `SYSTEM_PROMPT.txt`, or write your own. The
   system prompt should describe the sub-agents and how the orchestrator should route
   queries.
5. **Collections:** None required.
6. **Tools:** None required.
7. **LLM:** Configure the default LLM.
8. Start the orchestrator's server.

## How It Works

The no-code orchestrator uses RAM's built-in orchestrator agent, which:

1. Receives a user query.
2. Uses the LLM to decide which sub-agents to query based on their agent cards.
3. Sends queries to the selected sub-agents via A2A (Agent-to-Agent communication).
4. Synthesizes the sub-agent responses into a single answer.

This is the simplest way to set up an orchestrator in RAM. For more control over the
orchestration logic (custom routing, multi-step research, specialized prompts), see the
[News Orchestrator](../news_orchestrator/) example which uses a code template.

## Files

| File | Description |
| ---- | ----------- |
| `SYSTEM_PROMPT.txt` | System prompt for the orchestrator |

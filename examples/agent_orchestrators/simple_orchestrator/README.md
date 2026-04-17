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

1. On the `Agents` pane, click **Create an Agent Orchestrator**.
2. Create a new experiment. Everything can be left as default besides the `Agents` tab.
3. **Agents:** Add any sub-agents you'd like (at least two recommeneded).
4. Click `Create`.
5. Start the orchestrator's server.

## How It Works

The no-code orchestrator uses RAM's built-in orchestrator agent, which:

1. Receives a user query.
2. Uses the LLM to decide which sub-agents to query based on their agent cards.
3. Sends queries to the selected sub-agents via A2A (Agent-to-Agent communication).
4. Synthesizes the sub-agent responses into a single answer.

This is the simplest way to set up an orchestrator in RAM. For more control over the
orchestration logic (custom routing, multi-step research, specialized prompts), see the
[News Orchestrator](../news_orchestrator/) example which uses a code template.

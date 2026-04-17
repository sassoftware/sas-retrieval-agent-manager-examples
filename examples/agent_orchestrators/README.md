# Agent Orchestrator Examples

This folder contains examples of agent orchestrators built with RAM. An orchestrator is an agent
that delegates work to other agents (sub-agents) via A2A (Agent-to-Agent) communication, then
synthesizes their responses into a unified answer.

## Prerequisites

> **Important:** Before setting up an agent orchestrator, you must first create and configure all
> of the sub-agents that the orchestrator will delegate to. Each sub-agent must be fully set up
> as its own agent experiment (with its own code template or no-code configuration, system prompt,
> tools, and collections) and must have a running agent server before the orchestrator can
> communicate with it. See the [agents examples](../agents/) folder for guidance on setting up
> individual agents.

## How Orchestrators Work

1. The orchestrator receives a user query.
2. Based on its system prompt and the query content, it decides which sub-agents to delegate to.
3. It sends tasks to the selected sub-agents via A2A and waits for their responses.
4. It synthesizes the sub-agent responses into a single, coherent answer for the user.

## Creating an Orchestrator

1. In RAM, create the sub-agents first. Each sub-agent should be a separate agent with its own
   experiment, code template, system prompt, and any required tools or collections.
2. Start each sub-agent's server so it is running and available.
3. On the `Agents` pane, click **Create an Agent Orchestrator**.
4. Create a new experiment.
5. Choose between a **no-code** experiment (uses built-in orchestrator behavior) or a
   **code template** experiment (for custom orchestration logic).
6. On the `Agents` tab of the experiment, add the sub-agents by selecting them from the list of
   available agents.
7. Start the orchestrator's server.

## Examples

| Example | Description |
| ------- | ----------- |
| [Simple Orchestrator](simple_orchestrator/) | A minimal no-code orchestrator that demonstrates the basic pattern. Works with any sub-agents. Good starting point. |
| [News Orchestrator](news_orchestrator/) | An advanced code-based orchestrator that coordinates domain-specific news agents and a general information finder to produce cross-domain news analysis. |

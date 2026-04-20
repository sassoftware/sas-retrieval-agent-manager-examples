# Generic Agent Configuration Instructions

This folder contains several examples of agent code templates built with SAS Retrieval Agent Manager (RAM). Each example will include
the code needed (run.py/requirements.txt), a system prompt to use, and details on how to configure
the tools and collections that the example needs to work.

## Creating a New Code Agent Template

1. In RAM Code Templates, create a new Code Agent template.
2. Copy [run.py](run.py) into the template's run.py.
3. Save and publish the template.
4. In Experiments, create a template-based experiment from the template.
5. Configure LLM, system prompt, tools, collections, and environment variables as documented for your agent.

## Input to an Agent Experiment

### Retrieval Settings - System Prompt

Use the Retrieval Settings page to create a specific prompt for your agent. Example system prompts
are included with each agent example.

### Tools

These are the specific tools that each agent uses are configured in the "MCP Tools" page. See the MCP server examples folders
for details on how to configure these.

### Collections

These are the document collections that your agent is going to have access to. If desired, "agentic retrieval" can be used to
allow your agent to access your collection through tools. See the specific agent example for its recommendation.

### Environment Variables (optional)

Environment variables are required only if you define them in the agent's code template. Any specific
environment variables used by the agent. The agent examples will document if
these are required and how to use them.

### Aliases (optional)

Aliases are required only if you define them in the agent's code template. Aliases allow
you to configure multiple sets of LLMs, collections, or tools that your agent can use.

## Automation Hook (Optional)

The `init(client)` function in [run.py](run.py) is intended for scheduled RAM automation.
When triggered, it executes the code in the `init` function of your code template.


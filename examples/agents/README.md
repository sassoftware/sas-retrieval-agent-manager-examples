# Generic Agent Configuration Instructions

This folder contains several examples of agent code templates built with RAM. Each example will include
the code needed (run.py/requirements.txt), a system prompt to use, and details on how to configure
the tools and collections the example needs to work.

## Creating a new Code Agent template

1. In RAM Code Templates, create a new Code Agent template.
2. Copy [run.py](run.py) into the template's run.py.
3. Save and publish the template.
4. In Experiments, create a Template-based experiment from this template.
5. Configure LLM, system prompt, tools, collections, and environment variables as documented for your agent.

## Input to an agent experiment

### Retrieval Settings - System Prompt

Use the Retrieval Settings page to create a specific prompt for your agent. Example system prompts
are included with each agent example.

### Tools

The specific tools that each agent uses: these are configured in the "MCP Tools" page. See the MCP server examples folders
for details on how to configure these.

### Collections

The document collections that your agent is going to have access to. If desired, "agentic retrieval" can be used to
allow your agent to access your collection via tools. See the specific agent example for its recommendation.

### Environment Variables (optional)

Only required if you define them in the agent's code template. Any specific
environment variables used by the agent. The agent examples will document if
these are required and how to use them.

## Automation Hook (Optional)

The `init(client)` function in [run.py](run.py) is intended for scheduled RAM automation.
When triggered, it executes the code in the `init` function of your code template.


# Default Tool Calling Agent

This folder contains the default code template used when creating a new RAM code agent.

It forwards each user message to the LangGraph agent and returns the final assistant response, allowing RAM-configured tools, collections, and retrieval settings to drive behavior.

## Input to this agent experiment

### Retrieval Settings - System Prompt

Configure the system prompt in Retrieval Settings based on your use case.

### Tools

Any tools can be used with this template.

This template calls `ram_client.get_langgraph_agent()` and relies on the tools configured in your RAM agent experiment.

### Collections

Any collection(s) can be used with this template.

### Environment Variables (optional)

None required for this example.

## Runtime behavior

For each user message:

1. The template gets the LangGraph agent from `ram_client`.
2. It appends the new user message to session history.
3. It invokes the agent and returns the final response text.

## Automation Hook (Optional)

None.

# Tool Timeout Configuration Agent

This folder contains an agent example that behaves like the default tool calling
agent, but reads its tool and query timeout values from environment variables.

At a high level, this template shows how to:

- Configure the LangGraph agent with custom `tool_timeout` and `query_timeout` values
- Supply those values at deployment time through environment variables

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Any system prompt works for this template.

### Tools

Any MCP tools configured in RAM will work with this template.

### Collections

Any RAM collection will work with this template.

### Environment Variables

- `TOOL_TIMEOUT`: integer number of seconds an individual tool call may run. Defaults to `60`.
- `QUERY_TIMEOUT`: integer number of seconds the overall query may run. Defaults to `120`.

### Aliases

None.

## Runtime Behavior

The agent performs the same standard functionality as the default tool calling agent,
while letting agent developers provide their desired tool and query timeout values to use
during the agent's execution.

For each user message:

1. The template gets the LangGraph agent from `ram_client`, passing the configured timeouts.
2. The template appends the new user message to session history.
3. The template invokes the agent and returns the final response text.

## Example Prompts

- `Summarize this document set in 5 bullets`
- `Look up the latest status for account 12345 and explain what changed`

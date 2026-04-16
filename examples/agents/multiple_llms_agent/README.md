# Multiple LLMs Agent

This folder contains an agent example that routes user prompts to different LLM
endpoints based on requested reasoning effort.

At a high level, this template shows how to:

- Define multiple model names in a single code agent.
- Select a model dynamically from user input.

## Input to this agent experiment

### Retrieval Settings - System Prompt

Any system prompt will work for this template.

### Tools

None required for this example. This agent does not perform MCP tool calling.

### Collections

Configure a collection named `default` for this template.
The agent sends queries with `collection_name='default'`.

### Environment Variables

None required for this example.

### Aliases

This agent uses the following LLM aliases:
  - "high_reasoning_llm"
  - "low_reasoning_llm"

Edit [run.py](run.py) to configure which aliases are used:

- `low_reasoning_llm`
- `high_reasoning_llm`


## Runtime behavior

The agent routes prompts as follows:

- Prompts tagged for high reasoning are sent to `high_reasoning_llm`.
- Prompts tagged for low reasoning (or unspecified) are sent to `low_reasoning_llm`.


## Example prompts

- `Summarize this document set in 5 bullets #low`
- `Analyze trade-offs and provide a detailed recommendation #high`

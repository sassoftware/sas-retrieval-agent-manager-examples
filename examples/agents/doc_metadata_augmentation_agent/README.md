# Document Metadata Augmentation Agent

This folder contains an agent template that uses the sasram Python client `retrieve_docs`
function to perform a semantic search over a collection, and format this context
into an LLM query with both the text content and metadata for the document such as file name, page
number, and chunk index.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Any system prompt works for this template.

### Tools

No tools are required for this example. This agent does not perform tool calling.

### Collections

Any collection can be used with this template.

### Environment Variables (optional)

No environment variables are required for this example.

## Automation Hook (Optional)

There are no automations for this agent.
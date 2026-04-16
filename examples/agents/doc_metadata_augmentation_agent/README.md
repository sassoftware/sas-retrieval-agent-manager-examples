# Document Metadata Augmentation Agent

This folder contains an agent template that uses the sasram Python client `retrieve_docs`
function to perform a semantic search over a collection, and format this context
into an LLM query with both the document's text content and metadata like file name, page
number, and chunk index.

## Input to this agent experiment

### Retrieval Settings - System Prompt

Any system prompt will work for this template.

### Tools

None required for this example. This agent does not perform tool calling.

### Collections

Any collection will work for this template.

### Environment Variables (optional)

None required for this example.

## Automation Hook (Optional)

None.

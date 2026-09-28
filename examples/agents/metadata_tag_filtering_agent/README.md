# Metadata and Tag Filtering Agent

This folder contains a generic SAS Retrieval Agent Manager (RAM) code agent template that limits retrieval by source tags and custom metadata before semantic ranking.

The template is not tied to a particular source schema. Configure tags and custom metadata columns for each collection in RAM before using them in a query.

- Tags select eligible source files.
- Custom metadata selects eligible rows or chunks from supported structured sources.
- Semantic ranking orders the eligible chunks by relevance and returns the top matches.

## Query Interface

Place one JSON `#filters:` directive on the first line, followed by the question:

```text
#filters: {"tags":["approved-content"],"status":"published","region":"us"}
What policy applies to remote access?
```

The JSON object is passed directly to `post_query` as an exact-match retrieval filter. Metadata field names are not hardcoded, and tags and metadata can be combined in one request.

Use valid JSON with double-quoted keys and strings. Tag values must be provided as a non-empty list. Custom metadata values must be scalar JSON values and exactly match the indexed value and type. Field names, capitalization, dates, and other formatted values must match the source data.

`source`, `tags`, and `enabled` are reserved retrieval fields. Do not use those names for custom metadata columns.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Use [SYSTEM_PROMPT.txt](SYSTEM_PROMPT.txt) as a starting point.

### Tools

No MCP tools are required.

### Collections

Configure one or more collections that contain sources with tags or custom metadata columns.

For source tags:

1. Add global or local tags to the files in a source.
2. Revectorize each collection that includes the source.

RAM does not automatically assign tags. A tag narrows retrieval only when the collection also contains files without that tag. When every eligible file has the same tag, it still enforces scope but does not reduce the candidate set.

For custom metadata:

1. Use a `.csv` or `.xls` source with column headings.
2. Add custom metadata columns whose names exactly match the source-file column headings.
3. Enable agentic retrieval when customers also want RAM to infer metadata filters from natural-language requests. This template does not require inference because it supplies explicit filters.
4. Revectorize the champion configuration for each collection that includes the source.

Collections can contain files with different metadata schemas. Only request fields available on the intended files, and avoid assigning different meanings or types to the same field across collections.

### Environment Variables (optional)

No environment variables are required for this example.

## Runtime Behavior

For each user message, the template parses an optional first-line `#filters:` JSON object and calls `post_query` with `search_kwargs={"k": 10, "filter": ...}`. Requests without the directive use the same RAG path without exact-match filters. Filters apply only to the current message.

Different filter fields are combined with AND. Multiple values in `tags` are matched according to the configured vector store's tag behavior. Results are the top 10 semantically ranked matches, not an exhaustive query result.

## Automation Hook (Optional)

There are no automations for this agent.
# Metadata Filtering Agent

This example demonstrates how SAS Retrieval Agent Manager (RAM) can use custom metadata to narrow retrieval before semantic ranking.

The collection contains approximately 6,000 IT service management (ITSM) incidents with the following fields:

- incident_id
- description
- assigned_it_person
- category
- severity
- status
- date

## Metadata

The following fields are configured as custom metadata:

- category (Access, Application, Database, Email, Hardware, Infrastructure, Network, Security, Software)
- severity (Low, Medium, High, Critical)
- status (Open, In Progress, Investigating, Resolved, Closed)
- date
- assigned_it_person

Metadata filters reduce the candidate set before semantic search.

Example:

```text
#filters: {"category":"Security","severity":"Critical","status":"Open"}
Summarize active security incidents.
```

## How It Works

For each request:

1. Apply metadata filters.
2. Retrieve matching records.
3. Rank results semantically.
4. Return the most relevant matches.

This combines structured filtering with semantic retrieval. Use the
[tag filtering example](../tag_filtering_agent/) to select among separately tagged files instead.

# Generic Catalog MCP Server Instructions

This folder contains examples of Catalog MCP server templates for SAS Retrieval Agent Manager (RAM).

A Catalog MCP server is a built-in RAM template type that you select directly from a catalog of prebuilt connector types (for example, "OpenAPI MCP Server"), rather than a custom code or container-based server. RAM handles hosting and tool generation for you.

## Catalog Server Types

RAM's catalog includes the following built-in connector types:

- **DB Connector** — Connects directly to a database and automatically generates MCP tools for querying it.
- **Remote MCP Server** — Connects to an existing, externally hosted MCP server over Streamable HTTP or Server-sent events. 
- **OpenAPI MCP Server** — Connects to an existing REST API and automatically generates MCP tools from its OpenAPI/Swagger specification. 

## Remote MCP Server: Exa Web Search

This README.md documents how to set up a Remote MCP Server in SAS Retrieval Agent Manager (RAM) using the [Exa](https://exa.ai/) hosted web search MCP server.

A Remote MCP Server is a built-in RAM catalog template that connects directly to an existing, externally hosted MCP server over HTTP, so no custom code or container image is required.

### Template Settings (required fields)

- Transport: Streamable HTTP
- URL: `https://mcp.exa.ai/mcp`

### Authentication

No authentication is required.

### Creating the MCP Tool in RAM

1. In RAM, navigate to **MCP Tools** in the left-hand sidebar.
2. In the top-right corner, click **New**.
3. Select **Remote MCP Server**.
4. Click **Select Template**.
5. Set Transport to **Streamable HTTP** and enter the URL listed above.
6. Save. RAM connects to the remote server and exposes its tools (including web search) for agent use.

### Notes

Any remote server that implements the MCP Streamable HTTP transport can be onboarded the same way. Swap in a different URL to connect to a different hosted MCP server.

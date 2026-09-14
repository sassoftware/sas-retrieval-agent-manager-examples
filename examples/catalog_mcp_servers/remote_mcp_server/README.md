# Remote MCP Server

This folder contains examples of Remote MCP Servers configured with SAS Retrieval Agent Manager (RAM). A Remote MCP Server is a built-in RAM catalog template that connects directly to an existing, externally hosted MCP server over Streamable HTTP or Server-sent events. No custom code or container image is required — you just provide the server's URL and select a transport (for example, Streamable HTTP).

### Creating the MCP Tool Server in RAM

1. In RAM, navigate to **MCP Tools** in the left-hand sidebar.
2. In the top-right corner, click **New**.
3. Select **Remote MCP Server**.
4. Click **Select Template**.
5. Set Transport to **Streamable HTTP** and enter the URL listed above.
6. Save. RAM connects to the remote server and exposes its tools (including web search) for agent use.

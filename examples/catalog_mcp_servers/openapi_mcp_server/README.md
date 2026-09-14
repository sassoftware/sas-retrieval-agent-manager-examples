# OpenAPI MCP Server

This folder contains examples of OpenAPI MCP Servers built with SAS Retrieval Agent Manager (RAM). An OpenAPI MCP Server is a built-in RAM catalog template that connects to an existing REST API and automatically generates MCP tools from its OpenAPI/Swagger specification, one tool per operation. No custom code or container image is required — you just provide the API's base URL and the URL of its OpenAPI spec (JSON or YAML format are both supported).


### Creating the MCP Tool Server in RAM

1. In RAM, navigate to **MCP Tools** in the left-hand sidebar.
2. In the top-right corner, click **New**.
3. Select **OpenAPI MCP Server**.
4. Click **Select Template**.
5. Enter the URL and OpenAPI Spec URL listed above.
6. Save. RAM generates one MCP tool per operation defined in the OpenAPI spec.

### Note

If the OpenAPI spec is hosted in a public GitHub repo, use the raw content link (for example, `raw.githubusercontent.com/...`), not the HTML file view link.
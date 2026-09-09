# OpenAPI MCP Server

An OpenAPI MCP Server is a built-in RAM catalog template that connects to an existing REST API and automatically generates MCP tools from its OpenAPI/Swagger specification, one tool per operation. No custom code or container image is required — you just provide the API's base URL and the URL of its OpenAPI spec (JSON or YAML format are both supported). If the spec is hosted in a public GitHub repo, use the raw content link (for example, `raw.githubusercontent.com/...`), not the HTML file view link.

See [f1_connect_mcp_server](/examples/catalog_mcp_servers/openapi_mcp_server/f1_connect_mcp_server/) for a worked example.

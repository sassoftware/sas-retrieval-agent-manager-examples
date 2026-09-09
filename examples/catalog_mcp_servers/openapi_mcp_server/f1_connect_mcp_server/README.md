## OpenAPI MCP Server: F1 Connect API

This README.md documents how to set up an OpenAPI MCP Server in SAS Retrieval Agent Manager (RAM) using the [F1 Connect API](https://f1connectapi.vercel.app/), a free public API for Formula 1 data (drivers, teams, races, standings, etc.).

An OpenAPI MCP Server is a built-in RAM catalog template that automatically generates MCP tools directly from an OpenAPI specification, so no custom code or container image is required.

### Template Settings (required fields)

- URL: `https://f1connectapi.vercel.app/`
- OpenAPI Spec URL: `https://raw.githubusercontent.com/Rafacv23/F1-api/refs/heads/main/openapi.yaml`

### Authentication

No authentication is required.

### Creating the MCP Tool in RAM

1. In RAM, navigate to **MCP Tools** in the left-hand sidebar.
2. In the top-right corner, click **New**.
3. Select **OpenAPI MCP Server**.
4. Click **Select Template**.
5. Enter the URL and OpenAPI Spec URL listed above.
6. Save. RAM generates one MCP tool per operation defined in the OpenAPI spec.

### Notes

Any API with a publicly reachable OpenAPI/Swagger spec can be onboarded the same way. Swap in a different URL and OpenAPI Spec URL to expose a different API's operations as MCP tools.

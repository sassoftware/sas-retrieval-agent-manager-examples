## Postgres DB Connection Template

This README.md documents how to setup the GenAI toolbox MCP server
for use in RAM. It uses the MCP toolbox server from Google: https://github.com/googleapis/genai-toolbox

The MCP toolbox server contains many prebuilt tool configurations for various
database connections. This example uses the prebuilt postgres tools configuration.

### Template Settings (required fields)

Container image: us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:latest
Arguments: --address 0.0.0.0 --prebuilt postgres --log-level debug
Transport: HTTP
Port: 5000
Base Path: /mcp

### Authentication

None.

### Environment Variables

These environment variables are used by the container. You do not need to set a default value
for them. You can specify your specific DB connection parameters when you instantiate this template
in the MCP Tools page.

- POSTGRES_HOST
- POSTGRES_PORT
- POSTGRES_DATABASE
- POSTGRES_USER
- POSTGRES_PASSWORD: mark 'secret'

### Configuration File

Leave empty.
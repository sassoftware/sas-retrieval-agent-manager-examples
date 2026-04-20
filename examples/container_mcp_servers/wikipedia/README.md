## Wikepedia Tool Server Template

This README.md documents how to setup the Wikipedia MCP container
for use in RAM.

### Template Settings (required fields)

- Container image: docker.io/mcp/wikipedia-mcp
- Arguments: --transport sse --host 0.0.0.0 --port 8000
- Transport: Server-Sent Events
- Port: 8000
- Base Path: /sse

### Authentication

None.

### Environment Variables

None.

### Configuration File

Leave empty.
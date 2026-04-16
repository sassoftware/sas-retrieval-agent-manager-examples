# Generic Code MCP Server Instructions

This folder contains examples of Code MCP server templates for RAM.

A Code MCP server in RAM is a lightweight Python project made up of:

- `run.py`: tool implementations and tool definitions.
- `requirements.txt`: optional third-party Python packages used by the tools.
- Environment variables (optional): runtime configuration values used by the server.

## Creating a new Code MCP server template

1. In RAM Code Templates, create a new Code MCP server template.
2. Copy the example `run.py` into the template's `run.py`.
3. If needed, copy the example `requirements.txt` into the template's `requirements.txt`.
4. Configure any required environment variables.
5. Save and publish the template.

## What to include in run.py

At minimum, `run.py` should include:

- A definition for each exposed tool (name, description, and expected inputs/outputs).
- The Python implementation for each tool.

## requirements.txt (optional)

Additional packages that are required by your tool implementations.

## Environment Variables (optional)

Use environment variables for configuration that should not be hardcoded, such as:

- API endpoints
- API keys or tokens
- Feature flags or runtime options

## Testing and usage

After publishing the Code MCP server template, you will need to create a new
"MCP Tool Server" that uses the template in the "MCP Tools" page of RAM. After
creating and starting the tool server successfully, you can then register the tools
with your agent.

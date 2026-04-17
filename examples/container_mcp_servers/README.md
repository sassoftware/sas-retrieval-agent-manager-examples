# Generic Container MCP Server Instructions

This folder contains examples of Container MCP server templates for RAM.

A Container MCP server in RAM is a containerized tool server that you register as a template and then instantiate in the MCP Tools page for agent use.

Container templates typically define:

- Container image
- Startup arguments
- Transport protocol, port, and base path
- Authentication settings
- Environment variables (including secrets)
- Optional configuration file content

## Creating a new Container MCP server template

1. In RAM Code Templates, create a new Container MCP server template.
2. Enter the container image and startup arguments.
3. Configure transport settings (for example HTTP), port, and base path.
4. Configure authentication if required by the container.
5. Define required environment variables.
6. Save and publish the template.
7. In the MCP Tools page, instantiate the template and provide runtime values for environment variables.

## Authentication (Optional)

If your container is hosted in a registry that requires authentication, use this tab to enter the
credentials needed to access the image.

## Environment Variables (Optional)

Consult the container image's documentation for any required environment variables.

## Configuration File (Optional)

This file will be mounted in the MCP container at the path given (default is '/tmp/config/tools.yaml').
Consult the container image's documentation for details on how to use this file.

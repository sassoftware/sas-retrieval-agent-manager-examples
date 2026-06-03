## SAS Viya MCP Tool Server Template

This README.md documents how to setup the SAS Viya MCP container from
[sassoftware/sas-mcp-server](https://github.com/sassoftware/sas-mcp-server)
for use in Retrieval Agent Manager.

### Viya Setup

See [Register a Custom Application (OAuth Client)](https://go.documentation.sas.com/doc/en/sasadmincdc/v_076/calauthmdl/n1iyx40th7exrqn1ej8t12gfhm88.htm#n0ce1kz53qzmukn165fzrqdsws3e) 
for instructions to register a custom application.  The client should be registered with a custom group, UID, and GID.  An example client might look like this:
```json
{
    "client_id": "client-id",
    "client_secret": "client-secret",
    "authorities": ["group-id"],
    "authorized_grant_types": ["client_credentials"],
    "uid": "2001",
    "gid": "2001",
}
```

### Template Settings (required fields)

- Container image: ghcr.io/sassoftware/sas-mcp-server:main
- Transport: HTTP
- Port: 8134
- Base Path: /mcp

### Authentication

Authenticaion requires OAuth client credentials.

- The Client ID and Client Secret should correspond to the client in Viya.
- The OAuth Token URL should be set to `<Viya URL>/SASLogon/oauth/token`.
- The OAuth Scope can be left empty.

### Environment Variables

These environment variables are used by the container. You do not need to set a default value
for them. You can set your specific Viya URL when you instantiate this template
in the **MCP Tools** view in Retrieval Agent Manager.

- VIYA_ENDPOINT
- ALLOW_RAW_BEARER: true

### Configuration File

Leave the configuration file empty.

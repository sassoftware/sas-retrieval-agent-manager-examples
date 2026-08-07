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

#### Create the OAuth Client with the Example Script

The `create_viya_oauth_client.py` script creates the OAuth client in Viya with the
`client_credentials` grant type. It requires Python and the `requests` package:

```bash
pip install requests
```

Set `VIYA_URL` to the base URL of the Viya deployment. The script also accepts
the following optional variables:

- `CLIENT_ID`: OAuth client ID. Defaults to `ram-client`.
- `CLIENT_SECRET`: OAuth client secret. Defaults to `ram-secret`.
- `GROUP`: Viya group assigned to the client. Defaults to `ram-group`.
- `UID`: User ID assigned to the client. Defaults to `2001`.
- `GID`: Group ID assigned to the client. Defaults to `2001`.
- `ACCESS_TOKEN`: bearer token used to authenticate the client-creation request.

If `ACCESS_TOKEN` is not set, run the script once to print a SASLogon URL. Open
that URL in a browser authenticated to Viya, then set `ACCESS_TOKEN` to the
`access_token` value returned in the browser URL. Run the script again with the
same environment variables:

```bash
export VIYA_URL="https://viya.example.com"
export ACCESS_TOKEN="<access-token>"
python create_viya_oauth_client.py
```

The script prints the created client details. If the client already exists, it
prints a message and does not modify it. Update an existing client using the
[SASLogon update client API](https://developer.sas.com/rest-apis/SASLogon/updateClient).

### Template Settings (required fields)

- Container image: ghcr.io/sassoftware/sas-mcp-server:latest
- Transport: HTTP
- Port: 8134
- Base Path: /mcp

### Authentication

Authentication requires OAuth client credentials.

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

To use a custom CA certificate bundle for the Viya TLS connection, set the
configuration file to:

```text
/tmp/config/bundle.pem
```

Also add the following environment variable:

```text
SSL_CERT_FILE=/tmp/config/bundle.pem
```

The bundle should be a PEM file containing the custom CA certificate, along
with any required intermediate CA certificates. Obtain it from the Viya
platform administrator or from the CA/ certificate chain used by the Viya
ingress. If Viya uses an organization-managed private CA, the administrator
can usually provide the CA bundle or identify the Kubernetes secret or
certificate authority that contains it.

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
    "authorities": ["client-id"],
    "authorized_grant_types": ["client_credentials"],
    "uid": "2001",
    "gid": "2001",
}
```

#### Create the OAuth Client with the Example Script

The `create_viya_oauth_client.py` script creates the OAuth client in Viya with the
`client_credentials` grant type, along with a matching custom group. It requires
Python and the `requests` package:

```bash
pip install requests
```

Set `VIYA_URL` to the base URL of the Viya deployment. The script also accepts
the following optional variables:

- `CLIENT_ID`: OAuth client ID. Defaults to `ram-client`. The script also creates a Viya group with this same ID/name and assigns it to the client.
- `CLIENT_SECRET`: OAuth client secret. Defaults to `ram-secret`.
- `CUID`: User ID assigned to the client. Defaults to `2001`.
- `CGID`: Group ID assigned to the client. Defaults to `2001`.
- `GROUP_USERS`: comma-separated list of Viya user IDs to add as members of the group.
- `ACCESS_TOKEN`: bearer token used to authenticate the client-creation request.
- `CODE`: authorization code used to obtain a bearer token.
- `VIYA_USERNAME`: Viya username used to obtain a bearer token. Defaults to `sasboot`.
- `VIYA_PASSWORD`: password for `VIYA_USERNAME`.

If a user listed in `GROUP_USERS` cannot be added (for example, an invalid
user ID), the script prints a warning and continues rather than failing. Any
users that could not be added are listed at the end along with a ready-to-run
command, using the `--add-members-only` flag, to retry adding just those users
once the issue is fixed:

```bash
CLIENT_ID=<client-id> GROUP_USERS="<user1>,<user2>" python create_viya_oauth_client.py --add-members-only
```

To authenticate the request that creates the OAuth client, use one of the
following options. Set `VIYA_URL` in every case:

1. Provide an access token directly. Open the URL printed by the script in a
   browser authenticated to Viya, then set `ACCESS_TOKEN` to the
   `access_token` value returned in the browser URL.

```bash
export VIYA_URL="https://viya.example.com"
export ACCESS_TOKEN="<access-token>"
python create_viya_oauth_client.py
```

2. Provide an authorization code. Open the authorization-code URL printed by
   the script in a browser authenticated to Viya, then set `CODE` to the
   returned code. Authorization codes expire after approximately 10 minutes and
   can be used only once.

```bash
export VIYA_URL="https://viya.example.com"
export CODE="<authorization-code>"
python create_viya_oauth_client.py
```

3. Provide Viya user credentials. If `VIYA_USERNAME` is not set, the script
   uses `sasboot`.

```bash
export VIYA_URL="https://viya.example.com"
export VIYA_USERNAME="<username>"
export VIYA_PASSWORD="<password>"
python create_viya_oauth_client.py
```

The script prints the created client details. If the client already exists, it
prints a message and does not modify it. Update an existing client using the
[SASLogon update client API](https://developer.sas.com/rest-apis/SASLogon/updateClient).

#### Clean Up with the Example Script

The `delete_viya_oauth_client.py` script removes the group and OAuth client
created above. It uses the same `VIYA_URL`, `CLIENT_ID`, and authentication
variables (`ACCESS_TOKEN`, `CODE`, or `VIYA_USERNAME`/`VIYA_PASSWORD`) as
`create_viya_oauth_client.py`. If the group or client don't exist, the script
prints a message and continues without error.

```bash
export VIYA_URL="https://viya.example.com"
export CLIENT_ID="<client-id>"
export VIYA_USERNAME="<username>"
export VIYA_PASSWORD="<password>"
python delete_viya_oauth_client.py
```

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
platform administrator or from the CA certificate chain used by the Viya
ingress. If Viya uses an organization-managed private CA, the administrator
can usually provide the CA bundle or identify the Kubernetes secret or
certificate authority that contains it.

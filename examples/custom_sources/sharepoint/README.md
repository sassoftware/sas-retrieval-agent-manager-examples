# SharePoint Documents Custom Source

This folder contains a custom source template that downloads files from a SharePoint site's default document library through Microsoft Graph and saves them for ingestion by SAS Retrieval Agent Manager (RAM). The target SharePoint site is configured with the `SITE_ID` constant in `run.py`.

## How It Works

When the source runs, it:

1. **Authenticates with Microsoft Entra ID** — Uses the OAuth 2.0 client credentials flow with `TENANT_ID`, `CLIENT_ID`, and `CLIENT_SECRET` to obtain a Microsoft Graph access token.
2. **Finds the document library** — Retrieves the SharePoint site and its default document drive through Microsoft Graph.
3. **Traverses the library** — Recursively lists files and folders from the drive root.
4. **Downloads documents** — Writes each SharePoint file beneath `/tmp/sharepoint-documents`, preserving its folder structure and filename.

## Setup

These are the required dependencies for the SharePoint custom source:

- **SharePoint site:** Set `SITE_ID` in `run.py` to the Microsoft Graph site ID for the site whose default document library should be ingested.
- **Environment variables:** Configure `TENANT_ID`, `CLIENT_ID`, and `CLIENT_SECRET` for a Microsoft Entra application registration.
- **Microsoft Graph permissions:** Grant the application permission to read the target site. When using the `Sites.Selected` application permission, an administrator must also grant the application `read` access to that specific SharePoint site and provide tenant-wide admin consent.
- **Network access:** Allow outbound HTTPS access to `login.microsoftonline.com`, `graph.microsoft.com`, and `*.sharepoint.com`. Graph document downloads can redirect to temporary SharePoint URLs.

## Dependencies

- `requests`: Microsoft identity and Graph API calls
from sasram.source import SourceClient
import os
from pathlib import Path

import requests

GRAPH_URL = "https://graph.microsoft.com/v1.0"

# Obtains a Microsoft Graph access token using application credentials.
def get_access_token() -> str:
    response = requests.post(
        f"https://login.microsoftonline.com/{os.environ['TENANT_ID']}/oauth2/v2.0/token",
        data={
            "client_id": os.environ["CLIENT_ID"],
            "client_secret": os.environ["CLIENT_SECRET"],
            "scope": "https://graph.microsoft.com/.default",
            "grant_type": "client_credentials",
        },
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["access_token"]


# Sends an authenticated GET request to a Microsoft Graph path or URL.
def graph_get(path_or_url: str, token: str) -> dict:
    url = (
        path_or_url
        if path_or_url.startswith("https://")
        else f"{GRAPH_URL}{path_or_url}"
    )
    response = requests.get(
        url,
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )

    if not response.ok:
        raise RuntimeError(
            f"GET {url} returned {response.status_code}: {response.text}"
        )

    return response.json()


# Collects every item from a paginated Microsoft Graph response.
def graph_get_all(path: str, token: str) -> list[dict]:
    items = []
    next_url = path

    while next_url:
        data = graph_get(next_url, token)
        items.extend(data.get("value", []))
        next_url = data.get("@odata.nextLink")

    return items


# Recursively downloads all files and folders from a SharePoint drive item.
def download_documents(
    drive_id: str,
    parent_item_id: str,
    destination: Path,
    token: str,
) -> list[Path]:
    items = graph_get_all(
        f"/drives/{drive_id}/items/{parent_item_id}/children",
        token,
    )
    downloaded = []

    for item in items:
        item_path = destination / item["name"]

        if "folder" in item:
            item_path.mkdir(parents=True, exist_ok=True)
            downloaded.extend(
                download_documents(drive_id, item["id"], item_path, token)
            )
            continue

        if "file" not in item:
            continue

        response = requests.get(
            f"{GRAPH_URL}/drives/{drive_id}/items/{item['id']}/content",
            headers={"Authorization": f"Bearer {token}"},
            timeout=60,
        )
        response.raise_for_status()
        item_path.parent.mkdir(parents=True, exist_ok=True)
        item_path.write_bytes(response.content)
        downloaded.append(item_path)

    return downloaded


# Downloads the site's documents and saves each file to the RAM source.
def exec(client: SourceClient):
    site_id = os.environ.get("SITE_ID", "").strip()
    if not site_id:
        raise RuntimeError("SITE_ID environment variable is required")

    token = get_access_token()

    site = graph_get(f"/sites/{site_id}", token)
    print(f"Site: {site.get('webUrl')}")

    drive = graph_get(f"/sites/{site_id}/drive", token)
    destination = Path("/tmp/sharepoint-documents")
    destination.mkdir(parents=True, exist_ok=True)

    files = download_documents(drive["id"], "root", destination, token)
    for file_path in files:
        print(f"Saving: {file_path.relative_to(destination)}")
        client.save_file(str(file_path))

    print(f"Saved {len(files)} file(s) from {drive.get('webUrl')}")
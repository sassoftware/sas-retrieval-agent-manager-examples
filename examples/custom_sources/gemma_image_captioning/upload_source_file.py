import os
import requests

from get_token import get_auth_token

RAM_API_URL = os.environ["RAM_API_URL"]
SOURCE_ID = os.environ["SOURCE_ID"]

def download_image(filename):
    token_info = get_auth_token()

    if not token_info or not token_info.get("access_token"):
        raise RuntimeError("Failed to obtain RAM access token")

    token = token_info["access_token"]

    response = requests.get(
        f"{RAM_API_URL}/sources/{SOURCE_ID}/file/download",
        headers={"Authorization": f"Bearer {token}"},
        params={"fileName": filename},
        verify=False,
        allow_redirects=True,
        timeout=60,
    )

    response.raise_for_status()

    content_type = (
        response.headers
        .get("Content-Type", "")
        .split(";")[0]
        .strip()
        .lower()
    )

    if not response.content:
        raise ValueError(f"{filename} was empty.")

    if not content_type.startswith("image/"):
        raise ValueError(
            f"{filename} did not return an image. "
            f"Content-Type: {content_type}"
        )

    return response.content, content_type
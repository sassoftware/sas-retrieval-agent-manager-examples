import os

import requests

VIYA_URL = os.getenv("VIYA_URL", "").rstrip("/")
if not VIYA_URL:
    raise Exception("VIYA_URL is not set.")
CLIENT_ID = os.getenv("CLIENT_ID", "ram-client")
CLIENT_SECRET = os.getenv("CLIENT_SECRET", "ram-secret")
UID = int(os.getenv("CUID", "2001"))
GID = int(os.getenv("CGID", "2001"))


def get_token():
    token = os.getenv("ACCESS_TOKEN")
    if not token:
        username = os.getenv("USERNAME", "sasboot")
        password = os.getenv("PASSWORD")
        if username and password:
            response = requests.post(
                f"{VIYA_URL}/SASLogon/oauth/token",
                auth=("sas.cli", ""),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                data={
                    "grant_type": "password",
                    "username": username,
                    "password": password,
                },
                verify=False,
            )
            response.raise_for_status()
            token = response.json().get("access_token")
            if not token:
                raise Exception(
                    "Failed to retrieve access_token from password grant response."
                )
        else:
            ACCESS_TOKEN_BROWSER_URL = f"{VIYA_URL}/SASLogon/oauth/authorize?client_id=sas.cli&response_type=token"
            msg = (
                "ACCESS_TOKEN is not set. "
                "Either set USERNAME and PASSWORD environment variables for password-based authentication, "
                "or load the following URL in your browser and copy the 'access_token' parameter from the URL bar: "
                f"{ACCESS_TOKEN_BROWSER_URL}"
            )
            raise Exception(msg)

    return token


CLIENT_BODY = {
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,
    "authorities": [CLIENT_ID],
    "authorized_grant_types": ["client_credentials"],
    "uid": UID,
    "gid": GID,
}


def create_client():
    token = get_token()
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.post(
        f"{VIYA_URL}/SASLogon/oauth/clients",
        json=CLIENT_BODY,
        headers=headers,
        verify=False,
    )
    if response.status_code == 409:
        print(
            f"Client '{CLIENT_ID}' already exists. See https://developer.sas.com/rest-apis/SASLogon/updateClient to update an existing client."
        )
        return
    response.raise_for_status()
    print(f"Client '{CLIENT_ID}' created successfully.")
    print(response.json())


create_client()

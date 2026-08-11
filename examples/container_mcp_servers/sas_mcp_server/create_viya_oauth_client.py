import os
import sys
import warnings

import requests
import urllib3

warnings.filterwarnings("ignore", category=urllib3.exceptions.InsecureRequestWarning)

VIYA_URL = os.getenv("VIYA_URL", "").rstrip("/")
if not VIYA_URL:
    print("Error: VIYA_URL environment variable is not set.")
    sys.exit(1)
CLIENT_ID = os.getenv("CLIENT_ID", "ram-app")
CLIENT_SECRET = os.getenv("CLIENT_SECRET", "ram-secret")
UID = os.getenv("CUID", "2001")
GID = os.getenv("CGID", "2001")
CODE = os.getenv("CODE")
username = os.getenv("VIYA_USERNAME", "sasboot")
password = os.getenv("VIYA_PASSWORD")


def get_token():
    token = os.getenv("ACCESS_TOKEN")
    if token:
        return token

    # Verify the SASLogon endpoint is reachable before attempting authentication
    token_url = f"{VIYA_URL}/SASLogon/oauth/token"
    print(f"Checking connectivity to {token_url} ...")
    try:
        probe = requests.head(token_url, verify=False, timeout=10)
        print(f"Endpoint reachable (HTTP {probe.status_code})")
    except requests.exceptions.ConnectionError as e:
        print(f"Cannot reach {token_url}: {e}")
        print(
            "Check that VIYA_URL is correct and the host is accessible from this machine."
        )
        sys.exit(1)
    except requests.exceptions.Timeout:
        print(f"Connection to {token_url} timed out after 10 seconds.")
        print("The host may be unreachable or a firewall is blocking the connection.")
        sys.exit(1)
    print()

    if CODE:
        print("Exchanging authorization code for access token...")
        try:
            response = requests.post(
                f"{VIYA_URL}/SASLogon/oauth/token",
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                data={
                    "grant_type": "authorization_code",
                    "code": CODE,
                    "client_id": "sas.cli",
                },
                verify=False,
                timeout=30,
            )
        except requests.exceptions.Timeout:
            print("Request timed out while exchanging authorization code.\n")
        else:
            if response.status_code == 200:
                token = response.json().get("access_token")
                if token:
                    print("Successfully obtained access token via authorization code.")
                    return token
            error_info = (
                response.json()
                if "application/json" in response.headers.get("content-type", "")
                else response.text
            )
            error_msg = (
                error_info.get(
                    "error_description", error_info.get("error", "Unknown error")
                )
                if isinstance(error_info, dict)
                else error_info
            )
            print("Failed to obtain access token via authorization code.")
            print(f"Status: {response.status_code} - {error_msg}")
            print(
                "Possible causes: code expired (valid ~10 min), already used, or invalid.\n"
            )

    if username and password:
        print("Obtaining access token via username/password...")
        try:
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
                timeout=30,
            )
        except requests.exceptions.Timeout:
            print("Request timed out while authenticating with username/password.\n")
        else:
            if response.status_code == 200:
                token = response.json().get("access_token")
                if token:
                    print("Successfully obtained access token via username/password.")
                    return token
            error_info = (
                response.json()
                if "application/json" in response.headers.get("content-type", "")
                else response.text
            )
            error_msg = (
                error_info.get(
                    "error_description", error_info.get("error", "Unknown error")
                )
                if isinstance(error_info, dict)
                else error_info
            )
            print("Failed to obtain access token via username/password.")
            print(f"Status: {response.status_code} - {error_msg}\n")

    CODE_URL = (
        f"{VIYA_URL}/SASLogon/oauth/authorize?client_id=sas.cli&response_type=code"
    )
    TOKEN_URL = (
        f"{VIYA_URL}/SASLogon/oauth/authorize?client_id=sas.cli&response_type=token"
    )
    print(
        "No valid authentication method succeeded. Please use one of the following options:"
    )
    print()
    print("Option 1 - Access token directly:")
    print("  export ACCESS_TOKEN=<token>")
    print(f"  (obtain from: {TOKEN_URL})")
    print()
    print("Option 2 - Authorization code:")
    print("  export CODE=<code>")
    print(f"  (obtain from: {CODE_URL})")
    print()
    print("Option 3 - Username and password:")
    print("  export VIYA_USERNAME=<username>")
    print("  export VIYA_PASSWORD=<password>")
    sys.exit(1)


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
    if response.status_code != 201:
        print(f"Failed to create OAuth client '{CLIENT_ID}'.")
        print(f"Status: {response.status_code}")
        error_info = (
            response.json()
            if response.headers.get("content-type") == "application/json"
            else response.text
        )
        if isinstance(error_info, dict):
            print(f"Error: {error_info.get('message', error_info)}")
        else:
            print(f"Error: {error_info}")
        sys.exit(1)
    print(f"Client '{CLIENT_ID}' created successfully.")
    print(response.json())


create_client()

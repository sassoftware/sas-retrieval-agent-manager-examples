import os
import requests

from dotenv import load_dotenv
load_dotenv()

verifySSL = False  # Disable SSL verification (not recommended for production)

keycloak_realm = "sas-iot"
keycloak_subpath = "auth"
site_url = os.environ.get("SITE_URL")
auth_client_id = os.environ.get("KEYCLOAK_CLIENT_ID")
auth_client_secret = os.environ.get("KEYCLOAK_CLIENT_SECRET")
auth_username = os.environ.get("APP_USER_NAME")
auth_password = os.environ.get("APP_PASSWORD")
keycloak_base_url = f"{site_url}/{keycloak_subpath}"


def get_auth_token(
    auth_url=keycloak_base_url,
    client_id=auth_client_id,
    client_secret=auth_client_secret,
    username=auth_username,
    password=auth_password,
    offline_token=False,
    print_tokens=False,
):

    # Set authorization URL
    auth_url = (
        f"{keycloak_base_url}/realms/{keycloak_realm}/protocol/openid-connect/token"
    )

    # Data to be sent for token request
    # Payload for the token request
    payload = {
        "grant_type": "password",
        "client_id": client_id,
        "client_secret": client_secret,
        "username": username,
        "password": password,
    }

    # Add offline_access scope to the payload if offline_token is True
    if offline_token:
        payload["scope"] = "openid offline_access"

    # Headers for the token request
    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    try:
        # Send POST request to obtain the token
        response = requests.post(
            auth_url, data=payload, headers=headers, verify=verifySSL
        )
        response.raise_for_status()  # Raises HTTPError for bad responses

        # Parse the JSON response
        token_info = response.json()

        if token_info.get("access_token") is None:
            print("Error: Access token not found in the response.")
            return None

        if print_tokens:
            print(token_info)

        return token_info

    except requests.exceptions.RequestException as e:
        print(f"Error obtaining access token: {e}")
        return None

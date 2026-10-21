import base64
import json
import logging
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from sasram.mcp import tool


API_URL = "https://maps.googleapis.com/maps/api/streetview"
ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
TRAVEL_MODES = ("DRIVE", "WALK", "BICYCLE", "TWO_WHEELER")
logger = logging.getLogger(__name__)


def _read_response(request: str | Request, service: str, api_key: str) -> tuple[bytes, str]:
    for attempt in range(2):
        try:
            with urlopen(request, timeout=10) as response:
                return response.read(), response.headers.get_content_type()
        except HTTPError as error:
            if attempt or error.code not in (408, 500, 502, 503, 504):
                raise
            _log_http_error(service, error, api_key)
            error.close()
            logger.warning("%s request failed with HTTP %s; retrying once.", service, error.code)
        except (URLError, TimeoutError) as error:
            if attempt:
                raise
            logger.warning("%s request failed (%s); retrying once.", service, type(error).__name__)
    raise RuntimeError("HTTP request exhausted its retry attempts without a response.")


def _request(path: str, params: dict):
    return _read_response(f"{API_URL}{path}?{urlencode(params)}", "Google Street View", params["key"])


def _error(message: str) -> dict:
    return {"status": "error", "message": message}


def _log_http_error(service: str, error: HTTPError, api_key: str) -> None:
    try:
        details = error.read().decode("utf-8", errors="replace").strip() or "Empty response body."
    except OSError as read_error:
        details = f"Response body could not be read ({type(read_error).__name__})."
    reason = str(error.reason)
    if api_key:
        details = details.replace(api_key, "[REDACTED]")
        reason = reason.replace(api_key, "[REDACTED]")
    logger.error("%s HTTP %s: %s; response: %s", service, error.code, reason, details[:8192])


def _waypoint(location: str) -> dict:
    try:
        latitude, longitude = (float(part) for part in location.split(","))
        return {"location": {"latLng": {"latitude": latitude, "longitude": longitude}}}
    except ValueError:
        return {"address": location}


@tool
def get_street_view(location: str, heading: float = 0, pitch: float = 0, fov: float = 90) -> dict:
    """Retrieve Google Street View imagery for a visual site review.

    Call only when location-specific visual context is needed.
    location: Address or 'latitude,longitude' (latitude first).
    heading: Compass bearing [0,360]; 0 is north, 90 east, 180 south, 270 west.
    pitch: Camera tilt [-90,90]; 0 is level.
    fov: Horizontal field of view [10,120]; default 90 for site overviews.
    For zoom follow-ups, explicitly copy the reference location and heading,
    keeping pitch=0. Zoom in: halve its fov (minimum 10). Zoom out: double its
    fov (maximum 120). Honor a requested fov within [10,120]. At a limit, explain
    that further zoom is unavailable. Call once per requested reference view,
    with all calls in the same step. Ask which view if ambiguous.
    This tool does not navigate along streets.
    Returns status, metadata and image {mimeType, data (base64)}.
    The agent must pass the image to a vision model, not treat base64 as text.
    """
    location = location.strip()
    if not location or not (0 <= heading <= 360 and -90 <= pitch <= 90 and 10 <= fov <= 120):
        return _error("Provide a location, heading [0,360], pitch [-90,90] and fov [10,120].")
    api_key = os.getenv("GOOGLE_MAPS_API_KEY", "").strip()
    if not api_key:
        return _error("Configure GOOGLE_MAPS_API_KEY on the MCP server.")
    try:
        data, _ = _request("/metadata", {"location": location, "key": api_key})
        metadata = json.loads(data)
        if metadata.get("status") != "OK":
            return _error(f"Google Street View status: {metadata.get('status', 'UNKNOWN')}.")
        image, mime_type = _request("", {
            "pano": metadata["pano_id"], "size": "640x640", "heading": heading,
            "pitch": pitch, "fov": fov, "return_error_code": "true", "key": api_key,
        })
        if mime_type != "image/jpeg" or not image.startswith(b"\xff\xd8\xff"):
            return _error("Google did not return a JPEG image.")
        return {
            "status": "ok",
            "metadata": {
                "requested_location": location, "panorama_location": metadata["location"],
                "capture_date": metadata.get("date"), "copyright": metadata.get("copyright", ""),
                "attribution": "Google Maps", "heading": heading, "pitch": pitch, "fov": fov,
                "size": "640x640",
            },
            "image": {"mimeType": mime_type, "data": base64.b64encode(image).decode("ascii")},
        }
    except HTTPError as error:
        _log_http_error("Google Street View", error, api_key)
        return _error(f"Google returned HTTP {error.code}; check coverage, API enablement, billing and quota.")
    except (URLError, TimeoutError):
        return _error("Street View request failed or timed out.")
    except (ValueError, TypeError, KeyError, AttributeError):
        return _error("Google returned an invalid response.")


@tool
def get_street_distance(origin: str, destination: str, travel_mode: str = "DRIVE") -> dict:
    """Calculate the street (route) distance and travel time between two locations.

    Uses Google Routes, so this is distance along roads or paths, not straight-line distance.
    origin, destination: Address or 'latitude,longitude' (latitude first).
    travel_mode: DRIVE (default), WALK, BICYCLE or TWO_WHEELER.
    Returns status, distance_meters, distance_km and duration_minutes.
    """
    origin, destination, travel_mode = origin.strip(), destination.strip(), travel_mode.strip().upper()
    if not origin or not destination or travel_mode not in TRAVEL_MODES:
        return _error(f"Provide an origin, a destination and a travel_mode in {', '.join(TRAVEL_MODES)}.")
    api_key = os.getenv("GOOGLE_MAPS_API_KEY", "").strip()
    if not api_key:
        return _error("Configure GOOGLE_MAPS_API_KEY on the MCP server.")
    body = {"origin": _waypoint(origin), "destination": _waypoint(destination), "travelMode": travel_mode}
    request = Request(ROUTES_URL, data=json.dumps(body).encode(), method="POST", headers={
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
    })
    try:
        data, _ = _read_response(request, "Google Routes", api_key)
        routes = json.loads(data).get("routes")
        if not routes:
            return _error("Google found no route between these locations.")
        meters = routes[0].get("distanceMeters", 0)
        return {
            "status": "ok", "origin": origin, "destination": destination, "travel_mode": travel_mode,
            "distance_meters": meters, "distance_km": round(meters / 1000, 2),
            "duration_minutes": round(float(routes[0].get("duration", "0s").rstrip("s")) / 60, 1),
        }
    except HTTPError as error:
        _log_http_error("Google Routes", error, api_key)
        return _error(f"Google Routes returned HTTP {error.code}; check that the Routes API is enabled for this key.")
    except (URLError, TimeoutError):
        return _error("Routes request failed or timed out.")
    except (ValueError, TypeError, KeyError, AttributeError):
        return _error("Google returned an invalid response.")
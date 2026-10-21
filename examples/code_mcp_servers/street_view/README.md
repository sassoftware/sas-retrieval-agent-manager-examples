# Google Street View Code MCP Server

This Code MCP server provides Google Street View imagery and road or path route distances for SAS Retrieval Agent Manager (RAM).

## Template Files

- `run.py`: MCP tool implementations and definitions

## Tools

### `get_street_view(location: str, heading: float = 0, pitch: float = 0, fov: float = 90) -> dict`

Retrieves a 640 x 640 Street View panorama for an address or `latitude,longitude` location. Coordinates must be latitude first.

- `heading`: compass bearing from 0 to 360 degrees
- `pitch`: camera tilt from -90 to 90 degrees
- `fov`: horizontal field of view from 10 to 120 degrees
- Output: status, panorama metadata (including capture date when available), and a JPEG image encoded as base64 in `image.data`

The capture date describes the selected panorama; this tool does not select historical imagery. The returned metadata includes Google attribution. Pass the decoded image to a vision-capable model when visual analysis is needed; base64 is not image text.

### `get_street_distance(origin: str, destination: str, travel_mode: str = "DRIVE") -> dict`

Calculates route distance and estimated travel time using Google Routes. This is distance along a supported road or path, not straight-line distance.

- Locations: addresses or `latitude,longitude` coordinates, latitude first
- `travel_mode`: `DRIVE`, `WALK`, `BICYCLE`, or `TWO_WHEELER`
- Output: status, distance in meters and kilometers, and duration in minutes

## Setup

1. In a Google Cloud project, enable the Street View Static API and Routes API, and configure billing and API quotas.
2. Create an API key restricted to the APIs used by this server.
3. In the RAM Code MCP server template, use `run.py` and configure `GOOGLE_MAPS_API_KEY` as a secret environment variable.
4. Save and publish the template, create an MCP Tool Server from it, and register the tools with an agent.

No additional Python packages are required beyond the `sasram` runtime provided by RAM. Both tools require network access and are subject to Google Maps Platform coverage, quotas, billing, and terms. Street View imagery is available only where Google has panorama coverage.

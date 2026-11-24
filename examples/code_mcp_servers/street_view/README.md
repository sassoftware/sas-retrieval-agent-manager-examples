# Google Street View Code MCP Server

This Code MCP server provides Google Street View imagery and road or path route distances for SAS Retrieval Agent Manager (RAM).

See the [Street View Agent example](../../agents/street_view_agent/) for an agent that displays these images in chat and answers follow-up questions.

## Template Files

- `run.py`: MCP tool implementations and definitions

## Tools

### `get_street_view`

Retrieves a 640 x 640 Street View panorama for an address or `latitude,longitude` location. Coordinates must be latitude first.

- `heading`: compass bearing from 0 to 360 degrees
- `pitch`: camera tilt from -90 to 90 degrees
- `fov`: horizontal field of view from 10 to 120 degrees
- Returns an image with its location, camera settings, capture date when available, and attribution.

Images may not reflect current conditions. Use a vision-capable model to answer questions about what is visible.

### `get_street_distance`

Calculates route distance and estimated travel time using Google Routes. This is distance along a supported road or path, not straight-line distance.

- Locations: addresses or `latitude,longitude` coordinates, latitude first
- `travel_mode`: `DRIVE`, `WALK`, `BICYCLE`, or `TWO_WHEELER`
- Output: status, distance in meters and kilometers, and duration in minutes

## MCP Server Setup

1. In a Google Cloud project, enable the Street View Static API and Routes API, and configure billing and API quotas.
2. Create an API key restricted to the APIs used by this server.
3. In the RAM Code MCP server template, use `run.py` and configure `GOOGLE_MAPS_API_KEY` as a secret environment variable.
4. Save and publish the template, create an MCP Tool Server from it, and register the tools with an agent.

The MCP server uses the Python standard library and the `sasram` runtime provided by RAM. Both tools require network access and are subject to Google Maps Platform coverage, quotas, billing, and terms. Street View imagery is available only where Google has panorama coverage.

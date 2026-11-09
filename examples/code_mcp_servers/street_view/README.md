# Google Street View Code MCP Server

This Code MCP server provides Google Street View imagery and road or path route distances for SAS Retrieval Agent Manager (RAM).

The accompanying Code Agent runner uses a generic tool loop to analyze images, answer follow-up questions, and combine results from other attached tools.

## Template Files

- `run.py`: MCP tool implementations and definitions
- `agent_run.py`: reusable RAM Code Agent runner that passes tool-generated images to the model and renders images, metadata, and the model's answer in chat

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

## MCP Server Setup

1. In a Google Cloud project, enable the Street View Static API and Routes API, and configure billing and API quotas.
2. Create an API key restricted to the APIs used by this server.
3. In the RAM Code MCP server template, use `run.py` and configure `GOOGLE_MAPS_API_KEY` as a secret environment variable.
4. Save and publish the template, create an MCP Tool Server from it, and register the tools with an agent.

The MCP server uses the Python standard library and the `sasram` runtime provided by RAM. Both tools require network access and are subject to Google Maps Platform coverage, quotas, billing, and terms. Street View imagery is available only where Google has panorama coverage.

## Code Agent Setup

1. Create a RAM Code Agent template and copy `agent_run.py` into its `run.py`.
2. Configure the agent to use a vision-capable model and a RAM LangGraph agent with a `tools` node. The runner uses `langchain_core` and `sasram` from the RAM agent runtime.
3. Attach `get_street_view` and `get_street_distance` as needed. Attach other tools, such as destination lookup tools, for your use case.
4. Configure the agent's system prompt for the intended task, then save and publish the template and create an agent experiment.

The runner does not branch on tool names. It supports text results, MCP text and image content, structured JSON content, and JSON payloads containing an `image` object with base64 `data` and `mimeType`. Other tool servers using these formats can reuse the runner without Street View-specific code.

## Agent Behavior

- The model selects tools, receives their text results and images, and can request more tools before answering. Images are supplied as image content, not base64 text for the model to interpret.
- Tool-generated images appear in chat as numbered Markdown previews with the returned metadata. Supported user attachments are also previewed.
- Follow-ups use session text history, including previous observations and metadata. Earlier image content is omitted from subsequent turns to reduce repeated image costs; the model can fetch images again when it needs new visual evidence.
- Camera selection is model-driven. The runner does not automatically expand an overview into four compass views. Request specific headings or configure the agent's prompt when multiple views are needed.
- For zoom follow-ups, the Street View tool instructions tell the model to reuse the reference location and heading and adjust `fov` within 10 to 120 degrees. This changes the camera view, not the panorama location or capture date.
- Images-only requests instruct the model to omit analysis. Visual answers are instructed to distinguish visible evidence from uncertainty and respect capture dates and attribution.

The runner allows up to five tool rounds per request (`MAX_TOOL_ROUNDS`). Set the optional `TOOL_TIMEOUT` environment variable on the Code Agent to change the per-tool timeout from its default of 30 seconds. Vision support and image costs depend on the configured model.

## Example Requests

- "Show north- and east-facing views of 1 Market Street, San Francisco, and describe the visible sidewalks and entrances."
- "Zoom in on Image 1, keeping the same location and heading."
- "Based on the previous observations, what remains uncertain about the entrance?"
- "What is the walking route distance from 1 Market Street to the Ferry Building, San Francisco?"
- "Show a north-facing view of the Ferry Building, San Francisco. Images only."

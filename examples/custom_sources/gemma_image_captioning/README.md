# Gemma Image Captioning Custom Source

This folder contains a SAS Retrieval Agent Manager (RAM) custom source example that processes uploaded structural diagram PNG images, generates descriptive captions using a Gemma vision-capable model, and writes the structured JSON output to the configured RAM source.

## How It Works

When executed, this source:

1. Downloads the target structural diagram `.png` file from the RAM source 
2. Validates the image content type and sends the PNG to the configured Gemma model endpoint
3. Generates a structured text description/caption of the structural diagram
4. Saves the resulting JSON caption file back to the RAM source so downstream collections can index and retrieve information from the diagram

## Files

### Custom Source Job Files
- `run.py`: Custom source implementation executed by the RAM custom source job. Downloads the PNG from the RAM source, runs Gemma inference, and saves the JSON output.
- `requirements.txt`: Python dependencies for this custom source.

### External Scripts
> **Note:** `get_token.py` and `upload_source_file.py` are external scripts used to authenticate and upload the structural diagram `.png` file to the RAM source so it can be processed when the custom source job runs.

- `get_token.py`: External utility script to retrieve the bearer token for RAM API requests.
- `upload_source_file.py`: External utility script that uploads the PNG files prior to running the custom source job.

## Output

The source writes the generated analysis to a JSON file at:

- `/tmp/gemma-4B-6-images-per-image-analysis.json`

The file is then uploaded to the configured RAM source (via `client.save_file`) so downstream collections can index and retrieve information from the structural diagrams.

## Dependencies

- `requests`

## Notes and Caveats

- Before triggering the custom source job, you must run `get_token.py` and `upload_source_file.py` to upload the structural diagram `.png` file into the target RAM source.
- Requires `RAM_API_URL`, `SOURCE_ID`, and your Gemma model endpoint environment variables to be configured.
- This source relies on network availability and an active Gemma model endpoint capable of processing PNG images.
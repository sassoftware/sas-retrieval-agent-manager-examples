# Generic Custom Source Instructions

This folder contains examples of custom sources for RAM.

Custom sources are used to fetch or generate external content and save the resulting files into a RAM source so they can be ingested into document collections for retrieval.

Each example should document:

- What data it fetches or generates
- Which dependencies it requires
- What files it writes to the source

## Creating a custom source in RAM

1. In RAM Code Templates, create a custom source template in RAM.
2. Copy the example `run.py` into the template's `run.py`.
3. If needed, copy the example `requirements.txt` into the template's `requirements.txt`.
4. Configure any required environment variables or LLM aliases.
5. Save and publish the template.

## Expected structure

A custom source example will typically contain:

- `run.py`: source implementation
- `requirements.txt`: optional third-party dependencies

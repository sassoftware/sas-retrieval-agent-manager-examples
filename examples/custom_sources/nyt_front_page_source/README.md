# NYT Front Page Custom Source

This folder contains a custom source template that fetches daily headlines from the
New York Times Top Stories API across all 26 NYT sections. Unlike the
[News Custom Source](../news_source/) which focuses on a single category, this source
covers every section of the NYT for a broad overview of the day's top stories.

This custom source is used by the [News Information Finder](../../agents/news_information_finder/)
agent, which has access to all news collections including the NYT front pages collection.

## How It Works

When the source runs, it fetches headlines from all 26 NYT Top Stories sections (arts,
automobiles, books, business, fashion, food, health, home, insider, magazine, movies,
nyregion, obituaries, opinion, politics, realestate, science, sports, sundayreview,
technology, theater, t-magazine, travel, upshot, us, world) and saves each section's
headlines as a separate `.txt` file.

## Setup

### 1. Create the Source Template

1. In RAM, go to **Source Templates** and create a new custom source template.
2. Copy `run.py` into the template's `run.py`.
3. Copy the contents of `requirements.txt` into the template's `requirements.txt`.
4. **Before copying `run.py`**, replace `YOUR_NYT_API_KEY_HERE` with your own NYT API key.
5. Save and publish the template.

### 2. Create a Source from the Template

1. Go to the **Sources** tab and create a new source using the template you just published.
2. Name the source "NYT front page" (or similar).

### 3. Create a Collection

1. Go to the **Collections** tab and create a new collection (e.g., "NYT front pages").
2. Add the source you just created to the collection.
3. Vectorize the collection.

### 4. Set Up Automation

1. Go to the **Automations** tab.
2. Create a new automation that triggers re-vectorization of the collection whenever the
   source's cron job runs.
3. The default schedule is `0 13 * * *` (daily at 1:00 PM UTC). You can change this in
   the source's settings.

## Environment Variables

| Variable | Required | Description |
| -------- | -------- | ----------- |
| `NYT_API_KEY` | Yes | New York Times API key. Get one at [developer.nytimes.com](https://developer.nytimes.com/). Set this in the `run.py` file where indicated. |

> **Important:** Replace the placeholder `YOUR_NYT_API_KEY_HERE` in `run.py` with your
> own NYT API key. Do not commit API keys to version control.

## Dependencies

- `requests` — HTTP client for the NYT API

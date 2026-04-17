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

Follow the [general custom source instructions](../README.md) with these specifics:

- **Environment variables:** Add `NYT_API_KEY` set to your NYT API key
  (get one at [developer.nytimes.com](https://developer.nytimes.com/)).
- **File Update Schedule:** On the `File Update Schedule` tab of the source, change it
  to run on a schedule every day at a minute and hour of your choosing.

## Dependencies

- `requests` — HTTP client for the NYT API

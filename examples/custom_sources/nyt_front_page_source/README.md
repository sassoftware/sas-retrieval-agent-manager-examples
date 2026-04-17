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

1. On the `Code Templates` pane, click `Custom Source`.
2. Add [run.py](./run.py) and [requirements.txt](./requirements.txt)
3. Add an environment variable called `NYT_API_KEY` and set it to your NYT api key (which you can get from [developer.nytimes.com])
4. Save and publish the template.

### 2. Create a Source from the Template

1. Go to the **Sources** pane and create a new source using the template you just published.
2. On the `File Update Schedule` of the source, set it to a schedule and set it to update as often as you'd like. It's recommended to have it update everyday at some hour and minute of your choosing.
3. Click Save and open your newly created source.
4. On the Files tab, click `Syncronize`.
5. On the Jobs tab, you should see your synconization executing. This is where you can see its status.

### 3. Create a Collection

1. Go to the **Collections** pane and create a new collection (e.g., "NYT front pages").
2. Add the source you just created to the collection.
3. Create a new configuration and set the `Configuration update strategy` to `Append, sync, and delete`.
4. Vectorize the collection.

### 4. Set Up Automation

1. Go to the **Automation** pane.
2. Click on the pipeline of your news source's name
3. Hover over the dot on the right side of the yellow rectangle until you see your cursor become a +. Then click and drag your cursor to the right side of the blue rectangle. This tells RAM to re-vectorize your collection every time your custom source updates.

## Environment Variables

| Variable | Required | Description |
| -------- | -------- | ----------- |
| `NYT_API_KEY` | Yes | New York Times API key. Get one at [developer.nytimes.com](https://developer.nytimes.com/)|

## Dependencies

- `requests` — HTTP client for the NYT API

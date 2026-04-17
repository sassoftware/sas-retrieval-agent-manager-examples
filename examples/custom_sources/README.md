# Custom Sources

This folder contains examples of custom source templates built with RAM. Custom sources
let you write Python code that fetches data from external APIs and saves it as documents
for vectorization. Each example includes the code needed (`run.py`/`requirements.txt`)
and details on how to configure the source.

## Creating a Custom Source

Every custom source follows the same steps to set up.

### 1. Create the Source Template

1. On the `Code Templates` pane, click `Custom Source`.
2. Add `run.py` and `requirements.txt` from the example.
3. Add any environment variables the example requires (see the example's README).
4. Save and publish the template.

### 2. Create a Source from the Template

1. Go to the **Sources** pane and create a new source using the template you just published.
2. Click Save and open your newly created source.
3. On the Files tab, click `Synchronize`.
4. On the Jobs tab, you should see your synchronization executing. This is where you can
   see its status.

### 3. Create a Collection

1. Go to the **Collections** pane and create a new collection.
2. Add the source you just created to the collection.
3. Create a new configuration and set the `Configuration update strategy` to
   `Append, sync, and delete`.
4. Vectorize the collection.

### 4. Set Up Automation

1. Go to the **Automation** pane.
2. Click on the pipeline of your source's name.
3. Hover over the dot on the right side of the yellow rectangle until you see your cursor
   become a +. Then click and drag your cursor to the right side of the blue rectangle.
   This tells RAM to re-vectorize your collection every time your custom source updates.

## Examples

| Example | Description |
| ------- | ----------- |
| [News Source](./news_source/) | Parameterized news source that fetches from NYT, Reddit, and Yahoo Finance for a configurable news domain |
| [NYT Front Page Source](./nyt_front_page_source/) | Fetches daily headlines from all 26 NYT Top Stories sections |

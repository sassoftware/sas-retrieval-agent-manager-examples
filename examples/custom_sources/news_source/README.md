# News Custom Source

This folder contains a custom source template that fetches daily news from three sources
(New York Times top stories, Reddit, and Yahoo Finance) and saves them as documents for
vectorization. The source is parameterized by a `CATEGORY` variable that determines which
news domain to fetch.

This custom source is used by the domain-specific news agent examples:

- [Business News Agent](../../agents/business_news_agent/) — `CATEGORY = 'business'`
- [Health News Agent](../../agents/health_news_agent/) — `CATEGORY = 'health'`
- [Science and Technology News Agent](../../agents/science_tech_news_agent/) — `CATEGORY = 'tech'`

You can also create additional sources for other categories by changing the `CATEGORY`
variable (see "Available Categories" below).

## How It Works

When the source runs, it:

1. **NYT Top Stories** — Fetches headlines from the NYT Top Stories API for the
   category's relevant sections and saves them as `.txt` files.
2. **Reddit** — Fetches top posts from the category's relevant subreddits via RSS,
   extracts article content (including following external links), and saves as `.txt` files.
3. **Yahoo Finance** — Fetches sector-specific financial news and saves as `.pdf` files
   (only for categories that have Yahoo Finance sectors mapped).

## Setup

### 1. Create the Source Template

1. On the `Code Templates` pane, click `Custom Source`.
2. Add [run.py](./run.py) and [requirements.txt](./requirements.txt)
3. In run.py, edit the `CATEGORY` variable at the top to match the news
   domain you want (see "Available Categories" below).
4. Add an environment variable called `NYT_API_KEY` and set it to your NYT api key (which you can get from [developer.nytimes.com])
5. Save and publish the template.

### 2. Create a Source from the Template

1. Go to the **Sources** pane and create a new source using the template you just published.
2. Name the source to match the category (e.g., "Business news", "Health news").
3. On the `File Update Schedule` of the source, set it to a schedule and set it to update as often as you'd like. It's recommended to have it update everyday at some hour and minute of your choosing.
4. Click Save and open your newly created source.
5. On the Files tab, click `Syncronize`.
6. On the Jobs tab, you should see your synconization executing. This is where you can see its status.

### 3. Create a Collection

1. Go to the **Collections** pane and create a new collection (e.g., "Business News").
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

## Available Categories

Edit the `CATEGORY` variable in `run.py` to one of the following:

| Category | NYT Sections | Reddit Subreddits | Yahoo Finance Sectors |
| -------- | ------------ | ------------------ | --------------------- |
| `business` | business, home, insider, opinion, realestate | Economics, finance, investing, business, RealEstate, economy, StockMarket, stocks, ValueInvesting | consumer-defensive, financial-services, real-estate |
| `tech` | science, technology | science, technology, artificial, hardware, space, physics, TechNews, programming, cybersecurity, netsec, Futurology | communication-services, energy, technology |
| `global` | home, nyregion, opinion, politics, sundayreview, magazine, upshot, us, world | worldnews, geopolitics, politics, LessCredibleDefence, TrueReddit, uspolitics, europe, Law, SCOTUS, IRstudies, moderatepolitics, PoliticalDiscussion, news, anime_titties, UpliftingNews | (none) |
| `culture` | arts, books/review, fashion, food, movies, obituaries, sports, theater | movies, TrueFilm, television, books, literature, truelit, Art, museum, food, AskCulinary, fashion, malefashionadvice, femalefashionadvice, sports, nba, nfl, soccer, travel, architecture, cars | consumer-cyclical |
| `health` | health | medicine, Health, publichealth, biotech, ScientificNutrition | healthcare |
| `industry` | automobiles | energy, RenewableEnergy, electricvehicles | basic-materials, energy, industrials, utilities |

## Dependencies

- `feedparser` — RSS feed parsing (Reddit)
- `beautifulsoup4` — HTML parsing
- `trafilatura` — Web content extraction
- `fpdf2` — PDF generation (Yahoo Finance articles)
- `yfinance` — Yahoo Finance API

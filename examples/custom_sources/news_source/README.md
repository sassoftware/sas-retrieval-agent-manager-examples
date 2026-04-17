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

1. In RAM, go to **Source Templates** and create a new custom source template.
2. Copy `run.py` into the template's `run.py`.
3. Copy the contents of `requirements.txt` into the template's `requirements.txt`.
4. **Before copying `run.py`**, edit the `CATEGORY` variable at the top to match the news
   domain you want (see "Available Categories" below).
5. Save and publish the template.

### 2. Create a Source from the Template

1. Go to the **Sources** tab and create a new source using the template you just published.
2. Name the source to match the category (e.g., "Business news", "Health news").

### 3. Create a Collection

1. Go to the **Collections** tab and create a new collection (e.g., "Business News").
2. Add the source you just created to the collection.
3. Vectorize the collection.

### 4. Set Up Automation

1. Go to the **Automations** tab.
2. Create a new automation that triggers re-vectorization of the collection whenever the
   source's cron job runs.
3. The default schedule is `0 13 * * *` (daily at 1:00 PM UTC). You can change this in
   the source's settings.

This ensures your news collection stays up to date: the source fetches fresh articles on
schedule, and the automation re-vectorizes the collection with the new content.

## Environment Variables

| Variable | Required | Description |
| -------- | -------- | ----------- |
| `NYT_API_KEY` | Yes | New York Times API key. Get one at [developer.nytimes.com](https://developer.nytimes.com/). Set this in the `run.py` file where indicated. |

> **Important:** Replace the placeholder `YOUR_NYT_API_KEY_HERE` in `run.py` with your
> own NYT API key. Do not commit API keys to version control.

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

# News Custom Source

This folder contains a custom source template that fetches daily news from three sources
(New York Times top stories, Reddit, and Yahoo Finance) and saves them as documents for
vectorization. The source is parameterized by a `CATEGORY` variable that determines which
news domain to fetch.

This custom source is used by these domain-specific news agent examples:

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

Follow the [general custom source instructions](../README.md) with these specifics:

- **Template:** Before publishing, edit the `CATEGORY` variable at the top of `run.py`
  to match the news domain you want (see "Available Categories" below).
- **Environment variables:** Add `NYT_API_KEY` set to your NYT API key
  (get one at [developer.nytimes.com](https://developer.nytimes.com/)).
- **Source name:** Name it to match the category (e.g., "Business news", "Health news").
- **File Update Schedule:** On the `File Update Schedule` tab of the source, change it
  to run on a schedule every day at a minute and hour of your choosing.

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

# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

from datetime import date
import os
import time

import requests
import feedparser
from bs4 import BeautifulSoup
import trafilatura
from fpdf import FPDF
import yfinance as yf

# ---------------------------------------------------------------------------
# CHANGE THIS to the news category you want this source to fetch.
# Options: 'business', 'tech', 'global', 'culture', 'health', 'industry'
# ---------------------------------------------------------------------------
CATEGORY = "business"

# ---------------------------------------------------------------------------
# REPLACE THIS with your own NYT API key from https://developer.nytimes.com/
# ---------------------------------------------------------------------------
NYT_API_KEY = "YOUR_NYT_API_KEY_HERE"


# ---------------------------------------------------------------------------
# Category-to-source mappings
# ---------------------------------------------------------------------------

CATEGORY_TO_NYT_SECTORS = {
    "business": ["business", "home", "insider", "opinion", "realestate"],
    "tech": ["science", "technology"],
    "global": [
        "home", "nyregion", "opinion", "politics", "sundayreview",
        "magazine", "upshot", "us", "world",
    ],
    "culture": [
        "arts", "books%2Freview", "fashion", "food", "movies",
        "obituaries", "sports", "theater",
    ],
    "health": ["health"],
    "industry": ["automobiles"],
}

CATEGORY_TO_SUBREDDITS = {
    "business": [
        "Economics", "finance", "investing", "business", "RealEstate",
        "economy", "StockMarket", "stocks", "ValueInvesting",
    ],
    "tech": [
        "science", "technology", "artificial", "hardware", "space",
        "physics", "TechNews", "programming", "cybersecurity", "netsec",
        "Futurology",
    ],
    "global": [
        "worldnews", "geopolitics", "politics", "LessCredibleDefence",
        "TrueReddit", "uspolitics", "europe", "Law", "SCOTUS",
        "IRstudies", "moderatepolitics", "PoliticalDiscussion", "news",
        "anime_titties", "UpliftingNews",
    ],
    "culture": [
        "movies", "TrueFilm", "television", "books", "literature",
        "truelit", "Art", "museum", "food", "AskCulinary", "fashion",
        "malefashionadvice", "femalefashionadvice", "sports", "nba",
        "nfl", "soccer", "travel", "architecture", "cars",
    ],
    "health": [
        "medicine", "Health", "publichealth", "biotech", "ScientificNutrition",
    ],
    "industry": [
        "energy", "RenewableEnergy", "electricvehicles",
    ],
}

CATEGORY_TO_YAHOO_SECTORS = {
    "business": ["consumer-defensive", "financial-services", "real-estate"],
    "tech": ["communication-services", "energy", "technology"],
    "culture": ["consumer-cyclical"],
    "health": ["healthcare"],
    "industry": ["basic-materials", "energy", "industrials", "utilities"],
}


# ---------------------------------------------------------------------------
# NYT Top Stories
# ---------------------------------------------------------------------------

def get_headlines(sector) -> str:
    url = f"https://api.nytimes.com/svc/topstories/v2/{sector}.json"

    try:
        response = requests.get(url, params={"api-key": NYT_API_KEY})
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        if getattr(e.response, "status_code", None) == 429:
            time.sleep(60)
            try:
                response = requests.get(url, params={"api-key": NYT_API_KEY})
                response.raise_for_status()
            except requests.exceptions.RequestException:
                return ""
        else:
            return ""

    results = response.json().get("results", [])
    if not results:
        return ""
    return "\n".join([
        f"""
Title: {article['title']}
Abstract: {article['abstract']}
Published Date: {article['published_date']}
Section: {article['section']}
Subsection: {article['subsection']}
Topics: {', '.join(article['des_facet'] + article['org_facet'] + article['per_facet'] + article['geo_facet'])}
"""
        for article in results
    ])


def nyt_exec(client):
    sectors = CATEGORY_TO_NYT_SECTORS[CATEGORY]
    date_str = date.today().strftime("%Y-%m-%d")

    out_files = []
    for sector in sectors:
        content = get_headlines(sector)
        file_name = f"/tmp/nyt-{date_str}-{sector}-sector-news.txt"
        with open(file_name, "w", encoding="utf8") as f:
            f.write(content)
        out_files.append(file_name)
        print(file_name)

    for of in out_files:
        client.save_file(of)

    print("NYT files saved to source!")


# ---------------------------------------------------------------------------
# Reddit
# ---------------------------------------------------------------------------

def extract_article_content(url: str) -> str:
    """Safely extracts text from an external URL."""
    downloaded = trafilatura.fetch_url(url)
    if downloaded is None:
        return "[Failed to download: Site blocking scrapers or timed out]"

    text = trafilatura.extract(downloaded)
    return text if text else "[Failed to extract meaningful text: Incompatible page structure]"


def get_subreddit_news(subreddit_name: str, limit: int = 5) -> list:
    """Fetches top posts via RSS, handles network failures gracefully."""
    url = f"https://www.reddit.com/r/{subreddit_name}/top.rss?t=week&limit={limit}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }

    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"   [!] Network error fetching r/{subreddit_name}. Skipping. Details: {e}")
        return []

    feed = feedparser.parse(response.content)
    articles = []

    for entry in feed.entries:
        title = entry.title
        reddit_url = entry.link
        source_url = reddit_url
        content_text = ""

        if hasattr(entry, "summary"):
            soup = BeautifulSoup(entry.summary, "html.parser")
            text_content = soup.find("div", class_="md")

            if text_content:
                content_text = text_content.get_text(separator="\n", strip=True)
            else:
                link_tag = soup.find("a", string="[link]")
                if link_tag and "href" in link_tag.attrs:
                    source_url = link_tag["href"]
                    content_text = extract_article_content(source_url)
                else:
                    content_text = "[Media/Link Only Post]"

        articles.append({
            "title": title,
            "url": source_url,
            "content": content_text,
        })

    return articles


def save_articles_to_txt(subreddit: str, articles: list, filename: str) -> str:
    """Saves the extracted articles to a formatted text file."""
    if not articles:
        print(f"   No articles to save for r/{subreddit}. Skipping file generation.")
        return ""

    if os.path.exists(filename):
        print(f"   File {filename} already exists. Skipping write.")
        return filename

    with open(filename, "w", encoding="utf-8") as f:
        date_str = date.today().strftime("%Y-%m-%d")
        f.write(f"r/{subreddit} Top Posts - {date_str}\n")
        f.write("=" * 80 + "\n\n")

        for article in articles:
            f.write(f"TITLE: {article['title']}\n")
            f.write(f"URL: {article['url']}\n")
            f.write("-" * 40 + "\n")
            f.write(f"CONTENT:\n{article['content']}\n\n")
            f.write("=" * 80 + "\n\n")

    return filename


def reddit_exec(client):
    subreddits = CATEGORY_TO_SUBREDDITS[CATEGORY]
    date_str = date.today().strftime("%Y-%m-%d")

    out_files = []
    for subreddit in subreddits:
        articles = get_subreddit_news(subreddit, limit=10)
        filename = f"/tmp/reddit-{date_str}-{subreddit}-news.txt"

        out_file = save_articles_to_txt(subreddit, articles, filename)
        if out_file:
            out_files.append(out_file)

    for of in out_files:
        client.save_file(of)

    print(f"Reddit: Successfully generated {len(out_files)} text files!")


# ---------------------------------------------------------------------------
# Yahoo Finance
# ---------------------------------------------------------------------------

def get_article_content(url):
    headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        soup = BeautifulSoup(response.text, "html.parser")
        paragraphs = soup.find_all("p")
        content = ""
        for p in paragraphs:
            text = p.get_text()
            if text == "Oops, something went wrong":
                continue
            else:
                content += text + "\n"
        return content
    else:
        return f"Failed to fetch article (Status Code: {response.status_code})"


def clean_text(text):
    text_cleaned = "".join([i if ord(i) < 128 else " " for i in text])
    text_cleaned = text_cleaned.replace("\n", " ")
    return text_cleaned


def get_yahoo_news(sector):
    tech_sector = yf.Sector(sector)
    ticker = tech_sector.ticker
    news = ticker.news

    all_content = []

    for article in news:
        content = article["content"]
        title = content["title"]
        url = content["canonicalUrl"]["url"]
        print(f"Fetching article: {title}, url: {url}")

        article_content = get_article_content(url)
        article_info = {
            "title": clean_text(title),
            "url": url,
            "date": content["pubDate"],
            "summary": clean_text(content["summary"]),
            "content": clean_text(article_content),
        }
        all_content.append(article_info)

    return all_content


def save_articles_to_pdf(ticker, all_content, filename="news.pdf"):
    pdf = FPDF()
    pdf.add_page()

    date_str = date.today().strftime("%Y-%m-%d")
    pdf.set_font("helvetica", style="B", size=20)
    pdf.cell(40)
    pdf.cell(text=f"{ticker} daily news - {date_str}", align="C")
    pdf.ln(10)

    for article in all_content:
        pdf.set_font("helvetica", size=20)
        pdf.write(text=f"{article['title']}")
        pdf.ln(10)

        pdf.set_font("helvetica", size=12)
        pdf.write(text=f"URL: {article['url']}")
        pdf.ln(10)

        pdf.write(text=f"Publication date: {article['date']}")
        pdf.ln(10)
        pdf.write(text=f"Summary: {article['summary']}")
        pdf.ln(10)
        pdf.write(text=f"Content: {article['content']}")
        pdf.ln(10)

    pdf.output(filename)

    return filename


def yahoo_exec(client):
    if CATEGORY not in CATEGORY_TO_YAHOO_SECTORS:
        return
    sectors = CATEGORY_TO_YAHOO_SECTORS[CATEGORY]
    date_str = date.today().strftime("%Y-%m-%d")

    out_files = []
    for sector in sectors:
        content = get_yahoo_news(sector)
        out_files.append(
            save_articles_to_pdf(
                sector, content, filename=f"/tmp/yahoo-{date_str}-{sector}-news.pdf"
            )
        )

    for of in out_files:
        client.save_file(of)

    print("Yahoo Finance files saved to source!")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def exec(client):
    nyt_exec(client)
    reddit_exec(client)
    yahoo_exec(client)

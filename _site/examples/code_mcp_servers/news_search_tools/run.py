# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

from typing import Literal, Optional
from datetime import datetime
from urllib.parse import quote
import os

import httpx
import requests
import feedparser
from bs4 import BeautifulSoup
import trafilatura
from ddgs import DDGS
import yfinance as yf

from sasram.mcp import tool


@tool
async def search_nyt_headlines(
    query: str,
    begin_date: str = None,
    end_date: str = None,
    page: int = 0,
) -> str:
    """
    Search the New York Times archive for article headlines.

    Args:
        query: The search term to look for.
        begin_date: Optional start date for the search window in YYYYMMDD format.
        end_date: Optional end date for the search window in YYYYMMDD format.
        page: The page number of results (0-indexed). The API returns up to 10 results per page.
    """
    api_key = os.environ.get("NYT_API_KEY")
    if not api_key:
        raise ValueError("NYT_API_KEY environment variable is required but not set.")

    url = "https://api.nytimes.com/svc/search/v2/articlesearch.json"
    params = {
        "q": query,
        "page": page,
        "fl": "headline,pub_date,web_url",
        "api-key": api_key,
    }

    if begin_date:
        params["begin_date"] = begin_date
    if end_date:
        params["end_date"] = end_date

    async with httpx.AsyncClient() as client:
        response = await client.get(url, params=params)
        response.raise_for_status()

        data = response.json()
        docs = data.get("response", {}).get("docs", [])

        if not docs:
            return f"No results found for query: '{query}' on page {page}."

        return "\n".join(
            f"""
Headline: {doc['headline']}
Snippet: {doc['snippet']}
Publication Date: {doc['pub_date']}
Document type: {doc['document_type']}
Section name: {doc.get('section_name', 'N/A')}
Material type: {doc.get('type_of_material', 'N/A')}
"""
            for doc in docs
        )


def _extract_article_content(url: str, max_length: int = 5000) -> str:
    """Safely extracts text from an external URL using trafilatura."""
    downloaded = trafilatura.fetch_url(url)
    if downloaded is None:
        return "[Failed to download: Site blocking scrapers or timed out]"

    text = trafilatura.extract(downloaded)
    if not text:
        return "[Failed to extract meaningful text: Incompatible page structure]"
    if len(text) > max_length:
        return text[:max_length] + " [Content truncated]"
    return text


@tool
def search_reddit(
    query: str,
    subreddit: Optional[str] = None,
    limit: int = 5,
    max_content_length: int = 5000,
) -> str:
    """
    Searches Reddit for a specific query using RSS feeds and extracts content.
    Optionally restricts the search to a specific subreddit.
    If a post is a link to an external article, it attempts to scrape that article.

    Args:
        query: The search term.
        subreddit: (Optional) The name of the subreddit to restrict the search to.
        limit: The maximum number of results to return (default 5).
        max_content_length: Max characters of content to include per result (default 5000).
    """
    encoded_query = quote(query)

    if subreddit:
        url = f"https://www.reddit.com/r/{subreddit}/search.rss?q={encoded_query}&restrict_sr=on&sort=relevance&limit={limit}"
    else:
        url = f"https://www.reddit.com/search.rss?q={encoded_query}&sort=relevance&limit={limit}"

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }

    response = requests.get(url, headers=headers, timeout=10)
    response.raise_for_status()

    feed = feedparser.parse(response.content)

    if not feed.entries:
        return f"No results found for '{query}'."

    results = [
        f"Search Results for '{query}'"
        + (f" in r/{subreddit}" if subreddit else "")
        + ":\n"
        + "=" * 60
    ]

    for i, entry in enumerate(feed.entries, start=1):
        title = entry.title
        link = entry.link

        content_snippet = "No text content"
        if hasattr(entry, "summary"):
            soup = BeautifulSoup(entry.summary, "html.parser")
            text_content = soup.find("div", class_="md")

            if text_content:
                raw_text = text_content.get_text(separator=" ", strip=True)
                content_snippet = raw_text[:max_content_length] + (
                    "..." if len(raw_text) > max_content_length else ""
                )
            else:
                link_tag = soup.find("a", string="[link]")
                if link_tag and "href" in link_tag.attrs:
                    external_url = link_tag["href"]
                    extracted_text = _extract_article_content(
                        external_url, max_content_length
                    )
                    content_snippet = (
                        f"[External URL: {external_url}]\n" + extracted_text
                    )
                else:
                    content_snippet = "[Link/Media Post without standard text]"

        results.append(
            f"{i}. TITLE: {title}\n   REDDIT URL: {link}\n   CONTENT:\n   {content_snippet}\n"
            + "-" * 60
        )

    return "\n".join(results)


@tool
def search_internet(
    query: str,
    max_results: int = 5,
    page_num: int = 1,
    max_content_length_chars: int = 5000,
    timelimit: Optional[Literal["d", "w", "m", "y"]] = None,
) -> list[dict[str, str]]:
    """
    Searches the internet using DuckDuckGo's free internal API.

    Args:
        query: The search string.
        max_results: The maximum number of search results to return.
        max_content_length_chars: The maximum number of characters to include in the
            'content' field for each result. Longer content will be truncated.
        timelimit: Optional time limit for the search.
                   Valid options: "d" (day), "w" (week), "m" (month), "y" (year),
                   None/null (no time limit).

    Returns:
        A list of dictionaries containing 'title', 'href', 'snippet', and 'content'.
    """
    with DDGS() as ddgs:
        to_return = ddgs.text(
            query, max_results=max_results, timelimit=timelimit, page=page_num
        )
    for result in to_return:
        result["snippet"] = result.pop("body", "")
        result["content"] = _extract_article_content(
            result["href"], max_content_length_chars
        )
    return to_return


@tool
def search_yahoo_finance_news(
    query: str,
    max_results: int = 5,
    max_content_length_chars: int = 5000,
) -> list[dict]:
    """
    Search Yahoo Finance for the latest news related to a specific query or stock ticker.

    Args:
        query: The search term or stock ticker (e.g., 'AAPL', 'Interest rates').
        max_results: The maximum number of news articles to return.
        max_content_length_chars: The maximum number of characters to include in the
            'content' field for each article. Longer content will be truncated.
    """
    search_obj = yf.Search(query, news_count=max_results)
    news_items = search_obj.news

    if not news_items:
        return []

    to_return = [
        {
            "title": item.get("title", ""),
            "publisher": item.get("publisher", ""),
            "link": item.get("link", ""),
            "publish_timestamp": datetime.fromtimestamp(
                item.get("providerPublishTime", 0)
            ).strftime("%Y-%m-%d %H:%M:%S UTC"),
        }
        for item in news_items[:max_results]
    ]
    for article in to_return:
        article["content"] = _extract_article_content(
            article.get("link", ""), max_content_length_chars
        )
    return to_return

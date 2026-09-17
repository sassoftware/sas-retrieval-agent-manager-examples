# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

from datetime import date
import os
import time

import requests

API_KEY = os.environ.get("NYT_API_KEY")

SECTORS = [
    "arts", "automobiles", "books%2Freview", "business", "fashion", "food",
    "health", "home", "insider", "magazine", "movies", "nyregion",
    "obituaries", "opinion", "politics", "realestate", "science", "sports",
    "sundayreview", "technology", "theater", "t-magazine", "travel",
    "upshot", "us", "world",
]


def get_headlines(sector) -> str:
    url = f"https://api.nytimes.com/svc/topstories/v2/{sector}.json"

    try:
        response = requests.get(url, params={"api-key": API_KEY})
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        if getattr(e.response, "status_code", None) == 429:
            time.sleep(60)
            try:
                response = requests.get(url, params={"api-key": API_KEY})
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


def exec(client):
    date_str = date.today().strftime("%Y-%m-%d")

    out_files = []
    for sector in SECTORS:
        content = get_headlines(sector)
        file_name = f"/tmp/{date_str}-{sector}-sector-news.txt"
        with open(file_name, "w", encoding="utf8") as f:
            f.write(content)
        out_files.append(file_name)
        print(file_name)

    for of in out_files:
        client.save_file(of)

    print("Files saved to source!")

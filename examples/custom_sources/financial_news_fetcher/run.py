from datetime import date
import requests

from bs4 import BeautifulSoup
from fpdf import FPDF
import yfinance as yf


# Function to fetch and parse article content
def get_article_content(url):
    headers = {"User-Agent": "Mozilla/5.0"}  # Mimic a browser request
    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        soup = BeautifulSoup(response.text, "html.parser")

        # Extract the main content (this varies by website)
        paragraphs = soup.find_all("p")  # Most articles use <p> for text
        # Join content
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
    # Remove any non-unicode chars
    text_cleaned = ''.join([i if ord(i) < 128 else ' ' for i in text])

    # Remove any newlines
    text_cleaned = text_cleaned.replace("\n", " ")

    return text_cleaned


def get_news():
    tech_sector = yf.Sector("technology")
    ticker = tech_sector.ticker
    news = ticker.news

    all_content = []

    # Fetch and display article content for the first news link
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
            "content": clean_text(article_content)
        }
        all_content.append(article_info)

    return all_content


def save_articles_to_pdf(ticker, all_content, filename="news.pdf"):
    pdf = FPDF()
    pdf.add_page()

    date_str = date.today().strftime("%Y-%m-%d")
    # First add header info
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


def exec(client):
    """
    Uses yFinance to fetch the latest articles for companies in the technology sector.
    """
    date_str = date.today().strftime("%Y-%m-%d")

    out_files = []
    content = get_news()
    out_files.append(
        save_articles_to_pdf("Tech", content, filename=f"/tmp/{date_str}-tech-sector-news.pdf")
    )

    # Save files to source
    for of in out_files:
        client.save_file(of)

    print("Files saved to source!")
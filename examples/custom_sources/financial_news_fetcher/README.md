# Financial News Fetcher Custom Source

This folder contains a RAM custom source example that fetches recent technology-sector financial news, builds a daily PDF digest, and writes the file to the configured RAM source.

## What this source does

When executed, this source:

1. Uses yfinance to get recent technology-sector news metadata.
2. Fetches each article URL and extracts paragraph text.
3. Cleans text for PDF compatibility.
4. Generates a dated PDF digest containing title, URL, publication date, summary, and extracted content.
5. Saves the generated PDF file to RAM using client.save_file.

## Files

- run.py: Custom source implementation.
- requirements.txt: Python dependencies for this source.

## Output

The source writes a daily PDF in this format:

- /tmp/YYYY-MM-DD-tech-sector-news.pdf

The file is then uploaded to the RAM source via client.save_file.

## Dependencies

- fpdf2
- yfinance


## Notes and caveats

- This source relies on external web content and network availability.

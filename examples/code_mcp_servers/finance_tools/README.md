# Finance Tools Code MCP Server

This folder contains a Code MCP server template for finance and basic quantitative analysis workflows in SAS Retrieval Agent Manager (RAM).

The server exposes tools for:

- Fetching current market prices for one or more ticker symbols
- Fetching recent price history for a symbol
- Running simple linear regression predictions
- Computing summary statistics for numeric inputs
- Performing basic arithmetic helpers

## Template Files

- `run.py`: MCP tool implementations and tool definitions
- `requirements.txt`: optional third-party dependencies for this server template

## Tools

### `fetch_current_price(ticker_symbols: list[str]) -> dict[str, float]`

Returns the latest available market price for each ticker symbol in the input list.

- Input: list of ticker symbols (example: `['AAPL', 'MSFT']`)
- Output: dictionary mapping ticker symbol to current price
- Behavior note: if a live price is unavailable, the tool currently returns `-1.0` for that symbol

### `fetch_price_history(ticker_symbol: str)`

Returns the recent historical price data for a ticker symbol.

- Input: single ticker symbol
- Output: recent price history (30 day period)

### `predict_linear(x: list, y: list, x_new: list) -> dict`

Fits a linear regression model and predicts values for new inputs.

- Input:
  - `x`: training inputs
  - `y`: training outputs
  - `x_new`: values to predict
- Output:
  - `predictions`
  - `coef`
  - `intercept`
- Validation: returns an error object if `x` and `y` have different lengths

### `get_summary_statistics(values: list) -> dict`

Computes descriptive statistics for numeric values.

- Input: list of numbers
- Output includes:
  - count, mean, median, std, min, max
  - quartiles (25%, 50%, 75%)
  - skew, kurtosis
- Validation: returns an error object for empty or non-numeric input

### `add(a: float, b: float) -> float`

Returns the sum of two numbers.

### `multiply(a: float, b: float) -> float`

Returns the product of two numbers.

## Environment Variables (optional)

No environment variables are required for this example.

## Notes

- This template uses third-party libraries (`yfinance`, `numpy`, `scikit-learn`) in [run.py](run.py).
- Ensure those dependencies are available in the template environment.
- Market data retrieval depends on external data availability and network access.

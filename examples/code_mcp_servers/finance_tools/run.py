import numpy as np
from sklearn.linear_model import LinearRegression
import yfinance as yf

from sasram.mcp import tool


@tool
def fetch_current_price(ticker_symbols: list[str]) -> dict[str, float]:
    """Returns the current prices for a group of tickers. A dictionary is returned where
    the keys are the ticker strings and the values are ticker's price."""

    price_dict = {}
    for t in ticker_symbols:
        ticker = yf.Ticker(t)

        # Get a specific field like 'currentPrice' or 'regularMarketPrice'
        live_price = ticker.info.get('currentPrice') or ticker.info.get('regularMarketPrice')
        if not live_price:
            print("Live price not directly available in .info, using historical.")
            live_price = -1.0

        price_dict[t] = live_price
    return price_dict


@tool
def fetch_price_history(ticker_symbol: str):
    """Returns the closing price for a symbol for each of the last 30 days"""
    data = yf.download(ticker_symbol, period="30d") # 'period="30d"' gets the last 30 trading days
    return data


@tool
def predict_linear(x: list, y: list, x_new: list) -> dict:
    """Fit a simple linear regression model and predict values for new inputs.

    Args:
        x: List of numeric inputs for training.
        y: List of numeric outputs for training.
        x_new: List of numeric inputs to predict.
    """
    if len(x) != len(y):
        return {"error": "x and y must have the same length"}

    X = np.array(x).reshape(-1, 1)
    Y = np.array(y)
    model = LinearRegression()
    model.fit(X, Y)

    predictions = model.predict(np.array(x_new).reshape(-1, 1))
    return {"predictions": predictions.tolist(), "coef": model.coef_[0], "intercept": model.intercept_}


@tool
def get_summary_statistics(values: list) -> dict:
    """Compute descriptive statistics for a 1-D list of numbers.

    Args:
        values: A list of numeric values.
    """
    if not values:
        return {"error": "Input list is empty."}

    try:
        arr = np.array(values, dtype=float)
    except Exception:
        return {"error": "Values must be numeric."}

    stats = {
        "count": len(arr),
        "mean": float(np.mean(arr)),
        "median": float(np.median(arr)),
        "std": float(np.std(arr, ddof=1)),
        "min": float(np.min(arr)),
        "max": float(np.max(arr)),
        "quartiles": {
            "25%": float(np.percentile(arr, 25)),
            "50%": float(np.percentile(arr, 50)),
            "75%": float(np.percentile(arr, 75)),
        },
        "skew": float(((arr - arr.mean())**3).mean() / arr.std()**3) if arr.std() != 0 else 0.0,
        "kurtosis": float(((arr - arr.mean())**4).mean() / arr.std()**4 - 3) if arr.std() != 0 else 0.0,
    }

    return stats


@tool
def add(a: float, b: float) -> float:
    """Returns the sum of a and b"""
    return a + b

@tool
def multiply(a: float, b: float) -> float:
    """Returns the product of a and b"""
    return a * b
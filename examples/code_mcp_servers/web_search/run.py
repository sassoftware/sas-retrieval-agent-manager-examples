from typing import List, Dict

from sasram.mcp import tool

from ddgs import DDGS


@tool
def search_web(search_str: str) -> List[Dict]:
    """Search the web for a particular query"""
    result =  DDGS().text(search_str, max_results=5)
    return result

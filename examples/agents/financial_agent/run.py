# The goal of this agent is to show how unstructured data could be used along with
# structured data via MCP.

import asyncio
from datetime import datetime
import json
from typing import Any, Dict

from langchain_core.messages import HumanMessage, ToolMessage
from sasram.agent import Client


HELP_CMD = "#help"
DISPLAY_UPDATE_CMD = "#displayupdate"
GENERATE_UPDATE_CMD = "#generateupdate"

# TODO: These could be env vars or options
CLIENT_NAME = "Patricia Clark"
CLIENT_ID = "1dca66e8-077b-4e9e-a82b-0fde1a1dd6a0"

HELP_TEXT = f"""
## Welcome to the RAM Financial Agent w/ MCP

This agent has access to tools for querying a synthetic financial database, searching the
financial documents collection for relevant news, fetching real-time price information,
and generating graphs.

```
  Commands:
  - #help - Return this text.
  - #displayupdate - Returns the daily news summary for {CLIENT_NAME}
  - #generateupdate - Generates the daily news summary for {CLIENT_NAME}
```"""


def get_b64_images(messages) -> str:
    image_str = ""
    for m in messages:
        if isinstance(m, ToolMessage):
            # Check if this is an image result
            try:
                content_dict = json.loads(m.content)
            except json.JSONDecodeError:
                continue

            if isinstance(content_dict, dict):
                try:
                    for c in content_dict["content"]:
                        if c["type"] == "image":
                            image_str += f"![graph](data:image/png;base64,{c['data']})"
                except KeyError:
                    pass

    return image_str


async def exec(text: str, ram_client: Client, options: dict[str, Any]):
    if text == DISPLAY_UPDATE_CMD:
        try:
            summary = ram_client.store.get_all()["summary"]
            return summary + "\n\n" + HELP_TEXT
        except KeyError:
            return "Error fetching daily update from the agent store. Use the '#generateupdate' command to generate a new update."
    if text == GENERATE_UPDATE_CMD:
            summary = await generate_daily_client_summary(ram_client, CLIENT_NAME, CLIENT_ID)
            ram_client.store.set('summary', summary)
            await ram_client._patch_plugin_metadata()
            return summary

    agent = ram_client.get_langgraph_agent(collection_alias=None)

    session_history = ram_client.get_session_history_as_langchain()
    messages = session_history + [HumanMessage(content=text)]

    response = await agent.ainvoke({"messages": messages})
    images = get_b64_images(response["messages"])
    return images + response["messages"][-1].content


async def generate_daily_client_summary(ram_client: Client, client_name: str, client_id: str): 
    agent = ram_client.get_langgraph_agent(collection_alias=None)

    # Step 1. Fetch the client's current investment holdings
    investment_prompt = f"""Fetch the current investment holdings for {client_name}.
Their client ID is {client_id}. You can get their investments from the investments table
in the 'financial' schema of the DB. For each investment, fetch the quantity and purchase price."""
    messages = [HumanMessage(content=investment_prompt)]
    response = await agent.ainvoke({"messages": messages})
    messages = response["messages"]

    # Step 2. For each investment, fetch the current price
    price_prompt = f"""For each holding, fetch the current price to reference later."""
    messages.append(HumanMessage(content=price_prompt))
    response = await agent.ainvoke({"messages": messages})
    messages = response["messages"]

    # Step 3. Look up any relevant news for their investments
    news_prompt = f"""Search the knowledge base for any relevant news
related to {client_name} holdings. Try to find news related to the client's top holdings.
Filter your search to today's date, which is {datetime.now().strftime("%m/%d/%Y")}. You can 
list the files first to find the exact name of the file to filter on.
Then, create a summary of today's news tailored specifically for the client's holdings.
Reference specific holdings they own, how they pertain to the news, as well as include the current
price for that holding. This update will be sent to {client_name} directly, so address it to them."""
    messages.append(HumanMessage(content=news_prompt))
    response = await agent.ainvoke({"messages": messages})
    return response["messages"][-1].content


def init(client) -> str:
    """
    This function will be called daily via the configured automation in RAM.

    When this function is called, the source documents have been updated, so
    it is time to "write" a new newsletter.
    """
    summary = asyncio.run(generate_daily_client_summary(client, CLIENT_NAME, CLIENT_ID))

    client.store.set('summary', summary)

    return "Daily summary generated"
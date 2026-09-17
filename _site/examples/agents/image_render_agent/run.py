import asyncio
from datetime import datetime
import json
from typing import Any, Dict

from langchain_core.messages import HumanMessage, ToolMessage
from sasram.agent import Client


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
    agent = ram_client.get_langgraph_agent()

    session_history = ram_client.get_session_history_as_langchain()
    messages = session_history + [HumanMessage(content=text)]

    response = await agent.ainvoke({"messages": messages})
    images = get_b64_images(response["messages"])
    return images + response["messages"][-1].content

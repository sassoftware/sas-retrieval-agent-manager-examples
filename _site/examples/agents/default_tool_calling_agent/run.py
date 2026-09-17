
from typing import Any, Dict

from langchain_core.messages import HumanMessage
from sasram.agent import Client


async def exec(text: str, ram_client: Client) -> str:
    agent = ram_client.get_langgraph_agent()

    session_history = ram_client.get_session_history_as_langchain()
    messages = session_history + [HumanMessage(content=text)]

    response = await agent.ainvoke({"messages": messages})
    return response["messages"][-1].content


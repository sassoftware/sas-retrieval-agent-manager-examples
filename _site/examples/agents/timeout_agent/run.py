import os

from langchain_core.messages import HumanMessage
from sasram.agent import Client


TOOL_TIMEOUT = int(os.getenv("TOOL_TIMEOUT", "60"))
QUERY_TIMEOUT = int(os.getenv("QUERY_TIMEOUT", "120"))


async def exec(text: str, ram_client: Client) -> str:
    print(f"TOOL_TIMEOUT={TOOL_TIMEOUT}")
    print(f"QUERY_TIMEOUT={QUERY_TIMEOUT}")
    agent = ram_client.get_langgraph_agent(tool_timeout=TOOL_TIMEOUT, query_timeout=QUERY_TIMEOUT)

    session_history = ram_client.get_session_history_as_langchain()
    messages = session_history + [HumanMessage(content=text)]

    response = await agent.ainvoke({"messages": messages})
    return response["messages"][-1].content
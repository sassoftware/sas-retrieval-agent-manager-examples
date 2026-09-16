from langchain_core.messages import HumanMessage
from sasram.agent import Client

SHOW_NOTES_CMD = "shownotes"
CLEAR_NOTES_CMD = "clearnotes"

NOTES_KEY = "notes"

NOTES_UPDATE_PROMPT = """You are maintaining a running set of notes about a conversation.
Update the notes below with any new, useful details from the latest exchange (facts,
preferences, decisions, open questions). Keep the notes short -- a bulleted list is ideal.
Drop anything that is no longer relevant. Only return the updated notes, with no extra
commentary.

Existing notes:
{notes}

Latest user message:
{question}

Latest agent response:
{answer}

Updated notes:"""


def _get_notes(ram_client: Client) -> str:
    try:
        return ram_client.store.get(NOTES_KEY) or ""
    except KeyError:
        return ""


def _normalize_cmd(text: str) -> str:
    # Accept variations like "#show notes", "show notes", or "ShowNotes".
    return text.strip().lstrip("#").replace(" ", "").lower()


async def _update_notes(ram_client: Client, notes: str, question: str, answer: str) -> None:
    prompt = NOTES_UPDATE_PROMPT.format(notes=notes or "(none yet)", question=question, answer=answer)
    response = ram_client.post_query(prompt, direct_llm_query=True)

    ram_client.store.set(NOTES_KEY, response.response.answer)
    await ram_client._patch_plugin_metadata()


async def exec(text: str, ram_client: Client) -> str:
    # Debug commands read/write the store directly, bypassing the LLM, so you can verify
    # what is actually persisted -- including across brand-new conversations/sessions.
    cmd = _normalize_cmd(text)
    if cmd == SHOW_NOTES_CMD:
        return _get_notes(ram_client) or "(no notes stored yet)"
    if cmd == CLEAR_NOTES_CMD:
        ram_client.store.set(NOTES_KEY, "")
        await ram_client._patch_plugin_metadata()
        return "Notes cleared."

    # Fetch any notes saved from earlier turns before running the query.
    notes = _get_notes(ram_client)

    query = text
    if notes:
        query = f"Notes from earlier in this conversation:\n{notes}\n\nUser message: {text}"

    agent = ram_client.get_langgraph_agent()
    session_history = ram_client.get_session_history_as_langchain()
    messages = session_history + [HumanMessage(content=query)]

    response = await agent.ainvoke({"messages": messages})
    answer = response["messages"][-1].content

    # Summarize the exchange and persist the updated notes for the next turn.
    await _update_notes(ram_client, notes, text, answer)

    return answer

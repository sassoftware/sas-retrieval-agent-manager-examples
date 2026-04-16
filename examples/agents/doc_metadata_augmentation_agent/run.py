from pathlib import Path

from typing import Any
from sasram.agent import Client

def exec(text: str, client: Client, options: dict[str, Any]):
    docs = client.retrieve_docs(
        prompt=text,
        search_kwargs={
            "k": 40,
        }
    )
    context_str = "\n"
    for idx, d in enumerate(docs):
        context_str += f"Chunk: {idx}\n"
        context_str += f"Document: {Path(d.metadata['source']).name}\n"
        context_str += f"Page number: {d.metadata['page_number']}\n"
        context_str += f"Text: {d.page_content}\n\n"

    prompt = f"""Use the following context to answer the user's question.

    Question: {text}

    Context: {context_str}
    """

    response = client.post_query(prompt, direct_llm_query=True)
    return response.response.answer
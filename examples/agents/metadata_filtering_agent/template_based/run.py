import json

from sasram.agent import Client


def _parse(text: str) -> tuple[str, dict[str, object]]:
    content = text.strip()
    # Without a directive, use the whole prompt as an unfiltered retrieval question.
    if not content.lower().startswith("#filters:"):
        return content, {}

    # Optional first line: #filters: {"priority": "high"}; the question follows below.
    directive, _, question = content.partition("\n")
    try:
        filters = json.loads(directive.split(":", 1)[1].strip())
    except json.JSONDecodeError as error:
        raise ValueError("#filters must contain valid JSON.") from error

    if not isinstance(filters, dict):
        raise ValueError("#filters must contain a JSON object.")

    return question.strip(), filters


async def exec(text: str, ram_client: Client) -> str:
    try:
        question, filters = _parse(text)
    except ValueError as error:
        return str(error)

    if not question:
        return "Include a question after the retrieval directives."

    search_kwargs: dict[str, object] = {"k": 10}
    if filters:
        # Keys and values must match metadata already present in the collection.
        search_kwargs["filter"] = filters

    # RAM retrieves up to 10 matching results and generates the answer.
    response = ram_client.post_query(
        prompt=question,
        search_kwargs=search_kwargs,
        persistent=False,
    )
    return response.response.answer
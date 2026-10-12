import json

from sasram.agent import Client


def _parse(text: str) -> tuple[str, dict[str, object]]:
    content = text.strip()
    if not content.lower().startswith("#filters:"):
        return content, {}

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
        search_kwargs["filter"] = filters

    # Tags and metadata are applied together before semantic ranking.
    response = ram_client.post_query(
        prompt=question,
        search_kwargs=search_kwargs,
        persistent=False,
    )
    return response.response.answer
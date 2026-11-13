"""Let RAM's LangGraph agent run tools, then render image results as chat previews.

Visual analysis requires RAM's tool adapter to deliver images to the vision model;
extracting Markdown previews after execution does not provide vision input.
"""

import json
import re
from typing import Any
from urllib.parse import quote

from langchain_core.messages import BaseMessage, HumanMessage, ToolMessage, convert_to_messages
from sasram.agent import Client

DATA_URL = re.compile(r"data:[^\s()\"]*?;base64,[A-Za-z0-9+/=%]+")


def _text(message: BaseMessage) -> str:
    if isinstance(message.content, str):
        return message.content
    return "\n".join(
        part if isinstance(part, str) else part.get("text", "")
        for part in message.content
    )


def _strip_image_text(text: str) -> str:
    # Keep historical image labels without resending base64 or broken Markdown.
    text = DATA_URL.sub("[image omitted]", text)
    return re.sub(r"!\[([^\]\n]*)\]\(\[image omitted\]\)", r"\1 (image omitted)", text)


def _strip_images(message: BaseMessage) -> BaseMessage:
    """Keep text from earlier turns without retaining their image content."""
    if isinstance(message.content, str):
        content = _strip_image_text(message.content)
    else:
        content = [
            _strip_image_text(part) if isinstance(part, str)
            else {**part, "text": _strip_image_text(part["text"])}
            for part in message.content
            if isinstance(part, str) or (part.get("type") == "text" and isinstance(part.get("text"), str))
        ]
    return message.model_copy(update={"content": content})


def _attachments(messages: list[BaseMessage]) -> str:
    """Build display previews for user attachments, independently of model input."""
    previews: list[str] = []
    for message in messages:
        if message.type != "human" or not isinstance(message.content, list):
            continue
        for block in message.content:
            if not isinstance(block, dict) or block.get("type") not in ("image", "image_url", "file"):
                continue
            source, file, extras = (
                value if isinstance(value, dict) else {}
                for value in (block.get("source"), block.get("file"), block.get("extras"))
            )
            name = str(block.get("filename") or file.get("filename") or extras.get("name")
                       or f"Attachment {len(previews) + 1}")
            name = re.sub(r"([\\`*_{}\[\]()<>#!|])", r"\\\1", name.replace("\n", " ").replace("\r", " "))
            mime = block.get("mime_type") or block.get("mimeType") or source.get("media_type")
            image_url = block.get("image_url")
            url = image_url.get("url") if isinstance(image_url, dict) else image_url
            url = url or block.get("url") or source.get("url") or file.get("file_data") or block.get("file_data")
            data = block.get("base64") or block.get("data") or source.get("data")
            if not url and data and mime:
                url = f"data:{mime};base64,{data}"
            if isinstance(url, str) and url.startswith(("data:", "https://", "http://")):
                is_image = block["type"] in ("image", "image_url") or str(mime).startswith("image/")
                preview = f"{'!' if is_image else ''}[{name}]({quote(url, safe=':/?&=#%+,;@')})"
            else:
                preview = f"{name}: preview unavailable."
            previews.append(f"### Attachment {len(previews) + 1}\n\n{preview}")
    return "## Attached Files\n\n" + "\n\n".join(previews) + "\n\n" if previews else ""


def _image_urls(content: Any) -> list[str]:
    """Extract display URLs after execution; this does not supply vision input."""
    # The tool's image dictionary may arrive as JSON inside MCP text blocks.
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except json.JSONDecodeError:
            return []
    if isinstance(content, list):
        return [url for block in content for url in _image_urls(block)]
    if not isinstance(content, dict):
        return []
    image = content.get("image")
    if isinstance(image, dict) and image.get("data"):
        return [f"data:{image['mimeType']};base64,{image['data']}"]
    if content.get("type") == "text":
        return _image_urls(content.get("text", ""))
    return _image_urls(content.get("structuredContent")) or _image_urls(content.get("content"))


async def exec(text: str, ram_client: Client, messages: list | None = None) -> str:
    current = convert_to_messages(messages) if messages else [HumanMessage(content=text)]
    attachments = _attachments(current)
    history = ram_client.get_session_history_as_langchain()
    # Preserve the latest message's attachments; remove images only from history.
    context = [_strip_images(message) for message in history + current[:-1]] + current[-1:]
    agent = ram_client.get_langgraph_agent()
    # LangGraph owns tool selection, execution, and continuation until an answer.
    response = await agent.ainvoke({"messages": context})

    previews: list[str] = []
    # Only render this invocation's tool results, not images from earlier turns.
    for message in response["messages"][len(context):]:
        if not isinstance(message, ToolMessage):
            continue
        # Some adapters keep the original payload in the tool message's artifact.
        urls = _image_urls(message.content) or _image_urls(getattr(message, "artifact", None))
        for url in urls:
            label = f"Image {len(previews) + 1}"
            url = quote(url, safe=":/?&=#%+,;@")
            previews.append(f"### {label}\n\n![{label}]({url})")
    answer = _text(response["messages"][-1]).strip()
    # Hide the prompt's image-only signal only when previews were extracted.
    if answer == "NO_ANALYSIS_REQUIRED" and previews:
        answer = ""
    return attachments + "\n\n".join(previews + ([answer] if answer else []))
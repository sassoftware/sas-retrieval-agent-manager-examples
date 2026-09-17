import time
from typing import Dict
from logging import getLogger

logger = getLogger(__name__)


async def exec(
    text: str,
    ragu_client
) -> str:
    logger.info(f"Received request: {text}")

    reasoning_effort = "low"
    if text.contains("#low"):
        reasoning_effort = "low"
    elif text.contains("#high"):
        reasoning_effort = "high"

    logger.info(f'Using reasoning effort: {reasoning_effort}')
    try:
        if 'high' in reasoning_effort:
            response = ragu_client.post_query(
                prompt=text,
                collection_name='default',
                llm_name="high_reasoning_llm",
                timeout=20,
            )
            final = response.response.answer
        else:
            if 'low' not in reasoning_effort:
                logger.warning("Reasoning effort was an unknown value, defaulting to 'low'")
            response = ragu_client.post_query(
                prompt=text,
                collection_name='default',
                llm_name="low_reasoning_llm",
                timeout=20,
            )
            final = response.response.answer
    except Exception as e:
        msg = f"Error occurred during query: {str(e)}"
        logger.error(msg)
        return msg

    return final

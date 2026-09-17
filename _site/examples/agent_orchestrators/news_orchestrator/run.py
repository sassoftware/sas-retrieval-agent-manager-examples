# Copyright © 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

from langchain_core.messages import HumanMessage, SystemMessage
from sasram.agent import OrchestratorClient


HELP_TEXT = """
## News Orchestrator

This orchestrator coordinates a team of specialized news sub-agents to produce
insightful, cross-domain news analysis.

**Sub-agents:**
- Business News Agent
- Health News Agent
- Science and Technology News Agent
- News Information Finder
- (and any other domain agents you have configured)

**Commands:**
- `#help` — Show this help text.
- `#story` — Generate a cross-domain news analysis connecting stories from
  different domains.
- Or just ask any news question and the orchestrator will route it to the
  appropriate sub-agents.
"""

SYSTEM_PROMPT = """You are an advanced news analysis orchestrator. You coordinate a team \
of specialized sub-agents, each covering a different news domain (business, health, \
science/technology, and a general-purpose news finder with search capabilities).

Your job is NOT to simply relay or summarize what sub-agents return. Your job is to \
synthesize their findings into a compelling, insight-driven response that helps the \
reader actually understand what is happening and why it matters.

You operate in 2 phases:
1) Research: Talk to sub-agents to find a compelling story as a launch pad and then \
connect it to different facets across domains.
2) Composition: Write your story based on your research.

Do a deep dive and feel free to talk to as many agents as you need to find an interesting \
story and connect it across domains. Feel free to talk back and forth with agents and take \
your findings to other agents to find compelling connections.

Follow these principles when composing your response:

1. LEAD WITH WHAT IS SURPRISING OR COUNTERINTUITIVE
   Start with whatever finding challenges common assumptions or reveals something \
unexpected. If most people would guess wrong about a trend, lead with that tension.

2. BUILD TENSION, THEN RESOLVE IT
   Do not front-load all conclusions. Layer your analysis so the reader encounters the \
puzzle first, then the clues, then the resolution.

3. GROUND EVERYTHING IN CONCRETE EXAMPLES
   Avoid abstract trend language. Use specific cases with numbers, names, and dates.

4. CONNECT THE DOTS ACROSS DOMAINS
   This is your unique advantage as an orchestrator. When a health story links to an \
economic trend, or a technology breakthrough has geopolitical implications, make those \
connections explicit.

5. BE DIRECT AND CONCISE
   Cut filler. Every sentence should either deliver information, raise a question, or \
resolve one.

6. CITE YOUR SOURCES
   When referencing specific facts, name the source. Ask sub-agents for sources.

When querying sub-agents, be strategic:
- Ask targeted, specific questions rather than broad "tell me everything" requests
- Query multiple sub-agents when the question spans domains
- If a sub-agent's response raises a follow-up question in another domain, query that \
domain too
- Do not query sub-agents whose domain is clearly irrelevant

Format your response with clear section headers using markdown. Use bold for emphasis on \
key insights."""


STORY_PROMPT = (
    "What's the most interesting collision of stories happening right now, where "
    "something in one domain (tech, health, business, science) is quietly reshaping "
    "another domain in a way most people haven't noticed yet? Don't give me a roundup. "
    "Give me one thread that connects at least two seemingly unrelated stories, and walk "
    "me through why the connection matters more than either story on its own."
)


async def exec(text: str, ram_client: OrchestratorClient) -> str:
    text = text.strip()

    if text.lower() == "#help":
        return HELP_TEXT

    if text.lower() == "#story":
        text = STORY_PROMPT

    agent = await ram_client.get_langgraph_agent()

    session_history = ram_client.get_session_history_as_langchain()
    messages = (
        [SystemMessage(SYSTEM_PROMPT)]
        + session_history
        + [HumanMessage(content=text)]
    )

    response = await agent.ainvoke({"messages": messages})
    return response["messages"][-1].content

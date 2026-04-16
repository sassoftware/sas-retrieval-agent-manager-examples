# Financial Agent (MCP + RAM)

## Agent Purpose

This example demonstrates an agent that combines structured financial data and unstructured document retrieval in a single Retrieval Agent Manager (RAM) workflow.

At a high level, the agent:

- Looks up a client's holdings from a financial database.
- Fetches current market prices for holdings.
- Searches financial news documents for same-day updates relevant to those holdings.
- Produces and stores a personalized daily summary.

## RAM Setup Summary

1. In RAM Code Templates, create a new Code Agent template.
2. Copy [run.py](run.py) into the template's run.py.
3. Save and publish the template.
4. In Experiments, create a Template-based experiment from this template.
5. Configure LLM, system prompt, tools, collections, and environment variables as documented below.

## Configuration in Code

Edit [run.py](run.py) to set the target client:

- `CLIENT_NAME`
- `CLIENT_ID`

These values are used by the daily summary flow. The current defaults point to a sample client entry from a beta/demo environment, so update them to match your environment and data.

## Runtime Commands

The agent supports these chat commands:

- `#help`: Show available commands.
- `#displayupdate`: Return the most recently stored daily summary.
- `#generateupdate`: Generate a new daily summary and save it.

For normal user prompts, the agent delegates to the RAM LangGraph agent and returns the model response (including inline images when returned by tools).

## System Prompt

Configure the system prompt in your retrieval settings object.

Recommended prompt goals:

- Use tools instead of guessing when financial facts are required.
- Cross-reference holdings, current prices, and retrieved news before summarizing.
- Keep responses concise, accurate, and client-specific.
- Cite or reference supporting retrieved context when possible.

Note: This example does not currently include a separate SYSTEM_PROMPT.md file. Store your finalized prompt in RAM retrieval settings or add a prompt file if you want file-based versioning.

## Tools

Configure these tool groups for the experiment.

### 1) Database Tools

Server type:

- Container MCP server (for example, GenAI Toolbox prebuilt) connected to the financial client database.

Required tools:

- `execute_sql`
- `list_schemas`
- `list_tables`

### 2) Finance Market Tools

Server type:

- Code MCP server (for example, a finance tools template server).

Required tools:

- `fetch_current_price`
- `fetch_price_history`

### 3) Chart Tools

Server type:

- Container MCP server for chart generation.

Required tools:

- `generate_bar_chart`
- `generate_line_chart`
- `generate_pie_chart`

## Collections

Attach one or more collections that contain financial news and supporting context.

Minimum recommendation:

- A daily financial news collection.

Retrieval setting recommendation:

- Enable agentic retrieval.

## Environment Variables

None required for this example.

Use this section in other agents to list all required variables in the format:

- `VARIABLE_NAME`: purpose and expected value format.

## Automation Hook (Optional)

The `init(client)` function in [run.py](run.py) is intended for scheduled RAM automation. When triggered, it generates and stores the daily summary.

## Quick Validation

After setup:

1. Start the experiment.
2. Run `#generateupdate` and confirm a summary is returned.
3. Run `#displayupdate` and confirm the stored summary is returned.
4. Ask a follow-up question about a holding and confirm the response uses tool/data context.

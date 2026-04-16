# Banking Agent (ESG Analysis)

This folder contains a banking agent example built with RAM for Environmental, Social, and Governance (ESG) analysis. It uses document collections
containing annual and pillar reports from multiple European banks to answer ESG and climate
risk questions, generate comparison tables, and produce charts.

## Input to this agent experiment

### Retrieval Settings - System Prompt

Any system prompt will work with this template.

### Tools

This agent does not require any MCP tool servers. It uses RAM's built-in retrieval
(`client.retrieve_docs` and `client.post_query`) directly.

### Collections

Each supported bank requires its own collection, named to match the alias used in the code.
Configure collections AND aliases for:

- `ABN`
- `BBVA`
- `LBP`
- `Deutsche`
- `DNB`
- `ING`
- `Intesa Sanpaolo`
- `Nordea`
- `RBI`
- `UniCredit`

Populate each collection with the corresponding bank's report documents.
Do not enable Agentic retrieval. standard retrieval is used by the agent directly.

### Environment Variables (optional)

None required for this example.

## Runtime commands

This agent supports the following commands:

- `#HELP`: Show available commands and template question list.
- `<question_idx>, <bank_alias>`: Answer a template ESG question for a specific bank
  (or `ALL` to query all banks). Example: `0, ING`
- `#table: <query>`: Ask a question about the embedded ING Pillar 3 climate risk table.
  Example: `#table: What are the highest sectors by value?`
- `#plot: <column>`: Generate a bar chart from the Pillar 3 table for the given column.
  Example: `#plot: column b (Gross carrying amount)`
- `#compare: <group1>, <group2>, <topic>`: Compare two bank groups on a topic. Groups can
  be `large`, `medium`, `small`, or any individual bank alias.
  Example: `#compare: large, small, physical risk`

For any other input, the agent runs a standard retrieval query across all collections
and returns the answer.

## Template questions

The agent includes a set of pre-defined ESG template questions covering:

- Data sources used for climate-related physical risk analysis.
- Granularity level of climate-related physical risk analysis.
- Time horizons considered in climate-related physical risk analysis.

Use the question index and a bank alias (or `ALL`) to run these against the document collections.


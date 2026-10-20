# Skills Code MCP Server

This folder contains a Code MCP server template implementing the conversational agent skills pattern in SAS Retrieval Agent Manager (RAM).

Instead of putting procedural instructions or step-by-step guides directly into an agent system prompt, this server exposes an `invoke_skill` tool. The tool description dynamically lists all available skills in a standardized XML catalog (`<available_skills>`), which is automatically injected into the agent context through the tool schema. When the agent determines a task requires a specific skill, it invokes `invoke_skill` with the skill name to fetch the full instructions on demand.

Users can add, customize, or remove skills simply by uploading or modifying Markdown files in the code template without changing Python code.

## Template Files

- `run.py`: MCP tool implementation and dynamic skill discovery.
- `example_skills/`: Sample markdown skill files demonstrating YAML frontmatter headers.
  - `table_formatter.md`: Instructions for converting raw data into clean Markdown tables.
  - `text_summarizer.md`: Guidelines for summarizing articles and transcripts into executive summaries.
  - `support_ticket_analyzer.md`: Steps for extracting category, sentiment, and priority from support inquiries.

## Tools

### `invoke_skill(skill_name: str) -> str`

Loads and returns the procedural instructions for a skill by name.

- Input: `skill_name` (string, case-insensitive)
- Output: The markdown body of the requested skill instructions
- Tool description: Dynamically generated on startup containing the XML catalog of all discovered skills:

```xml
<available_skills>
  <skill>
    <name>support_ticket_analyzer</name>
    <description>Analyzes customer support inquiries to extract issue category, customer sentiment, and priority level.</description>
  </skill>
  <skill>
    <name>table_formatter</name>
    <description>Formats unorganized text, data records, or raw lists into clean Markdown tables.</description>
  </skill>
  <skill>
    <name>text_summarizer</name>
    <description>Summarizes lengthy articles, transcripts, or reports into structured executive briefings.</description>
  </skill>
</available_skills>
```

## Creating and Adding Skills

Skills are regular Markdown (`.md`) files placed in the template directory alongside `run.py` or in subdirectories.

### Skill Format with Frontmatter

To specify a custom skill name and description, add a YAML frontmatter block at the top of the file:

```markdown
---
name: my_custom_skill
description: Explains how to complete a specific task.
---
# My Custom Skill

Step-by-step instructions for the agent follow here.
```

### Skill Format without Frontmatter

If frontmatter is omitted, the server uses the filename stem (without `.md`) as the skill name, leaves the description empty, and treats the entire file as the skill body.

### Rules and Conventions

- Skill names are case-insensitive when invoked.
- `README.md` is automatically ignored during file scanning.
- Hidden files and folders (names starting with `.`) are ignored.
- Duplicate skill names will cause an error on startup to prevent ambiguous tool lookups.

## Environment Variables (Optional)

No environment variables are required for this example.

## Deployment and Usage in RAM

1. Navigate to **Code Templates** in the RAM navigation menu and click **New template**.
2. Select **Code MCP Server**, enter a name (such as `Skills MCP Server`), and click **Save**.
3. In the template editor:
   - Copy the content of `run.py` into the editor's `run.py`.
   - Add new files for your skills (for example, upload files from `example_skills/`).
4. Click **Publish** to publish version 1.
5. Navigate to **MCP Tools**, click **New MCP tool server**, select **Custom**, and choose your published template.
6. Once the MCP tool server pod starts and reaches `Running` status, navigate to your agent experiment.
7. Under the experiment **Tools** tab, attach the `invoke_skill` tool and save.
8. Start the agent production server. The agent can now discover and invoke skills on demand.

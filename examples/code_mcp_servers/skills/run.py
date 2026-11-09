import html
from pathlib import Path
import re
from typing import Dict, Tuple

from sasram.mcp import mcp

FRONTMATTER_PATTERN = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)$", re.DOTALL)


def parse_skill_file(file_path: Path) -> Tuple[str, str, str]:
    """Parse a markdown file extracting skill name, description, and body.

    Supports optional YAML frontmatter at the top of the file.
    """
    text = file_path.read_text(encoding="utf-8")
    stem_name = file_path.stem

    match = FRONTMATTER_PATTERN.match(text)
    if not match:
        return stem_name, "", text

    header, body = match.group(1), match.group(2)
    name = stem_name
    desc = ""

    for line in header.splitlines():
        trimmed = line.strip()
        if trimmed.startswith("name:"):
            parsed_name = trimmed.split("name:", 1)[1].strip().strip("\"'")
            if parsed_name:
                name = parsed_name
        elif trimmed.startswith("description:"):
            parsed_desc = trimmed.split("description:", 1)[1].strip().strip("\"'")
            if parsed_desc:
                desc = parsed_desc

    return name, desc, body


def discover_skills(base_dir: Path) -> Dict[str, Dict[str, str]]:
    """Scan base directory and subdirectories for markdown skills, ignoring README and hidden paths."""
    discovered: Dict[str, Dict[str, str]] = {}

    for path in sorted(base_dir.rglob("*.md")):
        parts = path.relative_to(base_dir).parts
        if any(part.startswith(".") for part in parts):
            continue
        if path.name.lower() == "readme.md":
            continue

        name, desc, body = parse_skill_file(path)
        normalized_key = name.strip().lower()

        if normalized_key in discovered:
            first_path = discovered[normalized_key]["file_path"]
            err_msg = f"Duplicate skill name '{name}' detected. Colliding files: '{first_path}' and '{path}'"
            raise ValueError(err_msg)

        discovered[normalized_key] = {
            "name": name,
            "description": desc,
            "body": body,
            "file_path": str(path),
        }

    return discovered


def build_available_skills_xml(skills: Dict[str, Dict[str, str]]) -> str:
    """Format discovered skills into standard available_skills XML catalog."""
    xml_lines = ["<available_skills>"]
    for skill_info in skills.values():
        name_esc = html.escape(skill_info["name"])
        desc_esc = html.escape(skill_info["description"])
        xml_lines.append("  <skill>")
        xml_lines.append(f"    <name>{name_esc}</name>")
        xml_lines.append(f"    <description>{desc_esc}</description>")
        xml_lines.append("  </skill>")
    xml_lines.append("</available_skills>")
    return "\n".join(xml_lines)


BASE_DIRECTORY = Path(__file__).resolve().parent
SKILLS = discover_skills(BASE_DIRECTORY)
SKILLS_XML = build_available_skills_xml(SKILLS)

TOOL_DOCSTRING = (
    "Load and return detailed instructions for a skill. Available skills:\n"
    + SKILLS_XML
)


def invoke_skill(skill_name: str) -> str:
    """Load and return instructions for a skill."""
    normalized_query = skill_name.strip().lower()

    if normalized_query in SKILLS:
        matched_skill = SKILLS[normalized_query]
        return matched_skill["body"]

    available = ", ".join(f"'{s['name']}'" for s in SKILLS.values())
    err = f"Unknown skill '{skill_name}'. Available skills: {available}"
    raise ValueError(err)


invoke_skill.__doc__ = TOOL_DOCSTRING
mcp.tool(invoke_skill)

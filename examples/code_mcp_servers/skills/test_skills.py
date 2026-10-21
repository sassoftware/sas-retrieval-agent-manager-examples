import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

# Mock sasram.mcp if running outside an environment where sasram is installed
if "sasram" not in sys.modules and importlib.util.find_spec("sasram") is None:
    mock_mcp_module = MagicMock()
    mock_mcp = MagicMock()
    mock_mcp.tool.side_effect = lambda fn: fn
    mock_mcp_module.mcp = mock_mcp
    sys.modules["sasram"] = MagicMock()
    sys.modules["sasram.mcp"] = mock_mcp_module

# Ensure the skills example folder is on the Python path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from run import (
    build_available_skills_xml,
    discover_skills,
    invoke_skill,
    parse_skill_file,
)


class TestSkillsMCPServer(unittest.TestCase):
    def test_parse_skill_file_with_full_frontmatter(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "sample_skill.md"
            content = (
                "---\n"
                "name: sample_skill\n"
                "description: 'A sample skill for testing purposes.'\n"
                "---\n"
                "# Sample Skill\n"
                "Instructions go here.\n"
            )
            file_path.write_text(content, encoding="utf-8")

            name, desc, body = parse_skill_file(file_path)
            self.assertEqual(name, "sample_skill")
            self.assertEqual(desc, "A sample skill for testing purposes.")
            self.assertEqual(body, "# Sample Skill\nInstructions go here.\n")

    def test_parse_skill_file_without_frontmatter(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "basic_doc.md"
            content = "# Basic Doc\nPlain markdown without frontmatter.\n"
            file_path.write_text(content, encoding="utf-8")

            name, desc, body = parse_skill_file(file_path)
            self.assertEqual(name, "basic_doc")
            self.assertEqual(desc, "")
            self.assertEqual(body, content)

    def test_parse_skill_file_partial_frontmatter(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "desc_only.md"
            content = (
                '---\ndescription: "Only description provided"\n---\nBody content.\n'
            )
            file_path.write_text(content, encoding="utf-8")

            name, desc, body = parse_skill_file(file_path)
            self.assertEqual(name, "desc_only")
            self.assertEqual(desc, "Only description provided")
            self.assertEqual(body, "Body content.\n")

    def test_parse_skill_file_preserves_internal_horizontal_rule(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "hr_test.md"
            content = (
                "---\n"
                "name: hr_skill\n"
                "description: Test with horizontal rules\n"
                "---\n"
                "Section 1\n"
                "---\n"
                "Section 2\n"
            )
            file_path.write_text(content, encoding="utf-8")

            name, desc, body = parse_skill_file(file_path)
            self.assertEqual(name, "hr_skill")
            self.assertEqual(desc, "Test with horizontal rules")
            self.assertEqual(body, "Section 1\n---\nSection 2\n")

    def test_discover_skills_skips_readme_and_hidden(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "README.md").write_text("# Readme", encoding="utf-8")
            (root / ".hidden_folder").mkdir()
            (root / ".hidden_folder" / "secret.md").write_text(
                "# Secret", encoding="utf-8"
            )
            (root / ".hidden_file.md").write_text("# Hidden", encoding="utf-8")

            sub = root / "skills_sub"
            sub.mkdir()
            (sub / "skill_one.md").write_text(
                "---\nname: skill_one\ndescription: Skill 1\n---\nBody 1",
                encoding="utf-8",
            )
            (root / "skill_two.md").write_text(
                "---\nname: skill_two\ndescription: Skill 2 & more <test>\n---\nBody 2",
                encoding="utf-8",
            )

            discovered = discover_skills(root)
            self.assertEqual(len(discovered), 2)
            self.assertIn("skill_one", discovered)
            self.assertIn("skill_two", discovered)

            xml = build_available_skills_xml(discovered)
            self.assertIn("<available_skills>", xml)
            self.assertIn("<name>skill_one</name>", xml)
            self.assertIn(
                "<description>Skill 2 &amp; more &lt;test&gt;</description>", xml
            )

    def test_duplicate_skill_name_raises_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "first.md").write_text(
                "---\nname: duplicate_skill\n---\nFirst", encoding="utf-8"
            )
            sub = root / "sub"
            sub.mkdir()
            (sub / "second.md").write_text(
                "---\nname: DUPLICATE_SKILL\n---\nSecond", encoding="utf-8"
            )

            with self.assertRaises(ValueError) as ctx:
                discover_skills(root)
            self.assertIn("Duplicate skill name", str(ctx.exception))

    def test_invoke_skill_success_and_case_insensitivity(self):
        body = invoke_skill("table_formatter")
        self.assertIn("# Table Formatter Skill", body)

        upper_body = invoke_skill("TABLE_FORMATTER")
        self.assertEqual(body, upper_body)

    def test_invoke_skill_unknown_raises_error(self):
        with self.assertRaises(ValueError) as ctx:
            invoke_skill("non_existent_skill")
        self.assertIn("Unknown skill 'non_existent_skill'", str(ctx.exception))
        self.assertIn("Available skills:", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()

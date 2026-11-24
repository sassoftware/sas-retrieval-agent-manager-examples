---
name: table_formatter
description: Formats unorganized text, data records, or raw lists into clean Markdown tables.
---
# Table Formatter Skill

Use this skill when the user provides unformatted data records, comma-separated values, key-value pairs, or unstructured lists and requests a tabular presentation.

## Instructions

1. Identify the logical columns across all records.
2. Ensure column headers are clear, concise, and capitalized.
3. Align numerical values to the right where appropriate, and text values to the left.
4. Replace empty or missing data fields with a dash (`-`) or `N/A`.
5. If the user does not specify column sorting, preserve the original record order.
6. Return only the formatted Markdown table followed by a brief one-sentence note if any records had missing fields.

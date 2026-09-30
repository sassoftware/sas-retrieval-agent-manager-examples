# Template-Based Metadata and Tag Filtering

This example uses a code agent that applies explicit metadata and tag filters supplied by the user.

The collection contains approximately 6,000 ITSM incidents, including VPN issues, phishing reports, database failures, hardware problems, and software incidents.

## Supported Metadata

- category
- severity
- status
- date
- assigned_it_person

## Example Query

```text
#filters: {"category":"Database","status":"Investigating"}
What database issues are currently under investigation?
```

RAM first applies the exact-match metadata filters and then performs semantic ranking on the remaining records.

## Why Use This Approach?

Use the template-based approach when:

- Exact filtering behavior is required
- Filters are generated programmatically
- Retrieval must be deterministic and reproducible
- Users already know which metadata filters should be applied

## Template-Based vs Agentic Retrieval

This approach gives the caller complete control over retrieval because filters are supplied explicitly.

For many business-facing applications, a tool-based agent with Agentic Retrieval may be simpler because RAM can infer metadata filters from natural-language requests. However, explicit filters are often preferred when accuracy, repeatability, or auditability are important.
# Template-Based Experiment Metadata Filtering

This example uses a code template that applies explicit metadata filters supplied by the user.

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

RAM first applies the exact-match metadata filters and then performs semantic retrieval on the remaining records.

## Why Use This Approach?

Use the template-based approach when:

- Exact filtering behavior is required
- Filters are generated programmatically
- Retrieval must be deterministic and reproducible
- Users already know which metadata filters should be applied

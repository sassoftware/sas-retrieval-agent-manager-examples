---
name: support_ticket_analyzer
description: Analyzes customer support inquiries to extract issue category, customer sentiment, and priority level.
---
# Support Ticket Analyzer Skill

Use this skill when analyzing incoming customer support requests, user complaint emails, or service desk feedback.

## Instructions

1. Parse the customer message and identify the core technical or operational problem.
2. Output a structured analysis containing:
   - **Category**: One of `Billing`, `Authentication`, `Data Access`, `Performance`, or `General Question`.
   - **Urgency / Priority**: One of `Low`, `Medium`, `High`, or `Critical` based on business impact and downtime indicators.
   - **Sentiment**: One of `Positive`, `Neutral`, `Frustrated`, or `Angry`.
   - **Root Cause Hypothesis**: A one-sentence explanation of what likely failed or needs resolution.
   - **Suggested Immediate Action**: The concrete first step the support engineer should take to assist the customer.

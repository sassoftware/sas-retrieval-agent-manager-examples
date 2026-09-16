# AgentStore Notes Agent

This folder contains an agent example that behaves like the default tool calling agent, but
uses the `AgentStore` to remember key details across turns in a conversation.

At a high level, this template shows how to:

- Read a value from `ram_client.store` before running a query.
- Write an updated value to `ram_client.store` after running a query.

## Input to This Agent Experiment

### Retrieval Settings - System Prompt

Any system prompt works for this template.

### Tools

Any MCP tools configured in RAM will work with this template.

### Collections

Any RAM collection will work with this template.

### Environment Variables (optional)

No environment variables are required for this example.

## Runtime Behavior

For each user message:

1. The template fetches any notes saved in the `AgentStore` from previous turns.
2. If notes exist, they're added alongside the user's message before it's sent to the agent.
3. The template invokes the agent and gets the final response.
4. The template asks the LLM to summarize the exchange into an updated set of notes
   (a direct LLM query, without tools or retrieval), and saves those notes back to the
   `AgentStore` with `ram_client.store.set(...)`.

This gives the agent a lightweight form of memory: instead of replaying the entire session
history on every turn, it carries forward a condensed summary of what matters.

### Debug Commands

These commands read/write the store directly, bypassing the LLM, so you can verify what is
actually persisted:

- `#shownotes`: Return the raw notes currently stored in the `AgentStore`.
- `#clearnotes`: Clear the stored notes.
- `#compactnotes`: Condense the stored notes if they've grown too large, keeping the key
  facts, preferences, and decisions but trimming everything else.

Matching ignores case, spaces, and a leading `#`, so `show notes`, `ShowNotes`, and `#shownotes`
all work the same way.

## Why This Is Different From the LLM "Just Remembering"

Within a single, continuous conversation, RAM already replays the full session history to the
LLM on every turn (`ram_client.get_session_history_as_langchain()`). This happens for **every**
template, including [default_tool_calling_agent](../default_tool_calling_agent/), so recall
within one conversation is not unique to this template and isn't a good test of `AgentStore`.

What `AgentStore` actually adds is memory that survives **outside** the current conversation:

- It persists across brand-new conversations/sessions with the same agent.
- It's available to scheduled automation (the `init` hook) with no live chat involved.
- It stays a small, bounded summary instead of growing with every turn of raw transcript.

## Example Prompts

To prove the difference, the test has to break the conversation, not just continue it:

1. In a conversation with this agent, send: `My favorite F1 driver is Lando Norris.`
2. Send `#shownotes` and confirm the stored notes mention Lando Norris.
3. Start a **brand-new conversation/session** with the same agent (not a follow-up message --
   a fresh chat thread).
4. In that new session, send `#shownotes` first -- the notes should still be there even though
   this session has no prior history.
5. Then ask: `What's my favorite driver's next race?` and confirm the agent still knows without
   you repeating who it is.

As a control, repeat the same steps against a plain `default_tool_calling_agent` experiment: in
a new session it will have no memory of your favorite driver at all, since it only relies on
session history.

## Automation Hook (Optional)

There are no automations for this agent.

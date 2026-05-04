<!--
Last updated: 2026-04-23
Owner: hpeluzio
-->

# QAP conversation message persistence and read

How a chat message travels from agent output into `conversation_messages.output` and back out via `GET /conversations/:workflow_id/:conversation_id`. Understanding this flow is required any time you add a new field to an assistant response (citations, confidence scores, tool-call traces, etc.) and need it to survive across reloads.

## Schema

- `models/conversation_message.py:ConversationMessage` — columns: `input: str` (user text), `output: dict | None` (JSON blob), `run_id: uuid | None`.
- `output` is an unstructured JSON column by design. The shape is a contract between the registry (write) and the API service (read), not enforced by the DB.

## Write path: POST /workflows/:id/invoke

1. Workflow runs, producing `output_state`. The workflow orchestrator namespaces agent outputs with the agent alias using `::` (e.g. `rag_agent::citations`). Top-level fields that the workflow builder explicitly maps (like `output_text`) may be unprefixed. See `services/workflow_description/workflow_description_assistant/tools.py` for the mapping logic.
2. `services/registry/registry.py:_invoke_and_persist` projects selected fields from `output_state` into a dict and calls `ConversationService.save_message(..., output=<dict>)`.
3. The dict today contains `{"text": output_state["output_text"], "citations": [...]}`. Citations come from either `output_state["rag_agent::citations"]` (workflow path) or `output_state["citations"]` (direct agent invoke). Pydantic `Citation` models are flattened via `.model_dump()` before being stored.

Anything not included in that projection is lost to history, even if the POST response exposes it.

## Read path: GET /conversations/:workflow_id/:conversation_id

1. `api/services/conversations.py:ConversationsApiService.get` loads messages for the conversation.
2. For each row, constructs `HumanTextMessage(text=m.input)` and, if `m.output` is truthy, `AITextMessage(text=..., citations=...)` where `citations` comes from `m.output.get("citations")`.
3. Response schema: `ConversationRead` contains a list of `ConversationMessagePair`, each with `human` and optional `ai`. Messages arrive as pairs, not a flat sequence. There is no per-message `created_at` in the response.

## Web-platform consumption

`web-platform/app/api/chat/threads/[threadId]/messages/route.ts` flattens pairs into `[user_msg, ai_msg, user_msg, ai_msg, ...]`, synthesizes per-message IDs and timestamps (IDs are deterministic from `threadId + index` for users, from `message_id` for assistants). It maps `pair.ai.citations` (structured) to the `Citation` domain type and falls back to `parseRagOutputText` regex parsing of `[Source N: filename, page X]` markers only when structured citations are empty — useful for legacy rows persisted before 2026-04-23.

## Legacy rows

Pre-2026-04-23 rows have `output = {"text": "..."}` without citations. The read path returns `citations: []` for those. There is no backfill.

## Adding a new assistant-side field

1. Add to the `output` dict projection in `registry.py:_invoke_and_persist`.
2. Add to `AITextMessage` in `api/schemas/traces.py` (Pydantic field with default).
3. Populate in `api/services/conversations.py:ConversationsApiService.get` when reading `m.output`.
4. Update `QBricksMessagesResponse.messages[].ai` in `web-platform/types/api.ts` and consume in the GET route handler.

Missing any of the four steps means the field works in POST (fresh from the agent) but vanishes on reload.

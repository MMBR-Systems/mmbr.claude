# Decision — Suggested Topic guided-response lives in the QAP agent prompt, not in the frontend

**Date:** 2026-05-11
**Status:** Accepted (planned implementation tracked in MMBR-209)
**Context:** Kellen's MemBrain Response Feedback Form, Q2 ("Operations and Control") and Q4 ("Equipment Information") from 2026-05-06.

## Decision

When a user clicks a Suggested Topic pill on the welcome screen (`mmbr.suggested_topics` — currently 5: Basic Plant Information, Drawings & Design Documents, Equipment Information, Operations and Control, Plant History), the **agent (QAP)** is responsible for producing a guide-style follow-up: acknowledge the category, list 3-5 sub-areas relevant to an MBR plant, offer 2-3 example specific questions. No retrieval, no citations on that first turn.

The frontend's only job is to **signal that the message came from a pill click** by attaching `source: "suggested_topic"` to the chat POST. The BFF forwards the flag to QBricks. The QAP agent has a dedicated prompt branch for `source=suggested_topic` that skips retrieval and produces the guide response.

## Context

Today, clicking "Equipment Information" sends the literal string `"Equipment Information"` to `/api/chat/threads/{id}/messages` as the user's message. QBricks treats it as a normal question, runs retrieval, and returns generic plant-related text that Kellen called "AI mumbo jumbo." His explicit feedback: the first response from a category pill should **not** retrieve documents — it should help the user narrow down their question with sub-areas and example prompts. Retrieval only kicks in when the user types a specific technical question.

## Alternatives considered

### Option A — Hardcode per-pill follow-up text on the frontend

**Pros**: Deterministic. No API call on first click. No "AI mumbo jumbo" risk.
**Cons**:
- Requires writing MBR-domain taxonomy (setpoints, HMI behavior, blower sequencing, etc.) for all 5 pills.
- Kellen gave us sample text for 2 of 5 pills (Q2 + Q4); for the other 3 we'd be inventing domain knowledge we don't own.
- Adding a 6th pill in `mmbr.suggested_topics` would require a code change + redeploy.
- Frontend becomes owner of agent-style copy, which is the wrong team's responsibility.

Rejected — we don't have the domain knowledge for all 5 pills, and hardcoding domain content in frontend code is a layering mistake.

### Option B — Wrap the prompt on the frontend (send a long instruction string to the agent)

The frontend builds a string like *"The user clicked the suggested topic 'X'. Respond as a guide, list sub-areas, give example questions, do not retrieve documents…"* and sends that as `message`.

**Pros**: Single repo. Single PR. No coordination with the ai-platform side.
**Cons**:
- `content` passed to `handleSend` in `NewChatClient.tsx` is used for three things at once: the prompt to QBricks, the optimistic user bubble in the chat, and the persisted user message in the DB. They are the same value. Sending the wrapper as `message` means **the user sees the entire scaffolding text as their own message bubble**, both on initial render and on page reload. UX regression vs the current state.
- Prompt engineering lives in frontend code (smell).
- Mitigating the UX issue requires adding a parallel `displayText` field, which expands scope into the BFF anyway.

Rejected — the UX cost is worse than the original "AI mumbo jumbo" problem, and the mitigation defeats the "frontend-only" benefit.

### Option C — Send the wrapper as the prompt, add `displayText` for the user bubble (single repo)

`{ message: <wrapped>, displayText: <pill label> }`. BFF forwards `message` to QBricks, persists `displayText ?? message` for display.

**Pros**: Clean UX. Single repo. No ai-platform coordination needed.
**Cons**:
- Prompt engineering still lives in frontend code (smell).
- Introduces an asymmetry: messages now have an "agent prompt" vs "display text" duality at the API surface, only ever used by this one flow.
- Domain knowledge ownership stays in the wrong layer.

Considered, but inferior to option D once we're already accepting a 2-repo change.

### Option D — Flag the click on the frontend; agent handles the guide branch (chosen)

`{ message: "Equipment Information", source: "suggested_topic" }`. BFF forwards `source` to QBricks. QAP agent detects the flag and switches to a guide-style system prompt that skips retrieval.

**Pros**:
- Domain knowledge (what counts as a sub-area for Equipment Information on an MBR plant) lives in the agent prompt, which is where MBR knowledge already lives.
- User bubble naturally shows the pill label — no `displayText` field needed.
- Frontend stays dumb: it knows "this came from a pill click" but knows nothing about how to respond.
- Adding a 6th pill in `mmbr.suggested_topics` requires zero code change on either side — the generic guide prompt adapts to any label.
- Owner of the response style is the ai-platform team (same people who own the rest of the agent's behavior).

**Cons**:
- Touches two repos (`web-platform` + `ai-platform`).
- Requires coordination with the ai-platform owner (Giovani).
- Slightly more deployment coordination — both sides need to ship before the change is observable end-to-end. Until the QAP side lands, the frontend flag is a no-op.

Chosen.

## Trade-offs accepted

- **Two-repo coordination**: explicitly accepted as the cost of putting domain logic in the right layer. Giovani (ai-platform owner) is already working on related Kellen feedback (Q3 + Q5) in PR #35 — the QAP-side change for this can land alongside or as a sibling PR.
- **Non-determinism**: the agent generates the sub-areas at inference time rather than reading them from a static map. Mitigated by a tightly-scoped system prompt that explicitly forbids retrieval and constrains the response shape (3-5 sub-areas + 2-3 example questions + no citations). If the agent drifts, we tighten the prompt; we don't fall back to per-pill hardcoded text.
- **Until QAP ships, the FE flag does nothing**: deliberate. The frontend half is harmless on its own — manually-typed messages keep their existing shape, and pill clicks send the same `message` they send today plus an ignored extra field.

## Implementation outline

Split across two repos:

1. **`web-platform` — frontend**
   - In `WelcomeScreen.tsx` (`handleTopicSelect`) / `SuggestedTopics.tsx`: when sending a pill click, attach `source: "suggested_topic"` to the request body alongside `message`.
   - In `NewChatClient.tsx::handleSend`: pass through the flag (extend signature or pass an options object).
   - In `types/api.ts`: add `source?: "suggested_topic"` to the relevant request type.

2. **`web-platform` — BFF (`app/api/chat/threads/[threadId]/messages/route.ts`)**
   - Read `source` from the body and forward it to QBricks in the request payload. Exact shape (top-level field, metadata object, etc.) negotiated with the ai-platform side.

3. **`ai-platform` — agent**
   - Recognize `source=suggested_topic` and route to a dedicated system prompt branch that skips retrieval and produces the guide response. Generic across all pill labels.

## Consequences

- The same mechanism scales to any future welcome-screen pill, sidebar quick-action, or similar "category-click" UI element: the frontend sends a `source` tag, the agent has a prompt branch.
- A small API contract now exists between `web-platform` and `ai-platform` around the `source` field. If we add more `source` values later (e.g. `source=onboarding_tutorial`), each one needs a corresponding agent-side branch.
- For users (and reviewers), the user message bubble in chat history shows exactly what the user clicked — no internal prompt text leaks into the UI.
- The frontend never owns MBR-domain copy. Reviewers should flag any future attempt to hardcode plant-specific taxonomy on the frontend as a violation of this decision.

## References

- Jira: MMBR-209 (this implementation), MMBR-199 (parent: review Kellen's feedback)
- Source of feedback: Kellen's MemBrain Response Feedback Form, 2026-05-06 entries (Q2 "Operations and Control", Q4 "Equipment Information"). Located in personal artifacts (Hiago's `.docs/`).
- Touched files (planned): `web-platform/components/chat/{WelcomeScreen.tsx,SuggestedTopics.tsx}`, `web-platform/app/(protected)/chat/NewChatClient.tsx`, `web-platform/app/api/chat/threads/[threadId]/messages/route.ts`, `web-platform/types/api.ts`, plus the agent prompt in `ai-platform`.
- Suggested Topics source data: `mmbr.suggested_topics` (Postgres), seeded in `web-platform/db/seed.sql`.

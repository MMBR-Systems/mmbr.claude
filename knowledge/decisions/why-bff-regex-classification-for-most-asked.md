---
created: 2026-05-13
updated: 2026-05-13
owner: henrique
---

# Decision — BFF-side regex classification for Most Asked Questions

**Status:** Accepted (first pass; revisit on LLM-driven initiative)
**Context:** MMBR-54 spike (Gap Dashboard "Most Asked Questions" tab). Confirmed in Slack with Sara Salazar on 2026-05-13, following planning meeting 2026-05-12.

## Decision

The Most Asked Questions endpoint enriches each gap with `category`, `entityType`, and `isProcessQuestion` **in the BFF, not the backend**. Classification is regex-based over the question text, with fixed enum values hardcoded on the frontend side.

- Logic: `classifyQuestion()` in `web-platform/app/api/gaps/most-asked/route.ts`.
- Enums: `QUESTION_CATEGORIES` and `ENTITY_TYPES` in `web-platform/types/domain.ts`.
  - 5 categories: `process | operations | maintenance | procedure | general`
  - 3 entity types: `alarm | equipment | plant_operations`
- The QAP backend (`ai-platform`) is unaware of these dimensions. `/gaps` returns only `gap_id`, `question`, `confidence`, `times_asked`, `last_occurred`, `plant_id`. The `knowledge_gaps` table has no `category` or `entity` columns.

## Context

The Most Asked Questions tab needs grouping/filtering by category and entity (Kellen's 2026-04-30 feedback, reaffirmed in planning 2026-05-12). Three classification strategies were available; one had to land before the chip-filter UI spike could ship.

## Alternatives considered

### Option A — Backend LLM classification at `record_gap` time
Add `category` and `entity` columns to `knowledge_gaps`. Call the LLM during `record_gap` to classify the question. Expose the fields on `/gaps`.

- Pros: Semantic, scalable, lists can be LLM-driven (matching Mauricio's planning comment about LLM-defined entity lists).
- Cons: Migration on `knowledge_gaps`, LLM call on every gap write (latency + cost), prompt tuning, telemetry/eval work, coordination with `ai-platform` owners.

Rejected as out of scope for the current spike. Deferred to a future backend initiative.

### Option B — Backend on-demand classification at list time
Keep `knowledge_gaps` unchanged but classify with the LLM whenever `/gaps` is queried.

- Pros: No migration.
- Cons: LLM latency on every list request, repeated cost for the same gaps, doesn't scale, no caching strategy.

Rejected. No realistic path to production.

### Option C — BFF regex stub with hardcoded enums (chosen)
The web-platform BFF runs a keyword-based regex over the question and tags each row with a fixed enum value before returning to the browser.

- Pros: Zero backend change. Ship-today-able. Unblocks the chip-filter UI spike.
- Cons: Regex misclassifies subtle questions. Enums are fixed in TypeScript; adding a category requires a code change + deploy. The classification source is opaque to anyone outside this file — looks like backend output but isn't.

Chosen.

## Consequences

- **Misclassification is expected** for ambiguous questions (e.g., `"tmp?"` falls into the default `general` / `plant_operations` bucket because no keyword matches). Acceptable for first-pass UX.
- **The enum lists are the contract.** The chip filter UI is built around exactly these 5 categories and 3 entity types. Any new value requires a `domain.ts` change and a code review.
- **Mismatch with Mauricio's planning comment.** Mauricio said in the 2026-05-12 planning that the entity list should be LLM-defined. This implementation does **not** match that vision. Sara confirmed on 2026-05-13 that the regex stub is intentional as a first pass, and the LLM-driven approach is a separate, larger effort outside the MMBR-54 spike.
- **Code reviewers should not flag `classifyQuestion()` as a bug.** It's a deliberate stub, not an oversight. Refactoring it to call the QAP API or an LLM is out of scope without an accompanying backend initiative.
- **No backend filtering today.** Because the BFF classifies after fetching, filter params on `/api/gaps/most-asked` (e.g. `?category=&entity=`) must be applied **after** the QAP fetch and **before** pagination math in the BFF handler. This is a known performance limitation: pagination totals reflect the unfiltered set unless the BFF refetches/recomputes.

## Revisit trigger

This decision should be revisited (and likely reversed) when a backend LLM-classification initiative is scoped and approved. Expected work at that point:

- New columns on `knowledge_gaps` (`category`, `entity`).
- LLM classification at `record_gap` time, with prompt + eval.
- New filter params on QAP's `/gaps`.
- Removal of `classifyQuestion()` from the BFF.
- Removal of the hardcoded `QUESTION_CATEGORIES` / `ENTITY_TYPES` enums (or repurposing them as fallback values).

## References

- Jira: [MMBR-54](https://qubika.atlassian.net/browse/MMBR-54) (Most Asked spike, current), [MMBR-59](https://qubika.atlassian.net/browse/MMBR-59) (Usage Metrics, parked).
- Sara's confirmation: Slack thread 2026-05-13, ~13:43.
- Planning meeting: 2026-05-12 transcript (Mauricio scopes the spike at line 378; LLM-entity remark at line 60).
- Touched files: `web-platform/app/api/gaps/most-asked/route.ts`, `web-platform/types/domain.ts`, `web-platform/components/gaps/MostAskedTable.tsx`.
- Backend baseline: `ai-platform/api/schemas/gaps.py`, `ai-platform/models/knowledge_gap.py`, `ai-platform/services/gap_service/gap_service.py`.

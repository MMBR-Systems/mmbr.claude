# BFF-side regex classification for Most Asked Questions

The Most Asked Questions endpoint enriches each gap with `category`, `entityType`, and `isProcessQuestion` in the **BFF** (`classifyQuestion()` in `app/api/gaps/most-asked/route.ts`), using regex over the question text against fixed enums in `types/domain.ts` (5 categories, 3 entity types). The QAP backend is unaware of these dimensions — `knowledge_gaps` has no category/entity columns. Backend LLM classification at `record_gap` time (the eventual target) and on-demand LLM classification at list time were both rejected as out of scope for the MMBR-54 spike (migration, LLM latency/cost, eval work, ai-platform coordination); the regex stub ships today and unblocks the chip-filter UI. Sara confirmed (2026-05-13) the stub is an intentional first pass.

## Consequences

Misclassification is expected for ambiguous questions (default `general`/`plant_operations`). The enum lists are the contract — a new value needs a `domain.ts` change + review. Filtering fetches up to QAP's 100-row cap and paginates in memory to keep `total` accurate. **Reviewers should not flag `classifyQuestion()` as a bug** — it's a deliberate stub. Status: revisit (and likely reverse) when a backend LLM-classification initiative is scoped.

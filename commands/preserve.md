---
description: Save a durable fact or decision into .claude/docs/ (cross-session, team-shareable)
---

Capture a durable, team-shareable fact under `.claude/docs/` — update an existing file rather than duplicate, then print the path and whether it was created or updated. Route by kind: a decision (only if hard-to-reverse **and** surprising-without-context **and** a real trade-off, per [ADR-FORMAT](../skills/grill-with-docs/ADR-FORMAT.md)) → `adr/000N-slug.md`; a gotcha → `known-issues/<slug>.md`; a system-design/flow doc → `architecture/<topic>.md`; a recipe, glossary, external-API contract, or runbook → `reference/<topic>.md`. Not here: behavioral rules (→ auto-memory), session state (→ `/handoff`), personal scratch (→ `.docs/`). No secrets, no narrative, keep files short.

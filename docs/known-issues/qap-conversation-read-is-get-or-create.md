---
created: 2026-06-10
updated: 2026-06-10
owner: hpeluzio
---

# QAP conversation read is user-scoped get-or-create — never use it for cross-user reads

## Symptom

A GET to QAP `GET /conversations/{workflow_id}/{conversation_id}` returns `500 Internal Server Error` with:

```
sqlalchemy.exc.IntegrityError: <asyncpg.exceptions.UniqueViolationError>:
  duplicate key value violates unique constraint "conversations_pkey"
[SQL: INSERT INTO conversations (...)]
```

— an INSERT failure on a **read** request. Deterministic, not a race: every retry fails identically. Through the BFF this surfaces as `502 SERVICE_UNAVAILABLE` (see `qbricks-bff-masks-qap-status.md`), or as silently-empty UI where the route swallows the error. Observed in QA on `/api/gaps/recent-messages` (2026-06-10).

## Where

- `ai-platform/services/conversation/conversation_service.py` → `get_conversation`
- Callers: `api/services/conversations.py` (read endpoint) and `services/registry/registry.py` (chat invoke flow)

## Cause

`get_conversation` is a **get-or-create scoped by `user_id`**:

1. `SELECT ... WHERE id = :id AND user_id = :requester` — misses when the row belongs to another user.
2. Fallback claims `user_id IS NULL` legacy rows only (see `qap-user-id-silent-null.md`) — does not cover "owned by someone else".
3. Falls through to `INSERT` with the same `id` → PK collision.

The create branch exists because the chat invoke flow legitimately needs create-on-first-message, so it cannot be removed.

## Rule

**Any cross-user read (admin analytics: GAPs, most-asked, negative-feedback context) must use the read-only endpoint** added for this purpose:

```
GET /conversations/{workflow_id}/{conversation_id}/messages?window_size=N
```

- No `user_id` filter, never creates, `404` when missing.
- Returns the most **recent** N messages in chronological order (the get-or-create read returns the **oldest** N — `ASC` + limit).
- QAP has no role model: the endpoint trusts the BFF to call it only from admin-gated routes (`requireRoleFromDB(["admin", "superadmin"])`). BFF builder: `conversationMessagesReadPath` in `web-platform/lib/api/qbricks.ts`.

Fixed in ai-platform PR #123 (endpoint + IntegrityError hardening in `get_conversation`) and web-platform PR #113 (GAPs drawer + negative-feedback context switched over).

## False-positive shield (pr-review)

- A new admin/analytics route calling `conversationMessagesPath` (the get-or-create read) for a conversation the requester may not own **is a real bug** — flag it.
- The duplicated-looking read logic in `read_conversation_messages` vs `get_conversation` is intentional: the create behavior cannot be mutated, so the read-only path is separate by design.

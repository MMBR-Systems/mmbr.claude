<!--
Last updated: 2026-04-28
Owner: hpeluzio
-->

# conversations.user_id silently becomes NULL or NIL UUID

## Symptom

Rows in ai-platform `public.conversations` have `user_id = NULL` or `user_id = 00000000-0000-0000-0000-000000000000` instead of the authenticated user's internal UUID. Any feature that depends on conversation ownership (per-user listing, per-user analytics, the legacy-claim fallback in `get_conversation`) is affected.

## Where

- `ai-platform/services/auth_service/token_validator.py` → `validate_api_token` (origin)
- `ai-platform/services/conversation/conversation_service.py:44-50` → silent coerce site (the `except Exception: user_id = None` block)
- `ai-platform/services/auth_service/auth_decorators.py:47-55` → NIL UUID source

## Cause

Two distinct failure modes:

1. **NULL under normal auth.** web-platform signs JWTs with `sub = user.auth0Id` (e.g. `auth0|69ea5e...`). QAP sets `UserContext.user_id` directly to `claims.sub`. Downstream, `ConversationService.get_conversation` calls `user_service.get_user_by_id(user_id)` which casts to UUID in Postgres. `auth0|...` fails to parse as UUID. The `except Exception` catches the error and sets `user_id = None`. A new `Conversation` is inserted with NULL user_id.

2. **NIL UUID under `DISABLE_AUTH=true`.** `get_current_user` returns a hardcoded dummy `UserContext(user_id="00000000-0000-0000-0000-000000000000", ...)`. That value propagates to `conversations.user_id` unchanged.

The fundamental design mismatch: QAP's `users.id` is a UUID, `users.external_id` holds the Auth0 ID, and `UniqueConstraint("provider", "external_id")` is the intended lookup. `validate_api_token` skipped that lookup and assumed `JWT.sub` was the internal UUID.

## Workaround / Fix status

Fixed on branch `fix/conversation-user-id-and-citation-persistence` (MMBR-Systems/ai-platform) as of 2026-04-23. The fix resolves `JWT.sub` via `UserService.get_user_by_provider_id(provider, external_id)` inside `validate_api_token` and rejects tokens whose sub has no matching user (forcing clients to call `POST /auth/login` first). Not yet merged at time of writing.

When merged, the `except Exception: user_id = None` in `conversation_service.py:44-50` becomes a silent error-hider and should be removed so future bugs of this class fail loudly.

## How to verify

```bash
docker exec ai-platform-postgres-1 psql -U postgres -d qap_api_dev \
  -c "SELECT user_id, COUNT(*) FROM conversations GROUP BY 1 ORDER BY 2 DESC;"
```

Any row with `user_id IS NULL` or `user_id = '00000000-...'` is a hit.

## Related

QAP user-row backfill: as of 2026-04-28 (web-platform PR #35), `ensureQapUserSynced` runs in the protected layout on every authenticated request, so users provisioned before `qbrick` was reachable — and users wiped by a QAP DB reset — are re-synced automatically on next login. See `architecture/qap-user-sync.md` for the full two-site sync flow.

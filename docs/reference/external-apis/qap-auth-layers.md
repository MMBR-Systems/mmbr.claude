# QAP Authentication Layers

The web-platform authenticates to the QAP backend (`qbrick`) through two independent layers. Confusing them leads to misconfigured environments.

## Layer 1 - Shared HMAC for JWT signing

- **Purpose:** every request from web-platform to qbrick carries an HS256 JWT with the user's identity. Both sides must share the same HMAC secret so qbrick can verify the signature.
- **Scope:** global per environment. Every service that signs or verifies a token uses the same value.
- **Env var names (legacy reasons):**
  - `web-platform` reads `QAP_JWT_SECRET`
  - `backend-ui` reads `NEXTAUTH_SECRET`
  - `qbrick` reads either — in `services/auth_service/api_token_service.py` the code is `os.getenv("QAP_JWT_SECRET") or os.getenv("NEXTAUTH_SECRET")`. The dev task def currently maps `NEXTAUTH_SECRET`.
- **Failure mode when mismatched:** qbrick returns 401 on every authenticated request. The JWT signature verification fails before any business logic runs.

Where web-platform signs: `web-platform/lib/api/qbricks.ts` - `generateQapJwt()` uses `QAP_JWT_SECRET` with `jose.SignJWT`, alg `HS256`, issuer `qubika-agentic-platform`, audience `qubika-api`.

## Layer 2 - Per-workflow API key / secret

- **Purpose:** workflow invocations (`POST /workflows/{id}/invoke`) also require `X-API-KEY` and `X-API-SECRET` headers. These are validated against a row in qbrick's Postgres, scoped to a specific workflow.
- **Scope:** per workflow, per environment. Every `(environment, workflow)` pair has its own key / secret.
- **Env vars on web-platform:** `QAP_AGENT_ID` (workflow UUID), `QAP_API_KEY`, `QAP_API_SECRET`.
- **Failure modes:**
  - Workflow UUID not in qbrick's DB: 401 "Unauthorized or workflow not available" (the route handler returns this for both "missing row" and "wrong creds" — no information leak).
  - API key / secret don't match the DB row: same 401.

### Evidence in ai-platform code

Validation (`services/workflow_description/workflow_description_service.py:151-171`):

```python
async def get_with_api_key(
    self, workflow_id: UUID, api_key: str, api_secret: str
) -> Optional[DBWorkflowDescription]:
    if not api_key or not api_secret:
        return None
    secret_hash = hashlib.sha256(api_secret.encode("utf-8")).hexdigest()
    ...
    .where(
        DBWorkflowDescription.id == workflow_id,
        ApiKey.api_key == api_key,
        ApiKey.secret_hash == secret_hash,
    )
```

Key generation (`api/routes/workflow_descriptions.py`):

```
POST /workflow_descriptions/{workflow_id}/generate_api_key
  -> returns { api_key, api_secret }
```

The secret is shown once and the sha256 hash is stored. There is no way to retrieve the secret later.

## How to set up a new environment

1. **HMAC secret:** generate one (`openssl rand -hex 32`) and put the same value on all three services under their respective env var names.
2. **Workflow + API key:** in the QAP admin UI for that environment (`ui.<env>.mem-brain.com/agents`), create the workflow. Note the UUID.
3. **API key generation:** via the UI or via `POST /workflow_descriptions/{uuid}/generate_api_key`. Capture `api_key` and `api_secret` immediately - the secret is not recoverable.
4. **Web-platform env:** write `QAP_AGENT_ID`, `QAP_API_KEY`, `QAP_API_SECRET`, `QAP_JWT_SECRET` into that environment's web-platform secret.

## Common misconceptions

- "The API key / secret are inter-service credentials set once per environment" - no, they are per workflow. Reusing them across workflows will fail.
- "I can copy `QAP_*` from local `.env.local` to a deployed environment" - only `QAP_JWT_SECRET` is potentially reusable (it is a chosen HMAC). `QAP_AGENT_ID`, `QAP_API_KEY`, and `QAP_API_SECRET` are tied to records in a specific qbrick database and cannot be reused.
- "The QAP admin UI is optional, I can seed workflows via SQL" - technically yes, but the API key generation still has to go through the `generate_api_key` service to produce the correct hash, so the UI or the endpoint is the path of least resistance.

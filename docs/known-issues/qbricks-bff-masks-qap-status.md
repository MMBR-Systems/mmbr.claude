---
created: 2026-05-05
updated: 2026-05-05
owner: hpeluzio
---

# web-platform's QAP proxy collapses every non-2xx into 502 SERVICE_UNAVAILABLE

## Symptom

The browser sees the same error regardless of what actually went wrong on the QAP side:

```json
{ "code": "SERVICE_UNAVAILABLE", "message": "AI assistant is temporarily unavailable. Please try again." }
```

…with HTTP `502 Bad Gateway`. This shows up for any route that proxies through `qapUserFetch` — `/api/documents`, `/api/chat/threads/*/messages`, `/api/chat/threads`, etc. UI surfaces it as `"Unable to load documents. Please try again."` for the documents page.

A real QAP `401` (auth/user resolution), `404` (route not registered on the deployed image), `422` (schema mismatch), `500` (Databricks error / DB error inside the service) all look identical from the client.

## Where

`web-platform/lib/api/qbricks.ts:59-62` — the proxy intentionally hides upstream status:

```ts
if (!res.ok) {
  console.error(`QAP API error: ${res.status} ${res.statusText} for ${path}`);
  return { error: badGateway("AI assistant is temporarily unavailable. Please try again.") };
}
```

`badGateway` lives in `web-platform/lib/api/errors.ts` and produces the `SERVICE_UNAVAILABLE` body + 502 status.

## Cause

This is by design — the BFF doesn't expose internal QAP details to the browser. The trade-off is that the only honest status signal lives in **server logs**, not in the network panel. Treating the browser status as the primary signal will send you down the wrong path (e.g., assuming "502 = QAP is down" when it's really an auth or contract issue).

Another QAP failure mode is masked separately: timeouts (`AbortController` after `QAP_TIMEOUT_MS = 30_000`) become `GATEWAY_TIMEOUT` instead of `SERVICE_UNAVAILABLE`. Both are 502 in HTTP terms.

## Workaround

When debugging anything QAP-related, **read server logs first**, never trust the browser status:

- **Local:** look at the `pnpm dev` terminal stdout. The `console.error("QAP API error: ${status} ${statusText} for ${path}")` line is your real status.
- **dev/qa/prod:** CloudWatch log group `web-platform-{env}` for the BFF's view, and `qbrick-{env}` for the QAP's structured error events. Both are needed — the BFF only logs `status`/`statusText`, while the actual error reasoning ("password is wrong", "psycopg2 not installed", "RDS Proxy requires TLS") only appears in `qbrick-{env}` logger entries.
  ```sh
  aws logs tail web-platform-qa --since 30m --format short --filter-pattern '"QAP API error"' \
    --profile AdministratorAccess-542035162757 --region us-east-2

  aws logs tail qbrick-qa --since 30m --format short \
    --profile AdministratorAccess-542035162757 --region us-east-2 \
    | grep -iE 'error|fail|password|tls|ssl|psycopg|asyncpg' | grep -v 'GET /\|POST /'
  ```

The pair of these tells you whether the failure is in transport (BFF can't reach QAP), auth (JWT/user resolution), or downstream (DB / Databricks / contract).

## Fix (if planned)

Deferred. Surfacing structured error codes from QAP through the BFF would be a contract change touching every route — not worth it just to make debugging easier. The runbook above is the supported path.

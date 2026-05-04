# QAP (Qubika Agentic Platform) — API Reference

> Extracted from `ai-platform/` codebase (MMBR fork of QAP). Read-only reference for MMBR frontend integration.

## Repo

`git@github-qubika:MMBR-Systems/ai-platform.git`

Upstream (for comparison only): `git@github-qubika:thisisqubika/qubika-agentic-platform.git`

## Services (compose.yml)

| Service | Port | Description |
|---------|------|-------------|
| api | 8000 | FastAPI backend |
| ui | 3000 | Next.js frontend (QAP's own UI) |
| postgres | 5432 | PostgreSQL with vector/AGE extensions |
| rerank-api | 8001 | Reranking service (optional) |

---

## Authentication

### 3 auth methods

| Method | How | Used by |
|--------|-----|---------|
| **JWT Bearer** | `Authorization: Bearer <oauth_token>` validated against Auth0/provider | Most endpoints (conversations, profile, workflows CRUD) |
| **API Key/Secret** | `X-API-KEY` + `X-API-SECRET` headers, generated per workflow | `POST /workflows/{id}/invoke` (execute workflow) |
| **Dev bypass** | `DISABLE_AUTH=true` env var → returns dummy user | Local development |

### API Key/Secret (most relevant for MMBR)

- Generated via `POST /workflows/workflow_descriptions/{id}/generate_api_key`
- Stored in DB: `api_key` (plaintext) + `secret_hash` (SHA-256)
- Used to invoke workflows without user JWT
- Simplest auth path for service-to-service communication

---

## Endpoints Relevant to MMBR

### Chat / Workflow Invocation

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/workflows/{workflow_id}/invoke` | API Key/Secret | Send question to RAG agent. This is the main "ask" endpoint |
| `GET` | `/conversations/{workflow_id}` | JWT Bearer | List conversations for a workflow |
| `GET` | `/conversations/{workflow_id}/{conversation_id}?window_size=N` | JWT Bearer | Get conversation messages |

### Auth

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/auth/login` | None | OAuth login/register |
| `POST` | `/auth/validate-token` | None | Validate JWT token |
| `GET` | `/auth/profile` | JWT | Get user profile |
| `GET` | `/auth/me` | JWT | Get current user (alias for /profile) |

### Utility

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health/` | None | Health check → `{"status": "healthy"}` |
| `GET` | `/test/db-test` | JWT | Test database connection |

---

## All Endpoints (complete list)

### Auth (/auth)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/auth/login` | No | OAuth login/register |
| `POST` | `/auth/validate-token` | No | Validate JWT |
| `GET` | `/auth/profile` | Yes | User profile |
| `GET` | `/auth/me` | Yes | Current user |

### Workflows (/workflows)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/workflows/workflow_descriptions` | JWT | List user's workflows |
| `GET` | `/workflows/workflow_descriptions/company` | JWT | List company workflows |
| `GET` | `/workflows/workflow_descriptions/{id}` | JWT | Get workflow details |
| `POST` | `/workflows/workflow_descriptions` | JWT | Create workflow |
| `PUT` | `/workflows/workflow_descriptions/{id}` | JWT | Update workflow |
| `DELETE` | `/workflows/workflow_descriptions/{id}` | JWT | Delete workflow |
| `POST` | `/workflows/workflow_descriptions/generate` | JWT | AI-generate workflow |
| `POST` | `/workflows/{id}/invoke` | API Key/Secret | Execute workflow |
| `POST` | `/workflows/workflow_descriptions/{id}/generate_api_key` | JWT | Generate API key pair |
| `POST` | `/workflows/{id}/triggers/slack` | No | Slack webhook trigger |
| `POST` | `/workflows/{id}/triggers/pagerduty` | No | PagerDuty webhook trigger |

### Conversations (/conversations)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/conversations/{workflow_id}` | JWT | List conversations |
| `GET` | `/conversations/{workflow_id}/{id}` | JWT | Get conversation + messages |

### Registry (/registry)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/registry/agents` | JWT | List all agents |
| `GET` | `/registry/agents/internal` | JWT | List internal agents |
| `GET` | `/registry/agent/{id}` | JWT | Get agent metadata |
| `POST` | `/registry/agent/{id}` | JWT | Execute agent directly |

### Judges (/judges)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/judges/` | JWT | List judges |
| `GET` | `/judges/{id}` | JWT | Get judge |
| `POST` | `/judges/` | JWT | Create judge |
| `PUT` | `/judges/{id}` | JWT | Update judge |
| `DELETE` | `/judges/{id}` | JWT | Delete judge |

### Monitoring (/monitoring)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/monitoring/overview` | JWT | Overview insights |
| `GET` | `/monitoring/scores` | JWT | Evaluation scores |
| `GET` | `/monitoring/insights` | JWT | Workflow insights |
| `GET` | `/monitoring/insights/my-workflows` | JWT | User workflow insights |
| `GET` | `/monitoring/insights/company-workflows` | JWT | Company-wide insights |

### Slack (/slack)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/slack/users` | JWT + `X-Slack-Bot-Token` | List Slack users |
| `GET` | `/slack/channels` | JWT + `X-Slack-Bot-Token` | List Slack channels |
| `GET` | `/slack/connection-status` | JWT + `X-Slack-Bot-Token` | Check connection |

### Google Drive (/api/google-drive)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/api/google-drive/webhook` | No | Drive push notification |
| `POST` | `/api/google-drive/setup-watch` | JWT | Subscribe to folder |
| `GET` | `/api/google-drive/folders` | JWT | List folders |
| `POST` | `/api/google-drive/check-access` | JWT | Check folder access |
| `GET` | `/api/google-drive/subscription-status/{id}` | JWT | Watch status |
| `POST` | `/api/google-drive/stop-watch` | JWT | Stop monitoring |
| `GET` | `/api/google-drive/service-account-info` | JWT | Service account email |

### Notifications (/api/notifications)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/api/notifications/stream` | JWT | SSE real-time stream |
| `GET` | `/api/notifications/types` | JWT | List notification types |

### Traces (/traces)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/traces` | JWT | List traces |
| `GET` | `/traces/{id}` | JWT | Get trace details |

### Realtime / Recall.ai (/realtime/recall)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/realtime/recall/start-recording` | JWT | Start meeting bot |
| `POST` | `/realtime/recall/webhook` | No | Transcript webhook |
| `WS` | `/realtime/recall/ws/{bot_id}` | No | Real-time stream |
| `GET` | `/realtime/recall/conversation/{bot_id}` | No | Get conversation |
| `DELETE` | `/realtime/recall/bot/{bot_id}` | `X-Recall-Api-Key` | Delete bot |

### Other
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health/` | No | Health check |
| `GET` | `/test/db-test` | JWT | Test DB |
| `GET` | `/test/redis-test` | JWT | Test Redis |
| `GET` | `/test/milvus-test` | JWT | Test Milvus |
| `GET` | `/test/managers-test` | JWT | Test all |
| `POST` | `/zoom/auth/start` | `x-zoom-app-context` | Zoom auth |

---

## Database Schema (key tables)

| Table | Purpose |
|-------|---------|
| `users` | User accounts (UUID, provider, external_id, email, name) |
| `workflow_descriptions` | Workflow definitions (user_id FK, name, metadata) |
| `api_keys` | API key/secret pairs per workflow |
| `conversations` | Chat histories (user_id FK, workflow_id FK, title) |
| `conversation_messages` | Messages (conversation_id FK, input, output as JSON) |
| `judges` | Evaluator definitions |
| `evaluators` | Evaluation configs per workflow |
| `workflow_agents` | Agent assignments to workflows |
| `flows` | Workflow routing logic |
| `flowsteps` | Flow transitions between agents |
| `routers` | Conditional routing rules |

---

## Key Insight for MMBR Integration

The `/workflows/{id}/invoke` endpoint uses **API Key/Secret** auth, not JWT. This means MMBR can authenticate to QAP by:

1. Generating an API key pair for the MMBR RAG workflow in QAP
2. Storing `X-API-KEY` and `X-API-SECRET` as env vars in web-platform
3. Sending these headers in `qbricksFetch()` — no JWT forwarding needed

This is simpler than both M2M token and user JWT forwarding approaches.

However, **conversation listing** (`GET /conversations/{workflow_id}`) still requires JWT Bearer — so a hybrid approach may be needed depending on which endpoints MMBR uses.

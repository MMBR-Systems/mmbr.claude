# Jira MCP Setup for Claude Code

> Token-based Jira integration — no browser/OAuth required.

## Why token over OAuth?

| Approach | Auth flow | Session | Reliability |
|----------|-----------|---------|-------------|
| `atlassian` (OAuth) | Opens Chrome tab for authorization | Temporary, expires | Unreliable — browser flow often fails to complete |
| `jira-mcp` (API token) | Direct token auth, no browser | Permanent until revoked | Always works |

## Prerequisites

1. **Jira API token** — generate at https://id.atlassian.com/manage-profile/security/api-tokens
2. **npx** (comes with Node.js)

## Setup

```bash
claude mcp add jira -s local \
  -e JIRA_INSTANCE_URL=https://qubika.atlassian.net \
  -e JIRA_USER_EMAIL=your-email@qubika.com \
  -e JIRA_API_KEY=your-api-token-here \
  -- npx -y jira-mcp
```

### Verify

```bash
claude mcp list
# Should show:
# jira: npx -y jira-mcp - ✓ Connected
```

## Available tools

| Tool | Description | Example |
|------|-------------|---------|
| `mcp__jira__get_issue` | Fetch a single issue by key | `MMBR-165` |
| `mcp__jira__jql_search` | Search issues with JQL | `project = MMBR AND status = "To Do"` |

## Usage in Claude Code

Once configured, Claude can directly read Jira tickets:

```
"Fetch MMBR-165 and summarize it"
"Search all open tickets assigned to me"
"What tickets are in To Do for MMBR project?"
```

## Remove OAuth MCP (if still present)

If you still have the `atlassian` OAuth server configured, remove it:

```bash
claude mcp remove atlassian -s local
```

## Troubleshooting

**"No MCP server found with name: jira"**
Re-run the `claude mcp add` command above.

**401 Unauthorized**
API token expired or revoked. Generate a new one at https://id.atlassian.com/manage-profile/security/api-tokens and update:
```bash
claude mcp remove jira -s local
# Re-run the add command with the new token
```

**Token rotation**
Atlassian API tokens don't expire automatically. Only regenerate if compromised or revoked.

## Config location

The MCP config is stored in the project-level `.claude.json` (local scope, not committed). Each developer needs to run the setup with their own email and token.

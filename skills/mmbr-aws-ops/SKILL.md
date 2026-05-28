---
name: mmbr-aws-ops
description: Hand off AWS operational tasks for MMBR (dev/qa/prod) to the existing scripts and reference doc instead of inventing commands. Trigger when the user mentions tunneling to a deployed DB ("DBeaver", "psql to qa", "tunnel"), shelling into a running container ("ecs exec", "entrar no container"), running migrations or seeds against a deployed env ("seed qa", "migrate dev"), poking at CloudWatch logs for the deployed services, redeploying ECS, or asking how to reach AWS resources for this project. Also trigger when the user mentions a known infra noun — bastion, RDS Proxy, ecs-dev, ecs-qa, web-platform-qa, mmbr-{env}-web-platform secret. DO NOT trigger for unrelated AWS work outside MMBR (other accounts, non-ECS services not used here, generic AWS questions).
---

# MMBR AWS Operations

You are working in a multi-repo workspace where the deployed stack lives in
three AWS accounts (dev / qa / prod). The team has already built the runbook
and parametrized scripts — your job is to use them, not to recreate them.

## Source of truth

- **Doc:** [`.claude/docs/reference/operations/aws-mmbr.md`](../../../.claude/docs/reference/operations/aws-mmbr.md)
- **Scripts:** [`.claude/docs/reference/operations/scripts/`](../../../.claude/docs/reference/operations/scripts/)
  - `_env.sh` — env → profile/cluster/bastion/RDS lookup (sourced by the others)
  - `bastion-tunnel.sh <env> [local_port]` — SSM port-forward to RDS Proxy
  - `ecs-exec.sh <env> [container]` — interactive shell in the running web-platform task
  - `db-migrate.sh <env>` — run all `db/migrations/*.sql` against the env
  - `db-seed.sh <env>` — run `db/seed.sql` against the env (idempotent)
  - `get-secret.sh <secret-name> [key]` — read a Secrets Manager secret (env inferred from name)
  - `set-secret-keys.sh <secret-name>` — merge stdin JSON into a secret with key-level diff + confirm

If something is missing, **add it to those locations** rather than handing
the user a one-off command — that is exactly the gap this skill exists to
close.

## How to use

When the user asks for any of the recipes above:

1. **Read** [`.claude/docs/reference/operations/aws-mmbr.md`](../../../.claude/docs/reference/operations/aws-mmbr.md)
   if you have not already. The env table there is authoritative.
2. **Hand the user the script command**, named explicitly. Do not paste the
   underlying `aws ecs execute-command` / `aws ssm start-session` invocation
   — that defeats the point of having scripts. Example:
   - User: "I need to seed QA"
   - You: `.claude/docs/reference/operations/scripts/db-seed.sh qa`
3. **Confirm SSO** before destructive ops. If you are unsure the SSO
   session is active for the env's profile, run
   `aws sts get-caller-identity --profile <profile>` first; the scripts
   themselves also check.
4. **Production writes need explicit user confirmation per call.** The
   platform safety layer blocks bypass of interactive confirmations on
   prod. Don't fight it — let the user run prod-write commands themselves
   so they see the diff and approve.
5. **One-off commands are fine** when the user explicitly wants something
   the scripts do not do (e.g. a partial migration with explicit
   BEGIN/COMMIT, or a single ad-hoc SQL query). After running it, consider
   whether it should become a script — if yes, add it.

## Env routing cheat sheet

| Env  | Profile                                | Cluster   | Web service        |
|------|----------------------------------------|-----------|--------------------|
| dev  | `AdministratorAccess-455842406405`     | `ecs-dev` | `web-platform-dev` |
| qa   | `AdministratorAccess-542035162757`     | `ecs-qa`  | `web-platform-qa`  |
| prod | `AdministratorAccess-819743217049`     | `ecs-prod`| `web-platform-prod`|

Region is always `us-east-2`. If the user's question implies a different
region, push back — that is almost certainly wrong for this project.

## Anti-patterns

- ✘ Pasting raw `aws ecs execute-command ...` when a script exists. Use
  the script.
- ✘ Hardcoding bastion IDs / RDS hostnames / profile names in chat. Refer
  to the doc / `_env.sh` so the values stay in one place.
- ✘ Running `db-migrate.sh prod` or `db-seed.sh prod` without explicit
  user confirmation that they want a prod write — these are shared-state
  operations.
- ✘ Logging or echoing the contents of `mmbr-{env}-web-platform` secrets
  into the conversation. Read what you need, do not dump the whole JSON.

# Custom subagents

This folder is for workspace-level custom subagent definitions. Empty by default — this template doesn't ship any subagents because they only pay off when a recurring role becomes clear.

## When to add a subagent

A custom subagent is worth defining when:
- The same specialized task comes up repeatedly (e.g. deploy validator, schema reviewer, test runner).
- That task benefits from a narrow tool set or a focused system prompt.
- You'd otherwise paste the same instructions into the Agent tool every time.

Built-in subagents (`general-purpose`, `Explore`, `Plan`, `claude-code-guide`, `statusline-setup`) already cover most needs — add a custom one only when those aren't enough.

## Shape

Each subagent is a single markdown file with frontmatter:

```markdown
---
name: agent-name
description: When to pick this agent. Used by the orchestrator to decide.
tools: Read, Grep, Bash   # optional — defaults to all
model: sonnet             # optional — inherits from parent otherwise
---

System prompt content for the subagent goes here.
```

## Invocation

From the main conversation, the Agent tool with `subagent_type: "agent-name"` loads this definition.

## Override

Nested `<repo>/.claude/agents/<same-name>.md` overrides the workspace one when Claude is working inside that repo.

# CONTEXT.md Format

In this workspace the domain glossary is a single file: **`.claude/CONTEXT.md`**.
It is push-loaded (linked from `CLAUDE.md`, so it lands in context every
session). There is no multi-context `CONTEXT-MAP.md`.

## Structure

```md
# CONTEXT — Domain vocabulary

## Terms

- **Order** — what it refers to in code AND in conversation. Call out confusing
  legacy names explicitly ("despite the name, it is X, not Y").
- **Invoice** — a request for payment sent to a customer after delivery.
- **Customer** — a person or organization that places orders.

## Cascades (optional)

- **<flow-name> cascade** — when X happens, A → B → C must update together.
```

## Rules

- **One line per term.** Define what it IS, not what it does. Deeper
  how-it-works material belongs in `.claude/docs/architecture/`.
- **Be opinionated.** When multiple words exist for the same concept, pick the
  best one and note the others to avoid ("_Avoid_: client, buyer").
- **Flag conflicts explicitly.** If a term is used ambiguously, resolve it in
  the entry — name the two concepts and which is which.
- **Only project-specific terms.** Entities, services, multi-step flows.
  General programming concepts (timeouts, error types, utility patterns) don't
  belong, even if used heavily. Before adding a term, ask: is this unique to
  this project's domain, or a general programming concept? Only the former
  belongs.
- **Keep it small.** Target under ~2 KB. If it grows past that, the surplus
  belongs in `.claude/docs/architecture/`.
- **Cascades** — short names for multi-step flows that recur. The short name
  beats re-describing the chain every time. Skip the section if there are none.

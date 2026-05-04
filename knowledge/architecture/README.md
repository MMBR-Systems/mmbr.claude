# Architecture

System designs, data flows, integration topologies. One `overview.md` per architectural scope.

## Conventions

- `overview.md` (this folder) — cross-system overview.
- `<module>/overview.md` — module-level architecture (Mermaid diagrams, queue/event flows).
- `<module>/<service>.md` — per-service "card" (responsibility, events in/out, dependencies).

Service files are named after the service domain, not the repo. Reference code as the source of truth — link into the actual repos rather than duplicating schemas.

See [`../README.md`](../README.md) for the full layout.

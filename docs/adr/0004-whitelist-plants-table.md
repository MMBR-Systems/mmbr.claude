# Introduce `mmbr.whitelist_plants` (intent layer for plant access)

A new table `mmbr.whitelist_plants (whitelist_id, plant_id)` captures plant-access **intent** before the user exists, and `provisionUser()` copies it into `mmbr.user_plants` in the same transaction that creates the `users` row. Today `user_plants.user_id` is an FK to `users(id)`, which only exists after the operator's first Auth0 login — so per-operator plant assignment can't be set up in advance, and operators land on the home screen with zero plants until an admin re-runs SQL. Auto-assigning all `enabled` plants was rejected because it destroys the per-operator granularity `user_plants` exists for; NULL-`auth0_id` ghost rows and an `AFTER INSERT` trigger were rejected as higher blast-radius / less queryable. Model: `whitelist` + `whitelist_plants` = intent; `users` + `user_plants` = reality.

## Consequences

Two sources of truth — editing `whitelist_plants` after registration does **not** propagate to `user_plants` without explicit reconciliation (deferred). Admin surfaces manage two tables (entry + its plants). Existing whitelist rows need a backfill (recommend mapping to current `enabled` plants). Status: planned — schema + provisioning ship first (Phase 1), admin CRUD UI later (Phase 2).

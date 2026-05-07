---
created: 2026-05-07
updated: 2026-05-07
owner: workspace owner
---

# Why we don't have a CI pipeline for `terraform plan`/`apply`

## Context

The `MMBR-Systems/infraestructure-iac` repo holds the canonical terraform code for the AWS infrastructure (ECS services, secrets, ALB, RDS proxy, autoscaling, alarms — see `globals/`). At the time this decision was reviewed (2026-05-07), there were three reasonable models for how `terraform plan` and `terraform apply` could run:

1. **Manual local apply.** A trusted operator runs `terraform plan`/`apply` from their laptop after each merge to `main`.
2. **Plan-on-PR + manual apply.** CI runs `terraform plan` on every PR and posts the diff as a comment so reviewers see the impact before merge. Apply is still manual locally.
3. **Full GitOps.** CI auto-applies on merge, with environment approval gates for `qa` and `prod`. The state-of-the-art for production teams.

Industry convention favors model 2 or 3 for safety and audit trail, but they require pipeline plumbing: IAM role for the CI runner, S3/state access from the runner, branch protection coordination, environment approval rules, plan-output security review (plans can leak resource ARNs/IPs).

## Decision

**Stay on model 1 — manual local apply by the terraform owner (Leandro).**

The CI workflow at `infraestructure-iac/.github/workflows/terraform-ci.yml` is intentionally limited to lint/validate on PRs (`terraform fmt`, `terraform validate`, `tflint`, `trivy`). It does **not** run `plan` or `apply`.

Apply is run manually, from the terraform owner's machine, against each env (`env/dev`, `env/qa`, `env/prod`) after a `main` merge. Same operator runs the apply each time.

## Alternatives considered

### Plan-on-PR + manual apply (model 2)

Would have caught today's (2026-05-07) incident where PR #2 was merged without anyone seeing what `apply` would do. Reviewers would see "this PR creates 18 new resources" before approval.

**Rejected because:** the additional infrastructure (IAM role for the GHA runner, state-bucket access, plan output handling) was deemed too much overhead for the project's current size. Decision made early when the team optimized for velocity over process.

### Full GitOps with auto-apply (model 3)

Highest safety — main is the source of truth, no human-in-the-loop drift, environment approval gates per env.

**Rejected because:** strictly more setup than model 2, plus cultural shift (atomic merges, no escape hatch via "I'll just edit the console real quick"). Premature for the team.

### Atlantis / Terraform Cloud / Spacelift

Hosted services that bundle plan-on-PR + approval workflows.

**Not seriously evaluated** — the explicit decision was "no pipeline at all", not "which pipeline". Worth revisiting if the team grows or apply frequency increases.

## Consequences

What this locks us into:

- **Single point of authority on apply.** Whoever owns terraform (currently Leandro) is the bottleneck for any infrastructure change reaching AWS. If they're unavailable, infrastructure changes wait.
- **No automated drift detection.** If someone edits a resource manually in the AWS console, terraform doesn't know until the next operator-triggered `plan`. Today's incident — manual task definition edit propagated by CI — is exactly this failure mode at the layer above terraform; the equivalent inside terraform's scope would silently rot for days/weeks.
- **No audit trail at the apply layer.** "Who applied what when" lives in the terraform owner's bash history and S3 state version timestamps, not in a queryable system.
- **Reviewers approve PRs blind.** They see the .tf diff but not the reconciled-with-AWS plan diff. PR #2 was a 30-file consolidation; nobody knew at merge time whether `apply` would create, change, or destroy. (The team's mitigation: trust the operator and plan locally before applying.)
- **Cheaper setup and maintenance.** No GitHub Actions for AWS, no IAM role to rotate, no plan-output redaction concerns, no environment-protection rules to keep up to date.

What this does **not** lock us into:

- Adding plan-on-PR later is a forward-compatible move. The terraform code stays as-is; only `.github/workflows/` gains a job.
- Moving to full GitOps later is also forward-compatible — same jump, larger scope.

## When to revisit this decision

Any of these triggers should reopen it:

- **Apply frequency** increases beyond ~1-2 per week (becomes operationally painful for one person to gate).
- **Team grows** — more than one person regularly proposes infra changes; the bottleneck friction outweighs setup cost.
- **Critical mistake** caused or amplified by lack of pre-merge plan visibility (e.g. accidental destroy not caught in review).
- **Compliance** requirement appears that needs queryable audit log for infrastructure changes.

The bar to revisit isn't high: model 2 (plan-on-PR) is roughly half a day of GitHub Actions work — doable as a single PR when the team is ready.

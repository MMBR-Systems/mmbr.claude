# No CI pipeline for `terraform plan`/`apply`

`infraestructure-iac` stays on **manual local apply**: CI (`terraform-ci.yml`) only lint/validates PRs (`fmt`, `validate`, `tflint`, `trivy`), and the terraform owner runs `plan`/`apply` from their machine against each env after a `main` merge. Plan-on-PR (model 2) and full GitOps auto-apply (model 3) are industry-standard and safer, but both need pipeline plumbing — a CI IAM role, state-bucket access from the runner, branch-protection coordination, plan-output redaction (plans leak ARNs/IPs) — judged too much overhead for the project's current size; the team optimized for velocity over process.

## Consequences

Single point of authority on apply (owner is the bottleneck); no automated drift detection; no queryable apply-layer audit trail; reviewers approve `.tf` diffs blind to the reconciled plan. Adding plan-on-PR later is forward-compatible (~half a day of GHA work). **Revisit when:** apply frequency exceeds ~1-2/week, more than one person proposes infra changes, a mistake is caused by missing pre-merge plan visibility, or a compliance audit-log requirement appears.

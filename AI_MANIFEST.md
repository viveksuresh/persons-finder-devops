# AI Manifest — persons-finder-devops

Purpose: Provide clear, enforceable guardrails for using AI tools (LLMs, copilots) with this repository.

Owner: DevOps / SRE contributor owning CI and infra changes.

Principles:
- Do not commit secrets or API keys into the repo. Secrets must be injected at deploy-time (K8s Secret, Vault, ExternalSecrets).
- Treat AI output as a draft: require automated validation and human review before applying infra or security changes.
- Log prompts and important AI responses to `AI_LOG.md` for auditability.

Quick rules (enforced):
- Secrets: scan with `detect-secrets`/`git-secrets` in CI; block commits/pushes containing secrets.
- PII: redact user PII before sending it to external LLMs. Use the documented redaction pattern and require a human review for any exception.
- Model/use parameters: for infra/manifest changes set deterministic LLM params (temperature 0.0-0.2, max tokens constrained).
- Approvals: any AI-generated Kubernetes manifests, Terraform, Dockerfiles or CI workflows must pass linting (kubeval/tfsec/hadolint) and one human approver.

CI guardrails (recommended pipeline steps):
1. Pre-commit: run `detect-secrets` and `prettier`/formatters.
2. PR checks: run secret-scan, static scanners (Trivy/snyk), `kubeval` for K8s manifests, `hadolint` for Dockerfile, `terraform validate` for Terraform.
3. AI-review step: produce `AI_LOG.md` entries (prompt + model name + response hash) and require maintainer signoff.

Operational controls:
- Do not allow committing `k8s/01-secret.yaml` with plaintext keys. Replace with instructions and templates that reference external secret stores.
- Add a GitHub Action to fail PRs that add large binary/build artifacts (e.g., `build/`, `.gradle/`).
- Maintain a `SECURITY.md` section explaining secret rotation and incident steps for leaked keys.

Prompting guidelines (examples):
- When asking for infra changes: explicitly include "DO NOT include secrets" and desired linting tools. Example prompt:
  "Generate a Kubernetes Deployment for `persons-finder` that: uses non-root user, readiness/liveness probes, resource requests/limits; do not include any secrets — reference a secret named `persons-finder-secret`. Return YAML only."

Response handling:
- Save the prompt + response to `AI_LOG.md` with a short note explaining applied edits.
- Run automated linters on AI output. If any linter fails, do not apply automatically — fix and re-run.

Enforcement & workflow:
- Pre-merge checks in CI are mandatory. Protect `main`/release branches with required status checks.
- Add a `CODEOWNERS` entry for infra dirs (`k8s/`, `deploy/`) to require human review.

Emergency & rollback:
- Keep a tested rollback/manifest for each production change. Tag releases and keep changelogs.

References / Helpful commands:
- Secret scanning: `detect-secrets scan .` and `git-secrets --scan`.
- Lint K8s manifests: `kubeval k8s/*.yaml`.
- Dockerfile lint: `hadolint Dockerfile`.
- Log AI interactions to `AI_LOG.md` in PR descriptions and in CI artifacts for auditing.

Status: created. Follow-up: I can add the CI checks and sample GitHub Actions configured to enforce these guardrails — want me to add them now?

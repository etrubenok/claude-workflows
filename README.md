# Claude Workflows

Reusable GitHub Actions workflows for Claude-powered automation: ad-hoc agent, researcher, dev loop (implement + review-fix), issue implement, PR feedback response, and dropped-run notifications.

Project-specific behavior is driven by each consuming repo's `CLAUDE.md`.

## Setup in a New Repo

### 1. Required Secrets

Add these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Required | Purpose |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Yes | Claude Code OAuth token for the claude-code-action |
| `PAT_WORKFLOWS` | No | PAT with `contents:write` + `pull-requests:write` for cross-repo push; falls back to `GITHUB_TOKEN` |

### 2. Required Labels

Create these labels in your repo (Issues > Labels > New label):

| Label | Purpose |
|---|---|
| `ready-for-implementation` | Trigger for dev-loop (issue path) |
| `research` | Trigger for researcher agent |
| `review-fix` | Trigger for dev-loop (PR path) |
| `🤖 claude-working` | Set while Claude is running |
| `✅ claude-done` | Set on successful completion |
| `❌ claude-failed` | Set on failure |
| `⚠️ claude-cancelled` | Set on cancellation |

### 3. Copy Trigger Files

Copy the 6 trigger files from `trigger-templates/` into your repo's `.github/workflows/` directory:

```bash
mkdir -p .github/workflows
cp trigger-templates/claude-dev-loop.yml .github/workflows/
cp trigger-templates/claude-issue-implement.yml .github/workflows/
cp trigger-templates/claude-review-response.yml .github/workflows/
cp trigger-templates/claude.yml .github/workflows/
cp trigger-templates/claude-code-researcher.yaml .github/workflows/
cp trigger-templates/claude-dropped-run-notify.yml .github/workflows/
```

### 4. Customize Runner (Optional)

Each trigger file has a commented-out `runner` input. Uncomment and set it to match your infrastructure:

```yaml
jobs:
  run:
    uses: etrubenok/claude-workflows/.github/workflows/claude-dev-loop.yml@v1
    with:
      event_name: ${{ github.event_name }}
      runner: '["self-hosted", "linux", "claude-agent"]'  # your custom runner labels
    secrets: inherit
```

Defaults:
- `claude.yml`: `["ubuntu-latest"]` (lightweight, no self-hosted needed)
- All others: `["self-hosted", "linux", "claude-agent"]`

### 5. Add a CLAUDE.md

Create a `CLAUDE.md` in your repo root. This is what drives project-specific behavior — coding standards, testing procedures, environment details, etc.

## Workflow Overview

| Trigger File | Shared Workflow | Events | What It Does |
|---|---|---|---|
| `claude.yml` | `claude.yml` | `@claude` in issue/PR comments | Ad-hoc Claude agent (read-only, answers questions) |
| `claude-code-researcher.yaml` | `claude-code-researcher.yaml` | `research` label or `@research` comment | Deep research agent, posts findings as issue comment |
| `claude-dev-loop.yml` | `claude-dev-loop.yml` | `ready-for-implementation` label, `review-fix` label, `workflow_dispatch` | Full implement + 3-round review-fix loop |
| `claude-issue-implement.yml` | `claude-issue-implement.yml` | `@implement` in issue comment | Implement from comment, then review-fix loop |
| `claude-review-response.yml` | `claude-review-response.yml` | `@fix` in PR comment | Fix PR feedback, then review-fix loop |
| `claude-dropped-run-notify.yml` | `claude-dropped-run-notify.yml` | `workflow_run` completed (cancelled) | Notifies when a run was cancelled by concurrency |

Internal (not exposed as trigger files):
- `claude-review-iteration.yml` — called by dev-loop, issue-implement, and review-response
- `claude-fix-iteration.yml` — called by dev-loop, issue-implement, and review-response

## Versioning

Consuming repos pin to `@v1`. The `v1` tag should be updated when pushing non-breaking changes. For breaking changes, create `v2`.

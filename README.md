# Claude factory

An autonomous issue loop for a GitHub repository, run by [Claude Code](https://claude.com/claude-code) on your
own Linux host. Open an issue; the loop checks it, builds it on its own branch, opens a pull request, gets it
reviewed, fixes what the review found, merges it on green CI and closes the issue — one fresh, headless Claude
session per step, each handing off through what GitHub already holds (a label, a comment, a pull request). It
asks you only for what you reserved for yourself, by a comment on the issue you answer by replying.

```
issue ──verify──▶ in-progress ──implement──▶ in-review ──review──▶ merged ──close──▶ closed
          │                          ▲                                 │
          └── waiting / needs-decision (parked; the hourly sweep or your reply resumes it)
                                     └──────── a new round when the merged work is not the whole issue
```

## What you get

- **A driver** (`scripts/factory-tick.sh`) that systemd timers run every few minutes: a *fast lane* that checks
  new issues, reviews and closes, and a *slow lane* that builds — each with its own workers and locks, at most N
  issues in flight, never two touching the same part of the code (`area:` labels), "blocked by" links honoured.
- **Five prompts** (`prompts/`): a shared header and one text per stage. Your project adds its own rules in its
  `CLAUDE.md` and, per stage, in `.factory/prompts/`.
- **An hourly sweep** that re-checks parked issues, retries what failed transiently, picks up your replies, tidies
  finished worktrees and reports on a monitor issue; **a live board** — one pinned issue that always shows what
  is in flight, what comes next and what waits on you; and a daily digest of everything it decided by itself.
- **A review workflow** for your repository (`templates/.github/workflows/claude-review.yml`): one
  severity-ranked pass per pull request, whose `fix-before-merge set: N` line the loop acts on, and a local
  self-review the build step runs with the same rubric before a PR opens.
- **Brakes:** a cap on the share of sessions spent on the loop's own tooling (that never idles a free slot), a
  pause on the account's usage limit, on an expired login and on a run of sessions that die at once, per-stage
  turn caps and effort levels, a load gate for extra workers.

## Quick start

You need a Linux host with systemd (user units, lingering on), `git`, `gh` (logged in as you), `jq`, `flock` and
`claude` on the PATH. Then, for a repository `you/app`:

```bash
git clone git@github.com:etrubenok/claude-workflows.git ~/factory-src
git clone git@github.com:you/app.git ~/factory/app        # the loop's own clone, on main; not your working copy
# In you/app, commit .factory/config, .factory/labels, the review workflow and a CLAUDE.md (see docs/adopting.md)
bash ~/factory-src/scripts/factory-install.sh ~/factory/app
claude setup-token     # then put CLAUDE_CODE_OAUTH_TOKEN=<token> in ~/.config/factory/app.env
```

The full walk-through — what to commit, the token, the first issue, how to stop and update — is
[docs/adopting.md](docs/adopting.md). How the loop works, label by label: [docs/how-it-works.md](docs/how-it-works.md).
Every label, transition and gate, as a reference: [docs/labels-and-gates.md](docs/labels-and-gates.md).

## Layout

| Path | What |
|---|---|
| `scripts/` | the driver, its stage runner, sweep and board, the installer and the helpers sessions call |
| `prompts/` | the header and the four stage texts every session is sent |
| `systemd/` | the unit templates the installer fills in |
| `templates/` | what a project commits: `.factory/config`, `.factory/labels`, the review workflows, a `CLAUDE.md` starting point, an allowlist, `.gitignore` lines |
| `tests/` | scenario tests on scratch state with fakes of `gh`, `claude` and `systemctl` (`bash tests/run.sh`) |
| `docs/` | adopting, how it works, the labels, transitions and gates, and the decisions behind the design |

## Status

Extracted on 2026-10-02 from the private project it was built for, where it ran for three weeks and merged about
two hundred pull requests; the history of that project is not part of this repository. It has not yet driven a second
project — expect rough edges in what a new project has to provide (see "Known limits" in docs/adopting.md). The
reusable GitHub Actions workflows this repository held before are in its history and under the `v1` tag.

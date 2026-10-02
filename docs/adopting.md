# Adopting the factory in a repository

Seven steps, about half an hour. Nothing here changes your working copy: the loop works in a clone of its own.

## 1. The host

A Linux machine that stays on, with systemd user units and lingering (`sudo loginctl enable-linger $USER`, once),
`git`, `jq`, `flock`, the GitHub CLI logged in as you (`gh auth login`; the loop posts through your account and
tells its own comments from your replies by a hidden mark), and Claude Code (`claude`). The loop's sessions run
your project's check command, so the host needs your project's toolchain too.

## 2. What the repository commits

Copy from this repository's `templates/` into yours, then edit:

| File | What to put in it |
|---|---|
| `.factory/config` | `FACTORY_CHECK` (the command every change must pass), and any setting you change from its default — each is listed there with its default |
| `.factory/labels` | your priority labels (highest first) and your `area:` labels: parts of the code whose changes would collide at merge; the description up to its first colon is what the board shows |
| `.github/workflows/claude-review.yml` | the review; adjust `runs-on` and the docs-only pattern if needed; keep the prompt's first sentence, the `fix-before-merge set: N` line and the `claude_args` line |
| `.github/workflows/claude-mention.yml` | optional: `@claude` in a comment gets an answer |
| `CLAUDE.md` | from `templates/CLAUDE.md`: what matters most, your hard stops, how you want to be written to, the check command |
| `.claude/settings.json` | the commands sessions may run without asking — `gh`, `git`, your build and test tools; deny what must never run |
| `.gitignore` | the lines in `templates/gitignore` |
| `.factory/prompts/<stage>.md` | optional: steps your project adds to a stage (header.md for all of them); `{{SANDBOX}}`, `{{CHECK}}`, `{{REPO}}` are filled in |

Then in the repository settings: add the secret `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) for the
review workflow. No branch protection is needed: the loop merges only on a review pass with nothing serious left
and every check green; add protection if you want GitHub to enforce that too.

## 3. The loop's own clone

```bash
git clone git@github.com:you/app.git ~/factory/app
```

On `main`, never worked in by hand: the loop fast-forwards it every few minutes and makes its worktrees under
`.claude/worktrees/` inside it.

## 4. Install

```bash
git clone git@github.com:etrubenok/claude-workflows.git ~/factory-src
bash ~/factory-src/scripts/factory-install.sh ~/factory/app
```

It refuses an edited factory checkout (what runs is always a commit) and a target that is not a clone of the
configured repository on `main`. It copies the factory to `~/.local/share/factory/<name>/`, writes the units
`factory-<name>-{fast,slow}@` and starts one worker each, creates `~/.config/factory/<name>.env` (mode 600) and
your labels. More workers: `FACTORY_IMPLEMENT_SLOTS=2 FACTORY_REVIEW_WORKERS=2 FACTORY_MAX_IN_FLIGHT=3 bash …`;
a re-run keeps what is installed unless you pass it again.

## 5. The loop's login

```bash
claude setup-token
echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> ~/.config/factory/<name>.env
```

Without it, sessions use the host's interactive login, which expires — the loop then pauses itself and says so on
its monitor issue.

## 6. The first issue

Before any timer fires, see what it would do: `FACTORY_CHECKOUT=~/factory/app
~/.local/share/factory/<name>/scripts/factory-tick.sh --dry-run`. Then open an issue that says what to change and
how you will know it worked. Within minutes the board issue appears (pinned), the issue gets a priority and an
area, and a build starts. Its log: `~/.local/state/factory/<name>/ticks.log`; one file per session beside it.

## 7. Day to day

- **Answer** a *Decision needed* by replying on the issue. Put `hold` on an issue the loop must leave alone.
- **Stop** the loop: `systemctl --user stop 'factory-<name>-*.timer'`; start it again with `start`.
- **Update** the factory: `git -C ~/factory-src pull`, then the install command again.
- **Remove** it: `bash ~/factory-src/scripts/factory-install.sh --uninstall ~/factory/app` (keeps the logs, the
  login and the labels).
- **Measure** it: `bash ~/.local/share/factory/<name>/scripts/factory-stats.sh` (busy time, sessions by stage).

## Known limits

- One host. Every instance is per repository and per host; two hosts running one repository would race.
- Linux with systemd only; the scripts are bash with GNU tools.
- The release check is yours to write: without one, merged is done. A service you deploy should get a
  `FACTORY_RELEASE_CHECK` that says when the change is really running.
- The board, the digest and the questions are written in English.
- Session cost: every stage is a full Claude session. The loop-share brake, the per-stage turn caps and the
  one-close-an-hour gate keep it bounded; `factory-stats.sh` shows where the sessions went.

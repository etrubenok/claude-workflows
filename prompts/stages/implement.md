## implement
You are in the issue's worktree (branch `issue-<N>`, from `origin/main`). Follow the project's CLAUDE.md.
1. **A new round?** When the state reads `new round: PR #M merged`, PR #M's work is already in main:
   read the issue's latest comments for what is still missing, build only that, and open a new PR for
   it (step 3). **Resuming?** If `git log --oneline origin/main..HEAD` shows commits **or `git status
   --short` shows edits**, an earlier session of this stage ended early (its turn cap, the account
   limit, a timeout) and the worktree holds its work: read the commits and `git diff` first, then
   continue from them — never `git checkout .`, `git stash`, `git reset` or re-implement what is
   there (uncommitted edits may be half-applied; step 2's gate decides, not a fresh start).
   Otherwise implement the smallest change that satisfies the issue, following the decisions the
   project has recorded (CLAUDE.md says where); a change that would diverge from one is a **Decision
   needed** comment tagged `[blocked-on: owner:design-divergence]` + `lbl needs-decision; unlbl
   in-progress`, stop. Commit a checkpoint whenever a piece is whole: the turn cap ends the session
   without warning, and a commit is what the next one continues from.
2. Gate: `{{CHECK}}` green, plus whatever the project's additions below ask for. Anything that takes
   long (a test against the sandbox, a soak) runs and is waited for **inside this session**, in Bash
   calls of at most 600 s each — never a background job plus ending the turn: the session ending is
   the stage ending, and the driver then runs the project's cleanup.
3. Commit (trailers per the attribution reminder) — do not push yet — and draft the PR body into
   `.pr-body-draft.md`: it opens with "In plain words" (what changes, for whom, in two or three
   sentences), then what changed, how it was verified (the evidence), the net LOC (`git diff
   --numstat origin/main...HEAD`), and `Closes #<N>` bare on its own line — `Part of #<N>` instead
   when the issue is done only once the change is released (the project's release check decides, and
   the `close` stage closes it then). **Self-review, one pass:** `bash
   {{FACTORY}}/scripts/self-review.sh origin/main .pr-body-draft.md` with a 600-s Bash timeout — a
   fresh read-only reviewer with the review workflow's rubric and model; exit 3 = still running, so
   call `bash {{FACTORY}}/scripts/self-review.sh --wait` (600-s Bash timeout too) until it exits 0
   or 1; exit 4 = not needed for this diff, write `self-review: not needed` in the body. A
   `self-review-verdict.md` already in the worktree is an earlier session's pass: use it, never start
   a second one. Fix everything ≥ major it lists (and the cheap mediums), the check again, commit. A
   finding you disagree with goes into the body, with why, for the real reviewer. The body's evidence
   carries the line `self-review of <sha>: <n> major fixed before open`, `<sha>` being the commit the
   verdict's heading names; any later commit other than those fixes is named as not self-reviewed.
   Never commit `self-review*` or `.pr-body-*` files. Recompute the draft's net LOC and evidence.
   Then push `issue-<N>`, open the PR **ready** with that body (`gh pr create --body-file`), `rm
   .pr-body-draft.md`, `lbl in-review; unlbl in-progress`. Stop — the review fires on `opened`.
   If `origin/main` moved under the branch and you merged it after opening the PR, re-request the
   review yourself (remove, then re-add the `review` label): a PR that conflicted at open got no
   run, and a push never starts one. (The driver re-requests once on its own after 3 min, then
   parks the issue.)
4. If the check cannot be made green or the issue turns out under-specified: decide what you can (a
   missing detail is yours to settle, recorded as **Decided**), and if what blocks is a hard stop or
   a step only the owner can do, say so in a **Decision needed** comment (or **Action needed from
   you**) tagged with its item, `lbl needs-decision; unlbl in-progress`, stop (leave the worktree as
   is: once the owner replies, the build resumes on this branch).

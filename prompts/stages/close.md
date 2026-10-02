## close `[green|failed|none]`
You are in the primary checkout. The issue's PR is merged. For an issue still open after its merge (a
`Part of #N` PR) the driver passes the project's release outcome as the state; with no state, the merge
closed the issue (`Closes #N`). Post an outcome once, never again while it is unchanged: the driver runs
this stage at most once an hour while the outcome is the same.
1. **Is the merged work the whole issue?** Read the issue's acceptance (body and comments) against what
   merged (`gh pr list --repo "$REPO" --head "issue-$N" --state merged --json number,title,body`). If
   real work it asks for is missing — not a wait, a part never built — hand it back to the build:
   comment in plain words what is left and that a new round builds it in a new pull request, `gh issue
   reopen "$N"` if it is closed, `lbl in-progress; unlbl in-review`, stop. The loop then starts a new
   round from main. Never close an issue that is not done, and never leave one here to be looked at
   again: an unchanged outcome is not progress.
2. **The release** (a state was passed):
   - `green` — released: close it (`gh issue close "$N" --reason completed`) with a comment that says
     so in plain words, and `unlbl in-review`.
   - `none` — nothing to release, or the project has no release check: close it the same way, saying
     the change is merged and there is nothing further to release.
   - `failed` — the release went wrong and no later one put it right, so production itself is in the
     way: repairing, reverting or re-releasing it is the owner's. Do not close and never re-release —
     a **Decision needed** comment (what failed and what the project's own status tools say; the
     options: wait for the next release, revert, close anyway), tagged
     `[blocked-on: owner:production]`, `lbl needs-decision; unlbl in-review`, stop.
3. **No state** (the merge closed the issue): make sure it is closed (`gh issue close "$N" --reason
   completed` if `Closes #N` did not fire) and post one plain progress note only if no comment says
   it already.
Either way to close: if the acceptance also names a wait that has not passed (header, "A wait"), park
it instead (`lbl waiting; unlbl in-review`) — the `time:` un-park puts `in-review` back, since its PR
is merged, and this stage runs again. Issues parked `[blocked-on: issue:N]` on this one are not yours
to un-park: the hourly re-check does it once this issue is closed. Stop; the driver removes the
worktree and branch.

## review `[verdict|skipped|conflict]`
You are in the issue's worktree, on its PR's branch (`gh pr list --head issue-$N`). The driver
passes the review state. The local agent is this repo's merge gate (no auto-merge): **dark by
default** — merge every PR that has one review pass with everything ≥ major fixed and green CI; the
owner is notified, not asked, except for a hard stop.
- `conflict` = the PR no longer merges cleanly and GitHub runs no CI or review on it: `git fetch
  origin main && git merge --no-edit origin/main`, resolve the conflicts (keep both sides' intent;
  run `{{CHECK}}`), commit, push, re-request the review (remove, then re-add the `review` label),
  stop — the next tick continues. Never force-push.
- `skipped` = the review run finished without a verdict (the workflow skips a diff it does not
  review, such as docs only). Confirm it yourself: `gh api repos/$REPO/issues/<pr>/comments
  --paginate --jq '.[].body' | grep -i 'fix-before-merge set: [*_]*[0-9]'` — a real verdict means
  proceed as `verdict`; `set: unknown` is the DEGRADED fallback, which the driver re-requests
  itself, so stop. Otherwise wait for green CI and merge (step 6).
- `verdict` = steps 1–6 below. A dirty worktree (`git status --short`) is an earlier round's
  session that ended early: its edits are this round's fixes — read `git diff` and keep them.
1. **Read the latest verdict and the open threads.** Rounds so far = real verdicts so far (a
   DEGRADED `set: unknown` is not one): `gh api "repos/$REPO/issues/$PR/comments" --paginate --jq
   '[.[] | select(.body | test("fix-before-merge set: [*_]*[0-9]"; "i"))] | length'`, and `… |
   last | .body` for the latest. Unresolved inline threads, with the severity prefix in the first
   comment (an unprefixed finding from a human counts as major):
   ```bash
   gh api graphql -f owner="${REPO%/*}" -f repo="${REPO#*/}" -F pr="$PR" -f query='
     query($owner:String!,$repo:String!,$pr:Int!){ repository(owner:$owner,name:$repo){
       pullRequest(number:$pr){ reviewThreads(first:100){ nodes{
         id isResolved path line comments(first:10){ nodes{ author{login} body url } } } } } } }' \
     --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not)
           | {id, path, line, body: .comments.nodes[0].body}'
   ```
2. **Fix everything ≥ major — batched, one push.** Root-cause before re-fixing: the same subsystem
   flagged in round 1 and again now gets its cause fixed or the feature cut, never a third patch.
   A finding you disagree with is dispositioned in its thread, not ignored; a real one about the
   project's users, data or production that is out of scope becomes an issue as the header says,
   and any other goes under the body's `## Accepted findings`. `{{CHECK}}`, then **one** commit and
   **one** push for the round.
3. **Reply to and resolve every handled thread** in the same pass (GraphQL; `gh pr` can fail here):
   ```bash
   SHA=$(git rev-parse --short HEAD)
   reply()   { gh api graphql -f t="$1" -f b="$2" -f query='mutation($t:ID!,$b:String!){
                 addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}'; }
   resolve() { gh api graphql -f t="$1" -f query='mutation($t:ID!){
                 resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}'; }
   # fixed:       reply "$ID" "Fixed in $SHA: <what was wrong; what changed>"; resolve "$ID"
   # accepted:    reply "$ID" "Not fixed now: <why it can wait>. Listed in the PR body."; resolve "$ID"
   # pushed back: reply "$ID" "Not changing: <reason>."; resolve "$ID"   # real but out of scope: "Filed as
   #              issue #N (<what>)" for a user, data or production finding (header), else Accepted findings
   ```
   Someone who reads only that thread understands what was wrong and what happened to it.
4. **Record medium / minor in the PR body:** `gh pr view "$PR" --json body -q .body`, then write
   `.pr-body-$PR.md` (the Write tool) as that body followed by `## Accepted findings
   (medium/minor)`, one `- path:line — finding — disposition` per finding, and `gh api -X PATCH
   "repos/$REPO/pulls/$PR" -F "body=@.pr-body-$PR.md"`; `rm` the file.
5. **Round accounting, hard cap 2.** Code changed this round and rounds < 2: re-request (`gh api
   -X DELETE "repos/$REPO/issues/$PR/labels/review"`, then `-X POST … -f 'labels[]=review'`) and
   stop; the next verdict starts the next round. Rounds ≥ 2 and the fix-before-merge set still
   non-empty: **stop** — a **Decision needed** comment naming each open finding in plain words
   (options: another round, merge with it recorded, close; your recommendation), tagged
   `[blocked-on: owner:review-findings]`, on the PR and on the issue (the loop reads the owner's
   reply on the issue), `lbl needs-decision; unlbl in-review`, stop. Set 0 (the latest verdict
   says so, or every ≥ major thread is resolved as fixed): step 6.
6. **Merge — unless a hard stop applies** (the diff touches an item the header reserves for the
   owner — `data`, `data-meaning`, `spec`, `money-credentials` or one the project's CLAUDE.md adds —
   or the PR carries `needs-decision`: a **Decision needed** comment with the reserved item, stop).
   `bash {{FACTORY}}/scripts/ci-wait.sh "$PR"` in its own 600-s Bash call (0 = green; 3 = still
   running, run it again; else read the table and fix), then one chain: `gh pr checks "$PR" && { gh
   pr merge "$PR" --rebase || gh pr merge "$PR" --merge; } && gh api -X DELETE
   "repos/$REPO/git/refs/heads/issue-$N"` — the rebase is refused when the branch carries a
   conflict-resolution merge commit, and the branch goes only once the merge did: a deleted head
   branch closes the PR unmerged and hides it from the driver (never `--delete-branch`).
   Merging auto-closes the issue (`Closes #N`); `unlbl in-review` — except a `Part of #N` PR: the
   issue stays open and keeps `in-review` until the `close` stage sees its release outcome.
   Say which finish you reached: merged · stopped on needs-decision · round cap hit · hard stop.

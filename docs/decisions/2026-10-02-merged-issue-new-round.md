# 2026-10-02 — A merged issue that is not done gets a new round

**Context.** The driver reads an issue's stage from its labels and the newest PR of its branch `issue-N`. A merged
PR always read as `close`. In the project the factory was extracted from, an issue's first PR merged, and a later
check found the issue needed a second change; it set `in-progress` again. The driver still read `close`; the close
session found nothing to close and stopped; the build lane left the issue to the close stage; and one close session
an hour re-read the same unchanged outcome — 28 sessions over 27 hours, nothing built, the issue holding a slot and
its area all along.

**Decision.** A merged PR on an issue that is `in-progress` without `in-review` is a **new round**: implement runs
again. The close stage is told to hand an unfinished issue back that way (reopen it if the merge closed it, then
`in-progress`), never to leave it for the next hourly look; verify starts a new round the same way. The new round
starts from main on a fresh `issue-N`: a local branch at the merged PR's head is that round's leftover and goes with
its worktree (uncommitted edits in it park the issue for the owner instead, `owner:unsaved-work`); the GitHub branch
at that head is deleted so `issue-N` can be pushed again; a branch past that head holds this round's own commits and
is kept. The session is told which PR already merged. Its new PR becomes the branch's newest, so review and close
follow as for any issue. An issue that waited mid-round resumes to the stage label it last lost (from GitHub's
label events), not to `in-review`, which would send it to close again.

**Alternatives.** A new issue per extra round — loses the issue's discussion and its link to the merged work, and
needs the loop to file issues about itself. A branch per round (`issue-N-2`) — every reader of `issue-N` (the
driver's PR lookup, the worktree, the sweep's tidy-up) would need the round number.

**Revisit if:** an issue runs more than two or three rounds — that is an issue too large for one, which the verify
stage should split instead.

**Tests.** `tests/factory-tick-test.sh`: "a merged pull request, in-progress again" (the stage), and the three
"new round" cases (leftover removed here and on origin, the session at main and told of the merged PR; uncommitted
edits parked; a branch past the merged head kept). A copy of the driver that reads every merged PR as `close` fails
all four.

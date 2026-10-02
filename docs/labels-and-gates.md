# Labels, transitions and gates

The rule book of the loop's state machine: every label, who may change it, every move an issue can make, and every
gate that can hold a move back. [how-it-works.md](how-it-works.md) is the overview; this file is the reference.
Each rule names the function or the prompt that holds it. A pull request that changes one changes this file too.

## 1. The labels

### The factory's own

The installer creates them (`labels` in `scripts/factory-install.sh`).

| Label | On | Means | Goes on | Comes off |
|---|---|---|---|---|
| `ready` | issue | Queue this now. Optional: an open issue with none of the loop's labels is queued just the same. On a waiting issue it is a person's word that the wait is over | by hand; by the driver when a build must wait for its area; by the loop when a wait ends on an issue with no pull request | when verify moves the issue on; by the sweep when it sits beside `in-progress` or `in-review` |
| `in-progress` | issue | Being built: the implement stage | by verify; by close or verify for a new round; by the loop when a wait in the middle of a new round ends | when implement opens the pull request; on any park; when the build must wait for its area |
| `in-review` | issue | Its pull request is in review, or merged and being closed | by implement; by the loop when a wait ends and the pull request is open | by review after the merge; by close; on any park |
| `waiting` | issue | Parked on something the loop ends by itself | by the stage or the driver that parks it | by the hourly sweep; by `ready` put on by hand |
| `needs-decision` | issue | Parked on the owner | by the stage, the driver or the sweep that parks it | when the owner replies on the issue; by `ready` put on by hand |
| `hold` | issue | The owner's brake: the pick leaves the issue alone | by the owner | by the owner |
| `tracking` | issue | Never built as one piece: a roadmap issue, the board, the monitor issue | by the owner; by the loop on its own two pages | by the owner |
| `review` | pull request | Adding it asks the review workflow for a pass | by the implement and review stages, the driver and the sweep, each time after taking it off; by hand | by the same, just before putting it back |

Three names used below: the **stage labels** are `in-progress` and `in-review`; the **wait labels** are `waiting`
and `needs-decision`; those four and `ready` are the **state labels**.

### The project's

From `.factory/labels` in the target repository; the installer creates them too.

| Labels | Given by | What the loop does with them |
|---|---|---|
| The priority labels (`FACTORY_PRIORITIES`, highest first) | verify, exactly one per issue, before anything else | The pick's order: priority, then age. An issue with none sorts last. Issues of `FACTORY_LOOP_CLASS` fall under the loop-share brake |
| `area:<part>` | verify, from the touch points; never a new one | Two issues that share one are never in flight together. An issue with none clashes with nothing |

## 2. How the loop reads an issue

Its labels first (`stage_of_labels` in `scripts/factory-tick.sh`); the first line that matches wins:

1. `waiting` or `needs-decision` — **parked**, whatever else it carries.
2. `in-progress` or `in-review` — **in flight**.
3. `hold` or `tracking` — **set aside**.
4. Anything else — **queued**: verify is its next stage.

A stage label outranks `hold`: the brake stops the pick, not a build or a review already under way.

For an issue in flight, the stage comes from the newest pull request of its branch `issue-N` (`read_stage`):

| Newest pull request | Labels | Stage |
|---|---|---|
| none | either stage label | implement |
| open | either stage label | review |
| merged | `in-review`, alone or with `in-progress` | close |
| merged | `in-progress` alone | implement, a **new round** |
| closed without merging | either stage label | parked for the owner (`owner:pr-closed`) |

## 3. The transitions

```
(no label | ready) ──verify──▶ in-progress ──implement──▶ in-review ──review──▶ merged ──close──▶ closed
        ▲                           │  ▲                       │                           │
        └── its area is busy ───────┘  └──── a new round: the merged work is not the whole issue
        any stage ──park──▶ waiting | needs-decision ──sweep, reply or `ready`──▶ the label section 4 names
```

Each row is one outcome of a stage. A session changes labels with the `lbl` / `unlbl` helpers of
`prompts/header.md`. The driver and the sweep move an issue from one state label to another through `set_state`,
which puts the new label on before it takes the old ones off, so a failed call leaves one label too many and never
none.

| Stage | Outcome | Labels afterwards | Held in |
|---|---|---|---|
| verify | already done | the issue is closed | `prompts/stages/verify.md` step 1 |
| verify | done but for a wait on the clock | `waiting`, `ready` off | step 1 |
| verify | reserved for the owner | `needs-decision`, `ready` off | step 2 |
| verify | an open blocker GitHub lists as "blocked by" | unchanged: it stays queued and the pick skips it | step 4 |
| verify | an open blocker whose link would not record | `waiting`, `ready` off | step 4 |
| verify | clear to build | one priority label, its `area:` labels, `in-progress`, `ready` off | step 5 |
| implement | an issue in flight shares one of its areas | `ready`, `in-progress` off; no session runs | `hold_area` |
| implement | pull request opened | `in-review`, `in-progress` off | `implement.md` step 3 |
| implement | a hard stop, a step only the owner can do, or a recorded decision it would break | `needs-decision`, `in-progress` off | steps 1 and 4 |
| implement | the session was cut off | unchanged: the next tick resumes on the branch | `advance` |
| review | fixes pushed and the review asked for again | unchanged: it waits for the next verdict | `review.md` step 5 |
| review | merged, the pull request says `Closes #N` | the issue is closed, `in-review` off; close runs in the same tick | step 6, `advance` |
| review | merged, the pull request says `Part of #N` | the issue stays open and keeps `in-review` | step 6 |
| review | two rounds done and something serious is still open | `needs-decision`, `in-review` off | step 5 |
| review | the change touches what is reserved for the owner | `needs-decision`, `in-review` off | step 6 |
| review | the review never started, never finished or failed twice | `waiting`, `in-review` off | `run_stage` |
| close | the merged work is not the whole issue | reopened if closed; `in-progress`, `in-review` off | `close.md` step 1 |
| close | released, or nothing to release, or the merge closed it | the issue is closed, `in-review` off | steps 2 and 3 |
| close | the release failed | `needs-decision`, `in-review` off | step 2 |
| close | merged for over `FACTORY_RELEASE_STALL` and still not released | `waiting`, `in-review` off | `run_stage` |
| close | the acceptance names a wait that has not passed | `waiting`, `in-review` off | last paragraph |
| any | its pull request was closed without merging | `needs-decision`, the stage label off | `advance` |

**A new round.** `in-progress` on an issue whose newest pull request merged builds what is left on a fresh
`issue-N` from main (`new_round_base` in `scripts/factory-stage.sh`). A leftover branch at the merged head is
removed, here and on GitHub. Uncommitted edits in its folder are never thrown away: the issue is parked
`owner:unsaved-work` instead. The new pull request becomes the branch's newest, so review and close follow as usual.

## 4. Parks: how an issue waits, and how the wait ends

**To park** (`park_issue`, and `prompts/header.md` for a session): a comment whose last visible line is
`[blocked-on: <class>]`, followed by the loop's hidden mark; then the wait label the class names; then the stage
label off. A park comment with no class reads as `owner`: the loop never guesses that a question answers itself.

| Class | Label | The wait ends when | Read by |
|---|---|---|---|
| `issue:<n>` | `waiting` | issue #n is closed | the hourly sweep (`cleared`) |
| `time:<instant>` | `waiting` | the instant has passed. It is UTC, `YYYY-MM-DDTHH:MM[:SS]Z`; one the loop cannot read becomes the owner's | the hourly sweep (`cleared`) |
| `ci` | `waiting` | the review or release moved on by itself; else the sweep retries hourly, up to `FACTORY_REREQUEST_MAX` (3) per pull request, then parks it `owner:ci-exhausted` | the hourly sweep (`retry_ci`) |
| `owner:<item>` | `needs-decision` | the owner replies on the issue | every fast tick (`resume_replied`) |

**The owner's items** are a closed list. The hard stops: `data`, `data-meaning`, `spec`, `force-push`,
`money-credentials`, and `hard-stop:<name>` for one the project's `CLAUDE.md` adds. A step only the owner can do:
`physical:<what>`. The loop's own stops: `ci-exhausted`, `pr-closed`, `review-findings`, `design-divergence`,
`production`, `unsaved-work`, and `filed-waiting`, which only the sweep writes, for an issue filed already carrying
a wait label. Anything that fits no item is not the owner's: the stage settles it and posts it as *Decided*.

**Three ways out of a park:**

| Way out | Rule | Passes the slot and area gate |
|---|---|---|
| The hourly sweep | the class's condition has cleared, or a `ci` retry is due | yes |
| The owner's reply | on a `needs-decision` issue only: a comment newer than the park comment, not from a bot and without the loop's mark. Quoted lines do not count. Each comment is judged once | yes |
| `ready` put on by hand | it must be newer than the wait label; an older one is taken off and the issue keeps waiting (`resume_answered`) | no |

**The label a wait goes back to** (`resume_label`):

| Newest pull request | Label put back | Next stage |
|---|---|---|
| open | `in-review` | review |
| none, or closed without merging | `ready` | verify again; a build then resumes on its branch |
| merged | the stage label the issue last lost: `in-progress` or `in-review`. `in-review` when the label history cannot be read | the new round, or close |

An issue going back in flight needs a free slot and free areas (`sweep_hold`). Without them it stays parked, is
listed as queued and is looked at again by the next sweep, or by the next tick for a reply. One going back to
`ready` joins the queue, which the pick gates.

## 5. The gates

A gate is a check that stops a move without failing it: the issue keeps its labels and is looked at again.

| Gate | Stops | Rule | Setting (default) | Held in |
|---|---|---|---|---|
| Pause | every session, both lanes | the account's usage limit until it resets; an expired login, 30 min at a time; three sessions in a row that died within 2 min, 30 min | — | `run_stage`, `run_lane` |
| Locks | two ticks of one lane and worker; two sessions on one issue | one lock per lane and worker, one per issue; the holder runs, the other skips | — | `with_issue_lock` |
| Load | a session of any worker above 1, except a close | the 1-minute load is over the ceiling | `FACTORY_LOAD_CEILING` (¾ of the cores) | `run_stage` |
| Lane | a stage in the wrong lane | fast: verify, review, close and the pick; slow: implement. With several fast workers, review is theirs and the rest is worker 1's | `FACTORY_REVIEW_WORKERS`, `FACTORY_IMPLEMENT_SLOTS` (1) | `advance`, `fast_stage_mine` |
| Stages per tick | a fourth stage of one issue in one tick; the same stage twice in a row | the next tick continues | `FACTORY_MAX_STAGES` (3) | `advance` |
| Slots | the pick; a wait ending back in flight | at most N issues in flight; a parked issue holds no slot | `FACTORY_MAX_IN_FLIGHT` (2) | `run_lane`, `sweep_hold` |
| Loop share | the pick of an issue of the loop's own class | its class took over the share of the last 24 h's sessions, unless nothing else can start | `FACTORY_LOOP_CLASS` (`p3-tooling`), `FACTORY_LOOP_SHARE_MAX` (20) | `run_lane`, `loop_share` |
| Area | the pick, a build, a wait ending back in flight | an issue in flight carries the same `area:` label | `.factory/labels` | `area_clash`, `hold_area` |
| Blocked by | the pick | an open "blocked by" link to an issue of this repository | — | `blockers_of` |
| Check and self-review | opening a pull request | the project's check is green; one read-only self-review pass, everything major fixed | `FACTORY_CHECK`, `FACTORY_SELF_REVIEW` (1) | `implement.md` steps 2 and 3 |
| Review state | the review session | `pending`: wait. `unrequested` (no run `FACTORY_REVIEW_GRACE` after the push) or `degraded`: ask once more. Twice, or unfinished after `FACTORY_REVIEW_STALL`: park `ci` | 180 s, 7200 s | `review_state` |
| Round cap | a third review round | two real verdicts, then the owner decides | — | `review.md` step 5 |
| Merge | the merge | nothing blocking, critical or major left; no hard stop in the diff; every check green (`ci-wait.sh` exits 0) | — | `review.md` step 6 |
| Release | the close of an issue still open after its merge | the project's release check says `pending`; `green`, `none` or `failed` lets the session run | `FACTORY_RELEASE_CHECK` (none), `FACTORY_RELEASE_STALL` (7200 s) | `release_state` |
| Close, hourly | a second close session on an unchanged release outcome | one an hour; a changed outcome runs at once | — | `run_stage` |

## 6. Rules that always hold, and what repairs a breach

`scripts/factory-label-audit.sh` checks five rules against GitHub and changes nothing:

1. A closed issue carries no state label.
2. An open issue carries at most one of `ready`, `in-progress`, `in-review`.
3. A parked issue carries no stage label. `ready` on one is a person's word and is not counted.
4. A `needs-decision` issue waits on the owner: its class is not `issue:`, `ci` or a readable `time:`.
5. A `waiting` issue waits on something the loop ends: `issue:`, `time:` or `ci`.

```bash
FACTORY_CHECKOUT=~/factory/<name> bash ~/.local/share/factory/<name>/scripts/factory-label-audit.sh
```

Exit 0 when every rule holds, 1 when one does not, 2 when GitHub could not be read.

A session that dies between its two label calls is the usual cause of a breach. The loop repairs most of them:

| Breach | Repair | By |
|---|---|---|
| A closed issue with a state label | the label is removed | the sweep (`sweep_tidy`) |
| `ready` beside `in-progress` or `in-review` | `ready` is removed | the sweep (`sweep_tidy`) |
| A wait label beside a stage label | the stage label is removed | the sweep (`hold_as`) |
| Both wait labels, or the wrong one for its class | the one the class names is kept | the sweep (`hold_as`) |
| `ready` older than the wait label beside it | `ready` is removed | the next fast tick (`resume_answered`) |

## 7. What the owner does by hand

- **Reply** on a `needs-decision` issue. That is the answer; no label is needed.
- **`ready`** on a queued issue changes nothing. On a parked issue it ends the wait, with no slot or area check.
- **`hold`** keeps a queued issue out of the pick. Taking it off puts the issue back in the queue.
- **`tracking`** marks an issue the loop must never build as one piece.
- **`review`** on a pull request, removed and added again, asks for a new review pass.
- **An issue filed already waiting** carries a wait label and says why in its first paragraph. The sweep reads
  that paragraph and tags the class in a comment.
- **A pull request closed without merging** parks its issue. Reopen it and reply, or close the issue. A fresh
  attempt needs a new issue.

## 8. Known gaps

Found in the review of pull request #4 on 2026-10-02. Each is what the code does today; delete a line when it is
fixed.

- **Nobody's identity is checked.** Any comment that is not a bot's and lacks the loop's mark counts as the owner's
  reply (`read_reply`), and every open issue is queued whoever opened it. On a public repository a stranger can
  answer a *Decision needed* or have an issue built.
- **A GitHub read that fails reads as a state.** No pull request found reads as implement, no labels as verify
  (`read_stage`); an issue whose state did not load reads as closed, and its folder and branch are removed
  (`advance`); label events that did not load resume a wait as `in-review` (`resume_label`).
- **`hold` on an issue in flight does nothing**, and a wait that ends on a held issue with an open or merged pull
  request puts its stage label back, so the work carries on while the loop's comment says it stays out of the queue
  (`unpark` in `scripts/factory-sweep.sh`).
- **A missing review secret reads as a skipped review.** Without `CLAUDE_CODE_OAUTH_TOKEN` in the repository the
  review workflow ends green with no verdict, `review_state` answers `skipped`, and the review stage merges on
  green CI alone. Neither the installer nor the driver checks for the secret.
- **A wait set by close on an issue the merge already closed is lost.** `close.md` does not say to reopen it, the
  sweep reads open issues only, and its tidy-up removes the label.
- **An issue reopened after its pull request merged, then parked by verify,** resumes with the old round's
  `in-review` and runs one close session before the build.
- **`in-progress` beside `in-review`** works, since the pull request decides the stage, but nothing removes the
  extra label while the issue is open, and the audit's rule 2 reports it.
- **The class `service:<name>`** is still named in the audit and in a comment of `scripts/factory-tick.sh`. No
  prompt writes it and the sweep has no rule for it.

## 9. Changing a rule

A label rule lives in up to four places, and a change touches each one it applies to:

1. The code: `stage_of_labels`, `read_stage`, `set_state`, `park_issue` and `resume_label` in
   `scripts/factory-tick.sh`; `advance` and `run_stage` in `scripts/factory-stage.sh`; the sweep in
   `scripts/factory-sweep.sh`.
2. The prompts: the **Labels** paragraph of `prompts/header.md`, and the stage's own file in `prompts/stages/`.
3. The tests: `tests/factory-labels-test.sh` (the sweep, the audit, the pick) and `tests/factory-tick-test.sh`
   (the stages, the new round, the brake). Run `bash tests/run.sh`.
4. This file, and the audit's rules when an invariant changes.

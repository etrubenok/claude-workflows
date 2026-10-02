# How the loop works

## One tick

Every few minutes a systemd timer runs `factory-tick.sh` for one lane and one worker. The tick fetches origin,
advances every issue in flight by at most a few stages, and — on the fast lane's worker 1 only — picks a new issue
when there is room, runs the hourly sweep, posts the daily digest and refreshes the board. Each stage is one
`claude -p` session: the header in `prompts/header.md`, that stage's text, and the project's own additions. The
session does the stage's work and hands off through GitHub; a crash at any point resumes from the labels.

## Stages and labels

| Labels | Newest PR of `issue-N` | Stage | Where it runs |
|---|---|---|---|
| none, or `ready` | — | verify | the primary checkout |
| `in-progress` | none | implement | the issue's worktree (slow lane) |
| `in-review` | open | review | the issue's worktree |
| `in-review` | merged | close | the primary checkout |
| `in-progress` | merged | implement: a **new round** | a fresh worktree from main |
| any | closed unmerged | parked for the owner | — |
| `waiting` / `needs-decision` | — | parked | — |
| `hold` / `tracking` | — | never picked | — |

The full rules — who changes each label, every outcome of every stage, how a wait ends and each gate — are in
[labels-and-gates.md](labels-and-gates.md).

**verify** gives the issue one priority label and its `area:` labels, closes it if it is already done, writes any
missing design detail as a *Decided* comment, links what it must wait for as GitHub "blocked by" links, and sets
`in-progress`. **implement** builds the smallest change, runs the project's check, runs one read-only self-review
with the review workflow's rubric, opens the PR (`Closes #N`, or `Part of #N` when the issue is done only once
released) and sets `in-review`. **review** acts on the review workflow's verdict: fixes everything blocking,
critical or major in one push, replies to and resolves each thread, at most two rounds, then waits for green CI and
merges. **close** checks that the merged work is the whole issue — handing it back for a new round if not — reads
the release outcome, and closes it.

## A new round

When a check finds that a merged PR did not finish its issue, the issue goes back to `in-progress`. The driver then
starts implement again from a fresh `issue-N` branch off main: a leftover branch or worktree at the merged PR's
head is removed (here and on GitHub), uncommitted edits in one park the issue rather than being thrown away, and
the session is told which PR already merged. Its new PR is the newest of the branch from then on. Why:
[decisions/2026-10-02-merged-issue-new-round.md](decisions/2026-10-02-merged-issue-new-round.md).

## Lanes, workers and limits

The **fast lane** (verify, review, close, the pick) and the **slow lane** (implement) run on their own timers, each
with 1–9 workers. With more than one fast worker, `review` is the extra workers' and everything else worker 1's,
so a long review never delays the pick. At most `FACTORY_MAX_IN_FLIGHT` issues are in flight; two that share an
`area:` label never are; an issue with an open "blocked by" link is skipped. Workers above 1 launch only while the
1-minute load is under `FACTORY_LOAD_CEILING`.

The queue is ordered by priority label, then age. Issues of `FACTORY_LOOP_CLASS` (the loop's own tooling) are held
back while their share of the last 24 h's sessions is over `FACTORY_LOOP_SHARE_MAX` — unless nothing else can
start, so a free slot is never left idle: [decisions/2026-10-02-loop-share-fills-idle-slots.md](decisions/2026-10-02-loop-share-fills-idle-slots.md).

## Waiting, and the owner

A stage that cannot go on **parks** the issue: a comment whose last visible line is `[blocked-on: <class>]` and the
label `waiting` (the loop ends it) or `needs-decision` (only you do). `issue:<n>` clears when that issue closes,
`time:<instant>` when the clock passes it, `ci` is retried hourly up to three times; `owner:<item>` names what
reserves it for you, from a closed list (your hard stops, a physical step, or one of the loop's own stops). The
hourly **sweep** reads every park, clears or retries what it can, and posts one report on the monitor issue when
something changed. You answer a question by **replying** on the issue; the next tick resumes it.

## What the loop writes on the host

| Path | What |
|---|---|
| `~/.local/share/factory/<name>/` | the installed copy of `scripts/` and `prompts/`, and `VERSION` |
| `~/.config/systemd/user/factory-<name>-*` | the units, and the budget drop-in |
| `~/.config/factory/<name>.env` | the login and any host-only setting |
| `~/.local/state/factory/<name>/` | `ticks.log`, one log per session (kept 14 days), locks, the board's and sweep's records |
| `<checkout>/.claude/worktrees/issue-N` | one worktree per issue being built |

## Pauses

A session that dies within two minutes never reached the model. The loop pauses both lanes on the account's usage
limit (until it resets), on an expired login (30 minutes at a time, with one note on the monitor issue) and on three
such deaths in a row of any kind, instead of relaunching every issue every few minutes.

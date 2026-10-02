#!/usr/bin/env bash
# factory-tick — one tick of the label-driven issue loop.
#
# Walks the GitHub issue labels and starts ONE fresh, stage-specific headless Claude session per issue and stage
# (`claude -p` with prompts/header.md plus that stage's prompts/stages/<stage>.md, and the project's own additions
# from its `.factory/prompts/`), never a long-lived agent: each stage hands off through an artifact GitHub already
# holds (a label, a comment, a PR), so a crashed tick resumes from the label. Stages:
#   no label     -> verify   : not already done? design complete, or written here?
#   (or `ready`)               -> in-progress | waiting | needs-decision | closed
#   in-progress  -> implement: worktree, code, the project's check, PR (Closes #n)
#                              -> in-review
#   in-review    -> review   : the verdict + threads on the PR (cap 2 rounds, merge)
#                              -> merged (issue auto-closes) -> close
#   merged       -> close    : report the outcome (the project's release check, if it has one), remove worktree + branch
#   merged + `in-progress`   -> implement again: a NEW round on a fresh branch from main, when a check decided the
#                              merged work is not the whole issue (docs/decisions/2026-10-02-merged-issue-new-round.md)
# A waiting issue carries `waiting` or `needs-decision` and no stage label; an issue the loop is to leave alone
# carries `hold` (the owner's) or `tracking`. Budget: at most MAX_IN_FLIGHT issues in flight (a waiting one is
# not), never two in flight sharing an `area:` label, MAX_STAGES stages per issue per tick. Two lanes, each with
# its own workers: the FAST lane (`--lane fast --worker k`, factory-<name>-fast@k.timer) runs verify/review/close
# and picks new issues, worker 1 keeping the short stages and every step that must happen exactly once (the pick,
# the sweep, the digest, the board) and leaving `review`, the one long stage here, to the workers above it; the
# SLOW lane (`--lane slow --worker k`, factory-<name>-slow@k.timer, one per implement slot) runs implement, one
# session per worker; no flag = both in turn. One tick per lane and worker (a lock each), one lane per issue (a
# lock per issue), and a usage-limit marker pauses both. Runs from the PRIMARY checkout (worktrees live under
# .claude/worktrees/), which the fast lane's worker 1 fast-forwards to origin/main when it is clean on main and no
# session is working in it. `--dry-run` prints the plan, `--issue N` restricts the tick to one issue, `--pr-of N`
# prints branch issue-N's newest PR as "<number> <state>" (nothing when it has none), `--review-state PR` prints a
# PR's review classification, `--release-state PR` prints a merged PR's release outcome (the close gate's
# reading), `--cleanup N` removes an issue's worktree + local branch (exit 1 if the folder or the branch stays or
# another lane holds the issue), `--sweep` runs the hourly sweep now (with `--dry-run`: classify every parked
# issue and print the report, change nothing), `--board` rewrites the live board now (with `--dry-run`: print
# its text, change nothing). The sweep's code is scripts/factory-sweep.sh, the board's scripts/factory-board.sh
# and the stage runner's — what happens to one issue in one tick — scripts/factory-stage.sh.
set -euo pipefail

HERE=$(cd "$(dirname "$(realpath "$0")")" && pwd)   # this file's folder: its siblings and prompts/ sit beside it
# shellcheck source=factory-config.sh
. "$HERE/factory-config.sh"
factory_config || exit 1
REPO="$FACTORY_REPO"
ROOT="$FACTORY_CHECKOUT"
NAME="$FACTORY_NAME"
STATE="${FACTORY_STATE:-$HOME/.local/state/factory/$NAME}"
POST="${FACTORY_MONITOR_POST:-$HERE/monitor-post.sh}"
SKILL="${FACTORY_HEADER:-$HERE/../prompts/header.md}"   # the header every stage session gets
STAGES="${FACTORY_STAGES:-$HERE/../prompts/stages}"     # … and its stages/<stage>.md, one file each
PROJECT_PROMPTS="${FACTORY_PROJECT_PROMPTS:-$ROOT/.factory/prompts}"   # the project's additions: header.md, <stage>.md
SWEEP_LIB="${FACTORY_SWEEP:-$HERE/factory-sweep.sh}"
BOARD_LIB="${FACTORY_BOARD:-$HERE/factory-board.sh}"
STAGE_LIB="${FACTORY_STAGE:-$HERE/factory-stage.sh}"
MAX_IN_FLIGHT="${FACTORY_MAX_IN_FLIGHT:-2}"
MAX_STAGES="${FACTORY_MAX_STAGES:-3}"
SESSION_TIMEOUT="${FACTORY_SESSION_TIMEOUT:-7200}"
REVIEW_GRACE="${FACTORY_REVIEW_GRACE:-180}"     # s after a push with no review run = nobody asked for one
REVIEW_STALL="${FACTORY_REVIEW_STALL:-7200}"    # s a review run may stay unfinished before the issue is parked
REVIEW_WORKFLOW="${FACTORY_REVIEW_WORKFLOW:-claude-review.yml}"   # the review workflow's file name in .github/workflows/
RELEASE_STALL="${FACTORY_RELEASE_STALL:-7200}"  # s after a merge with no release outcome before the issue is parked
MODEL="${FACTORY_MODEL:-claude-opus-5-5[1m]}"   # every stage session
# The project's release check (the close gate), or none. Run in the primary checkout as `<command> <merge sha>
# <issue>` for an issue still OPEN after its PR merged (a `Part of #N` PR: the issue is done only once its change is
# released, not merged). It prints ONE word: `green` (released), `failed` (the release went wrong; the owner
# decides), `none` (nothing to release — the close stage closes it), or `pending` (not yet; asked again next tick,
# until RELEASE_STALL parks the issue). Without one, an issue still open after its merge is closed by `close`.
RELEASE_CHECK="${FACTORY_RELEASE_CHECK:-}"
SWEEP_H="${FACTORY_SWEEP_INTERVAL_H:-1}"         # the sweep runs at most once per this many hours
PR_STALL_H="${FACTORY_PR_STALL_H:-2}"            # h with no new commit and no new verdict = a stalled PR
REREQUEST_MAX="${FACTORY_REREQUEST_MAX:-3}"      # sweep retries per PR before its issue is parked `owner:ci-exhausted`
# Implement slots: the slow-lane workers the fast lane may kick on a hand-off (the installer's drop-in sets it with
# the timers it enables), and the gate every worker but the first passes before it launches a session — the 1-min
# load average.
SLOTS="${FACTORY_IMPLEMENT_SLOTS:-1}"
# The fast lane's workers: how many factory-<name>-fast@k.timer the installer enabled. It decides the stage split,
# not this tick's own number: above 1, worker 1 hands `review` to the others and they run nothing else
# (fast_stage_mine).
REVIEW_WORKERS="${FACTORY_REVIEW_WORKERS:-1}"
LOAD_CEILING="${FACTORY_LOAD_CEILING:-$(( $(nproc 2> /dev/null || echo 4) * 3 / 4 )).0}"
LOADAVG="${FACTORY_LOADAVG:-/proc/loadavg}"
STAGGER="${FACTORY_WORKER_STAGGER:-60}"   # s worker k waits per k above 1, so worker 1 starts (and loads the host) first
# A review verdict's own line — the one pattern the driver, the sweep, the prompts and scripts/self-review.sh use;
# `[*_]*` because a bold count (`set: **2**`) is still a verdict.
VERDICT_RE='fix-before-merge set: [*_]*[0-9]'
# The priority labels, highest first: the pick's ladder. The sweep and board files fall back to the same list.
PRIORITIES="${FACTORY_PRIORITIES:-p1-production p2-product p3-tooling}"
# The loop's own share of its sessions, as a percentage of the trailing 24 h: above it, the pick starts a
# LOOP_CLASS issue only when nothing else can start (loop_share; docs/decisions/2026-10-02-loop-share-fills-idle-slots.md).
# An empty LOOP_CLASS, or a share of 100, turns the brake off. The owner's `--issue N` is never held by it.
LOOP_CLASS="${FACTORY_LOOP_CLASS-p3-tooling}"
LOOP_SHARE_MAX="${FACTORY_LOOP_SHARE_MAX:-20}"
# How many issues one list call may return. The pick's last class is every open issue, and GitHub returns the
# NEWEST when a list is cut off, so a limit below the number of open issues would hide the OLDEST — the very ones the
# queue takes first. Above the count either way, and a list that reaches it says so.
LIST_LIMIT="${FACTORY_LIST_LIMIT:-300}"
# The hidden line every comment the loop posts ends with: it posts through the owner's account, so this is how it
# tells its own comments from the owner's replies. The sweep file and the prompts use the same string.
FACTORY_MARK="${FACTORY_COMMENT_MARK:-<!-- claude-factory -->}"
DRY=0; ONLY=""; CLEANUP=""; SWEEP=0; BOARD=0; WORKER=1; SWEEP_LOADED=0; BOARD_LOADED=0; STAGE_LOADED=0
LAST_LABELS=""; LAST_LABELS_N=""   # the labels stage_of last read, and whose: run_stage's class tag reads them, not GitHub again
REVIEW_STATE=""; RELEASE_STATE=""; PR_OF=""; LANES="fast slow"; LANE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --issue) ONLY="$2"; shift ;;
    --cleanup) CLEANUP="$2"; shift ;;
    --pr-of) PR_OF="$2"; shift ;;
    --review-state) REVIEW_STATE="$2"; shift ;;
    --release-state) RELEASE_STATE="$2"; shift ;;
    --sweep) SWEEP=1 ;;
    --board) BOARD=1 ;;
    --lane) case "$2" in fast|slow) LANES="$2" ;; *) echo "--lane takes fast or slow"; exit 2 ;; esac; shift ;;
    --worker) WORKER="$2"; shift ;;
    *) echo "usage: factory-tick.sh [--lane fast|slow [--worker K]] [--dry-run] [--issue N] [--cleanup N] [--pr-of N] [--review-state PR] [--release-state PR] [--sweep] [--board]"; exit 2 ;;
  esac
  shift
done
[ "$SWEEP_H" -ge 1 ] 2>/dev/null || SWEEP_H=1
[[ $SLOTS =~ ^[1-9]$ ]] || SLOTS=1   # 1–9, the installer's range
[[ $REVIEW_WORKERS =~ ^[1-9]$ ]] || REVIEW_WORKERS=1   # the same range; anything else reads as the default, one worker
[[ $STAGGER =~ ^[0-9]+$ ]] || STAGGER=60
[[ $LOAD_CEILING =~ ^[0-9]+(\.[0-9]+)?$ ]] || LOAD_CEILING=6.0   # awk reads a word as 0: every worker above 1 gated off
[[ $LOOP_SHARE_MAX =~ ^[0-9]+$ ]] || LOOP_SHARE_MAX=20
[[ $WORKER =~ ^[1-9][0-9]*$ ]] || { echo "--worker takes a positive integer"; exit 2; }
# Both lanes have workers, so a worker above 1 must say which lane it is: with no --lane it would run as that
# worker in both, and the two have different stage splits.
[ "$WORKER" = 1 ] || [ "$LANES" != "fast slow" ] || { echo "--worker above 1 takes one lane: add --lane fast or --lane slow"; exit 2; }
W=""; [ "$WORKER" = 1 ] || W="-$WORKER"   # worker 1 keeps its lane's original lock and log tag

mkdir -p "$STATE"
log() { printf '%s %s%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${LANE:+[$LANE$W] }" "$*" | tee -a "$STATE/ticks.log"; }
for tool in git gh claude jq; do
  command -v "$tool" > /dev/null || { log "missing tool: $tool (PATH=$PATH)"; exit 1; }
done
[ -r "$SKILL" ] || { log "missing prompt header $SKILL — reinstall the factory"; exit 1; }
# Every stage's own text, checked here rather than at launch: a session sent the header alone would run a stage
# without its steps.
for s in verify implement review close; do
  [ -r "$STAGES/$s.md" ] || { log "missing stage text $STAGES/$s.md — reinstall the factory"; exit 1; }
done
# The project's sandbox (optional): the one working directory a stage session gets besides its checkout, for what
# its checks write outside the repository (a scratch data folder, a test database). `acceptEdits` auto-accepts
# edits, mkdir, touch, mv and cp under EVERY working directory, so nothing a session must not clobber may be one:
# the driver refuses a sandbox that is, lies under or holds any of FACTORY_PROTECTED (space-separated folders —
# production data, the installed factory, its state), every path resolved through symlinks. The factory's own
# install and state folders are always protected.
SANDBOX="${FACTORY_SANDBOX:-}"
if [ -n "$SANDBOX" ]; then
  sandbox_real=$(realpath -e -- "$SANDBOX" 2> /dev/null) && [ -d "$sandbox_real" ] || { log "missing sandbox folder $SANDBOX (FACTORY_SANDBOX)"; exit 1; }
  sandbox_real=${sandbox_real%/}/
  for p in ${FACTORY_PROTECTED:-} "$HERE/.." "$STATE"; do
    p_real=$(realpath -m -- "$p"); p_real=${p_real%/}/
    if [[ $sandbox_real == "$p_real"* || $p_real == "$sandbox_real"* ]]; then
      log "refusing sandbox $SANDBOX: it is, lies under or holds the protected folder $p, and a session gets auto-accepted edits in it"
      exit 1
    fi
  done
fi
cd "$ROOT"
# Worker k waits (k-1) × STAGGER before it does anything at all — before the fetch below, so the workers' fetches
# of this one checkout are spread out too, and worker 1 always starts first.
[ "$WORKER" = 1 ] || [ "$DRY" = 1 ] || sleep $(( (WORKER - 1) * STAGGER ))
# Every branch of origin: the fast lane fast-forwards this checkout to origin/main, a resumed implement / review
# its issue-<n> branch. Bounded; the retry covers the other lane fetching at the same moment (a ref lock); a fetch
# that still fails is one line and the tick goes on with the refs it has. `--prune` drops the origin/issue-<n> of a
# merged, deleted branch. The two queries that read no refs — `--review-state` and `--pr-of` — skip it
# (`--release-state` reads them).
fetch_origin() { timeout 60 git fetch -q --prune origin; }
if [ -z "$REVIEW_STATE$PR_OF" ]; then
  rc=0; fetch_origin || { sleep 2; fetch_origin; } || rc=$?
  [ "$rc" = 0 ] || log "git fetch origin FAILED twice (exit $rc; 124 = 60 s timeout) — this tick goes on with the refs it has"
fi

labels_of() { gh issue view "$1" --repo "$REPO" --json labels --jq '[.labels[].name] | join(" ")'; }
issue_state() { gh issue view "$1" --repo "$REPO" --json state --jq .state; }
# The newest pull request of branch issue-N as "<number> <state>", and NOTHING when that branch never had one.
# GitHub returns an empty list there, whose `last` is `null`, so without `// empty` this would print the literal
# `null null`: a number and a state that look like data, which a caller could repeat to the owner as the state of
# their pull request. A query that FAILS prints nothing too (`|| true`), so a caller cannot tell it from a branch
# with no pull request — no caller reads that difference today. `--pr-of N` prints this line;
# tests/factory-tick-test.sh holds it to both answers.
pr_of() { gh pr list --repo "$REPO" --state all --head "issue-$1" --json number,state --jq 'sort_by(.number) | last // empty | "\(.number) \(.state)"' 2>/dev/null || true; }
# Open issues carrying every label given, with their labels: "<n> <labels…>" lines, oldest first. The pick
# judges a candidate by its labels, and every open issue is one, so reading them one call per candidate would
# spend a large share of the account's 5,000 API reads an hour. This way they come with the list.
issues_labels_with() {
  local l x; local -a by=()
  for l in "$@"; do by+=(--label "$l"); done
  x=$(gh issue list --repo "$REPO" --state open "${by[@]}" --limit "$LIST_LIMIT" --json number,labels \
        --jq '.[] | "\(.number) \([.labels[].name] | join(" "))"' | sort -n) || return 1
  [ "$(grep -c . <<< "$x" || true)" -lt "$LIST_LIMIT" ] \
    || log "the open-issue list reached its limit of $LIST_LIMIT — the oldest issues may be missing from this pick"
  grep . <<< "$x" || true
}
issues_with() { issues_labels_with "$@" | cut -d ' ' -f 1; }   # just their numbers
# The issues in flight — open, `in-progress` or `in-review`, not waiting — one line each: "<n> <labels…>".
# An issue carrying both stage labels (a session that died between the flips) is one line: `sort -nu`
# keys on the number alone, so a label order that differs between the two reads cannot list it twice.
# Which of them counts is stage_of_labels' answer, never a second reading of the same labels here: a waiting
# issue drops its stage label and one that still carries one is in flight for neither this list
# nor the board, which is the same function's doing.
inflight_labels() {
  local l x all="" row
  for l in in-progress in-review; do
    x=$(issues_labels_with "$l") || return 1
    while read -r row; do
      [ -n "$row" ] && [ "$(stage_of_labels "${row#* }")" = flight ] || continue
      all+="$row"$'\n'
    done <<< "$x"
  done
  sort -nu <<< "$all" | grep . || true
}
# Never two in flight in one area: prints "area:<x> in
# flight on issue #<m>" for the first `area:` label among issue N's LABELS that another issue in the
# inflight_labels lines BUSY carries; fails when there is none — an issue with no `area:` label clashes
# with nothing. An area keeps work on one part of the code to one issue at a time; it bounds nothing else (a
# resource only one session may use at a time needs its own lock in the project's tooling).
area_clash() {
  local n="$1" own="$2" busy="$3" m ls a
  while read -r m ls; do
    [ -n "$m" ] && [ "$m" != "$n" ] || continue
    for a in $own; do
      case "$a" in area:*) case " $ls " in *" $a "*) echo "$a in flight on issue #$m"; return 0 ;; esac ;; esac
    done
  done <<< "$busy"
  return 1
}
# The open issues of this repository that issue N waits for, from GitHub's own "blocked by" links: one number per
# line, lowest first. A link to another repository's
# issue is not read: its number would name an issue here. One API call; fails when it fails.
blockers_of() {
  gh api "repos/$REPO/issues/$1/dependencies/blocked_by" --paginate \
    --jq ".[] | select(.state == \"open\" and (.repository_url | endswith(\"/repos/$REPO\"))) | .number" | sort -n
}

# What an issue's LABELS alone say about it — the ONE place the loop decides whether an issue is its to
# start, so the pick and the live board cannot
# drift apart. `ready` stopped being the gate: an issue carrying no label of ours is `verify`, exactly like
# one carrying `ready`, which is now only an explicit "queue this". The other three:
#   blocked — waiting for the owner or for the clock (the wait labels; a stage label on one does not count).
#   held    — the owner's `hold`, or `tracking`: a roadmap issue, the monitor issue, the board's own page.
#             Never started, never reported as a wait, because nothing is waiting for anything.
#   flight  — a stage label; which stage that is needs its PR (stage_of).
# A stage label outranks `hold` on purpose: the owner's brake stops the pick, not a build already under way,
# which with `in-progress` left on would hold a slot and its areas for good. It takes effect when that ends.
stage_of_labels() {
  case " $1 " in
    *" needs-decision "*|*" waiting "*) echo blocked ;;
    *" in-review "*|*" in-progress "*) echo flight ;;
    *" hold "*|*" tracking "*) echo held ;;
    *) echo verify ;;
  esac
}

# The class of a label list: the first of PRIORITIES it carries, else `none` (an issue `verify` has not rated).
issue_class() { local p; for p in $PRIORITIES; do case " $1 " in *" $p "*) echo "$p"; return ;; esac; done; echo none; }
# The loop's own share of the stage sessions it started in the trailing 24 h, a whole percentage: run_stage ends
# every stage line it logs with the issue's class, and this counts the LOOP_CLASS ones over all the tagged ones, so a
# fresh host starts at 0. A dry run's line counts too: it is the owner's own inspection, and rare. The sessions are
# counted, not their length: a one-minute check and a two-hour build are one each. 0 when there is no LOOP_CLASS.
loop_share() {
  local since
  [ -n "$LOOP_CLASS" ] || { echo 0; return; }
  since=$(date -u -d '24 hours ago' +%FT%TZ)
  awk -v s="$since" -v own_tag="[class:$LOOP_CLASS]" '$1 >= s && / stage (verify|implement|review|close)[^[]*\[class:/ { n++; if (substr($0, length($0) - length(own_tag) + 1) == own_tag) own++ }
                     END { print (n ? int(own * 100 / n + 0.5) : 0) }' "$STATE/ticks.log" 2> /dev/null || echo 0
}

# The stage an issue is in, from its labels (read once) and PR (the resumable state machine). A merged PR means
# `close` — unless the issue is `in-progress` again without `in-review`: a check (verify, close, the owner) found the
# merged work is not the whole issue and handed it back to the build, which then runs a NEW round on a fresh branch
# from main (run_stage, new_round_base) and opens a new PR, the newest pr_of reads from then on. Before this, such an
# issue kept reading `close` for good: the close found nothing to close, the build lane left it to the close, and
# one session an hour reran the same close (docs/decisions/2026-10-02-merged-issue-new-round.md).
# read_stage sets STAGE (and LAST_LABELS, LAST_LABELS_N) in the calling shell, so run_stage's class tag reuses the
# labels it read; stage_of prints the same answer for a caller that wants it as a value.
read_stage() {
  local n="$1" pr
  LAST_LABELS=$(labels_of "$n"); LAST_LABELS_N=$n
  STAGE=$(stage_of_labels "$LAST_LABELS")
  [ "$STAGE" = flight ] || return 0
  pr=$(pr_of "$n")
  case "${pr#* }" in
    MERGED) case " $LAST_LABELS " in *" in-review "*) STAGE=close ;; *" in-progress "*) STAGE=implement ;; *) STAGE=close ;; esac ;;
    OPEN) STAGE=review ;;
    CLOSED) STAGE=abandoned ;;   # closed without merging: a human decision, not a retry
    *) STAGE=implement ;;
  esac
}
stage_of() { read_stage "$1"; echo "$STAGE"; }

# Seconds since an ISO-8601 timestamp; -1 when there is none or GNU date cannot read it (callers treat that as
# "too young to judge", never as a verdict). Empty is checked first: `date -d ""` reads as today's midnight.
age_s() { local ts; [ -n "$1" ] || { echo -1; return; }; ts=$(date -d "$1" +%s 2>/dev/null) || { echo -1; return; }; echo $(( $(date +%s) - ts )); }

# Parks an issue: the reason as a comment (the owner and the daily digest read it), then its wait label —
# `needs-decision` for an `owner` class, else `waiting` — in place of its stage label. The comment carries
# the class the hourly sweep reads: `issue:<n>`, `service:<name>` and `time:<UTC instant>` (issue
# #198) clear themselves, `ci` is retried, `owner:<item>` waits for the owner and its item says what reserves it
# for them. Written for a reader who has opened
# nothing else (CLAUDE.md "Writing for the owner"), the tag last. An `owner` park takes ANSWER too, what the
# owner can do: only the caller knows which way on works (`ready` alone re-parks an issue whose PR was closed).
# The board's record of what each parked issue waits for: one line per issue, appended the moment
# an issue is parked and rewritten whole by every sweep. Both writes go through here, under one lock, because
# they come from different lanes at the same time and the file is read back a line at a time: the lock is what
# keeps a truncation and an append from leaving a half-written line behind. It does NOT save a park that lands
# while the sweep is running: the sweep builds its text from the parked issues it listed at the start, so a park
# made after that is dropped by the rewrite and that issue reads on the board as a bare "waiting" until the next
# sweep an hour later.
board_parked_write() {   # append|replace, then the text
  local fd
  exec {fd}> "$STATE/.lock-parked"; flock "$fd"
  case "$1" in
    append) printf '%s' "$2" >> "$STATE/board-parked" ;;
    *) printf '%s' "$2" > "$STATE/board-parked" ;;
  esac
  exec {fd}>&-
}

park_issue() {
  local n="$1" class="$2" why="$3" answer="${4:-}" next label=waiting line
  case "$class" in owner|owner:*) label=needs-decision ;; esac
  log "issue #$n: $why — parked, label $label [$class]"
  [ "$DRY" = 1 ] && return 0
  case "$class" in
    ci) next="**Nothing needed from you yet.** The automatic review or release check did not get through, which is usually a passing hiccup. The loop retries it every hour, up to $REREQUEST_MAX times, and asks you if that fails." ;;
    owner|owner:*) next="**This needs you:** the loop cannot clear it by itself."${answer:+$'\n\n'"$answer"} ;;
    *) next="**Nothing needed from you.** The loop re-checks this every hour and carries on by itself." ;;
  esac
  gh api -X POST "repos/$REPO/issues/$n/comments" -f body="## Waiting: $why"$'\n\n'"$next"$'\n\n'"[blocked-on: $class]"$'\n\n'"$FACTORY_MARK" > /dev/null
  # What the board says this issue waits for, until the next sweep rewrites the file from every parked issue:
  # the board reads the class here rather than re-reading each parked issue's comments every tick.
  # The reason is folded to one line of at most 200 characters, as the sweep folds its own, so a long or
  # multi-line one cannot break the one-line-per-issue format the board reads back.
  line=${why%%$'\n'*}
  board_parked_write append "$(printf '%s\t%s\t%s' "$n" "$class" "${line:0:200}")"$'\n'
  set_state "$n" "$(labels_of "$n")" "$label" || log "issue #$n: not fully relabelled $label"
}

# What the owner can do about an issue whose pull request was closed unmerged (stage_of's `abandoned`): the
# loop never starts it over — pr_of keeps finding that pull request — so only a reopen or a close moves it.
CLOSED_PR_ANSWER="**To answer:** to keep the work, reopen the pull request, then reply here: the loop resumes its review. If the work is not wanted, close this issue. A reply without reopening only runs one more check, which finds the closed pull request and stops here again, so a fresh attempt needs a new issue."

# The stage label an issue goes back to when its wait ends: `in-review` when its PR is open, `ready` when it has none
# (verify starts it again; a build resumes on its existing branch). With a merged PR, the stage label the issue last
# lost, from GitHub's own label events: `in-progress` for a new round that was waiting mid-build — `in-review` there
# would send it to close, the round unbuilt — and `in-review` for a close that was waiting (also when the events do
# not load: the close looks again and hands the issue back if work is left).
resume_label() {
  local pr last
  pr=$(pr_of "$1")
  case "${pr#* }" in
    OPEN) echo in-review ;;
    MERGED)
      last=$(gh api "repos/$REPO/issues/$1/events" --paginate --jq '.[] | select(.event == "unlabeled"
               and (.label.name == "in-progress" or .label.name == "in-review")) | .label.name' 2> /dev/null | tail -n 1) || last=""
      echo "${last:-in-review}" ;;
    *) echo ready ;;
  esac
}

# Puts state label TO on issue N, then takes every other state label among LABELS off — on first, so a failed
# call leaves one label too many, never none. Fails when TO could not go on or a label could not come off.
set_state() {
  local n="$1" labels="$2" to="$3" l rc=0
  gh api -X POST "repos/$REPO/issues/$n/labels" -f "labels[]=$to" > /dev/null || return 1
  for l in $labels; do
    case "$l" in
      ready|in-progress|in-review|waiting|needs-decision)
        [ "$l" = "$to" ] || gh api -X DELETE "repos/$REPO/issues/$n/labels/$l" > /dev/null || { log "issue #$n: could not remove $l"; rc=1; } ;;
    esac
  done
  return "$rc"
}

# `ready` put on a waiting issue: a person ended the wait by hand (the owner's usual answer is a reply, which
# resume_replied reads). It resumes by resume_label's rule, without the slot and area gate. Only a `ready` newer
# than the wait label counts: an older one (a session that died between its two label calls) comes off, and it waits.
resume_answered() {
  local x n ls to last
  x=$(gh issue list --repo "$REPO" --state open --label ready --limit 100 --json number,labels \
        --jq '.[] | select([.labels[].name] | index("waiting") or index("needs-decision")) | "\(.number) \([.labels[].name] | join(" "))"') \
    || { log "listing the ready issues failed — a \`ready\` put on a waiting issue is read next tick"; return 0; }
  # fd 3, not stdin: nothing inside may eat the list.
  while read -r -u 3 n ls; do
    [ -n "$n" ] || continue
    [ -z "$ONLY" ] || [ "$n" = "$ONLY" ] || continue
    last=$(gh api "repos/$REPO/issues/$n/events" --paginate --jq '.[] | select(.event == "labeled"
             and (.label.name | test("^(ready|waiting|needs-decision)$"))) | .label.name' | tail -n 1) || continue
    if [ "$last" != ready ]; then
      log "issue #$n: its \`ready\` is older than its \`$last\` — taken off, it keeps waiting"
      [ "$DRY" = 1 ] || gh api -X DELETE "repos/$REPO/issues/$n/labels/ready" > /dev/null || log "issue #$n: could not remove ready"
      continue
    fi
    to=$(resume_label "$n")
    log "issue #$n: \`ready\` was put on it while it waited — it resumes as $to"
    [ "$DRY" = 1 ] || with_issue_lock "$n" set_state "$n" "$ls" "$to" || log "issue #$n: not resumed — next tick"
  done 3<<< "$x"
}

# Fast-forwards the primary checkout to origin/main: `verify` and `close` read its tree and
# take the headless allowlist from it. Only a clean `main` that origin/main descends from moves; anything
# else stays as it is, with one line naming why — the owner works here: never a reset, stash, checkout or
# clean. git refuses on its own a merge that would overwrite a file (an edit or an untracked file made
# since the check, an index.lock held). Called through ff_locked, which is what keeps the tree from moving
# under a session working in it.
ff_checkout() {
  local head from to dirty err
  head=$(git symbolic-ref -q --short HEAD) || head="a detached HEAD"
  from=$(git rev-parse -q --verify HEAD) || from=""
  to=$(git rev-parse -q --verify origin/main) || { log "checkout: no origin/main ref — not fast-forwarded"; return 0; }
  [ "$head" = main ] || { log "checkout: on $head, not main — not fast-forwarded"; return 0; }
  [ "$from" != "$to" ] || return 0
  if ! git merge-base --is-ancestor HEAD origin/main; then
    log "checkout: main ${from:0:7} is ahead of or diverged from origin/main ${to:0:7} — not fast-forwarded"; return 0
  fi
  if ! dirty=$(git --no-optional-locks status --porcelain --untracked-files=no) || [ -n "$dirty" ]; then
    log "checkout: uncommitted edits on main ${from:0:7} — not fast-forwarded to ${to:0:7}"; return 0
  fi
  if err=$(git merge -q --ff-only origin/main 2>&1); then
    log "checkout: main fast-forwarded ${from:0:7} → ${to:0:7} (origin/main)"
  else
    log "checkout: fast-forward of main ${from:0:7} refused, left as is — ${err%%$'\n'*}"
  fi
}

# ff_checkout under the primary checkout's own lock. `verify` and `close` sessions run IN that
# tree, and it must not move under one. With a single fast worker the lane's own lock said so: every such
# session was that worker's, and it ran none while it fast-forwarded. With more workers, the close a worker
# above 1 runs after its own review merged the pull request is in that tree while worker 1's next tick starts,
# so the two now say it directly — a session takes this lock SHARED (run_stage), the fast-forward takes it
# exclusively and skips this tick when a session holds it, with one line. Two read-only sessions in the tree are
# fine and still run side by side; worker 1's next tick moves the tree, two minutes later. It guards the tree against
# what a SESSION does not expect: the driver's own writes there (cleanup_issue's worktree remove, prune and
# branch delete) stay outside it, because git takes its own ref and index locks and a refusal is one logged line
# the sweep retries — never a session reading a tree that moved mid-read.
ff_locked() {
  local fd rc=0
  exec {fd}> "$STATE/.lock-checkout"
  if flock -n -x "$fd"; then ff_checkout || rc=$?
  else log "checkout: a stage session is working in it — not fast-forwarded this tick"; fi
  exec {fd}>&-
  return "$rc"
}

# with_issue_lock N cmd args…: never two sessions for one issue — a lane or slow worker that finds
# the issue in flight elsewhere skips it this tick. Held across the whole command (stages + the
# project's cleanup + the worktree's), which closes the label-flip window at the end of an implement session.
with_issue_lock() {
  local n="$1" fd rc=0; shift
  exec {fd}>"$STATE/issue-$n.lock"
  if flock -n "$fd"; then "$@" || rc=$?; else log "issue #$n: in flight in another lane or worker"; rc=1; fi
  exec {fd}>&-
  return "$rc"
}

# An `in-progress` issue about to be built goes back to `ready` when an issue in flight shares one of its
# `area:` labels (the verify stage labels them; the pick skips it until that area is free). `ready` goes on
# before `in-progress` comes off (set_state). Succeeds — no build now — whenever an area clashes, even if a
# label did not move: advance checks again before the slow lane builds, so that only delays the comment. The
# comment says when the build had already started, which happens when resume_answered put a same-area issue
# back in flight without the area check: it has a branch_of, which run_stage resumes on.
hold_area() {
  local n="$1" busy why own area other lead="Checked and ready to build, but it waits its turn" next="starts this one"
  own=$(labels_of "$n") || { log "issue #$n: its labels did not load — its areas are not checked"; return 1; }
  case " $own " in *" area:"*) ;; *) log "issue #$n: no \`area:\` label — the area rule does not cover it"; return 1 ;; esac
  busy=$(inflight_labels) || { log "issue #$n: listing the in-flight issues failed — its areas are not checked"; return 1; }
  why=$(area_clash "$n" "$own" "$busy") || return 1
  log "issue #$n: $why — back to ready, not built"; [ "$DRY" = 1 ] && return 0
  area=${why%% in flight*}; other=${why##*#}   # area_clash's line, split for the comment below
  set_state "$n" "$own" ready || { log "issue #$n: not fully moved back to ready — not built; the next check retries"; return 0; }
  if branch_of "$n" > /dev/null; then
    lead="Its build has started, on branch \`issue-$n\`, but it waits its turn"; next="continues this build from that branch"
  fi
  gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$lead: issue #$other is being worked on (building, or in code review) and touches the same part of the code (\`$area\`). Two issues that touch the same part of the code are never built at once, because their changes would collide at merge. The loop $next by itself when the other is done. Nothing needed from you."$'\n\n'"$FACTORY_MARK" > /dev/null \
    || log "issue #$n: back to ready, but the comment did not post"
}

# The hand-off kick: starts the first idle slow worker now instead of at its next timer fire (`--no-block`:
# starting a oneshot otherwise waits for it to finish). Only from the fast lane's timer tick — a manual
# both-lanes tick runs its own slow lane next. A failed start is logged: the worker's timer still runs it.
kick_worker() {
  local n="$1" k st
  [ "$LANES" = fast ] || return 0
  for k in $(seq 1 "$SLOTS"); do
    st=$(systemctl --user is-active "factory-$NAME-slow@$k.service" 2> /dev/null || true)
    case "$st" in active|activating|deactivating|reloading) continue ;; esac
    if systemctl --user start --no-block "factory-$NAME-slow@$k.service" 2> /dev/null; then
      log "issue #$n: handed to the slow lane — worker $k started"
    else
      log "issue #$n: could not start slow worker $k — its timer starts it"
    fi
    return 0
  done
  log "issue #$n: every slow worker is busy — the first free one takes it"
}

# Which of the fast lane's stages this worker runs. With one worker, all of them. With more, `review`
# — the one long stage here — is the workers above 1's and nothing else is, so the short steps behind it, above
# all the pick that hands a free build slot its next issue, never wait half an hour for it. A `close` that
# follows a merge this worker's own review just made is not this decision: it runs in advance, after the stage.
fast_stage_mine() {
  [ "$REVIEW_WORKERS" -gt 1 ] || return 0
  if [ "$WORKER" = 1 ]; then [ "$1" != review ]; else [ "$1" = review ]; fi
}
fast_stage_whose() { if [ "$WORKER" = 1 ]; then echo "a review worker's"; else echo "worker 1's"; fi; }

# One lane's tick. The fast lane takes in-review before in-progress, so a mergeable PR never
# waits behind a resumed implement; the slow lane the reverse; oldest first within a label.
run_lane() {
  # 0. Both lanes pause while the account usage limit is on (the marker run_stage writes).
  local pause="$STATE/.usage-limit-until" lifts why
  if [ -e "$pause" ]; then
    lifts=$(cat "$pause" 2>/dev/null || echo 0)
    if [ "$(date +%s)" -lt "${lifts:-0}" ]; then
      why=$(head -n 1 "$STATE/.pause-reason" 2> /dev/null || true)   # pause_lanes's words; a marker older than it has none
      log "${why:-account usage limit} — paused until $(date -u -d "@$lifts" +%FT%H:%MZ); no session launched"; return 0
    fi
    rm -f "$pause" "$STATE/.pause-reason"; log "usage-limit pause over — resuming"
  fi
  # 1. Resume every waiting issue a person put `ready` on or the owner replied on (the sweep file's reply
  # check), then advance every in-flight issue (bounded stages per tick). Resuming is worker 1's, like the
  # pick below: two workers reading the same answer would post the note twice.
  [ "$LANE" != fast ] || [ "$WORKER" != 1 ] || { resume_answered; [ "$SWEEP_LOADED" = 0 ] || resume_replied; }
  local -a inflight=(); local n order
  if [ "$LANE" = fast ]; then order="in-review in-progress"; else order="in-progress in-review"; fi
  for n in $(for l in $order; do issues_with "$l"; done); do
    case " ${inflight[*]-} " in *" $n "*) ;; *) inflight+=("$n") ;; esac
  done
  for n in "${inflight[@]-}"; do
    [ -n "$n" ] || continue
    [ -z "$ONLY" ] || [ "$n" = "$ONLY" ] || continue
    with_issue_lock "$n" advance "$n" || true   # a stopped stage must not end the tick (set -e)
  done
  # What follows — the pick of a new issue and the daily digest, as the sweep and the board do at the end of the
  # tick — happens once per lane however many workers it has, so it is worker 1's. That is also
  # what keeps a free build slot from waiting: worker 1 reaches the pick in seconds, whatever the others run.
  { [ "$LANE" = fast ] && [ "$WORKER" = 1 ]; } || return 0

  # 2. Room for a new one? Pick the oldest startable issue (or --issue N) and verify it.
  # In flight = inflight_labels, read after step 1 (an issue it closed frees its slot and its areas):
  # a waiting issue launches nothing and can wait for days, so it holds no slot.
  local busy count=-1 pick="" class="" skipped=0 walked=1 seen="" c why own held=0 share=0
  local -A cand_labels=()
  if busy=$(inflight_labels); then count=$(grep -c . <<< "$busy" || true); else log "no issue picked: listing the in-flight issues failed — next tick"; fi
  if [ "$count" -ge 0 ] && [ "$count" -lt "$MAX_IN_FLIGHT" ]; then
    # The priority ladder: PRIORITIES in their order, then every other open issue — one with no priority label
    # sorts last, never disappears; oldest first within a class. `bug` is descriptive, not a class. A candidate
    # needs no `ready`: the last class is every open issue, and what keeps an issue out is a label
    # of its own (stage_of_labels). A candidate that is not startable — waiting, already in flight, set aside
    # by hand, sharing an `area:` label with an issue in flight, or blocked by an open issue
    # (read after the area check, which costs no call) — is skipped for the next one with no session and no label
    # change, never a silent end of the pick. While the loop's own share of the last 24 h's sessions is over
    # LOOP_SHARE_MAX, a LOOP_CLASS candidate is put aside, all of them under one line: the loop builds the
    # project, and works on itself with what is left. What is left includes a slot nothing else can use: when the
    # walk ends with no other issue startable, the first one put aside that can start is picked after all. A brake
    # that only held them idled the loop for good once the project's own queue drained into waits for the owner,
    # since only the loop's own sessions were then left to count, and the share could never fall back under the cap
    # (docs/decisions/2026-10-02-loop-share-fills-idle-slots.md).
    local candidates="" l b aside=""
    share=$(loop_share)
    if [ -n "$ONLY" ]; then
      candidates="$ONLY:--issue"
      cand_labels[$ONLY]=$(labels_of "$ONLY") || { log "issue #$ONLY: its labels did not load — not picked this tick"; candidates=""; walked=0; }
    else
      for c in $PRIORITIES ""; do
        # A failed query stops the walk at its class, since a class missing from the walk would let a
        # lower one jump it; the classes above it keep their candidates.
        if ! l=$(issues_labels_with ${c:+"$c"}); then
          if [ -z "$candidates" ]; then log "no issue picked: listing the ${c:-open} issues failed — next tick"
          else log "listing the ${c:-open} issues failed — this tick picks from the classes above it only"; fi
          walked=0; break
        fi
        while read -r n own; do
          [ -n "$n" ] || continue
          candidates="$candidates $n:${c:-no-priority}"; cand_labels[$n]=$own
        done <<< "$l"
      done
    fi
    for c in $candidates; do
      n=${c%%:*}
      case " $seen " in *" $n "*) continue ;; esac   # an issue is judged in its highest class only
      seen="$seen $n"
      own=${cand_labels[$n]:-}
      # Labels only — the list above brought them, and no candidate's stage needs its PR. An issue waiting, in
      # flight or set aside is not a candidate at all and is not counted: the count below is of issues the loop
      # could have started but for their areas or their blockers, which is what a starved queue looks like.
      [ "$(stage_of_labels "$own")" = verify ] || continue
      if [ -n "$LOOP_CLASS" ] && [ "${c#*:}" = "$LOOP_CLASS" ] && [ "$share" -gt "$LOOP_SHARE_MAX" ]; then
        held=$((held + 1)); aside+=" $n"; continue
      fi
      if why=$(area_clash "$n" "$own" "$busy"); then :
      elif ! b=$(blockers_of "$n"); then why="its \"blocked by\" links did not load"
      elif [ -z "$b" ]; then pick="$n"; class=${c#*:}; break
      else why="blocked by$(printf ' issue #%s,' $b)"; why=${why%,}; fi
      log "issue #$n skipped: $why"
      skipped=$((skipped + 1))
    done
    local filled=""
    if [ "$held" != 0 ] && [ -z "$pick" ] && [ "$walked" = 1 ]; then
      # Nothing else could start: the slot goes to the loop's own work rather than to no one. Judged like any
      # candidate (areas, blockers), oldest first; a list that failed part-way (walked=0) may hide an issue
      # that outranks them, so then they wait.
      for n in $aside; do
        own=${cand_labels[$n]:-}
        if why=$(area_clash "$n" "$own" "$busy"); then :
        elif ! b=$(blockers_of "$n"); then why="its \"blocked by\" links did not load"
        elif [ -z "$b" ]; then pick="$n"; class="$LOOP_CLASS"; break
        else why="blocked by$(printf ' issue #%s,' $b)"; why=${why%,}; fi
        log "issue #$n skipped: $why"
        skipped=$((skipped + 1))
      done
      [ -z "$pick" ] || { filled=1; log "the loop's own work took $share % of the last 24 h's sessions, over its $LOOP_SHARE_MAX % share, but no other issue can start: issue #$pick takes the free slot"; }
    fi
    [ "$held" = 0 ] || [ -n "$filled" ] || log "the loop's own work took $share % of the last 24 h's sessions, over its $LOOP_SHARE_MAX % share: $held issue(s) about the loop not picked this tick"
    if [ -n "$pick" ]; then
      log "issue #$pick: picked from class $class"
      with_issue_lock "$pick" advance "$pick" || true
      # Verified and not held back by its areas: a slow worker starts it now, once the issue lock is free.
      [ "$DRY" = 1 ] || [ "$(stage_of "$pick")" != implement ] || kick_worker "$pick"
    elif [ "$skipped" -gt 0 ]; then
      log "no startable issue ($skipped candidate(s) sharing an area in flight, blocked by an open issue, or whose links did not load)"
    elif [ "$walked" = 1 ] && [ -z "$ONLY" ] && [ "$held" = 0 ]; then
      # An empty queue said out loud: before, a starved loop and an idle one logged the same
      # nothing, which is how 2026-09-18's seven idle hours looked like a working factory for a day. Never
      # under `--issue N`, where one issue was asked for and the queue was not looked at at all, and not
      # while a held `p3-factory` issue is what is left: the line above said so.
      log "queue empty: no open issue the loop may start"
    fi
  elif [ "$count" -ge 0 ]; then
    log "in-flight budget full ($count/$MAX_IN_FLIGHT); no new issue picked"
  fi

  # 3. Daily digest on the monitor issue (first tick after 00:00 UTC).
  local marker="$STATE/.digest-$(date -u +%Y%m%d)" since digest
  if [ "$DRY" = 0 ] && [ ! -e "$marker" ]; then
    since=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
    digest="$STATE/digest-$(date -u +%Y%m%d).txt"
    {
      echo "merged PRs (24 h):"; gh pr list --repo "$REPO" --state merged --search "merged:>=$since" --json number,title --jq '.[] | "  PR #\(.number) \(.title)"'
      echo "closed issues (24 h):"; gh issue list --repo "$REPO" --state closed --search "closed:>=$since" --limit 50 --json number,title --jq '.[] | "  #\(.number) \(.title)"'
      # What the loop settled by itself, so the owner's after-the-fact review has one place: every `## Decided:`
      # comment of the last 24 h. One repo-wide
      # call — the only way to read comments by time — and a failed read says so rather than ending the tick
      # before the sweep: an empty list under this heading would read as "the loop decided nothing today",
      # which is the one thing this list must not say by accident. `since` is GitHub's `updated_at`, so an
      # older decision edited yesterday is listed again: a repeat in the digest, never a missing one.
      echo "decided by the loop (24 h) — reply on the issue to reverse one:"
      gh api "repos/$REPO/issues/comments?since=$since&per_page=100" --paginate \
        --jq '.[] | select(.body // "" | startswith("## Decided:"))
              | "  #\(.issue_url | split("/") | last) \(.body | split("\n") | first | ltrimstr("## Decided: "))"' \
        || echo "  (could not be read this time — this list may be short, not empty)"
      echo "needs-decision (waits for the owner):"; gh issue list --repo "$REPO" --state open --label needs-decision --json number,title --jq '.[] | "  #\(.number) \(.title)"'
      echo "waiting (the loop resumes these itself):"; gh issue list --repo "$REPO" --state open --label waiting --json number,title --jq '.[] | "  #\(.number) \(.title)"'
      echo "in flight:"; for n in $(inflight_labels | cut -d ' ' -f 1); do echo "  #$n $(stage_of "$n")"; done   # waiting ones are listed above
    } > "$digest"
    "$POST" "📰 daily digest" "$digest" && touch "$marker"
    # Retention: two weeks of per-run files (the session logs, as
    # factory-stats.sh names them, the digests and their markers), and the running log cut to its last lines. Its
    # readers want 24 h — loop_share, read above in this tick, and factory-stats.sh by default — and 50,000 lines
    # is about three weeks at a busy loop's rate. A line another lane appends during the swap is lost. Neither
    # step ends the tick, which still has its sweep to run.
    find "$STATE" -maxdepth 1 -type f -mtime +14 \( -name 'issue-*-*-????????T??????Z.log' -o -name 'digest-*.txt' \
      -o -name '.digest-*' \) -delete || log "session logs or digests older than 14 days not all deleted this time"
    { tail -n 50000 "$STATE/ticks.log" > "$STATE/ticks.log.tmp" && mv "$STATE/ticks.log.tmp" "$STATE/ticks.log"; } \
      || log "ticks.log not trimmed this time"
  fi
}

# The fast lane's own files, each loaded once per fast tick: the
# sweep with the owner's-reply check and the live board. A copy that is missing or
# does not parse skips only what it holds, with one line per fast tick, never the tick: the stages still run until
# the factory is reinstalled, and `ready` still resumes an issue. `bash -n` first, so a file broken
# half-way defines nothing. The line does not start `sweep:` or `board:`, which only a sweep or a board writes.
load_lib() {
  local path="$1" what="$2"; shift 2
  if [ -r "$path" ] && bash -n "$path" 2> /dev/null && . "$path" && declare -F "$@" > /dev/null; then return 0; fi
  log "$what skipped — $path is missing or does not parse; reinstall the factory"
  return 1
}
load_sweep() { load_lib "$SWEEP_LIB" "sweep and reply check" sweep sweep_if_due resume_replied && SWEEP_LOADED=1; }
load_board() { [ "$BOARD_LOADED" = 1 ] || load_lib "$BOARD_LIB" "the live board" board board_run board_wait && BOARD_LOADED=1; }
# The stage runner's file, loaded the same way by every lane
# and worker, once per lane tick, and by each query below that reads through it. The one difference: the loop
# cannot do without this one. A copy that is missing or does not parse costs that tick its stages, its pick and
# its sweep (which calls into this file) — one line, no session, the board still refreshed, `tick done` — and the
# queries that need it exit 1; nothing moves until the installer puts the file back.
load_stage() {
  [ "$STAGE_LOADED" = 1 ] || load_lib "$STAGE_LIB" "the stage runner" advance run_stage cleanup_issue reap_issue \
    review_state release_state request_review && STAGE_LOADED=1
}

# --cleanup N: one teardown path — the project's cleanup (FACTORY_REAP), the worktree, the branch. Exits 1 while the
# folder stays, or when another lane holds the issue.
if [ -n "$CLEANUP" ]; then load_stage || exit 1; rc=0; with_issue_lock "$CLEANUP" cleanup_issue "$CLEANUP" || rc=$?; [ "$rc" != 0 ] || log "issue #$CLEANUP: cleanup done"; exit "$rc"; fi
# --pr-of N: the line every caller of pr_of reads (nothing when branch issue-N never had a pull request).
if [ -n "$PR_OF" ]; then pr_of "$PR_OF"; exit 0; fi
# --review-state PR: how the driver classifies a PR's review
# (pending|verdict|skipped|conflict|unrequested|unrequested-twice|stalled|degraded|degraded-twice).
if [ -n "$REVIEW_STATE" ]; then load_stage || exit 1; echo "PR #$REVIEW_STATE: $(review_state "$REVIEW_STATE")"; exit 0; fi
# --release-state PR: how the close gate classifies a merged PR's release (pending|green|failed|none|stalled).
if [ -n "$RELEASE_STATE" ]; then load_stage || exit 1; echo "PR #$RELEASE_STATE: $(release_state "$RELEASE_STATE")"; exit 0; fi
# --sweep: the sweep now, under the fast lane's lock (it is that lane's step); with --dry-run it
# reads everything, prints the report and changes nothing.
if [ "$SWEEP" = 1 ]; then
  LANE=sweep; exec 9>"$STATE/.lock-fast"
  load_stage || exit 1
  load_sweep || exit 1
  if [ "$DRY" = 1 ]; then sweep; exit 0; fi
  flock -n 9 || { log "a fast-lane tick is running — it sweeps when due"; exit 0; }
  sweep_if_due force; exit 0
fi
# --board: the live board now, under the board's own lock so two runs never write it at once;
# with --dry-run it prints the text it would write and changes nothing, on GitHub or in the state.
if [ "$BOARD" = 1 ]; then
  LANE=board; load_board || exit 1
  if [ "$DRY" = 1 ]; then board; else board_run; fi
  exit 0
fi

# One tick per lane and worker: its own lock, so the other lane's tick and the other workers run
# beside it (a dry run starts nothing and reads beside a running lane). Worker k's head start for worker 1 is
# the wait above, before this script touches anything.
for LANE in $LANES; do
  exec 9>"$STATE/.lock-$LANE$W"
  if [ "$DRY" = 0 ] && ! flock -n 9; then
    log "a $LANE-lane tick is already running"
    continue
  fi
  # Worker 1's alone, so each happens once per lane whatever the other workers are doing: moving
  # the shared checkout to origin/main, the hourly sweep, and the board — which the workers above 1 therefore
  # never load, and so never write. A dry run moves nothing.
  [ "$LANE" != fast ] || [ "$WORKER" != 1 ] || { [ "$DRY" = 1 ] || ff_locked; load_sweep || true; load_board || true; }
  # An `if`, never `load_stage && run_lane`: a function called inside an `&&` / `||` list runs with `set -e` off.
  load_stage || true
  if [ "$STAGE_LOADED" = 1 ]; then run_lane; fi
  # The sweep goes last, still under the lane's lock: a review it re-requests then has until the
  # next tick to appear as a run before `review_state` reads that PR again.
  if [ "$LANE" = fast ] && [ "$DRY" = 0 ] && [ -z "$ONLY" ] && [ "$SWEEP_LOADED" = 1 ] && [ "$STAGE_LOADED" = 1 ]; then sweep_if_due; fi
  # Then the board, after everything this tick moved: it shows the picture the next tick starts from, and
  # writes only when that picture changed. It never ends the tick — `|| true`.
  [ "$LANE" != fast ] || [ "$DRY" = 1 ] || [ "$BOARD_LOADED" != 1 ] || board_run || true
  log "tick done"
  exec 9>&-
done

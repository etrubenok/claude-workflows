#!/usr/bin/env bash
# Scenario test of the factory's state labels: whole-script runs of scripts/factory-tick.sh on
# scratch state only, against a `gh` fake that keeps every issue's and PR's labels,
# comments and label events in a scratch folder, so each case reads back the labels the run left. The
# checkout is a clone of a scratch bare repo; state, prompt text, sandbox, monitor poster and HOME are
# scratch; `claude`, `docker`, `systemctl`, the project's cleanup and its release check are fakes first on PATH. The runs:
# - one forced sweep over parked issues of every class, closed issues with labels and working folders, and
#   an issue with two stage labels: a wait the loop ends keeps `waiting` and no stage label, the owner's
#   keeps `needs-decision`, a cleared wait gets `in-review` (its PR open or merged) or `ready` back; the
#   owner's waits are grouped in the report by what reserves each for the owner, in plain words, two sharing
#   a reason under one heading; one with no reason written since that rule is listed as a fault in the loop,
#   an older one as an older one, and a tag the re-check cannot read as neither — an instant with the shape of
#   one but naming no such day included, which the label audit leaves alone for the same reason — though they
#   too become the owner's; an issue filed already waiting is tagged as the re-check's own bookkeeping, so the
#   next sweep, which reads that comment back, does not report it as a fault either; a
#   closed issue's folder and branch go, unless they hold work found only on this host — uncommitted edits,
#   a new file, a commit that no branch on GitHub and no pull request holds, or what git cannot vouch for:
#   a pull request's last commit missing here, a folder that is no worktree, whose report line names the
#   remedy that works, each line naming only what is left, the folder, the branch or both — and a
#   locked worktree, which git will not remove, is reported with the steps that clear it, not as tidied, a
#   folder git refuses for another reason with git's reason; a locked worktree with edits names
#   the unlock first, a branch checked out in another folder is reported with git's reason, not as removed,
#   each kept folder's leftover goes, and the kept folders have their own heading; a
#   branch whose folder was deleted by hand goes, and a hand copy of a locked worktree is not read as locked
#  ; a locked worktree deleted by hand names its unlock, a folder git does not list as a worktree
#   — a hand copy, a plain folder — is to be deleted by hand, and a branch nothing else holds stays while git
#   refuses its folder; a dry run that changes nothing, its reply records included, that lists
#   what git's list of worktrees decides as the sweep does, and that promises no removal git may
#   refuse; then a second sweep, which changes nothing but the hourly retry note of a merged pull
#   request (and the leftovers and reply record it takes); a third, after the owner commits a kept folder's
#   edits, which reports the new reason; `--cleanup` of the locked worktree fails, and once it is unlocked
#   removes it; `--cleanup` of the branch checked out elsewhere fails; once the
#   folder deleted while locked is unlocked, `--cleanup` deletes its branch;
# - slow ticks for one issue each: an `in-progress` issue whose area is in flight is not built
#   and goes back to `ready`, with one note — which names its branch when the build had started (issue
#   #319); when its `in-progress` will not come off it is still not built; one with no area is built beside
#   them;
# - fast ticks for one issue each: a review that never finishes parks `waiting`, a pull request closed
#   unmerged parks `needs-decision`, both without a stage label; `ready` put on a waiting issue resumes it,
#   and a `ready` older than the wait comes off;
# - one fast tick with room for one issue in flight: two waiting issues that still carry a stage label and
#   the area of the ready one neither fill that room nor hold the area — the ready one is picked;
# - the area rule, one `--dry-run` fast tick each, which must log `tick done`: with issue 77 in
#   flight, a `ready` issue whose areas differ from 77's is picked, one sharing an area is skipped, one with no
#   area is picked;
# - a class whose list fails, one `--dry-run` fast tick each: the p3-tooling list failing still picks
#   the ready p1-production issue, the p1-production list failing picks nothing, and each logs the failed class; the
#   last class, every open issue, failing picks nothing and does not call the queue empty;
# - "blocked by" links: a `--dry-run` fast tick skips a `ready` issue whose blocker is open, with a
#   line naming the blocker, and picks the next one, reading blockers only for candidates past the area check; a
#   real tick starts one check session, for that next one, leaves the skipped ones `ready` with no comment, logs a
#   check that linked a blocker as that, not as no progress, and its hourly report names what the owner's open
#   question holds up and the two issues that block each other, and a later one whose links do not load reuses
#   the last ones read, so it does not post the same report again; an idle
#   tick reads at most one blocker list per candidate; once the blocker is closed, the issue is picked; one
#   whose blocker list does not load is skipped, and the hourly sweep logs that and still posts its report; a link
#   to another repository's issue is not read as this repository's issue of the same number;
# - the queue is opt-out, `--dry-run` fast ticks on one world: an issue with no stage label at all
#   is picked, ahead of a `ready` one of a lower class; once that one is closed the `ready` one is picked
#   exactly as before; and with both gone, one set aside by hand (`hold`), a roadmap issue (`tracking`), one
#   waiting for another issue, one waiting for the owner and one in flight are none of them picked, which the
#   log says once as an empty queue;
# - fast ticks for one issue each: the owner's reply, a comment without the loop's mark newer than
#   the question, resumes a `needs-decision` issue once with the right stage label, and its note links that
#   comment; a newer comment with the mark, a bot's, a reply already acted on, an unmarked comment older than
#   the question, or a comment on a `waiting` issue resumes nothing; comments that do not load change nothing
#   and are logged; a reply whose area is in use, or that finds no free slot, waits with one note
#   (the hourly report lists it as answered, not as needing the owner) and resumes once the area is free; the
#   note on an issue going back to `ready` with no priority label says it sorts last.
# - the live board, one world with a line for every section: a dry run prints the whole text and
#   writes nothing; a real run creates the board's own issue, labels it `tracking` and pins it, then writes the
#   text on it once; a second run minutes later, with the same picture, writes nothing; one past the heartbeat,
#   and one whose picture changed, write again; a refused write forgets the number it held, and the next run
#   finds the page again by its title; a page closed by hand is left alone and a new one opened; the account's
#   usage limit shows at the top; an issue with no label at all is in the queue and one set aside by hand is on
#   no list; an issue closed before the last 24 h is left out of what finished; and a tick
#   whose session holds its lane for seconds keeps the page fresh beside it, stops doing so when the session
#   ends, and leaves the lane free; sessions each too short for a look of their own still add up to one. Each
#   section is checked on its own line, in the plain words the owner reads;
# - the fast lane's workers, a world each with two finished code reviews, one unfinished, an issue
#   ready to start and a merged service issue whose deploy went green: with three workers installed, worker 1
#   hands every review to the others and still starts the ready issue, closes the merged one, re-checks the
#   waiting issues, posts the digest and writes the board; a worker above 1 takes the reviews and does none of
#   those, the waiting close included; the default of one worker does everything itself, and its digest lists what
#   the loop decided by itself in the last 24 h and nothing else; a worker above 1 stands
#   down while the host's 1-min load is over the ceiling; and with all three run at once, the two reviews land on
#   two different workers and two different issues, the issue one holds is skipped by the others, the close runs
#   once and under worker 1, the digest is posted once, and the third review is taken on a later run — by a
#   worker above 1, never by worker 1. The board's own line about it names the real cap, one below the workers.
# Also runs scripts/factory-label-audit.sh on the fake before and after the sweep. Exit 1 on a failure.
# Usage: bash tests/factory-labels-test.sh [driver-path [sweep-path [board-path [stage-path]]]]
# Negative controls: a copy whose cleanup_issue deletes the branch whatever becomes of the folder fails the case of
# the folder git refuses; one whose ask_keep tears down in a dry run, the dry-run case and the second sweep's
# cleanup; one whose area_clash never matches, the two skipped area cases; one that exits 0 before its `tick done`
# line, every area case; one whose hold_area treats an issue with no area as a clash, the no-area build case; one
# whose blockers_of reads every repository's links, the other repository's link; a board whose picture carries the
# time of its run, the no-second-write case; one whose board_wait counts from the start of its own call, the
# short-sessions case; one whose stage_of_labels answers `verify` for `hold` and `tracking`, the third opt-out
# case and the board's set-aside line.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
DRIVER=$(realpath -e "${1:-scripts/factory-tick.sh}") || exit 1
SWEEP=$(realpath -e "${2:-scripts/factory-sweep.sh}") || exit 1
BOARDLIB=$(realpath -e "${3:-scripts/factory-board.sh}") || exit 1
STAGELIB=$(realpath -e "${4:-scripts/factory-stage.sh}") || exit 1   # the stage runner, out of the driver since issue #375
AUDIT=$(realpath -e scripts/factory-label-audit.sh) || exit 1
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
unset "${!FACTORY_@}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=labels-test GIT_AUTHOR_EMAIL=labels-test@invalid GIT_COMMITTER_NAME=labels-test GIT_COMMITTER_EMAIL=labels-test@invalid
mkdir -p "$S/bin" "$S/home" "$S/test-root"
printf -- '---\nname: fake\n---\nfake skill text\n' > "$S/skill.md"
mkdir -p "$S/stages"; for s in verify implement review close; do printf 'fake %s text\n' "$s" > "$S/stages/$s.md"; done   # one file per stage
export FACTORY_STAGES="$S/stages"
# The 1-min load every worker above 1 reads before it launches a session: a quiet host, so the
# cases below do not depend on what this machine is doing. The load-gate case points at its own file.
printf '0.10 0.20 0.30 1/234 5678\n' > "$S/loadavg"
cat > "$S/bin/gh" << 'EOF'
#!/usr/bin/env bash
# `gh` fake with state: issue or PR <n> is the folder $FAKE_GH/<n> (one number space, as on GitHub) holding
# kind (issue|pr), state, title, body, labels (one per line), comments.jsonl and events.jsonl; a PR also holds
# head, merge (its mergeStateStatus), runs.json, merge_oid (the commit its merge made, which the close gate
# looks for in the deploy log) and, when its last commit is a real one, oid (else it is
# sha<n>). An issue-<n> PR has head issue-<n>. A label listed in stuck will not come off; a list (comments,
# events) named in down does not load, nor an issue list by a label named in $FAKE_GH/list-down. An issue's
# blocked_by lists the issues GitHub shows it as blocked by, and a repo file puts an issue in another
# repository. An issue created here takes the next number from next-issue, starting at 900 (the board's own), and a
# PATCH of an issue's body rewrites its body file. Writes go to calls, api reads to reads,
# every call's first two words to invocations.
D=$FAKE_GH
jq_of() { local p="" a; for a in "$@"; do [ "$p" = --jq ] && { printf '%s' "$a"; return; }; p=$a; done; printf .; }
opt() { local want=$1 p="" a; shift; for a in "$@"; do [ "$p" = "$want" ] && printf '%s\n' "$a"; p=$a; done; }
obj() {   # the JSON object of issue or PR <n>
  local d=$D/$1
  jq -cn --argjson number "$1" --arg state "$(cat "$d/state")" --arg title "$(cat "$d/title" 2> /dev/null)" \
    --arg labels "$(cat "$d/labels" 2> /dev/null)" --arg head "$(cat "$d/head" 2> /dev/null)" \
    --arg merge "$(cat "$d/merge" 2> /dev/null || echo CLEAN)" --arg now "$(date -u +%FT%TZ)" --arg oid "$(cat "$d/oid" 2> /dev/null)" \
    --arg mc "$(cat "$d/merge_oid" 2> /dev/null)" \
    --arg closed "$(cat "$d/closed" 2> /dev/null || echo 2026-09-01T00:00:00Z)" \
    '{number: $number, state: $state, title: $title, body: "", url: "https://example.invalid/\($number)",
      id: "ID_\($number)", closedAt: (if $state == "CLOSED" then $closed else null end),
      labels: [$labels | split("\n")[] | select(. != "") | {name: .}], headRefName: $head,
      mergeStateStatus: $merge, headRefOid: (if $oid == "" then "sha\($number)" else $oid end),
      mergeCommit: (if $mc == "" then null else {oid: $mc} end), mergedAt: (if $mc == "" then null else $now end),
      commits: [{committedDate: $now}], comments: [], changedFiles: 1, statusCheckRollup: []}'
}
Q=$(jq_of "$@")
echo "$1 $2" >> "$D/invocations"
case "$1 $2" in
  "issue view"|"pr view") obj "$3" | jq -r "$Q" ;;
  "issue list"|"pr list")
    kind=${1}; st=$(opt --state "$@"); st=${st:-open}; head=$(opt --head "$@"); mapfile -t want < <(opt --label "$@")
    for l in "${want[@]}"; do ! grep -qx -- "$l" "$D/list-down" 2> /dev/null || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }; done
    # A list with no label filter — the pick's last class, every open issue — fails on `(open)`.
    [ "${#want[@]}" -gt 0 ] || ! grep -qx -- '(open)' "$D/list-down" 2> /dev/null || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
    srch=$(opt --search "$@"); case "$srch" in "closed:>="*) since=${srch#closed:>=} ;; *) since="" ;; esac
    for d in "$D"/*/; do
      n=$(basename "$d"); [ "$(cat "$d/kind")" = "$kind" ] || continue
      case "$st" in all) ;; *) [ "$(cat "$d/state")" = "${st^^}" ] || continue ;; esac
      # `--search closed:>=<instant>`: the only filter the board's "finished in the last 24 h" list has. RFC 3339
      # UTC instants compare as text, which is what makes this one line.
      [ -z "$since" ] || [[ ! "$(cat "$d/closed" 2> /dev/null || echo 2026-09-01T00:00:00Z)" < "$since" ]] || continue
      [ -z "$head" ] || [ "$(cat "$d/head" 2> /dev/null)" = "$head" ] || continue
      ok=1; for l in "${want[@]}"; do grep -qx -- "$l" "$d/labels" || ok=0; done
      [ "$ok" = 1 ] && obj "$n"
    done | jq -rs "$Q" ;;
  "run list") c=$(opt --commit "$@"); cat "$D/${c#sha}/runs.json" 2> /dev/null | jq -r "$Q" ;;
  "issue create")   # the board's own issue on first use: the next free number, its labels, its URL
    n=$(cat "$D/next-issue" 2> /dev/null || echo 900); echo $((n + 1)) > "$D/next-issue"
    d=$D/$n; mkdir -p "$d"; echo issue > "$d/kind"; echo OPEN > "$d/state"; opt --title "$@" > "$d/title"
    opt --label "$@" > "$d/labels"; : > "$d/events.jsonl"; opt --body "$@" > "$d/body"
    echo "created issue $n" >> "$D/calls"; echo "https://example.invalid/$n" ;;
  "label create") echo "label $3" >> "$D/calls" ;;
  "api graphql") echo "graphql $(opt -f "$@" | paste -sd ' ' -)" >> "$D/calls"; echo '{"data": {}}' ;;
  "api "*)
    m=$(opt -X "$@"); m=${m:-GET}; path=""; for a in "${@:2}"; do case "$a" in repos/*) path=$a; break ;; esac; done
    f=$(opt -f "$@"); now=$(date -u +%FT%TZ)
    if [ "$m" = GET ]; then echo "$path" >> "$D/reads"; else printf '%s %s %s\n' "$m" "$path" "${f%%$'\n'*}" >> "$D/calls"; fi
    n=$(cut -d / -f 5 <<< "$path"); d=$D/$n
    case "$m ${path#repos/*/*/issues/}" in
      "GET repos/"*"/issues?state=open"*)   # the REST list: every open issue, with how many of its blockers are open
        for x in "$D"/*/; do
          [ "$(cat "$x/kind")" = issue ] && [ "$(cat "$x/state")" = OPEN ] || continue
          k=0; for b in $(cat "$x/blocked_by" 2> /dev/null); do [ "$(cat "$D/$b/state")" = CLOSED ] || k=$((k + 1)); done
          obj "$(basename "$x")" | jq -c --argjson k "$k" '. + {issue_dependencies_summary: {blocked_by: $k}}'
        done | jq -rs "$Q" ;;
      "GET $n/dependencies/blocked_by")   # REST states are lower case; a blocker with a repo file is in that repository
        ! grep -qx blocked_by "$d/down" 2> /dev/null || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
        for b in $(cat "$d/blocked_by" 2> /dev/null); do
          obj "$b" | jq -c --arg r "https://api.github.com/repos/$(cat "$D/$b/repo" 2> /dev/null || cut -d / -f 2,3 <<< "$path")" \
            '.state |= ascii_downcase | .repository_url = $r'
        done | jq -rs "$Q" ;;
      "POST $n/labels")
        l=${f#"labels[]="}; grep -qx -- "$l" "$d/labels" || { echo "$l" >> "$d/labels"
          jq -cn --arg l "$l" --arg t "$now" '{event: "labeled", label: {name: $l}, created_at: $t}' >> "$d/events.jsonl"; } ;;
      "DELETE $n/labels/"*)
        l=${path##*/}; grep -qx -- "$l" "$d/labels" || { echo "gh: Label does not exist (HTTP 404)" >&2; exit 1; }
        ! grep -qx -- "$l" "$d/stuck" 2> /dev/null || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
        grep -vx -- "$l" "$d/labels" > "$d/labels.new"; mv "$d/labels.new" "$d/labels"
        jq -cn --arg l "$l" --arg t "$now" '{event: "unlabeled", label: {name: $l}, created_at: $t}' >> "$d/events.jsonl" ;;
      "POST $n/comments")
        k=$(( $(cat "$d/comments.jsonl" 2> /dev/null | wc -l) + 1 ))
        jq -cn --argjson id "$n$k" --arg b "${f#"body="}" --arg t "$now" \
          '{id: $id, html_url: "https://example.invalid/c\($id)", created_at: $t, body: $b}' >> "$d/comments.jsonl" ;;
      "GET comments"*)   # every comment of the repository since <instant>, which is how the daily digest reads
        s=${path#*since=}; s=${s%%&*}   # what the loop decided by itself
        for x in "$D"/*/; do
          jq -c --arg u "https://api.github.com/$(cut -d / -f 1,2,3 <<< "$path")/issues/$(basename "$x")" --arg s "$s" \
            'select(.created_at >= $s) | . + {issue_url: $u}' "$x/comments.jsonl" 2> /dev/null
        done | jq -rs "$Q" ;;
      "GET $n/comments"|"GET $n/events")
        ! grep -qx -- "${path##*/}" "$d/down" 2> /dev/null || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
        jq -rs "$Q" "$d/${path##*/}.jsonl" 2> /dev/null || jq -rn "[] | $Q" ;;
      "PATCH comments/"*) ;;
      "PATCH "[0-9]*)   # the board's text: `-F body=@<file>`, kept as the issue's body
        ! grep -qx body "$d/down" 2> /dev/null || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
        b=$(opt -F "$@"); cat "${b#body=@}" > "$d/body" ;;
      *) echo "gh fake: unhandled api call: $*" >&2; exit 1 ;;
    esac ;;
  *) echo "gh fake: unhandled call: $*" >&2; exit 1 ;;
esac
EOF
cat > "$S/bin/claude" << 'EOF'
#!/usr/bin/env bash
# `claude` fake: records the session's stage and issue. A check of an issue with a link_on_verify file adds the
# blockers it lists to the issue's blocked_by, as the check stage's step 4 does. An issue with a
# `slow` file takes that many seconds, as a real review round takes half an hour. A review of an
# issue with a `merges_at_load` file closes it, as a merge with `Closes #N` does, and leaves the host as loaded
# as that round's build and test run leaves it: the file's line becomes the 1-min load the rest of the tick
# reads.
s=$(grep -om1 'stage `[a-z]*` of issue #[0-9]*' <<< "$2") || exit 0
echo "$s" >> "$FAKE_DIR/sessions"; d=$FAKE_GH/${s##*#}
[ ! -e "$d/slow" ] || sleep "$(cat "$d/slow")"
case "$s" in 'stage `verify`'*) [ ! -e "$d/link_on_verify" ] || cat "$d/link_on_verify" >> "$d/blocked_by" ;; esac
case "$s" in 'stage `review`'*) [ ! -e "$d/merges_at_load" ] || { echo CLOSED > "$d/state"
  cat "$d/merges_at_load" > "${FACTORY_LOADAVG:-/dev/null}"; } ;; esac
EOF
cat > "$S/bin/docker" << 'EOF'
#!/bin/sh
# `docker` fake: `ps` lists the leftover projects named in $FAKE_GH/leftovers; each `compose` call goes to $FAKE_GH/docker.
case "$1" in ps) cat "$FAKE_GH/leftovers" 2> /dev/null ;; compose) echo "$*" >> "$FAKE_GH/docker" ;; esac
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$S/bin/systemctl"
printf '#!/bin/sh\necho "$1" >> "$FAKE_DIR/posts"; cat "$2" >> "$FAKE_DIR/reports"\n' > "$S/bin/post"
# The project's cleanup (FACTORY_REAP): a leftover of issue N is a line `proj-N` in $FAKE_GH/leftovers, and taking it
# down is one `compose -p proj-N down` line in $FAKE_GH/docker, as a Compose project of the issue's would be.
printf '#!/bin/sh\n! grep -qx "proj-$1" "$FAKE_GH/leftovers" 2> /dev/null || echo "compose -p proj-$1 down" >> "$FAKE_GH/docker"\n' > "$S/bin/reap"
# The project's release check (FACTORY_RELEASE_CHECK): the word in $FAKE_GH/release-<issue>, else `pending` — a
# change not yet released, as a merge with no deploy line read in the loop this test was first written for.
printf '#!/bin/sh\ncat "$FAKE_GH/release-$2" 2> /dev/null || echo pending\n' > "$S/bin/release"
chmod +x "$S/bin/"*
for t in gh claude docker systemctl; do
  [ "$(PATH="$S/bin:$PATH"; command -v "$t")" = "$S/bin/$t" ] || { echo "factory-labels-test: the fake $t is not first on PATH — no driver runs"; exit 2; }
done
O=$S/origin.git W=$S/seed
git init -q --bare -b main "$O"
git init -q -b main "$W"
echo a > "$W/a.txt"; git -C "$W" add -A; git -C "$W" commit -qm base; git -C "$W" push -q "$O" main

T0=2026-09-01T00:00:00Z
M=$(sed -n 's/^FACTORY_MARK="${FACTORY_COMMENT_MARK:-\(.*\)}"$/\1/p' "$DRIVER")   # the driver's mark: every comment the loop posts ends with it
[ -n "$M" ] || { echo "factory-labels-test: the driver's comment mark could not be read"; exit 2; }
bad=0 cases=0
check() {   # name, got, want
  cases=$((cases + 1))
  if [ "$2" = "$3" ]; then echo "PASS $1"; else printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; bad=$((bad + 1)); fi
}
# fresh: a new world — an empty fake GitHub, a fresh clone as the checkout, fresh state.
fresh() {
  k=$((${k:-0} + 1)); G=$S/w$k/gh co=$S/w$k/co st=$S/w$k/state
  mkdir -p "$G" "$st"; git clone -q "$O" "$co"; : > "$S/sessions"; : > "$S/posts"; : > "$S/reports"
}
# issue <n> <OPEN|CLOSED> "<labels>" [tag]: an issue; a tag posts, at T0, the comment that parked it, and its
# wait labels were put on at T0.
issue() {
  local d=$G/$1 l; mkdir -p "$d"; echo issue > "$d/kind"; echo "$2" > "$d/state"; echo "issue $1" > "$d/title"
  : > "$d/labels"; : > "$d/events.jsonl"
  for l in $3; do echo "$l" >> "$d/labels"
    jq -cn --arg l "$l" --arg t "$T0" '{event: "labeled", label: {name: $l}, created_at: $t}' >> "$d/events.jsonl"; done
  [ -z "${4:-}" ] || jq -cn --argjson id "${1}0" --arg b $'## Waiting: seeded\n\n[blocked-on: '"$4"']' --arg t "$T0" \
    '{id: $id, html_url: "https://example.invalid/c\($id)", created_at: $t, body: $b}' > "$d/comments.jsonl"
}
# say <n> <time> <body> [bot]: one more comment on issue <n>, posted at <time>; a fourth word makes a bot its author
say() {
  local d=$G/$1 k; k=$(( $(cat "$d/comments.jsonl" 2> /dev/null | wc -l) + 1 ))
  jq -cn --argjson id "$1$k" --arg b "$3" --arg t "$2" --arg bot "${4:-}" \
    '{id: $id, html_url: "https://example.invalid/c\($id)", created_at: $t, body: $b} + (if $bot == "" then {} else {user: {type: "Bot"}} end)' \
    >> "$d/comments.jsonl"
}
notes() { jq -r .body "$G/$1/comments.jsonl" 2> /dev/null | grep -cF -- "$2"; }   # comments on <n> holding <text>
# pr <p> <issue n> <OPEN|MERGED|CLOSED> [merge-state [runs-json]]: the pull request of branch issue-<n>
pr() {
  local d=$G/$1; mkdir -p "$d"; echo pr > "$d/kind"; echo "$3" > "$d/state"; echo "issue-$2" > "$d/head"; : > "$d/labels"
  echo "${4:-CLEAN}" > "$d/merge"; echo "${5:-[]}" > "$d/runs.json"
}
labels() { grep -v -e '^p[0-9]-' -e '^area:' "$G/$1/labels" | sort | paste -sd ' ' -; }
# tick <args…>: one driver run on this world's scratch paths. The knobs a case sets as a prefix: `max` the
# issues in flight, `beat` the board's heartbeat, `workers` the fast lane's workers, `loadavg` the file the
# load gate reads, and `out` where the output goes — its own file
# for each of the workers a case runs at the same time. No stagger: the workers' 1-min waits are
# the host's timers, not what these cases are about.
tick() {
  env PATH="$S/bin:$PATH" HOME="$S/home" FAKE_DIR="$S" FAKE_GH="$G" FACTORY_MAX_IN_FLIGHT="${max:-5}" \
    FACTORY_CHECKOUT="$co" FACTORY_STATE="$st" FACTORY_HEADER="$S/skill.md" FACTORY_SWEEP="$SWEEP" \
    FACTORY_BOARD="$BOARDLIB" FACTORY_STAGE="$STAGELIB" FACTORY_BOARD_HEARTBEAT="${beat:-600}" \
    FACTORY_REVIEW_WORKERS="${workers:-1}" FACTORY_IMPLEMENT_SLOTS="${slots:-1}" FACTORY_WORKER_STAGGER=0 \
    FACTORY_LOADAVG="${loadavg:-$S/loadavg}" \
    FACTORY_SANDBOX="$S/test-root" FACTORY_PROTECTED="$S/prod" FACTORY_MONITOR_POST="$S/bin/post" FACTORY_REAP="$S/bin/reap" \
    FACTORY_RELEASE_CHECK="$S/bin/release" FACTORY_REPO=fake/repo FACTORY_LOAD_CEILING=6.0 \
    timeout 60 bash "$DRIVER" "$@" > "${out:-$S/out}" 2>&1
  rc=$?
}
audit() { env PATH="$S/bin:$PATH" FAKE_GH="$G" FACTORY_REPO=fake/repo bash "$AUDIT" > "$S/audit" 2>&1; echo "exit $?"; }

# --- the sweep ---------------------------------------------------------------------------------------
fresh
issue 150 OPEN "" ; issue 151 CLOSED ""
issue 101 OPEN "needs-decision in-review p1-production area:factory-driver" time:2099-01-01T00:00:00Z; pr 201 101 MERGED
issue 102 OPEN "needs-decision in-progress area:docs" issue:150
say 102 2026-09-01T01:00:00Z $'Checked again: issue #150 is still open.\n\n'"$M"   # a later note, no tag: not the park
issue 104 OPEN "needs-decision in-review area:deploy" ci; pr 204 104 MERGED
issue 105 OPEN "waiting in-progress area:python" owner
issue 106 OPEN "needs-decision area:ci" issue:151; pr 206 106 OPEN
issue 107 OPEN "needs-decision" time:2026-09-02T00:00:00Z
issue 109 OPEN "ready in-progress area:db"
# What reserves an owner wait: two that name it, and a bare one written since the rule, which the
# report reads as a fault in the loop — unlike issue 105, parked at T0, before a park had to say why.
issue 130 OPEN "needs-decision" owner:data-meaning
issue 131 OPEN "needs-decision" owner:physical:sudo
issue 132 OPEN "needs-decision"
# Written under the rule = after the moment the sweep stamps when it first runs with this code, so the seed is
# taken from the same clock rather than written as a date (review round 2: a date here would stop being "under
# the rule" the moment the host clock passed it).
say 132 "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" '## Waiting: seeded with no item'$'\n\n''[blocked-on: owner]'
issue 133 OPEN "needs-decision" owner:data-meaning   # a second one under the same heading
issue 134 OPEN "waiting" time:tomorrow                # a token the re-check cannot read: not a missing item
issue 135 OPEN "needs-decision"                       # filed already waiting: the reason is its own description
issue 136 OPEN "needs-decision" time:2026-09-31T00:00:00Z   # the shape of an instant, but no such day
issue 110 CLOSED "in-review needs-decision"
issue 111 OPEN "in-progress area:api"
issue 112 CLOSED ""
for n in 100 108 113 114 115 116 117 118 119 120 121 122 124 125 126; do issue "$n" CLOSED ""; done
for n in 110 111 112 113 114 115 116 117 119 120 122 124 125; do git -C "$co" worktree add -q -b "issue-$n" "$co/.claude/worktrees/issue-$n"; done
rm -rf "$co/.claude/worktrees/issue-122"   # deleted by hand: git's record of the folder stays, and holds the branch
git -C "$co" worktree lock "$co/.claude/worktrees/issue-125"; rm -rf "$co/.claude/worktrees/issue-125"   # … a locked record too, which prune keeps
echo garbled > "$co/.claude/worktrees/issue-124/.git"   # a worktree git cannot read, which no prune takes
git -C "$co" worktree add -q -b issue-100 "$S/w$k/elsewhere"   # its copy below reads as clean, but is none of git's worktrees
cp -a "$S/w$k/elsewhere" "$co/.claude/worktrees/issue-100"; git -C "$co" worktree lock "$S/w$k/elsewhere"   # the copy is not locked
# A worktree git will not remove, whose .git file points at another's record, and a branch nothing holds.
git -C "$co" worktree add -q --detach "$co/.claude/worktrees/issue-126"; git -C "$co" branch issue-126
cp "$co/.claude/worktrees/issue-111/.git" "$co/.claude/worktrees/issue-126/.git"
git -C "$co" worktree lock "$co/.claude/worktrees/issue-119"   # nothing unsaved, but git will not remove it
echo edit >> "$co/.claude/worktrees/issue-112/a.txt"
echo edit >> "$co/.claude/worktrees/issue-120/a.txt"; git -C "$co" worktree lock "$co/.claude/worktrees/issue-120"   # both
git -C "$co" worktree add -q -b issue-121 "$S/w$k/other-121"   # no folder of its own; its branch, checked out there, will not delete
printf 'proj-%s\n' 100 110 112 119 120 125 126 > "$G/leftovers"   # leftovers: every kept folder's goes, once a sweep
for n in 113 115 116 117; do git -C "$co/.claude/worktrees/issue-$n" commit -q --allow-empty -m "work of issue $n"; done
git -C "$co" branch issue-108 issue-113   # no folder: only its branch holds a commit found nowhere else
echo new > "$co/.claude/worktrees/issue-114/new.txt"
pr 215 115 MERGED; git -C "$co" rev-parse issue-115 > "$G/215/oid"   # merged and its branch deleted: only the PR holds its commit
git -C "$co" push -q origin issue-116   # a branch on GitHub holds its commit
pr 217 117 MERGED; echo 0123456789abcdef0123456789abcdef01234567 > "$G/217/oid"   # its PR's last commit is not in this checkout
mkdir -p "$co/.claude/worktrees/issue-118"; echo x > "$co/.claude/worktrees/issue-118/x.txt"   # a folder that is no git worktree
check "audit before: finds the closed issue's labels, the double stage label and needs-decision on waits" "$(audit)" "exit 1"
tick --sweep
check "sweep: exit" "$rc" 0
check "sweep: a clock wait not passed — waiting, its needs-decision and in-review off" "$(labels 101)" "waiting"
check "sweep: an issue wait not cleared — waiting, in-progress off" "$(labels 102)" "waiting"
check "sweep: a retry wait on a merged PR — waiting, in-review off" "$(labels 104)" "waiting"
check "sweep: the retry was counted on the PR" "$(grep -c 'sweep retry 1/3' "$G/204/comments.jsonl" 2> /dev/null)" 1
check "sweep: an owner wait — needs-decision, waiting and in-progress off" "$(labels 105)" "needs-decision"
check "sweep: a wait that names what reserves it keeps needs-decision too" "$(labels 130) $(labels 131) $(labels 132)" \
  "needs-decision needs-decision needs-decision"
check "sweep: the questions are grouped by what only the owner can settle, in its own words" \
  "$(grep -cx '  Changing what a stored field, a timestamp or a public interface means:' "$S/reports") $(grep -cx '    issue #130 issue 130' "$S/reports") $(grep -cx '  A step only you can do: sudo:' "$S/reports") $(grep -cx '    issue #131 issue 131' "$S/reports")" \
  "1 1 1 1"
check "sweep: two issues reserved for the same reason share one heading, listed under it" \
  "$(grep -A 3 -x '  Changing what a stored field, a timestamp or a public interface means:' "$S/reports" | grep -cE '^    issue #(130|133) ')" "2"
check "sweep: a wait whose tag the re-check cannot read says that, is not counted as a missing reason, and becomes the owner's" \
  "$(grep -cx '  A wait the loop could not read, so it cannot end it either:' "$S/reports") $(grep -cx 'needs issue #134 unreadable-tag' "$st/sweep-posted") $(labels 134)" "1 1 needs-decision"
check "sweep: the moment the rule started running here is taken from the clock, not from a date in the code" \
  "$(grep -cxE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$st/owner-item-from")" "1"
check "sweep: a wait with no reason, written since the rule, is listed as a fault in the loop — an older one is not" \
  "$(grep -c '^  No reason given for why this needs you — the loop should have decided these itself' "$S/reports") $(grep -cx '    issue #132 issue 132' "$S/reports") $(grep -cx '  No reason given for why this needs you (parked before the loop had to give one):' "$S/reports") $(grep -cx '    issue #105 issue 105' "$S/reports")" \
  "1 1 1 1"
check "sweep: an instant shaped like one but naming no such day is the owner's too, and the label audit agrees" \
  "$(grep -cx 'needs issue #136 unreadable-tag' "$st/sweep-posted") $(labels 136) $(audit)" "1 needs-decision exit 0"
check "sweep: an issue filed already waiting is tagged as the re-check's own bookkeeping, under its own heading" \
  "$(jq -r .body "$G/135/comments.jsonl" | grep -cx '\[blocked-on: owner:filed-waiting\]') $(grep -cx 'needs issue #135 filed-waiting' "$st/sweep-posted") $(grep -cx '  An issue filed already waiting, with the reason in its own description — the loop cannot tell what would end it:' "$S/reports")" \
  "1 1 1"
check "sweep: the report keys carry the item, so a wait that gains one is posted again" \
  "$(grep -cx 'needs issue #130 data-meaning' "$st/sweep-posted") $(grep -cx 'needs issue #131 physical:sudo' "$st/sweep-posted") $(grep -cx 'needs issue #132 no-item-new' "$st/sweep-posted") $(grep -cx 'needs issue #105 no-item' "$st/sweep-posted")" \
  "1 1 1 1"
check "sweep: a cleared wait with an open PR — in-review back" "$(labels 106)" "in-review"
check "sweep: a cleared wait with no PR — ready back" "$(labels 107)" "ready"
check "sweep: ready beside in-progress — ready off" "$(labels 109)" "in-progress"
check "sweep: a closed issue — its state labels off" "$(labels 110)" ""
check "sweep: a closed issue — its working folder gone" "$([ -d "$co/.claude/worktrees/issue-110" ] && echo kept || echo gone)" gone
check "sweep: a closed issue — its branch gone" "$(git -C "$co" branch --list issue-110)" ""
check "sweep: an open issue — its working folder kept" "$([ -d "$co/.claude/worktrees/issue-111" ] && echo kept || echo gone)" kept
check "sweep: a closed issue with uncommitted edits — its folder kept" "$([ -d "$co/.claude/worktrees/issue-112" ] && echo kept || echo gone)" kept
check "sweep: … and the owner is told, naming both as left" \
  "$(grep -c '^  issue #112 (closed): its working folder .* has uncommitted edits, so the loop left its working folder and its branch in place; ' "$S/reports")" 1
check "sweep: a closed issue whose branch alone holds an unpushed commit — the owner is told of the branch, no folder" \
  "$(grep -c '^  issue #108 (closed): its branch issue-108 has 1 commit(s) .*, so the loop left its branch in place; ' "$S/reports")" 1
check "sweep: a closed issue with an unpushed commit — its folder and branch kept" \
  "$([ -d "$co/.claude/worktrees/issue-113" ] && echo kept || echo gone) $(git -C "$co" branch --list issue-113 | tr -d ' +*')" "kept issue-113"
check "sweep: … and the owner is told" "$(grep -c '^  issue #113 (closed): its branch issue-113 has 1 commit(s) that no branch on GitHub' "$S/reports")" 1
check "sweep: a closed issue with a new file — its folder and branch kept" \
  "$([ -d "$co/.claude/worktrees/issue-114" ] && echo kept || echo gone) $(git -C "$co" branch --list issue-114 | tr -d ' +*')" "kept issue-114"
check "sweep: … and the owner is told" "$(grep -c '^  issue #114 (closed): its working folder .* has new files never added to git' "$S/reports")" 1
check "sweep: a closed issue whose PR's last commit is not here — its folder and branch kept" \
  "$([ -d "$co/.claude/worktrees/issue-117" ] && echo kept || echo gone) $(git -C "$co" branch --list issue-117 | tr -d ' +*')" "kept issue-117"
check "sweep: … and the owner is told" "$(grep -c '^  issue #117 (closed): its branch issue-117 may hold commits found nowhere else' "$S/reports")" 1
check "sweep: a folder that is no git worktree, and no branch — kept, and the owner is told to delete it by hand, of no branch" \
  "$([ -d "$co/.claude/worktrees/issue-118" ] && echo kept || echo gone) $(grep -c '^  issue #118 (closed): its working folder .* is none of git'"'"'s worktrees, so the loop left its working folder in place; .* delete the folder by hand$' "$S/reports")" "kept 1"
check "sweep: a worktree git cannot read — kept, and the owner is told to delete it by hand, under its own key" \
  "$([ -d "$co/.claude/worktrees/issue-124" ] && echo kept || echo gone) $(grep -c '^  issue #124 (closed): git cannot read its working folder .*, so the loop left its working folder and its branch in place; .* delete the folder by hand, and the next sweep handles the branch$' "$S/reports") $(grep -cx 'needs folder issue #124 not-worktree' "$st/sweep-posted")" "kept 1 1"
check "sweep: a worktree git will not remove — kept, and not reported as tidied" \
  "$([ -d "$co/.claude/worktrees/issue-119" ] && echo kept || echo gone) $(grep -c '^  issue #119:' "$S/reports")" "kept 0"
check "sweep: … the owner is told it is locked, and the steps that clear it" \
  "$(grep -c "^  issue #119 (closed): git will not remove its working folder .*: it is locked, .* \`git worktree unlock $co/.claude/worktrees/issue-119\`, then \`[^\`]*factory-tick\.sh --cleanup 119\`" "$S/reports")" 1
check "sweep: a hand copy of a locked worktree — kept, the owner is told it is none of git's worktrees, to be deleted by hand once its work is saved" \
  "$([ -d "$co/.claude/worktrees/issue-100" ] && echo kept || echo gone) $(grep -c "^  issue #100 (closed): its working folder .* is none of git's worktrees, so the loop left its working folder and its branch in place; neither the loop nor \`--cleanup\` removes it: once its work is saved or not wanted, delete the folder by hand, and the next sweep handles the branch$" "$S/reports") $(grep -cx 'needs folder issue #100 unlisted' "$st/sweep-posted")" "kept 1 1"
check "sweep: a folder git will not remove for another reason — kept, and the owner is told git's reason as code, under its own key" \
  "$([ -d "$co/.claude/worktrees/issue-126" ] && echo kept || echo gone) $(grep -c "^  issue #126 (closed): git would not remove its working folder .* (\`[^\`]*\`), so the loop left its working folder and its branch in place; \`[^\`]*factory-tick\.sh --cleanup 126\` removes what is left once git can" "$S/reports") $(grep -cx 'needs folder issue #126 refused' "$st/sweep-posted")" "kept 1 1"
check "sweep: … and its branch, which nothing else holds, is not deleted while the folder stays" "$(git -C "$co" branch --list issue-126 | tr -d ' +*')" issue-126
check "sweep: a locked worktree deleted by hand — its branch kept, the owner told the folder is gone and to unlock it, then \`--cleanup\`, under its own key" \
  "$(git -C "$co" branch --list issue-125 | tr -d ' +*') $(grep -c "^  issue #125 (closed): its working folder $co/.claude/worktrees/issue-125 was deleted by hand while locked, .*, so the loop left its branch in place; \`git worktree unlock $co/.claude/worktrees/issue-125\`, then \`[^\`]*factory-tick\.sh --cleanup 125\` deletes it$" "$S/reports") $(grep -cx 'needs folder issue #125 deleted-locked' "$st/sweep-posted")" \
  "issue-125 1 1"
check "sweep: a locked worktree with uncommitted edits — kept, its line names the unlock before \`--cleanup\`" \
  "$([ -d "$co/.claude/worktrees/issue-120" ] && echo kept || echo gone) $(grep -c "^  issue #120 (closed): its working folder .* has uncommitted edits, so the loop left its working folder and its branch in place; the folder is also locked: .*\`git worktree unlock $co/.claude/worktrees/issue-120\`, then \`[^\`]*factory-tick\.sh --cleanup 120\`" "$S/reports")" "kept 1"
check "sweep: a branch checked out in another folder — kept, not reported as removed, the owner told git's reason" \
  "$(git -C "$co" branch --list issue-121 | tr -d ' +*') $(grep -c '^  issue #121:' "$S/reports") $(grep -c "^  issue #121 (closed): git would not delete its branch issue-121 (\`[^\`]*\`), so the loop left its branch in place; .*\`[^\`]*factory-tick\.sh --cleanup 121\` deletes it$" "$S/reports") $(grep -cx 'needs folder issue #121 branch' "$st/sweep-posted")" \
  "issue-121 0 1 1"
check "sweep: a branch whose folder was deleted by hand — deleted, and reported as tidied" \
  "$(git -C "$co" branch --list issue-122 | grep -c .) $(grep -c '^  issue #122: closed, so its working folder and branch were removed$' "$S/reports")" "0 1"
check "sweep: a kept folder's leftover goes once — the locked one, the one with edits, both, the copy, the one git refused, the one deleted while locked" \
  "$(for n in 119 112 120 100 126 125; do grep -c "^compose -p proj-$n down" "$G/docker"; done | paste -sd ' ' -)" "1 1 1 1 1 1"
check "sweep: the kept folders are under their own heading, none under what needs a reply" \
  "$(grep -c '^Left on this host after the issue closed' "$S/reports") $(awk '/^Needs you/ {f = 1; next} /^[^ ]/ {f = 0} f' "$S/reports" | grep -c '(closed)')" "1 0"
for n in 115 116; do
  check "sweep: a closed issue whose commit $([ "$n" = 115 ] && echo "its merged PR" || echo "a branch on GitHub") holds — folder and branch gone" \
    "$([ -d "$co/.claude/worktrees/issue-$n" ] && echo kept || echo gone) $(git -C "$co" branch --list "issue-$n")" "gone "
done
check "sweep: the report lists every tidy-up, one line each" "$(grep -oE '^  issue #(101|102|104|105|109|110):' "$S/reports" | sort | uniq -c | paste -sd ' ' - | tr -s ' ')" \
  " 1 issue #101: 1 issue #102: 1 issue #104: 1 issue #105: 1 issue #109: 3 issue #110:"
check "sweep: the report was posted" "$(cat "$S/posts")" "🧹 factory sweep"
check "audit after: clean" "$(audit)" "exit 0"
# hold: every write the fake GitHub took, every docker compose call, every folder and local branch of an issue, the
# loop's state but the log, the report and the empty lock files any run writes, whether or not an earlier run wrote them
hold() {
  cat "$G/calls" "$G/docker"; ls "$co/.claude/worktrees"; git -C "$co" for-each-ref --format='%(refname)' 'refs/heads/issue-*'
  find "$st" ! -name ticks.log ! -name sweep-report.txt ! -name '*.lock' ! -name '.lock-*' | sort
  grep -r --exclude=ticks.log --exclude=sweep-report.txt . "$st"
}
echo "1191 read" > "$st/issue-119.replied"   # a kept folder's reply record: a sweep takes it, a dry run must not
before=$(hold)
tick --sweep --dry-run   # changes nothing, and prints the report it would post
check "dry run: the locked worktree, the one deleted while locked and the hand copy are listed as the sweep lists them, not as tidied" \
  "$(for n in 119 125 100; do grep -c "^  issue #$n (closed): " "$S/out"; grep -c "^  issue #$n:" "$S/out"; done | paste -sd ' ' -)" "1 0 1 0 1 0"
check "dry run: the folder and the branch git refuses are not listed as removed, but as what git may refuse" \
  "$(grep -c '^  issue #12[16]: closed, so its working folder and branch go, unless git refuses' "$S/out") $(grep -c '^  issue #.*were removed' "$S/out")" "2 0"
check "dry run: no label or comment written, no leftover torn down, no folder, branch or reply record removed, nothing posted" \
  "$([ "$(hold)" = "$before" ] && echo same || echo changed) $(grep -c . "$S/posts")" "same 1"
# The second sweep, the next hour as far as it can tell: every wait keeps its label, because the
# comment that parked it still dates from the first wait label, and nothing is posted
# but the retry note a merged PR with no release outcome earns each hour.
calls=$(wc -l < "$G/calls")
stamp=$(cat "$st/owner-item-from")
tick --sweep
check "second sweep: exit" "$rc" 0
check "second sweep: the moment the rule started running here is not moved on" "$(cat "$st/owner-item-from")" "$stamp"
check "second sweep: its one write is a comment on the merged PR" "$(tail -n +$((calls + 1)) "$G/calls" | cut -d ' ' -f 1,2 | paste -sd ' ' -)" \
  "POST repos/fake/repo/issues/204/comments"
check "second sweep: … which is its retry 2 of 3" "$(grep -c 'sweep retry 2/3' "$G/204/comments.jsonl")" 1
check "second sweep: no second report" "$(grep -c . "$S/posts")" 1
# The comment the first sweep posted for the issue filed already waiting is read back here as the park. Its
# own item is what keeps it out of the faults: a bare `owner` on it would read as a stage that gave no reason
# from this sweep on, so the issue would be reported as a fault in the loop every hour.
check "second sweep: the re-check reads its own comment back as its own, and no issue is newly at fault" \
  "$(grep -c 'sweep: issue #135 — \[blocked-on: owner\] ' "$st/ticks.log") $(grep -c 'No reason given for why this needs you — the loop should have decided' "$S/reports")" "0 1"
check "second sweep: the locked worktree's leftover goes again, and its reply record" \
  "$(grep -c '^compose -p proj-119 down' "$G/docker") $([ -e "$st/issue-119.replied" ] && echo kept || echo gone)" "2 gone"
# The third: the owner commits issue 112's edits, which leaves a commit found nowhere else — a new
# reason with a new step, so a new report.
git -C "$co/.claude/worktrees/issue-112" commit -q -am "the owner commits the edits"
tick --sweep
check "third sweep: the reason a folder is kept changed — a new report" "$(grep -c . "$S/posts")" 2
check "third sweep: … which names the commit" "$(grep -c '^  issue #112 (closed): its branch issue-112 has 1 commit(s)' "$S/reports")" 1
# `--cleanup` fails while the folder or the branch stays, and works once git can remove it.
tick --cleanup 119
check "--cleanup of a locked worktree: exit 1, the folder kept" "$rc $([ -d "$co/.claude/worktrees/issue-119" ] && echo kept || echo gone)" "1 kept"
git -C "$co" worktree unlock "$co/.claude/worktrees/issue-119"
tick --cleanup 119
check "--cleanup once unlocked: exit 0, the folder and branch gone" \
  "$rc $([ -d "$co/.claude/worktrees/issue-119" ] && echo kept || echo gone) $(git -C "$co" branch --list issue-119)" "0 gone "
tick --cleanup 121
check "--cleanup of a branch checked out in another folder: exit 1, the branch kept, the log says why" \
  "$rc $(git -C "$co" branch --list issue-121 | tr -d ' +*') $(tail -n 1 "$st/ticks.log" | grep -c 'issue #121: its branch issue-121 was not deleted — ')" "1 issue-121 1"
git -C "$co" worktree unlock "$co/.claude/worktrees/issue-125"   # the report's step for a locked folder deleted by hand
tick --cleanup 125
check "--cleanup once the folder deleted while locked is unlocked: exit 0, the branch gone" "$rc $(git -C "$co" branch --list issue-125)" "0 "

# --- a park by the driver, and `ready` put on a waiting issue --------------------------------------
fresh
issue 150 OPEN ""
issue 120 OPEN "in-review area:factory-driver"; pr 220 120 OPEN CLEAN '[{"status": "in_progress", "createdAt": "2026-09-01T00:00:00Z"}]'
issue 121 OPEN "in-progress area:docs"; pr 221 121 CLOSED
issue 122 OPEN "needs-decision ready area:deploy" owner; pr 222 122 MERGED
issue 123 OPEN "waiting ready area:python" issue:150
issue 124 OPEN "ready waiting area:ci" issue:150   # `ready` older than the wait: a session that died mid-park
for n in 120 121 122 123 124; do tick --lane fast --issue "$n"; [ "$rc" = 0 ] || check "tick for issue #$n: exit" "$rc" 0; done
check "driver: a review that never finishes — waiting, in-review off" "$(labels 120)" "waiting"
check "driver: its comment ends with the retry tag, then the mark" "$(jq -r .body "$G/120/comments.jsonl" | grep . | tail -n 2 | paste -sd ' ' -)" "[blocked-on: ci] $M"
check "driver: a pull request closed unmerged — needs-decision, in-progress off" "$(labels 121)" "needs-decision"
check "driver: ready on the owner's wait, PR merged — in-review, the rest off" "$(labels 122)" "in-review"
check "driver: ready on a loop's wait, no PR — ready, waiting off" "$(labels 123)" "ready"
check "driver: the resumed issue is verified again" "$(grep -c 'stage `verify` of issue #123' "$S/sessions")" 1
check "driver: a ready older than the wait — taken off, still waiting" "$(labels 124)" "waiting"
check "driver: … and no session for it" "$(grep -c 'issue #124' "$S/sessions")" 0

# --- a waiting issue takes no room and holds no area -----------------------------------------------
fresh
issue 150 OPEN ""
issue 130 OPEN "waiting in-progress area:factory-driver" issue:150
issue 131 OPEN "needs-decision in-review area:factory-driver" owner; pr 231 131 OPEN
issue 132 OPEN "ready p1-production area:factory-driver"
max=1 tick --lane fast
check "pick: exit" "$rc" 0
check "pick: the ready issue is picked beside two waiting ones, room for one" "$(grep -c 'issue #132: picked from class p1-production' "$st/ticks.log")" 1
check "pick: its verify session ran" "$(grep -c 'stage `verify` of issue #132' "$S/sessions")" 1

# --- the area rule: issue 77 in flight, issue 5 ready -----------------------------------
# <77's areas>|<5's areas, empty: none>|<the area 5 is skipped on, or empty: picked>
for c in 'area:factory-driver|area:factory-rules|' 'area:factory-host|area:factory-driver area:factory-rules|' \
         'area:factory-driver|area:factory-driver|area:factory-driver' \
         'area:factory-driver area:factory-host|area:factory-rules area:factory-host|area:factory-host' \
         'area:factory-driver||'; do
  IFS='|' read -r theirs mine shared <<< "$c"
  fresh; issue 77 OPEN "in-progress $theirs"; issue 5 OPEN "ready p1-production $mine"
  tick --lane fast --dry-run
  want="issue #5: picked from class p1-production"; [ -z "$shared" ] || want="issue #5 skipped: $shared in flight on issue #77"
  check "area: $theirs in flight, ${mine:-no area} ready — ${shared:+skipped on }${shared:-picked}, no session, the tick done" \
    "$rc|$(grep -oE 'issue #5(: picked from .*| skipped: .*)$' "$st/ticks.log" | paste -sd '|' -)|$(grep -c . "$S/sessions")|$(grep -c '\] tick done$' "$st/ticks.log")" \
    "0|$want|0|1"
done

# --- a class whose list fails: the classes above it keep their candidates, none below is picked --
# <the class whose list fails>|<the pick, or empty: none>|<the log line>
for c in 'p3-tooling|issue #5: picked from class p1-production|listing the p3-tooling issues failed — this tick picks from the classes above it only' \
         'p1-production||no issue picked: listing the p1-production issues failed — next tick'; do
  IFS='|' read -r down want line <<< "$c"
  fresh; issue 5 OPEN "ready p1-production"; issue 6 OPEN "ready p3-tooling"; echo "$down" > "$G/list-down"
  tick --lane fast --dry-run
  check "pick: the $down list fails — ${want:-nothing picked}, and the log says so" \
    "$rc|$(grep -oE 'issue #[0-9]+: picked from .*$' "$st/ticks.log")|$(grep -cF -- "$line" "$st/ticks.log")" "0|$want|1"
done
# The last class is every open issue, which only an issue with no priority label reaches: when
# that list fails, nothing is picked and the tick must not say the queue is empty — it did not see the queue.
fresh; issue 5 OPEN "area:docs"; echo '(open)' > "$G/list-down"
tick --lane fast --dry-run
check "pick: the open-issue list fails — nothing picked, and no claim that the queue is empty" \
  "$rc|$(grep -oE 'issue #[0-9]+: picked from .*$' "$st/ticks.log")|$(grep -c 'no issue picked: listing the open issues failed — next tick' "$st/ticks.log")|$(grep -c 'queue empty' "$st/ticks.log")" \
  "0||1|0"

# --- "blocked by" links: issue 77 in flight in area:factory-driver; ready are 89 in that area, 90
# blocked by 95, which waits for the owner, 91, free until its check links it to 95, and 96 and 97, which block
# each other ------------------------------------------------------------------------------------------------
fresh
issue 77 OPEN "in-progress area:factory-driver"
issue 89 OPEN "ready p1-production area:factory-driver"
issue 90 OPEN "ready p1-production"; echo 95 > "$G/90/blocked_by"
issue 91 OPEN "ready p1-production"; echo 95 > "$G/91/link_on_verify"
issue 95 OPEN "needs-decision" owner
issue 96 OPEN "ready p3-tooling"; echo 97 > "$G/96/blocked_by"
issue 97 OPEN "ready p3-tooling"; echo 96 > "$G/97/blocked_by"
picks() { grep -oE 'issue #[0-9]+(: picked from .*| skipped: .*)$' "$st/ticks.log" | paste -sd '|' -; }
deps() { grep -oE 'issues/[0-9]+/dependencies/blocked_by$' "$G/reads" | cut -d / -f 2 | paste -sd ' ' -; }
: > "$G/reads"; tick --lane fast --dry-run
check "blocked: the one in a busy area and the blocked one skipped, the next one picked" "$rc|$(picks)" \
  "0|issue #89 skipped: area:factory-driver in flight on issue #77|issue #90 skipped: blocked by issue #95|issue #91: picked from class p1-production"
check "blocked: one blocker read per candidate past the area check, none for the one in a busy area" "$(deps)" "90 91"
: > "$G/reads"; : > "$st/ticks.log"; tick --lane fast
check "blocked: a real tick — one check session, for the free one" "$rc|$(cat "$S/sessions")" "0|stage \`verify\` of issue #91"
check "blocked: … the skipped ones keep \`ready\`, with no comment" "$(labels 89)|$(labels 90)|$(cat "$G/89/comments.jsonl" "$G/90/comments.jsonl" 2> /dev/null | grep -c .)" "ready|ready|0"
check "blocked: a check that linked a blocker and kept \`ready\` is logged as that, not as no progress" \
  "$(grep -c 'issue #91: stage verify: checked, and blocked by issue #95 — it keeps its place in the queue' "$st/ticks.log") $(grep -c 'issue #91: stage verify made no progress' "$st/ticks.log")" "1 0"
check "blocked: the hourly report names what the owner's question holds up" \
  "$(grep -cx '      blocked by this issue on GitHub, so your answer also frees: issue #90, issue #91' "$S/reports") $(grep -cx 'needs issue #95 no-item frees 90 91' "$st/sweep-posted")" "1 1"
check "blocked: … and the two issues that block each other, once, under their own heading" \
  "$(grep -c '^Issues that wait for each other' "$S/reports") $(grep -cx '  issue #96, issue #97' "$S/reports") $(grep -cx 'loop 96 97' "$st/sweep-posted")" "1 1 1"
echo blocked_by > "$G/90/down"; tick --sweep; rm "$G/90/down"
check "blocked: a sweep whose links do not load uses the last ones read — the same report, not posted again" \
  "$rc $(grep -c 'links did not load — this report uses the last ones read' "$st/ticks.log") $(grep -cx '🧹 factory sweep' "$S/posts")" "0 1 1"
echo CLOSED > "$G/91/state"; : > "$G/reads"; : > "$G/invocations"; : > "$st/ticks.log"; tick --lane fast --dry-run   # an idle tick: nothing startable
check "blocked: an idle tick — every candidate skipped, the circle's two each on the other" "$rc|$(picks)|$(grep -c 'no startable issue (4 candidate' "$st/ticks.log")" \
  "0|issue #89 skipped: area:factory-driver in flight on issue #77|issue #90 skipped: blocked by issue #95|issue #96 skipped: blocked by issue #97|issue #97 skipped: blocked by issue #96|1"
check "blocked: … at most one extra call per candidate: 3 blocker reads for 4 candidates" "$(deps)" "90 96 97"
echo "info: that idle tick made $(grep -c . "$G/invocations") gh calls, $(grep -c /dependencies/ "$G/reads") of them blocker reads"
echo CLOSED > "$G/95/state"; : > "$st/ticks.log"; tick --lane fast --dry-run
check "blocked: once its blocker is closed, it is picked" "$(picks | cut -d '|' -f 2)" "issue #90: picked from class p1-production"
fresh   # the blocker list of issue 90 does not load
issue 90 OPEN "ready p1-production"; echo 95 > "$G/90/blocked_by"; echo blocked_by > "$G/90/down"
issue 91 OPEN "ready p1-production"
issue 95 OPEN "needs-decision" owner
tick --lane fast
check "blocked: its links do not load — skipped, said so, the next one picked" "$rc|$(picks)" \
  "0|issue #90 skipped: its \"blocked by\" links did not load|issue #91: picked from class p1-production"
check "blocked: … the hourly sweep says so, and still posts its report, without the note" \
  "$(grep -c 'sweep: GitHub.s "blocked by" links did not load' "$st/ticks.log") $(grep -cx '🧹 factory sweep' "$S/posts") $(grep -c 'your answer also frees' "$S/reports")" "1 1 0"
fresh   # issue 88's one blocker is issue 98 of another repository, not this one's issue 98
issue 88 OPEN "ready p1-production"; echo 98 > "$G/88/blocked_by"
issue 98 OPEN ""; echo other/repo > "$G/98/repo"
tick --lane fast --dry-run
check "blocked: a link to another repository's issue is not read as this one's issue of that number" "$rc|$(picks)" "0|issue #88: picked from class p1-production"

# --- the queue is opt-out: `ready` is no longer the gate --------------------------------
fresh
issue 50 OPEN "p1-production area:docs"              # no stage label at all: a candidate, and of the highest class
issue 51 OPEN "ready p3-tooling"                  # queued by hand, a class below
issue 52 OPEN "hold p1-production"                   # set aside by the owner
issue 53 OPEN "tracking p1-production"               # a roadmap issue or the loop's own page
issue 54 OPEN "waiting p1-production" issue:56       # waiting for another issue, one that stays open
issue 55 OPEN "needs-decision p1-production" owner   # waiting for the owner
issue 56 OPEN "in-progress p1-production"            # already in flight
tick --lane fast --dry-run
check "opt-out: an issue with no stage label is picked, ahead of a queued one of a lower class" \
  "$rc|$(picks)" "0|issue #50: picked from class p1-production"
echo CLOSED > "$G/50/state"; : > "$st/ticks.log"; tick --lane fast --dry-run
check "opt-out: with that one gone, the issue carrying \`ready\` is picked, exactly as before" \
  "$rc|$(picks)" "0|issue #51: picked from class p3-tooling"
echo CLOSED > "$G/51/state"; : > "$st/ticks.log"; : > "$S/sessions"; tick --lane fast --dry-run
check "opt-out: set aside, a roadmap issue, the two waiting and the one in flight are never picked — the empty queue says so, once" \
  "$rc|$(picks)|$(grep -c 'queue empty: no open issue the loop may start' "$st/ticks.log")|$(grep -c . "$S/sessions")" "0||1|0"

# --- the loop's own share of its sessions ---------------------------------------------------
# Over a fifth of the sessions the loop started in the last 24 h about the loop, a `p3-tooling` issue still takes
# a slot nothing else can use, said in one line, and the queue is not called empty; a project issue is picked
# whatever the share; at exactly a fifth the loop's own issue is picked as any other; `--issue N` is never held.
share_log() {   # <classes…>: one tagged stage line per class, dated now, as run_stage writes them
  local c now; now=$(date -u +%FT%TZ)
  for c in "$@"; do echo "$now [slow] issue #1: stage implement (cwd x) [class:$c]" >> "$st/ticks.log"; done
}
fresh
issue 60 OPEN "ready p3-tooling"
share_log p3-tooling p3-tooling p3-tooling p3-tooling p2-product; tick --lane fast --dry-run
check "share: over a fifth about the loop, and nothing else can start — the loop's own issue takes the free slot, said once, and the queue is not called empty" \
  "$rc|$(picks)|$(grep -c "the loop's own work took 80 % of the last 24 h's sessions, over its 20 % share, but no other issue can start: issue #60 takes the free slot" "$st/ticks.log")|$(grep -c 'queue empty' "$st/ticks.log")" "0|issue #60: picked from class p3-tooling|1|0"
issue 61 OPEN "ready p2-product"; : > "$st/ticks.log"; share_log p3-tooling p3-tooling p3-tooling p3-tooling p2-product; tick --lane fast --dry-run
check "share: … while a project issue is picked whatever the share" "$rc|$(picks)" "0|issue #61: picked from class p2-product"
echo CLOSED > "$G/61/state"; : > "$st/ticks.log"; share_log p3-tooling p2-product p2-product p2-product p2-product; tick --lane fast --dry-run
check "share: at exactly a fifth, the loop's own issue is picked" "$rc|$(picks)" "0|issue #60: picked from class p3-tooling"
: > "$st/ticks.log"; share_log p3-tooling p3-tooling p3-tooling p3-tooling p2-product; tick --lane fast --dry-run --issue 60
check "share: the owner's own pick is never held by it" "$rc|$(picks)" "0|issue #60: picked from class --issue"

# --- a build waits while its area is in flight --------------------------------------------
fresh
issue 170 OPEN "in-review area:factory-driver"; pr 270 170 OPEN
issue 171 OPEN "in-progress area:factory-driver"
issue 172 OPEN "in-progress area:factory-driver"; echo in-progress > "$G/172/stuck"   # its in-progress will not come off
issue 173 OPEN "in-progress area:factory-driver"; git -C "$co" branch issue-173   # a build that had started
issue 174 OPEN "in-progress p1-production"   # just checked, no area: its files are ones no area names
for n in 171 172 173 174; do tick --lane slow --issue "$n"; [ "$rc" = 0 ] || check "slow tick for issue #$n: exit" "$rc" 0; done
check "area: an in-progress issue whose area is in flight — back to ready, not built" "$(labels 171) $(grep -c 'issue #171' "$S/sessions")" "ready 0"
# Issue #170 holds the area from code review, not from a build, so the note says "worked on".
check "area: … with one note naming the issue that holds the area, and how it holds it" \
  "$(notes 171 'Checked and ready to build, but it waits its turn: issue #170 is being worked on (building, or in code review)')" 1
check "area: a build that had started — back to ready, not built" "$(labels 173) $(grep -c 'issue #173' "$S/sessions")" "ready 0"
check "area: … its note names its branch and says the build continues from it" \
  "$(notes 173 'Its build has started, on branch `issue-173`, but it waits its turn: issue #170') $(notes 173 'continues this build from that branch')" "1 1"
check "area: its in-progress will not come off — ready on, still not built" "$(labels 172) $(grep -c 'issue #172' "$S/sessions")" "in-progress ready 0"
check "area: … and no note while its labels have not moved" "$(notes 172 'waits its turn')" 0
check "area: an in-progress issue with no area, issue 170 in flight — built, still in-progress, no note" \
  "$(grep -c 'stage `implement` of issue #174' "$S/sessions") $(labels 174) $(notes 174 'waits its turn')" "1 in-progress 0"

# --- the owner's reply ------------------------------------------------------------------
# Each question is posted a second before its label, as park_issue and the sessions post, and answered a
# minute later: inside the 10 min in which park_comment used to take the latest comment for the park.
fresh
Tq=2026-08-31T23:59:59Z T1=2026-09-01T00:01:00Z
ask=$'## Decision needed: A or B?\n\n**To answer:** reply here with `A` or `B`.\n[blocked-on: owner]\n\n'"$M"
issue 150 OPEN ""
issue 140 OPEN "needs-decision area:python"; pr 240 140 OPEN; say 140 $Tq "$ask"; say 140 $T1 A
issue 141 OPEN "needs-decision area:ci"; say 141 $Tq "$ask"; say 141 $T1 "$(sed 's/^/> /' <<< "$ask")"$'\n\nB'   # "Quote reply": the mark too
issue 142 OPEN "needs-decision area:deploy"; say 142 $Tq "$ask"; say 142 $T1 $'Checked again.\n\n'"$M"
issue 143 OPEN "needs-decision area:api"; say 143 $Tq "$ask"; say 143 $T1 "a bot's note" bot
issue 144 OPEN "waiting area:db" issue:150; say 144 $T1 A
issue 145 OPEN "needs-decision area:ui"; say 145 $Tq "$ask"; say 145 $T1 A; echo "1452 resumed" > "$st/issue-145.replied"
issue 146 OPEN "needs-decision area:core" owner; pr 246 146 MERGED; say 146 $T1 A   # parked before the mark
issue 147 OPEN "needs-decision p3-tooling area:docs"; say 147 $Tq $'## Decision needed: A or B?\n\n[blocked-on: owner]'; say 147 $T1 A   # the mark forgotten
issue 148 OPEN "needs-decision area:factory-host"; say 148 $Tq $'## Decision needed: A or B?\n\n[blocked-on: owner]'
say 148 $T1 $'> ## Decision needed: A or B?\n>\n> [blocked-on: owner]\n\nA'   # … and the reply quotes its tag
issue 149 OPEN "needs-decision area:factory-rules"; say 149 2026-08-31T12:00:00Z "an old remark"; say 149 $Tq "$ask"   # older than the question
issue 139 OPEN "needs-decision area:factory-driver"; say 139 $Tq "$ask"; say 139 $T1 A; echo comments > "$G/139/down"   # a 502
for n in 140 141 142 143 144 145 146 147 148 149 139; do tick --lane fast --issue "$n"; [ "$rc" = 0 ] || check "reply tick for issue #$n: exit" "$rc" 0; done
check "reply: a minute after the question, PR open — in-review, needs-decision off" "$(labels 140)" "in-review"
check "reply: … one note says work resumes" "$(notes 140 'was picked up; work resumes.')" 1
check "reply: … it links the comment it read as the reply" "$(notes 140 '[Your reply](https://example.invalid/c1402) was picked up')" 1
check "reply: … the note ends with the mark" "$(jq -r .body "$G/140/comments.jsonl" | tail -n 1)" "$M"
check "reply: … and the reply acted on is recorded" "$(cat "$st/issue-140.replied" 2> /dev/null)" "1402 resumed"
check "reply: one that quotes the whole question, mark included, no PR — ready" "$(labels 141)" "ready"
check "reply: … and it is verified again in the same tick" "$(grep -c 'stage `verify` of issue #141' "$S/sessions")" 1
check "reply: … with no priority label, its note says it sorts last" "$(notes 141 'Your reply') $(notes 141 'not yet rated how urgent')" "1 1"
check "reply: a newer comment with the mark — nothing resumed" "$(labels 142)" "needs-decision"
check "reply: a newer comment by a bot — nothing resumed" "$(labels 143)" "needs-decision"
check "reply: a comment on a wait for another issue — nothing resumed" "$(labels 144)" "waiting"
check "reply: a reply already acted on — not again" "$(labels 145)" "needs-decision"
check "reply: a park from before the mark, PR merged — in-review" "$(labels 146)" "in-review"
check "reply: a question that forgot the mark, answered a minute later — ready" "$(labels 147)" "ready"
check "reply: … with a priority label, its note says nothing of how it sorts" "$(notes 147 'Your reply') $(notes 147 'how urgent')" "1 0"
check "reply: … answered with a quote of its tag — ready" "$(labels 148)" "ready"
check "reply: the latest unmarked comment is older than the question — nothing resumed" "$(labels 149)" "needs-decision"
check "reply: … and it is recorded as read" "$(cat "$st/issue-149.replied" 2> /dev/null)" "1491 read"
check "reply: its comments do not load — nothing resumed, nothing recorded" \
  "$(labels 139) $([ -e "$st/issue-139.replied" ] && echo recorded || echo none)" "needs-decision none"
check "reply: … and the log says so" "$(grep -c 'issue #139: its comments did not load' "$st/ticks.log")" 1
check "reply: no note where nothing resumed" "$(for n in 142 143 144 145 149 139; do notes "$n" 'Your reply'; done | paste -sd ' ' -)" "0 0 0 0 0 0"

# --- a reply waits its turn: its part of the code in use, or no free slot ---------------------------
fresh
issue 160 OPEN "in-progress area:factory-driver"
issue 161 OPEN "needs-decision area:factory-driver"; pr 261 161 OPEN; say 161 $Tq "$ask"; say 161 $T1 A
issue 162 OPEN "needs-decision area:factory-driver"; say 162 $Tq "$ask"; say 162 $T1 A
issue 163 OPEN "needs-decision area:python"; pr 263 163 OPEN; say 163 $Tq "$ask"; say 163 $T1 A
tick --lane fast --issue 161; tick --lane fast --issue 161
check "turn: its area in use — it keeps waiting" "$(labels 161)" "needs-decision"
check "turn: … one note in two ticks, naming the issue that holds the area" "$(notes 161 'waits its turn: issue #160 is being worked on')" 1
tick --sweep
check "turn: the hourly report lists it as answered and waiting its turn" "$(grep -c '^  issue #161 issue 161: you replied' "$S/reports")" 1
check "turn: … not under what needs the owner" "$(grep -cx '  issue #161 issue 161' "$S/reports")" 0
check "turn: … and it keeps waiting" "$(labels 161)" "needs-decision"
tick --lane fast --issue 162
check "turn: its area in use, no PR — back in the queue" "$(labels 162)" "ready"
check "turn: … its note says it waits its turn" "$(notes 162 'starts when its turn comes: issue #160 is being worked on')" 1
check "turn: … and no session while the area is in use" "$(grep -c 'issue #162' "$S/sessions")" 0
max=1 tick --lane fast --issue 163
check "turn: no free slot — it keeps waiting" "$(labels 163)" "needs-decision"
check "turn: … its note says why" "$(notes 163 'waits its turn: no free work slot')" 1
echo CLOSED > "$G/160/state"
tick --lane fast --issue 162; tick --lane fast --issue 161
check "turn: the area free — the queued one is verified" "$(grep -c 'stage `verify` of issue #162' "$S/sessions")" 1
check "turn: the area free — the waiting one resumes as in-review" "$(labels 161)" "in-review"
check "turn: … with one note that work resumes" "$(notes 161 'was picked up; work resumes.')" 1

# --- the live board --------------------------------------------------------------------
# One world holding a line for every section: two issues in flight, two that can start, two that cannot, a wait
# on the clock, a wait for another issue, a question for the owner and an issue closed in the last 24 h.
fresh
# The project's labels file: the board says each label in its words, the description up to the first colon.
mkdir -p "$co/.factory"
printf '%s\n' '# name|color|description' 'p1-production|B60205|something wrong in production: the service is down or losing data' \
  'p2-product|FBCA04|the product work: what the spec asks for' "p3-tooling|C2E0C6|the loop's own machinery: CI, tooling" \
  "area:factory-driver||the loop's own code: scripts/factory-*.sh" > "$co/.factory/labels"
issue 300 OPEN "in-progress p1-production area:factory-driver"            # being built: no pull request yet
issue 301 OPEN "in-review p1-production area:python"; pr 401 301 OPEN     # its pull request is open
issue 310 OPEN "ready p1-production area:core"                    # next up, first
issue 311 OPEN "ready p3-tooling area:docs"                            # next up, second
issue 312 OPEN "ready p1-production area:factory-driver"                  # the part of the code issue 300 holds
issue 313 OPEN "ready p2-product"; echo 320 > "$G/313/blocked_by"   # blocked by the owner's question
issue 316 OPEN ""                                                      # no label at all: in the queue all the same
issue 317 OPEN "hold p1-production"                                       # set aside by the owner: on no list
issue 314 OPEN "waiting p3-tooling" time:2099-01-01T00:00:00Z          # a wait on the clock
issue 315 OPEN "waiting p3-tooling" issue:320                          # a wait for another issue
issue 320 OPEN "needs-decision p1-production" owner                       # the question itself
issue 330 CLOSED "p3-tooling"                                          # finished in the last 24 h
issue 331 CLOSED "p3-tooling"                                          # closed weeks ago: outside that list
ago=$(date -u -d '2 hours ago' +%FT%TZ); echo "$ago" > "$G/330/closed"  # 331 keeps the fake's default, 2026-09-01
tick --sweep   # the sweep records what each parked issue waits for, and the "blocked by" links
check "board: the sweep recorded each parked issue's wait for the board" \
  "$(cut -f 1,2 "$st/board-parked" | tr '\t' ' ' | paste -sd ' ' -)" "314 time:2099-01-01T00:00:00Z 315 issue:320 320 owner"
calls() { grep -c . "$G/calls" 2> /dev/null || echo 0; }   # writes the fake GitHub took; none yet in this world
was=$(calls)
tick --board --dry-run
b() { grep -cF -- "$1" "$S/out"; }   # lines of the board text the dry run printed, matched as plain text
check "board: dry run exit" "$rc" 0
check "board: how many issues the loop has in hand and the time of this run" \
  "$(b '**2 of the 5 issues the loop may work on at once are in hand, 3 free. Last checked 20')" 1
check "board: the loop's own share of its sessions, and its cap" \
  "$(grep -c "^The loop's own machinery took [0-9]* % of the sessions the loop started in the last 24 hours\. It may take at most 20 %; over that, the loop starts nothing about itself until the share falls\.$" "$S/out")" 1
check "board: how often it is rewritten and when its time means the loop has stopped, from the one setting" \
  "$(b 'at least every 10 minutes — beside a step that is running too — so the time above stays fresh. If that time is more than 15 minutes old, the loop itself has stopped.')" 1
check "board: the queue's order in the same words as the order it is sorted in, and the caps on builds and reviews" \
  "$(b "The loop takes these in this order: something wrong in production, then the product work, then the loop's own machinery, oldest first within each. It starts one when a place above is free, and it builds at most 1 issue at a time and handles at most 1 finished code review at a time, so a free place does not always mean one starts at once.")" 1
check "board: an issue being built, since when, and the part of the code it holds" \
  "$(grep -c '^- \*\*issue #300\*\* issue 300 — being built\. At this step since 20.*\. Part of the code it holds: the loop.s own code\.$' "$S/out")" 1
check "board: one whose pull request is open" \
  "$(b '- **issue #301** issue 301 — its change is open as pull request #401, waiting for the automatic code review')" 1
check "board: what comes next, in the loop's own order" "$(grep -c '^1\. \*\*issue #310\*\* issue 310 — something wrong in production\.$' "$S/out") $(grep -c '^2\. \*\*issue #311\*\* issue 311 — the loop.s own machinery\.$' "$S/out")" "1 1"
check "board: an issue with no label at all is in that queue too, last because nothing rates it" \
  "$(grep -c '^3\. \*\*issue #316\*\* issue 316 — not yet rated, so it sorts behind every issue that is\.$' "$S/out")" 1
check "board: one the owner set aside is on no list" "$(grep -c 'issue #317' "$S/out")" 0
check "board: one that cannot start because its part of the code is in use, named in plain words" \
  "$(b "- **issue #312** issue 312 — the loop is already working on the same part of the code (the loop's own code), in issue #300.")" 1
check "board: one that cannot start until another issue closes" "$(b '- **issue #313** issue 313 — after issue #320, which is still open.')" 1
check "board: a wait the loop ends itself, and when" "$(b '- **issue #315** issue 315 — after issue #320, which is still open. The loop starts it when that one closes.')" 1
check "board: a wait on the clock" "$(b '- **issue #314** issue 314 — until 2099-01-01 00:00 UTC. The loop re-checks it then')" 1
check "board: the owner's question, where to reply, and what it holds up" \
  "$(b '- **issue #320** issue 320 — seeded. [Open the issue](https://github.com/fake/repo/issues/320) and reply there. Your answer also lets these start: issue #313.')" 1
check "board: what finished in the last 24 hours, and nothing closed before them" \
  "$(b "- **issue #330** issue 330 (closed $(date -u -d "$ago" +'%Y-%m-%d %H:%M UTC'))") $(grep -c 'issue #331' "$S/out")" "1 0"
check "board: no repo shorthand in what the owner reads" \
  "$(grep -ciE "$(sed -n "s/^SHORTHAND='\(.*\)'\$/\1/p" tests/factory-comments-test.sh)" "$S/out")" 0
check "board: every section is there, and each says so when it holds nothing" \
  "$(grep -c '^## ' "$S/out") $(b '## Being worked on now') $(b '## Next up, in order') $(b '## Queued, but cannot start yet') $(b '## Waiting for a set time') $(b '## Waiting for you') $(b '## Finished in the last 24 hours')" "6 1 1 1 1 1 1"
check "board: the dry run wrote nothing — no issue, no text, no state" \
  "$(calls) $([ -e "$st/board.txt" ] || [ -e "$st/board-issue" ] && echo wrote || echo none)" "$was none"
tick --board
check "board: its own issue is created, labelled \`tracking\` and pinned" \
  "$rc $(grep -c '^created issue 900$' "$G/calls") $(cat "$G/900/labels") $(grep -c 'graphql .*pinIssue' "$G/calls")" "0 1 tracking 1"
check "board: the text is written on it once, and reads as the dry run printed it" \
  "$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls") $(grep -c '^# What the factory is doing$' "$G/900/body") $(grep -c '^- \*\*issue #320\*\* issue 320 — seeded\.' "$G/900/body")" "1 1 1"
check "board: it never lists itself" "$(grep -c 'issue #900' "$G/900/body")" 0
tick --board
check "board: the same picture minutes later — no second write" "$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls")" 1
echo 0 > "$st/board-written"; tick --board   # a picture that has not changed is still rewritten once its time is old enough
check "board: an unchanged picture older than the heartbeat — written again, so its time stays fresh" \
  "$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls") $(grep -c 'board: issue #900 rewritten — its \"last checked\" time was' "$st/ticks.log")" "2 1"
echo CLOSED > "$G/310/state"; echo "$ago" > "$G/310/closed"
tick --board
check "board: the picture changed — written again, and the closed issue moved to what finished" \
  "$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls") $(grep -c '^1\. \*\*issue #311\*\*' "$G/900/body") $(grep -c '^- \*\*issue #310\*\* issue 310 (closed ' "$G/900/body")" "3 1 1"
echo body > "$G/900/down"; echo CLOSED > "$G/311/state"; echo "$ago" > "$G/311/closed"   # the write is refused: a board issue deleted or moved
tick --board
check "board: its page will not take the text — said so, and the number it held is forgotten" \
  "$(grep -c 'board: issue #900 could not be rewritten' "$st/ticks.log") $([ -e "$st/board-issue" ] && echo kept || echo forgotten)" "1 forgotten"
rm "$G/900/down"
tick --board
check "board: the next run finds the page again by its title, and writes what it could not before" \
  "$(cat "$st/board-issue") $(grep -c 'issue #311' "$G/900/body") $(grep -c '^created issue' "$G/calls")" "900 1 1"
# The board issue closed by hand: the loop leaves it closed and opens the next one (a page nobody sees is not a
# board, and GitHub takes a write to a closed issue without a word).
echo CLOSED > "$G/900/state"; echo "$ago" > "$G/900/closed"
wrote=$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls")
tick --board
check "board: its page closed by hand — a new one is created, and the closed one is not written to again" \
  "$(grep -c '^created issue 901$' "$G/calls") $(cat "$st/board-issue") $(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls")" "1 901 $wrote"
# The account's usage limit pauses both lanes: the board says so, instead of showing free work slots and a queue.
echo $(($(date +%s) + 3600)) > "$st/.usage-limit-until"
tick --board --dry-run
check "board: while the account's usage limit pauses the loop, the page says so, and until when" \
  "$(b "**Paused until ") $(b ": the AI account's usage limit was reached, so the loop starts nothing new until then.**")" "1 1"
rm "$st/.usage-limit-until"
# A stage session holds its lane for as long as it runs — a review round is often half an hour — and the fast
# lane's systemd unit starts no second tick meanwhile. The page is kept fresh beside the session instead, and
# the child doing it stops with the tick, so nothing is left writing the page afterwards.
fresh
issue 340 OPEN "ready p1-production area:docs"
echo 4 > "$G/340/slow"            # its check takes 4 s; the board looks every second below
beat=1 tick --lane fast --issue 340
wrote=$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls")
check "board: the page is kept fresh beside a session that holds the lane" \
  "$rc $(grep -c 'stage `verify` of issue #340' "$S/sessions") $([ "$wrote" -ge 2 ] && echo fresh || echo "stale after $wrote write(s)")" "0 1 fresh"
sleep 2
check "board: the run that refreshes it stops with the tick — nothing writes the page afterwards" \
  "$(grep -c 'PATCH repos/fake/repo/issues/900' "$G/calls")" "$wrote"
check "board: that tick holds its lane afterwards for no one — the next one takes it" \
  "$(flock -n "$st/.lock-fast" true && echo free || echo held)" free
# One tick runs one session after another, and each can be shorter than the gap between two looks at the page.
# The countdown to the next look runs from the last look, kept in the state folder, so their time adds up; started
# afresh in every call, a tick full of short sessions would go half an hour without a single look (round 2).
looks=$(env FACTORY_BOARD_HEARTBEAT=12 bash -c '
  STATE=$1; DRY=0; log() { :; }
  . "$2"
  looks=0
  board_run() { looks=$((looks + 1)); date +%s > "$STATE/board-looked"; }
  date +%s > "$STATE/board-looked"   # looked at just now: no session below is long enough on its own
  for _ in 1 2 3; do sleep 2 & board_wait $!; wait $!; done
  echo "$looks"' _ "$st" "$BOARDLIB")
check "board: sessions too short for a look of their own still add up to one" \
  "$([ "${looks:-0}" -ge 1 ] && echo looked || echo "no look in ${looks:-?} session(s) of work")" looked

# --- the fast lane's workers -----------------------------------------------------------------
# One world per case: two finished code reviews waiting, a third whose review has not finished, an issue ready
# to start, and a service issue whose pull request is merged and whose deploy went green — the close step that
# is waiting. A *finished* review is what the driver calls `verdict`: a completed run of the review workflow for
# the pull request's head, and a comment naming its fix-before-merge set posted after that run started.
tl() { grep -cF -- "$1" "$st/ticks.log"; }         # lines of this world's tick log holding a piece of text
sessions() { grep -cF -- "$1" "$S/sessions"; }     # sessions the fake `claude` recorded
digests() { grep -cx '📰 daily digest' "$S/posts"; }
RUNS='[{"status": "completed", "createdAt": "2026-09-01T00:00:00Z"}]'
world() {   # world [seconds a review session takes]
  fresh
  issue 500 OPEN "in-review p1-production area:core"; pr 600 500 OPEN CLEAN "$RUNS"
  issue 501 OPEN "in-review p1-production area:python"; pr 601 501 OPEN CLEAN "$RUNS"
  issue 502 OPEN "in-review p1-production area:db"; pr 602 502 OPEN CLEAN '[]'   # its review has not finished
  say 600 2026-09-01T01:00:00Z 'Review verdict — fix-before-merge set: 0'
  say 601 2026-09-01T01:00:00Z 'Review verdict — fix-before-merge set: 0'
  issue 510 OPEN "ready p1-production area:docs"
  issue 520 OPEN "in-review p1-production area:deploy"; pr 620 520 MERGED
  sha=$(git -C "$co" rev-parse HEAD); echo "$sha" > "$G/620/merge_oid"
  echo green > "$G/release-520"
  [ -z "${1:-}" ] || { echo "$1" > "$G/500/slow"; echo "$1" > "$G/501/slow"; }
}
workers=3
world
tick --lane fast --worker 1
check "workers: worker 1 leaves every finished review to the others and runs none itself" \
  "$rc $(tl "stage review — a review worker's") $(sessions 'stage `review` of issue #')" "0 3 0"
check "workers: … and starts a new issue in the same tick" \
  "$(tl 'issue #510: picked from class p1-production') $(sessions 'stage `verify` of issue #510')" "1 1"
check "workers: … and closes the one whose deploy went green" \
  "$(tl '[fast] issue #520: stage close (green)') $(sessions 'stage `close` of issue #520')" "1 1"
check "workers: … and it is the one that re-checks the waiting issues, posts the digest and writes the board" \
  "$(tl '[fast] sweep: 0 parked issue(s)') $(digests) $([ "$(tl '[fast] board: issue #900')" -ge 1 ] && echo wrote || echo none)" "1 1 wrote"
world
tick --lane fast --worker 2
check "workers: a worker above 1 takes the finished reviews" \
  "$rc $(tl '[fast-2] issue #500: stage review (verdict)') $(sessions 'stage `review` of issue #501')" "0 1 1"
check "workers: … and never starts a new issue, never closes one, re-checks nothing, posts no digest, writes no board" \
  "$(tl 'picked from class') $(sessions 'stage `verify`') $(tl "[fast-2] issue #520: stage close — worker 1's") $(sessions 'stage `close`') $(tl '[fast-2] sweep: ') $(digests) $(tl '[fast-2] board: ')" "0 0 1 0 0 0 0"
check "workers: … and a review that has not finished is left for the next run, with no session" \
  "$(tl 'issue #502: review verdict pending on PR #602') $(sessions 'stage `review` of issue #502')" "1 0"
# The default install, one worker: it does every stage itself, as it did before this change.
workers=1
world
# What the loop settled by itself in the last day, which the digest collects for the owner.
say 510 "$(date -u +%FT%TZ)" '## Decided: the cache keeps an entry for one hour. Nothing needed from you.'$'\n\n'"$M"
say 510 "$(date -u +%FT%TZ)" 'A progress note, which is no decision.'$'\n\n'"$M"
tick --lane fast
check "digest: it lists what the loop decided by itself in the last 24 h, and nothing else" \
  "$(grep -cx '  #510 the cache keeps an entry for one hour. Nothing needed from you.' "$S/reports") $(grep -c 'A progress note' "$S/reports")" "1 0"
check "workers: one worker does every stage itself, as before" \
  "$rc $(tl '[fast] issue #500: stage review (verdict)') $(sessions 'stage `review` of issue #500') $(tl 'issue #510: picked from class p1-production') $(sessions 'stage `close` of issue #520')" "0 1 1 1 1"
check "workers: … and hands no stage to another worker" "$(tl "— a review worker's") $(tl "— worker 1's")" "0 0"
# A worker above 1 on a host already busy: it launches nothing at all this run.
workers=3
world
printf '9.99 1.00 1.00 1/1 1\n' > "$S/w$k/loadavg"
loadavg=$S/w$k/loadavg tick --lane fast --worker 2
check "workers: a worker above 1 stands down while the host is loaded, and launches nothing" \
  "$rc $(tl 'issue #500: 1-min load 9.99 is above the ceiling 6.0 — worker 2 launches no session this tick') $(grep -c . "$S/sessions")" "0 1 0"
# …except the close that follows the merge its own review just made: that round's build and test run is what
# loaded the host, and once the merge closed the issue no later tick lists it (run_lane reads open issues only),
# so a gated close is the deploy outcome the owner never reads. The next review still waits.
world
printf '0.10 0.20 0.30 1/1 1\n' > "$S/w$k/loadavg"
printf '9.99 1.00 1.00 1/1 1\n' > "$G/500/merges_at_load"
loadavg=$S/w$k/loadavg tick --lane fast --worker 2
check "workers: … but the close of the merge its own review just made runs on the host that round loaded" \
  "$rc $(sessions 'stage `close` of issue #500') $(sessions 'stage `review` of issue #501') $(tl 'issue #501: 1-min load 9.99 is above the ceiling 6.0 — worker 2 launches no session this tick')" "0 1 0 1"
# The three workers at once, as their timers fire them: each finished review to its own worker, and worker 1
# free to start a new issue meanwhile. Two workers can only end up on different issues by way of the per-issue
# lock — one taking the issue the other holds is what a single lane did.
world 4
out=$S/out-1 tick --lane fast --worker 1 &
out=$S/out-2 tick --lane fast --worker 2 &
out=$S/out-3 tick --lane fast --worker 3 &
wait
took=$(grep -oE '\[fast-[23]\] issue #50[01]: stage review \(verdict\)' "$st/ticks.log" | sort -u)
check "workers: the two finished reviews are handled at the same time, one per worker, and never by worker 1" \
  "$(grep -oE '#50[01]' <<< "$took" | sort -u | grep -c .) $(grep -oE 'fast-[23]' <<< "$took" | sort -u | grep -c .) $(grep -cE '\[fast\] issue #[0-9]+: stage review \(' "$st/ticks.log")" "2 2 0"
check "workers: … an issue one worker holds is skipped by the others while it holds it" \
  "$([ "$(tl 'in flight in another lane or worker')" -ge 1 ] && echo skipped || echo none)" skipped
check "workers: … while they run, worker 1 starts a new issue and finishes its own tick" \
  "$(tl 'issue #510: picked from class p1-production') $(sessions 'stage `verify` of issue #510') $(tl '[fast] tick done')" "1 1 1"
check "workers: … and the close of the merged one is worker 1's, run once and not three times" \
  "$(tl '[fast] issue #520: stage close (green)') $(sessions 'stage `close` of issue #520')" "1 1"
check "workers: … and the steps that must happen once did, under worker 1 alone" \
  "$(digests) $(grep -cE '\[fast-[23]\] (sweep|board):' "$st/ticks.log") $(grep -cE '\[fast-[23]\].*picked from class' "$st/ticks.log")" "1 0 0"
# The third review finishes: a later run of a worker above 1 takes it, not worker 1.
echo "$RUNS" > "$G/602/runs.json"; say 602 2026-09-01T01:00:00Z 'Review verdict — fix-before-merge set: 0'
out=$S/out-2b tick --lane fast --worker 2
check "workers: the third finished review is taken on a later run, again by a worker above 1" \
  "$rc $(tl '[fast-2] issue #502: stage review (verdict)') $(sessions 'stage `review` of issue #502')" "0 1 1"
# What the page tells the owner about the cap is the real one: with five workers, four reviews at once, because
# worker 1 runs none of them — and never more than the issues the loop may hold at all, since a review needs
# one of those places.
workers=5 tick --board --dry-run
check "workers: the page names the cap on reviews handled at once as one below the workers" \
  "$rc $(grep -cF -- 'it builds at most 1 issue at a time and handles at most 4 finished code reviews at a time' "$S/out")" "0 1"
max=3 slots=4 workers=5 tick --board --dry-run
check "workers: … held down to the issues the loop may work on at once, which is the smaller number here" \
  "$rc $(grep -cF -- 'it builds at most 3 issues at a time and handles at most 3 finished code reviews at a time' "$S/out")" "0 1"

echo "factory-labels: $cases checks, $bad failed"
[ "$bad" -eq 0 ]

#!/usr/bin/env bash
# Test of the comments the factory driver writes and reads back: a comment that makes an issue wait leads with plain
# words and carries its `[blocked-on: …]` tag on the last visible line, and the hourly re-check still reads the tag
# and the one-line reason from that shape and from a session's "Decision needed" comment. Every comment the driver
# and its sweep file post, and every comment shape of prompts/header.md (as a session reads it, its placeholders
# filled in), ends with the driver's hidden mark — the shapes written as prose by the rule the header states once —
# and none tells the owner to answer with a label. A wait that needs the owner names in its own tag what reserves
# it for them, and neither the header nor the project rules template tells a stage to stop for a missing metric or
# a recommended default. The driver also reads two of its own comment lines back — the marker that says it asked
# for a code review again, and the count of hourly retries — so its own posts are fed to its own readers here.
# The functions are cut out of the driver and its sweep file and run with `gh` stubbed: nothing is posted and no
# host state is read. Exit 1 on any failure.
# Usage: bash tests/factory-comments-test.sh [driver-path [sweep-path [header-path [rules-path [stages-dir [stage-path]]]]]]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
DRIVER=${1:-scripts/factory-tick.sh}
SWEEP=${2:-scripts/factory-sweep.sh}
SKILL=${3:-prompts/header.md}
RULES=${4:-templates/CLAUDE.md}   # the rules a project adopts with the factory
STAGES=${5:-prompts/stages}   # the stage files post the parks, so they write the tags
STAGELIB=${6:-scripts/factory-stage.sh}   # the stage runner: request_review posts
for f in "$DRIVER" "$SWEEP" "$SKILL" "$RULES" "$STAGES"/verify.md "$STAGES"/implement.md "$STAGES"/review.md "$STAGES"/close.md "$STAGELIB"; do
  [ -f "$f" ] || { echo "factory-comments-test: no such file: $f"; exit 2; }
done
src=$(cat "$DRIVER" "$STAGELIB" "$SWEEP")   # what the loop runs: the driver and the files it sources
cut=$(mktemp)
sed -n '/^FACTORY_MARK=/p; /^PRIORITIES=/p; /^REVIEW_GRACE=/p; /^owner_item_from() /p; /^resume_label() {/,/^}/p;
  /^age_s() /p; /^park_class() {/,/^}/p;
  /^park_line() {/,/^}/p; /^owner_item() {/,/^}/p; /^owner_item_says() {/,/^}/p;
  /^park_issue() {/,/^}/p; /^unrated() {/,/^}/p; /^unpark() {/,/^}/p;
  /^review_state() {/,/^}/p; /^request_review() {/,/^}/p; /^sweep_retries() {/,/^}/p; /^retry_pr() {/,/^}/p' <<< "$src" > "$cut"
# shellcheck disable=SC1090
. "$cut"
rm -f "$cut"
# The prompts as a session reads them: stage_prompt fills the placeholders in, the mark above all.
R=$(mktemp -d); mkdir -p "$R/stages"
render() { local t; t=$(cat "$1"); t=${t//'{{MARK}}'/$FACTORY_MARK}; t=${t//'{{REPO}}'/example/repo}; printf '%s\n' "$t" > "$2"; }
render "$SKILL" "$R/header.md"; for s in verify implement review close; do render "$STAGES/$s.md" "$R/stages/$s.md"; done
SKILL=$R/header.md STAGES=$R/stages

fails=0
check() { # name, got, want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}
# Repo shorthand the owner cannot read (CLAUDE.md "Writing for the owner"), for `grep -iE`. "Review v2" is
# the loop's own name for the automatic code review, and means nothing to a reader outside the session.
SHORTHAND='objective function|priority [0-9]|priority label|hard-stop list|\bsweep\b|\bverify\b|in flight|un-parked|Review v2'

# --- what the driver writes: park_issue, with `gh` recording the comment body -------------------
POSTED=""
gh() { local a; for a in "$@"; do case "$a" in body=*) POSTED=${a#body=} ;; esac; done; }
log() { :; }
labels_of() { :; }; set_state() { :; }   # park_issue's labels are scripts/factory-labels-test.sh's
board_parked_write() { :; }              # and its line for the board is not comment text either
DRY=0 REPO=example/repo REREQUEST_MAX=3
STATE=$(mktemp -d)   # what owner_item reads the rule's start from below; scratch, and removed below
trap 'rm -rf "$STATE" "$R"' EXIT
park_issue 7 ci "the automatic code review of PR #12 ended without a verdict twice in a row"
check "park_issue: leads with the reason" "$(head -n 1 <<< "$POSTED")" \
  "## Waiting: the automatic code review of PR #12 ended without a verdict twice in a row"
check "park_issue: the mark is the last line" "$(tail -n 1 <<< "$POSTED")" "${FACTORY_MARK-no mark in the driver}"
check "park_issue: the tag is the last line above it" "$(grep . <<< "$POSTED" | tail -n 2 | head -n 1)" "[blocked-on: ci]"
check "park_issue: a retried wait asks nothing of the owner" "$(grep -c 'Nothing needed from you' <<< "$POSTED")" "1"
check "park_issue: read back, class" "$(park_class "$POSTED")" "ci"
check "park_issue: read back, reason" "$(park_line "$POSTED")" \
  "the automatic code review of PR #12 ended without a verdict twice in a row"
park_issue 8 owner "its pull request was closed without being merged" "**To answer:** reopen it, or close this issue."
check "park_issue: an owner wait says it needs the owner" "$(grep -c 'This needs you' <<< "$POSTED")" "1"
check "park_issue: an owner wait says how to answer" "$(grep -c '^\*\*To answer:\*\* reopen it' <<< "$POSTED")" "1"
check "park_issue: an owner wait, the tag is still the last line above the mark" "$(grep . <<< "$POSTED" | tail -n 2 | head -n 1)" "[blocked-on: owner]"
check "park_issue: an owner wait promises no generic way out" "$(grep -c 'carries on from where it stopped' <<< "$POSTED")" "0"
park_issue 9 issue:50 "the paging design of issue #50 is not settled yet"
check "park_issue: a wait that clears itself asks nothing" "$(grep -c 'Nothing needed from you' <<< "$POSTED")" "1"
check "park_issue: a wait that clears itself, read back" "$(park_class "$POSTED")" "issue:50"
# Only the caller knows which way on works for an owner park (the label taken off alone re-parks an
# issue whose pull request was closed), so every owner park in the driver passes that text.
bare=$(grep -cE 'park_issue "\$n" owner(:[a-z:-]+)? "[^"]*"[[:space:]]*(;|$)' <<< "$src" || true)
check "driver: every owner park says how to answer" "$bare" "0"

# --- what reserves a wait for the owner --------------------------------------------
park_issue 10 owner:data-meaning "the marker would change what a recorded timestamp means" "**To answer:** reply \`A\` or \`B\`."
check "park_issue: an owner wait carries its item in the tag" "$(grep . <<< "$POSTED" | tail -n 2 | head -n 1)" \
  "[blocked-on: owner:data-meaning]"
check "park_issue: … and still says it needs the owner" "$(grep -c 'This needs you' <<< "$POSTED")" "1"
check "park_issue: … read back, class" "$(park_class "$POSTED")" "owner:data-meaning"
check "item: the class names it" "$(owner_item owner:physical:sudo 2026-09-01T00:00:00Z)" "physical:sudo"
# While no sweep has stamped this host, no stage could have written an item, so no park is a fault — whatever
# its date. The boundary is when this code started running here, which no date written into the file can know:
# the stamp below is what the first real sweep leaves.
check "item: with the rule not yet running here, even a park written now has none" \
  "$(owner_item owner "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" "no-item"
printf '2026-09-21T00:00:00Z\n' > "$STATE/owner-item-from"
check "item: a bare owner park written before the rule has none" "$(owner_item owner 2026-09-20T23:59:59Z)" "no-item"
check "item: … and one written since is the loop's own fault" "$(owner_item owner 2026-09-21T00:00:01Z)" "no-item-new"
check "item: an owner tag with nothing after the colon is a missing item too, not a tag it cannot read" \
  "$(owner_item owner: 2026-09-21T00:00:01Z)" "no-item-new"
check "item: a token the re-check could not read is that, not a missing item" "$(owner_item time:tomorrow 2026-09-21T01:00:00Z)" "unreadable-tag"
check "item: a park read from the issue's description predates the rule" "$(owner_item owner)" "no-item"
check "item: each reads as a sentence, and one the loop does not know is quoted" \
  "$(owner_item_says data-meaning)|$(owner_item_says 'physical:a login')|$(owner_item_says wat)" \
  "Changing what a stored field, a timestamp or a public interface means|A step only you can do: a login|A reason the loop has no words for: \`wat\`"
# The list of items is closed, and the two halves of it cannot drift apart: every item the
# prompts tell a stage to write as a tag has its own words here, so none of them can reach the owner as "a
# reason the loop has no words for", and every item these words know is named in the closed list the header
# gives a stage. The three the loop reads a park as — `no-item`, `no-item-new`, `unreadable-tag` — are not
# items a tag ever carries, so they are not in that list. (The hard-stop five are named in the header's prose
# rather than written as a tag there, so the second loop is the one that covers them. `physical:<what>` is in
# neither loop — its case label carries a `:`, which the second loop's pattern does not match — and is covered
# by the two direct checks above instead.)
for it in $(grep -oE '\[blocked-on: owner:[a-z-]+\]' "$SKILL" "$STAGES"/*.md | grep -oE 'owner:[a-z-]+' | cut -d : -f 2 | sort -u); do
  check "item: the prompts' \`$it\` has its own words" "$(owner_item_says "$it" | grep -c 'no words for')" "0"
done
for it in $(sed -n '/^owner_item_says() {/,/^}/p' "$SWEEP" | grep -oE '^ +[a-z][a-z-]*\)' | tr -d ' )'); do
  case "$it" in no-item|no-item-new|unreadable-tag) continue ;; esac
  check "item: \`$it\` is named in the closed list the header gives a stage" \
    "$(grep -qF -- "\`$it\`" "$SKILL" && echo named || echo missing)" "named"
done
# A bare `owner` park written by the loop's own code is the fault the report exists to catch, so there is none.
bare=$(grep -cE 'park_issue "\$n" owner ' <<< "$src" || true)
check "driver and sweep: no owner park of their own leaves the item out" "$bare" "0"

# --- the un-park comment: a `ready` restore with no priority label says so, in plain words
pr_of() { :; }   # no PR: the un-park restores `ready`
SWEEP_UNPARKED=""
unpark 51 "needs-decision" "issue #50 is closed"
check "unpark: no priority label, said" "$(grep -c 'not yet rated how urgent' <<< "$POSTED")" "1"
check "unpark: … in plain words" "$(grep -ciE "$SHORTHAND" <<< "$POSTED")" "0"
unpark 52 "needs-decision p1-production area:factory" "issue #50 is closed"
check "unpark: a priority label, nothing said" "$(grep -c 'how urgent' <<< "$POSTED")" "0"
check "unrated: a whole label only" "$(unrated ready "p1-production-extra readyp2-spec" | grep -c .)" "1"
check "unrated: nothing said of an issue going back in-review" "$(unrated in-review "needs-decision")" ""
check "sweep file: its fallback priority list is the driver's" \
  "$(sed -n 's/^: "\${PRIORITIES:=\(.*\)}"$/\1/p' "$SWEEP")" "${PRIORITIES-no list in the driver}"

# --- the two lines the driver reads back out of its own comments -------------------
# The loop escalates a code review that never started, and gives up on a stuck one, by finding its own
# earlier line on the pull request: review_state looks for the marker request_review posts for THIS head
# commit, and sweep_retries counts the retry markers. Both patterns anchor at the start of a line, so a
# wording change that folded either marker into the plain sentence above it would leave the loop asking
# for a review for ever and never telling the owner. Nothing held that until now, so here the driver's own
# posts are fed back to its own readers, with `gh` standing in for GitHub: what the pull request carries is
# whatever those posts left in COMMENTS.
PR=12 SHA=1a2b3c4d COMMENTS="" POST_FAILS=none READ_FAILS=0   # POST_FAILS: which write fails, as a pattern
gh() {   # the calls these three make: a pull request's merge state and head, its review runs, its comments
  local a
  case "$1 $2" in
    "pr view") case " $* " in *" .mergeStateStatus "*) echo CLEAN ;; *) echo "$SHA" ;; esac; return 0 ;;
    "run list") case " $* " in *claude-review.yml*) return 0 ;; esac   # no review run for this head, ever
                echo 2020-01-01T00:00:00Z; return 0 ;;                 # the push that did run CI, long ago
  esac
  case " $* " in *" -X "*) ;; *) [ "$READ_FAILS" = 0 ] || return 1
                                printf '%s' "$COMMENTS"; return 0 ;; esac   # every read here is its comments
  case " $* " in $POST_FAILS) return 1 ;; esac   # the argument list always has spaces, so `none` fails nothing
  for a in "$@"; do case "$a" in body=*) COMMENTS+="${a#body=}"$'\n' ;; esac; done
}
check "read back: with no marker on it, the miss is the first" "$(review_state "$PR")|$(sweep_retries "$PR")" "unrequested|0"
# Neither reader may count a comment that only writes ABOUT a marker: a session's report or a reply quotes
# one mid-sentence, and the count reads the "try k of n" shape, not any line that opens like a marker and
# names a number. The start-of-line anchor and that `/` are what tell the loop's own lines from prose about
# them — the second line below is the deliberate near-miss for the `/`.
COMMENTS+="Why was it asked for twice? The loop's own line reads \`factory: review re-requested for $SHA\`, quoted here."$'\n'
COMMENTS+="factory: sweep retry 3 was as far as this pull request got before the owner was asked."$'\n'
check "read back: writing about a marker is not a marker" "$(review_state "$PR")|$(sweep_retries "$PR")" "unrequested|0"
request_review "$PR" "no review run existed for this head"
check "re-request: the marker is the last line above the hidden mark" "$(grep . <<< "$COMMENTS" | tail -n 2 | head -n 1)" \
  "factory: review re-requested for $SHA — no review run existed for this head"
check "re-request: the driver reads its own comment back as a second miss" "$(review_state "$PR")" "unrequested-twice"
check "re-request: … and it is not one of the hourly retries" "$(sweep_retries "$PR")" "0"
SHA=9f9f9f9f
check "re-request: a marker left for an earlier commit is not this head's" "$(review_state "$PR")" "unrequested"
# The two posts an hourly retry makes — an open pull request's review re-requested, a merged one's marker
# alone — are each counted once, and at REREQUEST_MAX (3) the issue goes to the owner instead.
retry_pr 7 "$PR" OPEN "the automatic code review ended without a verdict"
check "retry count: the first try says which try it is, and counts once" "$RETRIED|$(sweep_retries "$PR")" "1/3|1"
retry_pr 7 "$PR" MERGED "no deploy has included it yet"
check "retry count: a merged pull request's marker counts too" "$RETRIED|$(sweep_retries "$PR")" "2/3|2"
# A marker that never posted would leave the count where it was and the retries would never run out, so a
# post that fails is a failed retry: it says so to its caller, which tries again next hour. Either write can
# fail — a merged pull request's marker comment, and an open one's `review` label, which is the write that
# actually asks for the review, so failing it must not leave a marker saying one was asked for.
POST_FAILS='*'; rc=0; retry_pr 7 "$PR" MERGED "no deploy has included it yet" || rc=$?; POST_FAILS=none
check "retry count: a marker that did not post is a failed retry, and is not counted" "$rc|$(sweep_retries "$PR")" "1|2"
POST_FAILS='*labels*'; rc=0; retry_pr 7 "$PR" OPEN "the automatic code review ended without a verdict" || rc=$?; POST_FAILS=none
check "retry count: an open one's unasked review is a failed retry too" "$rc|$(sweep_retries "$PR")" "1|2"
# Nor may a fetch that failed read as "no marker yet": that would restart the count at 0 every hour and the
# cap would never fire, and it would escalate a review nobody has been asked for twice.
READ_FAILS=1; rc=0; k=$(sweep_retries "$PR") || rc=$?
check "read back: a fetch that failed is not a count of none" "$(review_state "$PR")|$rc|$k" "pending|1|"
rc=0; retry_pr 7 "$PR" MERGED "no deploy has included it yet" || rc=$?; READ_FAILS=0
check "retry count: a fetch that failed is a failed retry, not a fresh count" "$rc|$(sweep_retries "$PR")" "1|2"
retry_pr 7 "$PR" MERGED "no deploy has included it yet"
retry_pr 7 "$PR" MERGED "no deploy has included it yet"
check "retry count: after three tries the issue goes to the owner" "$RETRIED" "owner"

# --- what sessions write: the templates of prompts/header.md "Comments" -------
ask=$'## Decision needed: which timestamp goes on the marker of an empty data file?\n\n**Context.** At the start of every hour a service opens a new file.\n\n**Options:**\n- **A** the start of the hour\n\n[blocked-on: owner]'
check "decision request: class" "$(park_class "$ask")" "owner"
check "decision request: the report quotes the question" "$(park_line "$ask")" \
  "Decision needed: which timestamp goes on the marker of an empty data file?"
wait=$'## Waiting: the 24-hour soak of the first production start ends at 01:10 UTC\n\nNothing needed from you.\n\n[blocked-on: time:2026-09-19T01:10:00Z]'
check "timed wait: class" "$(park_class "$wait")" "time:2026-09-19T01:10:00Z"
tagged=$'The close stage did not close this: the release check reported a failure.\n\n<sub>Tag added by the hourly re-check, read from the text above:</sub>\n[blocked-on: owner]'
check "tag appended by the re-check: class" "$(park_class "$tagged")" "owner"
check "tag appended by the re-check: reason" "$(park_line "$tagged")" \
  "The close stage did not close this: the release check reported a failure."

# --- a park comment's class is its tag, and only its tag -------------------------------------------
old=$'factory: needs-decision [blocked-on: issue:50] — waits for the paging decision'
check "one-line park: class" "$(park_class "$old")" "issue:50"
check "one-line park: reason" "$(park_line "$old")" "waits for the paging decision"
# A comment with no tag is the owner's: the loop never guesses a class that would clear itself from free text, so
# a wait that should end by itself must say so in its tag.
untagged=$'This is blocked on issue #50, and the service is not running in production yet.'
check "an untagged comment: the owner's, whatever its text names" "$(park_class "$untagged")" "owner"
check "an untagged comment: its reason is its first line" "$(park_line "$untagged")" "This is blocked on issue #50, and the service is not running in production yet."

# --- no repo shorthand in a comment the driver posts --------------------------------------------
# Every string that reaches a comment is judged, not only the lines that name `body=`: the
# reason a park or a retry is called with becomes the comment's heading, and the "To answer" text below it is
# written on another line again — one of them through two variables. So the strings of a `body=` line and of
# the arguments of a call to a function that posts one — and WHICH functions post is read out of the loop's
# own source (`posters` below), never written down here, because a list written down here went stale twice
# — plus the two functions that
# write no comment but put the owner's words in the hourly report, `ask_owner` and `queue_unpark`, whose
# surface this test does not cover. Then, grown until the set stops growing, the strings every
# variable those name is filled from — written out (`x="…"`) *or* printed by one of the loop's own functions
# (`x=$(f …)`), which is how `sweep_hold`'s reason reaches the note read_reply posts (161 strings today; the
# check fails if the growing has not settled). Exempt: the shapes the loop parses back out of its own text
# and which therefore keep their wording — the head of each of the two markers above, `review re-requested
# for <sha>` and `sweep retry k/n`, and ONLY the head, so the free prose the loop appends after it is judged
# like any other, and the `area:… in flight on issue #…` that both of sweep_hold's comment callers rewrite
# before posting — and a `log "…"` message or whatever follows a redirect, neither of which is comment text;
# `${…}` expansions are dropped. What the sweep builds for its report on the monitor issue, in its own
# SWEEP_* lines, is judged nowhere yet — its stalled-PR line included: that is a second surface,
# and this check covers comments.
posted() { sed -E 's/> \/dev\/null.*//; s/log "([^"\\]|\\.)*"//g
                   s/(factory: )?(review re-requested for \$sha|sweep retry \$RETRIED)( — |: )?//
                   s/"\$a in flight on issue #\$m"//' \
             | grep -oE '"([^"\\]|\\.)*"'; }   # a string may hold an escaped quote (\") and still be one
posters=$(awk '/^[a-z_]+\(\) \{/ { f = substr($0, 1, index($0, "(") - 1) } /^\}/ { f = "" }
               f && /-f body=/ { print f }' <<< "$src" | sort -u | paste -sd '|' -)
check "driver and sweep: the functions that post a comment are read from the source (seven since issue #246)" \
  "$(( $(tr '|' '\n' <<< "$posters" | grep -c .) >= 7 ))" "1"
judged=$( { grep -E 'body=' <<< "$src"
            grep -oE "\b(${posters:-no posters found}|ask_owner|queue_unpark) .*" <<< "$src"; } | posted)
tries="1 2 3 4 5 6 7 8"
settled="did not settle in $(wc -w <<< "$tries") passes — lengthen that list in this test"
for _ in $tries; do
  vars=$(grep -oE '\$\{?[A-Za-z_]+' <<< "$judged" | tr -d '${' | sort -u | paste -sd '|' -)
  fns=$([ -z "$vars" ] || grep -oE "\b($vars)\+?=\\\$\([a-z_]+" <<< "$src" | grep -oE '[a-z_]+$' | sort -u | paste -sd '|' -)
  grown=$(printf '%s\n%s\n%s\n' "$judged" \
    "$([ -z "$vars" ] || grep -E "\b($vars)\+?=\"" <<< "$src" | grep -v 'body=' | posted)" \
    "$([ -z "$fns" ] || awk -v fns="$fns" 'BEGIN { n = split(fns, f, "|"); for (i = 1; i <= n; i++) want[f[i]] }
         /^[a-z_]+\(\) \{/ { inf = (substr($0, 1, index($0, "(") - 1) in want) } /^\}/ { inf = 0 }
         inf && /echo |printf /' <<< "$src" | posted)" | sort -u)
  [ "$grown" = "$judged" ] && { settled=settled; break; }
  judged=$grown
done
check "driver comments: every string that reaches one is judged" "$settled" "settled"
check "driver comments: no repo shorthand" \
  "$(sed -E 's/\$\{[^}]*\}//g' <<< "$judged" | grep -iE "$SHORTHAND" | head -n 3)" ""

# --- the hidden mark on every comment the loop posts --------------------------------
# The reply check reads a comment without it as the owner's answer, so a post that forgets it resumes a
# waiting issue. Every comment post of the driver and the sweep file ends its body with the mark; the sweep
# file's fallback copy and the header's shapes carry the same string.
mark=${FACTORY_MARK-}
check "driver: it sets the mark" "$([ -n "$mark" ] && echo set)" "set"
posts=$(grep -E 'gh api -X POST "repos/\$REPO/issues/[^/"]+/comments"' <<< "$src")
check "driver and sweep: comment posts found (eight since issue #253)" "$(( $(grep -c . <<< "$posts") >= 8 ))" "1"
check "driver and sweep: every comment post ends with the mark" "$(grep -vc '"\$FACTORY_MARK" > /dev/null' <<< "$posts")" "0"
check "sweep file: its fallback mark is the driver's" "$(sed -n 's/^: "\${FACTORY_MARK:=\(.*\)}"$/\1/p' "$SWEEP")" "$mark"
shapes=$(awk '/^## Comments/ { c = 1; next } /^## verify/ { c = 0 }
  c && /^```/ { if (b) { print last; b = 0 } else { b = 1; last = "" }; next } c && b { last = $0 }' "$SKILL")
check "header: three comment shapes" "$(grep -c . <<< "$shapes")" "3"
check "header: every comment shape ends with the mark" "$(grep -vcxF -- "${mark:-no mark}" <<< "$shapes")" "0"
# The shapes written as prose ("Action needed from you", the progress note) have no block to check: the rule
# the header states once covers them (the sentence wraps, so the file is read as one line).
check "header: it states that every comment ends with the mark" \
  "$(tr '\n' ' ' < "$SKILL" | grep -cF -- "**Every comment you post ends with the line \`${mark:-no mark}\`**")" "1"
check "header: a decision is answered with a reply" "$(grep -c '^\*\*To answer:\*\* reply here' "$SKILL")" "1"
answers=$( { grep -o '\*\*To answer:\*\*[^"]*' <<< "$src"; grep '^\*\*To answer:\*\*' "$SKILL"; } | grep -c 'ready')
check "driver, sweep and header: no answer asks for a label" "$answers" "0"

# --- autonomy v3: a stage decides, and only a reserved item stops one ---------------
check "header and rules: neither tells a stage to stop for a missing metric or a recommended default" \
  "$(grep -ciE 'not guess metrics|propose them on the issue|Metrics must already exist' "$SKILL" "$RULES" | paste -sd ' ' -)" \
  "$SKILL:0 $RULES:0"
check "header and rules: each says a recommended default is a decision" \
  "$(tr '\n' ' ' < "$SKILL" | grep -cF 'A recommended default is a decision, never a question') $(tr '\n' ' ' < "$RULES" | grep -cF 'A recommended default is a decision, never a question')" \
  "1 1"
check "header: the question shape carries the item in its tag" "$(grep -cx '\[blocked-on: owner:<item>\]' "$SKILL")" "1"

echo "factory-comments-test: $fails failure(s)"
[ "$fails" = 0 ]

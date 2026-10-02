# shellcheck shell=bash
# The factory's hourly sweep, and the owner's-reply check each fast tick runs. Not a program:
# scripts/factory-tick.sh sources it once per fast tick (scripts/factory-label-audit.sh too, for park_comment and
# park_class), and it runs on the driver's settings (SWEEP_H, PR_STALL_H, REREQUEST_MAX, …) and functions (log,
# park_issue, with_issue_lock, …) and on those of scripts/factory-stage.sh, which the driver loads too
# (review_state, release_state, cleanup_issue, …).

# The driver's FACTORY_MARK and PRIORITIES, set here when they are not: for the label audit, which loads this file
# without the driver.
: "${FACTORY_MARK:=<!-- claude-factory -->}"
: "${PRIORITIES:=p1-production p2-product p3-tooling}"
# jq defs over one comment (--arg mark "$FACTORY_MARK"): `marked` = the loop posted it, `tagged` = it carries a
# `[blocked-on: …]` token. Both read only the comment's own lines: a reply made with "Quote reply" copies the
# question behind "> ", its mark and token too, and it is still the owner's reply.
COMMENT_JQ='def own: (.body // "") | split("\n") | map(select(test("^\\s*>") | not));
  def marked: own | any(startswith($mark));
  def tagged: own | any(test("\\[blocked-on: [^\\]]+\\]"));'

# ---- The sweep ---------------------------------------
# Parking was one-way: only a `close` stage un-parked, and only the issues naming its own, so on
# 2026-09-18 eleven parked issues waited on conditions that had cleared hours before. Once per
# SWEEP_H, after the fast lane's tick, the sweep reads every parked issue's class — the
# `[blocked-on: …]` token of the comment that parked it, inferred from the text and written in once
# for a comment older than the token — clears the `issue:` / `time:` parks whose condition
# is gone, retries `ci` parks through their PR (REREQUEST_MAX per PR, then `owner`), looks at every idle
# `issue-<n>` PR, tidies up (sweep_tidy), reads the "blocked by" links between open issues for what an owner
# question holds up and for circles (sweep_deps), and posts one report on the monitor issue only when it differs
# from the last one posted. An `owner` park is never cleared here: the report asks the owner, grouped by the
# item its class names — what reserves it for the owner. The class names the
# label: `waiting` for a wait the loop ends, `needs-decision` for `owner`, and no stage label.

# The comment that parked issue N, as one JSON object. The issue last started waiting when a wait label
# (`waiting`, `needs-decision`) went on while it had none, so a re-park or a swap between the two moves
# nothing. The loop comments first and a session may label first, so the park is the latest of the loop's own
# comments (FACTORY_MARK) with a `[blocked-on: …]` token posted from 10 min before that on; else, for a park
# older than the mark or a comment that forgot it, the latest comment with a token posted from then
# on, else the latest comment posted up to 10 min after the wait began. The mark and the token count only on a
# comment's own lines (COMMENT_JQ), so a reply that quotes the question is not the park, and the token tells a
# quick reply from an unmarked question: without them, an owner's "Agree with option A" would read as the park. Empty when the issue has no comment.
park_comment() {
  local n="$1" ev e l ts on="" at="" from="" cut all
  ev=$(gh api "repos/$REPO/issues/$n/events" --paginate \
         --jq '.[] | select((.event == "labeled" or .event == "unlabeled") and (.label.name == "needs-decision" or .label.name == "waiting")) | "\(.event) \(.label.name) \(.created_at)"') || return 1
  while read -r e l ts; do
    case "$e" in
      labeled) [ -n "$on" ] || at=$ts; case "$on " in *" $l "*) ;; *) on+=" $l" ;; esac ;;
      unlabeled) on=${on/ $l/} ;;
    esac
  done <<< "$ev"
  [ -z "$at" ] || from=$(date -u -d "@$(( $(date -d "$at" +%s) - 600 ))" +%FT%TZ)
  cut=$(date -u -d "@$(( $(date -d "${at:-2100-01-01T00:00:00Z}" +%s) + 600 ))" +%FT%TZ)
  all=$(gh api "repos/$REPO/issues/$n/comments" --paginate --jq '.[] | {id, html_url, created_at, body}') || return 1
  [ -z "$all" ] || jq -sc --arg from "$from" --arg cut "$cut" --arg mark "$FACTORY_MARK" \
    "$COMMENT_JQ"'
     ([.[] | select(.created_at >= $from and marked and tagged)] | last)
     // ([.[] | select(.created_at >= $from and tagged)] | last)
     // ([.[] | select(.created_at <= $cut)] | last) // empty' <<< "$all"
}

# A park comment's class: its `[blocked-on: …]` token. A park comment with none — written by hand, or by a stage that
# forgot it — is `owner`: never a class that clears itself, so a question is never answered by the loop guessing.
park_class() {
  local b="$1" t
  t=$(grep -oE '\[blocked-on: [^]]+\]' <<< "$b" | head -n 1 || true)
  if [ -n "$t" ]; then t=${t#"[blocked-on: "}; echo "${t%]}"; return; fi
  echo owner
}

# When the rule that a park needing the owner says why began running ON THIS HOST: stamped by the first sweep
# that runs and never rewritten afterwards. Read from that stamp, not written here as a date: a park comment
# written before an install could not know the rule, and a date guessed here would read it as a fault the loop
# never committed — on every hourly report from then on, since a park comment's time never moves.
# A park comment written before the stamp could not carry an item (no stage knew of one), and while there is
# no stamp none could: both read `no-item`. One written from the stamp on that carries none is a fault in the
# stage that wrote it, which should have decided the question itself, and the report says so rather than
# passing it on to the owner as a question.
owner_item_from() { cat "$STATE/owner-item-from" 2> /dev/null || true; }
owner_item_stamp() { [ -e "$STATE/owner-item-from" ] || date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE/owner-item-from"; }

# The item of an owner park — what reserves it for the owner: the `owner:<item>` of class C, one of the
# closed list the prompt header gives every stage (the hard stops `data`, `data-meaning`, `spec`, `force-push`,
# `money-credentials` and the project's own `hard-stop:<name>`; `physical:<what>`; and the loop's own
# `ci-exhausted`, `pr-closed`, `review-findings`, `design-divergence`, `production`, `unsaved-work`, plus this
# file's own `filed-waiting`). A bare `owner`, and an `owner:` with nothing after it, have
# none: `no-item`, or `no-item-new` when the park comment (posted AT; empty for a park read from the
# issue's description, which predates the rule) is from the stamp above on. Any other class reached the
# owner because the sweep could not read it (`unreadable-tag`), which is not a missing item.
# AT is compared as text with the stamp, as the "blocked by" reads do: both instants are RFC 3339 UTC with a
# `Z`, one format, so their text order is their time order.
owner_item() {
  local from
  case "$1" in
    owner:?*) printf '%s' "${1#owner:}"; return ;;
    owner|owner:|"") ;;
    *) echo unreadable-tag; return ;;
  esac
  from=$(owner_item_from)
  if [ -n "${2:-}" ] && [ -n "$from" ] && [[ ! $2 < $from ]]; then echo no-item-new; else echo no-item; fi
}

# What an item means to the owner, as the heading of its group in the report (CLAUDE.md "Writing for the
# owner": say the thing, not its label). An item the loop does not know is quoted as it was written.
owner_item_says() {
  case "$1" in
    data) echo "Deleting or rewriting data the project keeps" ;;
    data-meaning) echo "Changing what a stored field, a timestamp or a public interface means" ;;
    spec) echo "Weakening a rule the project calls non-negotiable, or editing its specification" ;;
    force-push) echo "Rewriting the history of a branch" ;;
    money-credentials) echo "Spending money, or using credentials or an account" ;;
    hard-stop:*) echo "A step the project's rules reserve for you: ${1#hard-stop:}" ;;
    physical:*) echo "A step only you can do: ${1#physical:}" ;;
    ci-exhausted) echo "An automatic review or release check that kept failing, so the loop stopped retrying" ;;
    pr-closed) echo "A pull request closed without being merged, or a branch that never had one, so only you can say whether the work is still wanted" ;;
    review-findings) echo "Two rounds of automatic review left something serious unfixed" ;;
    design-divergence) echo "A change that would diverge from a decision already recorded" ;;
    production) echo "A service in production only you can repair, revert or release again — the loop never changes production by itself" ;;
    unsaved-work) echo "Changes in a working folder that were never committed, which the loop will not throw away" ;;
    filed-waiting) echo "An issue filed already waiting, with the reason in its own description — the loop cannot tell what would end it" ;;
    unreadable-tag) echo "A wait the loop could not read, so it cannot end it either" ;;
    no-item-new) echo "No reason given for why this needs you — the loop should have decided these itself, so each one is a fault in the loop" ;;
    no-item) echo "No reason given for why this needs you (parked before the loop had to give one)" ;;
    *) echo "A reason the loop has no words for: \`$1\`" ;;
  esac
}

# The line of a park comment that says why: the first one that is not the backfill note, without the
# driver's prefix, the token or markdown bold, cut to 200 characters.
park_line() {
  local l
  l=$(grep -vE '^[[:space:]]*$|^\[blocked-on: [^]]*\] — class inferred' <<< "$1" | head -n 1 || true)
  l=${l//\*\*/}; l=${l#factory: needs-decision }; l=${l#\[blocked-on: *\] }; l=${l#— }
  while [ "${l#\#}" != "$l" ]; do l=${l#\#}; done; l=${l# }; l=${l#Waiting: }
  printf '%s' "${l:0:200}"
}

# A `time:` instant the loop can act on, printed as seconds since the epoch, and nothing on one it cannot.
# Here rather than inside `cleared` because the label audit judges a wait by the same rule and
# must judge it by the whole rule: the shape — UTC with a `Z` and nothing else, no offset, no local time, no
# duration — *and* a date that exists, since `2026-09-31T00:00:00Z` has the shape
# and is no day. Both ways an instant the loop cannot read is the owner's, not a breach of the label rules.
TIME_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$'
time_instant() { [[ $1 =~ $TIME_RE ]] && date -u -d "$1" +%s 2> /dev/null; }

# What cleared an `issue:<n>` or `time:<instant>` park; fails while it holds (1; a `time:` park prints the hours
# left) and on a token it cannot read (2). An instant has the shape above and must parse.
cleared() {
  local c="$1" at left
  case "$c" in
    time:*)
      at=$(time_instant "${c#time:}") || return 2
      left=$(( at - $(date -u +%s) ))
      [ "$left" -le 0 ] || { echo "$(( (left + 3599) / 3600 ))h left"; return 1; }
      echo "the set time ${c#time:} has passed" ;;
    issue:*) [ "$(issue_state "${c#issue:}" 2>/dev/null)" = CLOSED ] || return 1; echo "issue #${c#issue:} is closed" ;;
    *) return 1 ;;
  esac
}

# What the loop says when it puts `ready` (TO) back on an issue whose labels (L) hold no whole priority label (issue
# #181): the pick sorts it last, and the loop never guesses a class — `verify` sets one before it parks, so this is an
# issue filed waiting, or parked before that order. Empty otherwise. Both ways the loop puts `ready` back say it: the
# sweep's unpark and the owner's reply (read_reply), in the comment and the log.
unrated() {
  local p
  [ "$1" = ready ] || return 0
  for p in $PRIORITIES; do case " $2 " in *" $p "*) return 0 ;; esac; done
  echo "the loop has not yet rated how urgent it is, so it waits behind every issue that has been rated"
}

# Un-parks issue N: its stage label back by resume_label's rule (in-review when its PR is open or merged,
# else ready) and its wait labels off, through set_state — the stage label on first, each step checked
# (`set -e` is off under `with_issue_lock … || true`), so a failed call leaves the issue waiting, never
# label-less — and one comment naming what cleared, with unrated's note. Priority labels are never touched
# Back in
# flight at once unless it goes back to `ready` (the pick gates those), so it takes a slot of SWEEP_ROOM
# and its areas (sweep_hold) or waits for the next sweep: the sweep never lifts the loop past MAX_IN_FLIGHT.
unpark() {
  local n="$1" labels="$2" why="$3" restore hold said lead="Back in the queue" ends=" The loop carries on by itself."
  # Its wait is over, but an issue the owner set aside — or one that is never built as one piece — stays out
  # of the queue whatever stage label goes back on. Saying "the loop carries on
  # by itself" there would be the opposite of what happens.
  case " $labels " in
    *" hold "*) lead="The wait is over"; ends=" It stays out of the loop's queue while it carries the label \`hold\`, which only you put on and take off." ;;
    *" tracking "*) lead="The wait is over"; ends=" It stays out of the loop's queue while it carries the label \`tracking\`, which marks an issue that is never built in one piece." ;;
  esac
  restore=$(resume_label "$n")
  if [ "$restore" != ready ]; then
    if hold=$(sweep_hold "$n" "$labels"); then queue_unpark "$n" "$why" "$hold"; return 0; fi
    SWEEP_ROOM=$((SWEEP_ROOM - 1)); SWEEP_BUSY+="$n $labels"$'\n'
  fi
  said=$(unrated "$restore" "$labels"); said="label \`$restore\` put back${said:+; $said}"
  if [ "$DRY" = 0 ]; then
    set_state "$n" "$labels" "$restore" || { log "sweep: issue #$n — could not put \`$restore\` back and take its wait label off; still waiting"; return 1; }
    gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$lead: $why ($said).$ends Nothing needed from you."$'\n\n'"$FACTORY_MARK" > /dev/null \
      || log "sweep: issue #$n — un-parked, but the comment did not post"
  fi
  SWEEP_SETTLED=1
  SWEEP_UNPARKED+="  issue #$n: $why — $said"$'\n'
  log "sweep: issue #$n un-parked — $why ($said)"
}

# Keeps issue N (labels L) waiting under WANT, the label its class names: WANT on first, then
# the other wait label and any stage label but `ready` (a person's word that the wait is over, which the
# fast lane reads: resume_answered) off, through set_state. One report line when it changed anything;
# fails when a label did not change.
hold_as() {
  local n="$1" labels="$2" want="$3" add="$3" off="" l what=""
  case " $labels " in *" $want "*) add="" ;; esac
  for l in waiting needs-decision in-progress in-review; do
    [ "$l" = "$want" ] || case " $labels " in *" $l "*) off+=" $l" ;; esac
  done
  [ -n "$add$off" ] || return 0
  [ "$DRY" = 1 ] || set_state "$n" "$off" "$want" || { log "sweep: issue #$n — not fully relabelled $want; next sweep"; return 1; }
  case "$add" in
    waiting) what="labelled \`waiting\`: the loop ends this wait by itself" ;;
    needs-decision) what="labelled \`needs-decision\`: only the owner ends this wait" ;;
  esac
  # shellcheck disable=SC2086   # one word per label
  [ -z "$off" ] || what+="${what:+; }removed while it waits:$(printf ' `%s`' $off)"
  tidied "$n" "$what"
}

# One tidy-up line for the report, and the log.
tidied() { SWEEP_TIDIED+="  issue #$1: $2"$'\n'; log "sweep: issue #$1 — $2"; }

# The slots left under MAX_IN_FLIGHT (SWEEP_ROOM) and the in-flight lines (SWEEP_BUSY) sweep_hold judges by, read
# as run_lane's pick reads them: step 1 advances every in-flight issue, so an un-park past them would burst.
# Fails when the in-flight issues did not list.
read_room() {
  SWEEP_BUSY=$(inflight_labels) || return 1
  SWEEP_ROOM=$(( MAX_IN_FLIGHT - $(grep -c . <<< "$SWEEP_BUSY" || true) ))
  [ -z "$SWEEP_BUSY" ] || SWEEP_BUSY+=$'\n'
}

# Why issue N (labels L) cannot go back in flight now, if it cannot: no slot left under MAX_IN_FLIGHT, or
# an issue in flight shares one of its `area:` labels. Fails when it can.
sweep_hold() {
  if [ "$SWEEP_ROOM" -le 0 ]; then echo "no free work slot (the loop works on at most $MAX_IN_FLIGHT issues at a time)"; return 0; fi
  area_clash "$1" "$2" "$SWEEP_BUSY"
}

# A cleared park that cannot go back in flight yet (sweep_hold's reason): it stays parked, and the next
# sweep un-parks it.
queue_unpark() {
  SWEEP_QUEUED+="  issue #$1: $2 — $3"$'\n'; SWEEP_KEYS+="queued issue #$1"$'\n'
  log "sweep: issue #$1 — $2; $3 — next sweep"
}

# An `owner` park: the report's "needs you" quotes why it waits under the heading of its ITEM — what reserves it
# for the owner — and names the open issues GitHub lists as blocked
# by it (sweep_deps), so the cost of an open question shows; `needs-decision` makes it a label query. One the owner
# already answered, whose reply waits its turn (resume_replied), is listed with the queued instead. The item keys
# the group, and the report's keys too, so a park that gains one posts a new report.
ask_owner() {
  local n="$1" title="$2" labels="$3" q="$4" url="${5:-}" item="${6:-no-item}" was="" held l
  read -r _ was < "$STATE/issue-$n.replied" 2> /dev/null || true
  if [ "$was" = queued ]; then
    SWEEP_QUEUED+="  issue #$n $title: you replied, and it resumes by itself when its turn comes"$'\n'; SWEEP_KEYS+="queued issue #$n"$'\n'
  else
    held=$(grep "^$n " <<< "$SWEEP_BLOCKS" | cut -d ' ' -f 2 | sort -nu | paste -sd ' ' - || true)
    SWEEP_NEEDS_BY["$item"]+="    issue #$n $title"$'\n'"      ${q:-(no park comment)}${url:+ — $url}"$'\n'
    # shellcheck disable=SC2086   # one word per issue
    [ -z "$held" ] || { l=$(printf 'issue #%s, ' $held); SWEEP_NEEDS_BY["$item"]+="      blocked by this issue on GitHub, so your answer also frees: ${l%, }"$'\n'; }
    SWEEP_KEYS+="needs issue #$n $item${held:+ frees $held}"$'\n'
  fi
  SWEEP_SETTLED=1
  hold_as "$n" "$labels" needs-decision || true
}

# How many times the sweep has retried PR P: the markers its retries leave on the PR.
sweep_retries() {
  local b; b=$(gh api "repos/$REPO/issues/$1/comments" --paginate --jq '.[].body') || return 1
  grep -cE '^factory: (review re-requested for [0-9a-f]+ — )?sweep retry [0-9]+/' <<< "$b" || true
}

# One more retry of issue N's PR P in state S: its review re-requested when open — a merged PR's close
# gate asks the release check again by itself, so it gets the marker only — or, at REREQUEST_MAX, the
# issue parked `owner` instead. Sets RETRIED to "k/max" or "owner"; fails when nothing could be done.
retry_pr() {
  local n="$1" pr="$2" st="$3" why="$4" k a
  k=$(sweep_retries "$pr") || { log "sweep: PR #$pr — its comments did not load; next sweep"; return 1; }
  if [ "$k" -ge "$REREQUEST_MAX" ]; then
    if [ "$st" = OPEN ]; then
      a="**To answer:** look at PR #$pr. Once its automatic review has a result (taking its \`review\` label off and putting it back asks for one), reply here and the loop carries on from the review. If the change is not wanted, close that pull request and this issue."
    else
      a="**To answer:** check why the project's release check still does not say PR #$pr is released (its output is in $STATE/release-check.log on the host). Once it is released, reply here and the loop reads the outcome and finishes this issue."
    fi
    park_issue "$n" owner:ci-exhausted "the loop retried PR #$pr $k times, an hour apart, and it still fails: $why" "$a"
    RETRIED=owner; return 0
  fi
  k=$((k + 1)); RETRIED="$k/$REREQUEST_MAX"
  if [ "$st" = OPEN ]; then
    request_review "$pr" "sweep retry $RETRIED: $why" || { log "sweep: PR #$pr — its review re-request did not post; next sweep"; return 1; }
  elif [ "$DRY" = 0 ]; then
    # Unchecked, a marker that never posts would keep the count at 0 and the cap would never fire.
    gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="This pull request is merged, but the project's release check does not yet say it is released. The loop looks again in an hour. Nothing needed from you."$'\n\n'"factory: sweep retry $RETRIED — $why"$'\n\n'"$FACTORY_MARK" > /dev/null \
      || { log "sweep: PR #$pr — its retry marker did not post; next sweep"; return 1; }
  fi
}

# A `ci` park — a transient review / CI / release failure. Cleared when the PR's state has moved on
# (a verdict, a run in flight, a release outcome); else retried: an open PR's review re-requested and
# the issue un-parked, a merged PR's stalled release only counted (un-parked, it would re-park on the
# next tick) until the cap hands it to the owner.
retry_ci() {
  local n="$1" labels="$2" title="$3" why="$4" pr st now hold a="$CLOSED_PR_ANSWER"
  read -r pr st <<< "$(pr_of "$n")"
  case "$st" in
    OPEN) now=$(review_state "$pr") ;;
    MERGED) now=$(release_state "$pr") ;;
    *) # pr_of prints nothing when the branch never had a pull request, so st is empty and this
       # branch parks the issue as MISSING — the loop cannot retry a pull request that is not there.
       [ "$st" = CLOSED ] || { st=MISSING; a="**To answer:** reply here and the loop builds the change again and opens a new pull request. If the work is not wanted, close this issue."; }
       park_issue "$n" owner:pr-closed "this issue was waiting for a retry of its pull request, but that pull request (branch issue-$n) is ${st,,}: $why" "$a"
       ask_owner "$n" "$title" needs-decision "waiting for a retry of its pull request, which is ${st,,}: $why" "" pr-closed; return ;;   # park_issue relabelled it
  esac
  case "$st:$now" in
    OPEN:verdict|OPEN:skipped|OPEN:pending|OPEN:conflict|MERGED:green|MERGED:failed|MERGED:none)
      log "sweep: issue #$n — PR #$pr now reads $now"
      unpark "$n" "$labels" "the automatic review or release of PR #$pr moved on by itself"; return ;;
  esac
  # A retry un-parks: while it cannot go back in flight it waits, its retry not spent.
  if [ "$st" = OPEN ] && hold=$(sweep_hold "$n" "$labels"); then queue_unpark "$n" "due for another try at the automatic review of PR #$pr ($why)" "$hold"; return; fi
  retry_pr "$n" "$pr" "$st" "$why" || return 0
  if [ "$RETRIED" = owner ]; then
    ask_owner "$n" "$title" needs-decision "the hourly retries ran out: $why" "" ci-exhausted   # retry_pr's park relabelled it
  elif [ "$st" = OPEN ]; then
    unpark "$n" "$labels" "the loop asked again for the automatic review of PR #$pr (try $RETRIED), after: $why"
  else
    log "sweep: issue #$n — still no release outcome for PR #$pr (sweep retry $RETRIED)"
  fi
}

# One parked issue: its class (the token, or inferred and written in once), then clear, retry or ask. One
# that stays parked and is not the owner's keeps `waiting` and no stage label.
sweep_issue() {
  local n="$1" labels="$2" title="$3" pc body cid url at class how=token why rc
  case " $labels " in *" ready "*) log "sweep: issue #$n — it carries \`ready\`, which the next fast tick reads (resume_answered)"; return 0 ;; esac
  pc=$(park_comment "$n") || { log "sweep: issue #$n — its events or comments did not load; next sweep"; return 0; }
  if [ -z "$pc" ]; then
    # Filed parked, so the reason is the issue body; only its first paragraph states a blocker (a
    # design body names other issues in passing). Bodies are never edited: the token goes in a comment.
    pc=$(gh issue view "$n" --repo "$REPO" --json body,url --jq '{body: ((.body // "") | split("\n\n") | first // ""), html_url: .url}') \
      || { log "sweep: issue #$n — its body did not load; next sweep"; return 0; }
    how=body
  fi
  body=$(jq -r '.body // ""' <<< "$pc"); cid=$(jq -r '.id // ""' <<< "$pc"); url=$(jq -r '.html_url // ""' <<< "$pc")
  at=$(jq -r '.created_at // ""' <<< "$pc")   # when the park was written: owner_item judges a missing item by it
  class=$(park_class "$body")
  if [ "$how" = body ]; then
    # This comment is the sweep's own bookkeeping, and the next sweep reads it back as the park. A bare
    # `owner` on it would then be read as a stage that failed to decide — and reported to the owner as a
    # fault in the loop, every hour — so it carries the sweep's own item instead: the reason is the issue's
    # own description, which no stage wrote.
    [ "$class" != owner ] || class=owner:filed-waiting
    body="## Waiting: this issue was filed already waiting, and the reason is in its description above"$'\n\n'"The hourly re-check read that reason and tagged it so it knows when to look again."$'\n\n'"[blocked-on: $class]"
    [ "$DRY" = 1 ] || gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$body"$'\n\n'"$FACTORY_MARK" > /dev/null || log "sweep: issue #$n — could not post its class token"
  elif ! grep -qE '\[blocked-on: [^]]+\]' <<< "$body"; then
    how=inferred
    if [ -n "$cid" ] && [ "$DRY" = 0 ]; then
      gh api -X PATCH "repos/$REPO/issues/comments/$cid" \
        -f body="$body"$'\n\n'"<sub>Tag added by the hourly re-check, read from the text above:</sub>"$'\n'"[blocked-on: $class]" > /dev/null \
        || log "sweep: issue #$n — could not write the class token into $url"
    fi
  fi
  log "sweep: issue #$n — [blocked-on: $class] ($how)"
  SWEEP_PARKED+="$n"$'\t'"$class"$'\t'"$(park_line "$body")"$'\n'   # the line the live board reads
  SWEEP_SETTLED=""   # unpark and ask_owner set it: they label the issue themselves
  case "$class" in
    issue:*|time:*)
      rc=0; why=$(cleared "$class") || rc=$?
      case "$rc" in
        0) unpark "$n" "$labels" "what it was waiting for has happened — $why" ;;
        2) ask_owner "$n" "$title" "$labels" "the token \`$class\` could not be read (an instant is UTC: YYYY-MM-DDTHH:MM[:SS]Z) — $(park_line "$body")" "$url" "$(owner_item "$class" "$at")" ;;
        *) log "sweep: issue #$n — $class still holds${why:+ ($why)}"
           if [[ $class == time:* ]]; then   # the report shows every wait on a clock
             SWEEP_WAITS+="  issue #$n $title — until ${class#time:} ($why)"$'\n'; SWEEP_KEYS+="waits issue #$n $class"$'\n'
           fi ;;
      esac ;;
    ci) retry_ci "$n" "$labels" "$title" "$(park_line "$body")" ;;
    *) ask_owner "$n" "$title" "$labels" "$(park_line "$body")" "$url" "$(owner_item "$class" "$at")" ;;   # owner, or a token it cannot read
  esac
  [ -n "$SWEEP_SETTLED" ] || hold_as "$n" "$labels" waiting || true
}

# Every open `issue-<n>` PR whose issue is not parked (a parked one is handled above) and that has had
# no new commit and no new verdict for PR_STALL_H: re-request a review nobody asked for, report the
# rest with a recommendation. Nothing is closed here — a PR that looks obsolete is the owner's call.
sweep_prs() {
  local list x pr n st labels title info last files red age line rs why
  list=$(gh pr list --repo "$REPO" --state open --limit 100 --json number,headRefName \
           --jq '.[] | select(.headRefName | test("^issue-[0-9]+$")) | "\(.number):\(.headRefName)"') || return 1
  for x in $list; do
    pr=${x%%:*}; n=${x#*:issue-}
    IFS='|' read -r st labels title <<< "$(gh issue view "$n" --repo "$REPO" --json state,labels,title \
      --jq '"\(.state)|\([.labels[].name] | join(" "))|\(.title)"' 2>/dev/null || true)"
    [ -n "$st" ] || continue
    case " $labels " in *" needs-decision "*|*" waiting "*) continue ;; esac
    info=$(gh pr view "$pr" --repo "$REPO" --json commits,comments,changedFiles,statusCheckRollup --jq '
      "\([(.commits | last | .committedDate), (.comments[] | select(.body | test("'"$VERDICT_RE"'"; "i")) | .createdAt)]
          | map(select(. != null)) | max // "")|\(.changedFiles)|\([.statusCheckRollup[]
          | select((.conclusion // .state // "") | test("^(FAILURE|ERROR|TIMED_OUT|STARTUP_FAILURE)$"))
          | (.name // .context)] | unique | join(", "))"') || continue
    IFS='|' read -r last files red <<< "$info"
    age=$(age_s "$last")
    [ "$age" -ge $((PR_STALL_H * 3600)) ] || continue
    line="PR #$pr (issue #$n, idle $((age / 3600)) h)"
    if [ "$st" = CLOSED ] || [ "$files" = 0 ]; then
      if [ "$st" = CLOSED ]; then why="issue #$n is closed"; else why="its diff against main is empty — main already carries the change"; fi
      SWEEP_STALLED+="  $line: candidate for closing — $why. The owner decides; nothing is closed automatically"$'\n'
      SWEEP_KEYS+="close-candidate PR #$pr"$'\n'
      continue
    fi
    rs=$(review_state "$pr")
    if [ "$rs" = conflict ]; then
      SWEEP_STALLED+="  $line: DIRTY — the review stage merges origin/main on its next run"$'\n'
    elif [ -n "$red" ]; then
      SWEEP_STALLED+="  $line: CI red ($red) — left as is"$'\n'; rs=ci-red
    elif [ "$rs" = unrequested ] || [ "$rs" = unrequested-twice ]; then
      RETRIED=""
      with_issue_lock "$n" retry_pr "$n" "$pr" OPEN "the automatic code review never started for its latest commit" || continue
      if [ "$RETRIED" = owner ]; then
        ask_owner "$n" "$title" needs-decision "the hourly retries of the automatic code review of PR #$pr ran out" "" ci-exhausted; continue   # retry_pr's park relabelled it
      fi
      SWEEP_STALLED+="  $line: the automatic code review never started for its latest commit — asked again (try $RETRIED)"$'\n'; rs="retry-$RETRIED"
    else
      SWEEP_STALLED+="  $line: review state \`$rs\` — the loop's next stage has it"$'\n'
    fi
    SWEEP_KEYS+="stalled PR #$pr $rs"$'\n'
  done
}

# What of closed issue N's working folder D and branch issue-N exists on this host only: edits not
# committed, files never added (the build outputs and the loop's own leftovers are ignored, so they do not
# count), or commits that no branch on GitHub holds and that the issue's last pull request did not carry.
# Neither the branch nor main can say that of merged work: GitHub deletes a merged branch, and a rebase merge
# copies its commits onto main under new ids, but it keeps a pull request's last commit. A last commit missing
# here counts as unsaved. What it prints is the reason's class (edits, new-files, commits, not-worktree), a
# space and the reason. Returns:
#   0  something is unsaved (prints what);
#   1  nothing is unsaved;
#   2  GitHub could not be asked;
#   3  git cannot read the folder (prints that), such as a worktree whose .git file is gone: git stops at the
#      folder that holds the worktrees, never reading the primary checkout, which holds that folder, in its place.
unsaved() {
  local n="$1" d="$2" s head
  if [ -d "$d" ]; then
    s=$(GIT_CEILING_DIRECTORIES="${d%/*}" git -C "$d" --no-optional-locks status --porcelain 2> /dev/null) \
      || { echo "not-worktree git cannot read its working folder $d"; return 3; }
    if [ -n "$s" ]; then
      if grep -qv '^??' <<< "$s"; then echo "edits its working folder $d has uncommitted edits"; else echo "new-files its working folder $d has new files never added to git"; fi
      return 0
    fi
  fi
  git show-ref --quiet "refs/heads/issue-$n" || return 1
  head=$(gh pr list --repo "$REPO" --state all --head "issue-$n" --json number,headRefOid --jq 'sort_by(.number) | last | .headRefOid // empty') || return 2
  s=$(git rev-list "refs/heads/issue-$n" --not --remotes ${head:+"$head"} 2> /dev/null) \
    || { echo "commits its branch issue-$n may hold commits found nowhere else: its pull request's last commit is not in this checkout"; return 0; }
  [ -n "$s" ] || return 1
  echo "commits its branch issue-$n has $(grep -c . <<< "$s") commit(s) that no branch on GitHub and no pull request holds"
}

# How `git worktree list --porcelain`, read on stdin, lists the worktree at path P: "listed", then
# " locked" when it is locked; nothing when P is none of git's worktrees, such as a folder copied or made by hand.
# Git lists a path with its symlinks resolved, and never lists a locked worktree as `prunable`, even when its
# folder is gone.
wt_state() {
  local l s=""
  while IFS= read -r l; do
    case "$l" in
      "worktree "*) [ -z "$s" ] || break; [ "$l" != "worktree $1" ] || s=listed ;;
      locked|"locked "*) [ -z "$s" ] || s+=" locked" ;;
    esac
  done
  echo "$s"
}

# The owner's line for closed issue N whose working folder D or branch the tidy-up leaves: WHY, what
# of the two is left, and FIX, the step that clears it, then MORE when the branch is left. Keyed on the reason's
# class CLS, so a new reason posts a new report, with the new step. Listed under its own heading: no
# label marks it and no reply answers it. The rest of what cleanup_issue takes goes as for any closed
# issue (reap_issue: the project's cleanup, the reply record), under its lock and never in a dry run; a folder or
# branch git refused went through cleanup_issue already.
ask_keep() {
  local n="$1" d="$2" cls="$3" why="$4" fix="$5" more="${6:-}" left=""
  case "$cls" in refused|branch) ;; *) [ "$DRY" = 1 ] || with_issue_lock "$n" reap_issue "$n" || true ;; esac
  [ ! -d "$d" ] || left="its working folder"
  if git show-ref --quiet "refs/heads/issue-$n"; then left+="${left:+ and }its branch"; fix+=$more; fi
  SWEEP_KEPT+="  issue #$n (closed): $why, so the loop left ${left:-it} in place; $fix"$'\n'
  SWEEP_KEYS+="needs folder issue #$n $cls"$'\n'; log "sweep: issue #$n — closed, but $why: left in place"
}

# The tidy-up: what a hand merge, a hand close or a session that died between two label changes
# leaves behind. A closed issue loses its state labels, and its working folder and branch go through
# cleanup_issue — the close stage's own teardown — under its lock, unless they hold work found only on this
# host (unsaved), and the owner is asked then and when git will not remove the folder or delete the branch (a
# locked worktree, a folder that is none of git's worktrees, or cleanup_issue's CLEANUP_ERR); `ready` comes off an
# open issue that also carries `in-progress` or `in-review`, the label stage_of goes by (a waiting one keeps it:
# resume_answered reads it). One report line each; a failed query skips its part until the next sweep.
sweep_tidy() {
  local l x n ls d why rc fix wl ws unlock lk lock
  for l in ready in-progress in-review waiting needs-decision; do
    x=$(gh issue list --repo "$REPO" --state closed --label "$l" --limit 100 --json number --jq '.[].number') \
      || { log "sweep: listing the closed issues labelled $l failed — next sweep"; continue; }
    for n in $x; do
      [ "$DRY" = 1 ] || gh api -X DELETE "repos/$REPO/issues/$n/labels/$l" > /dev/null || { log "sweep: issue #$n — could not remove $l"; continue; }
      tidied "$n" "closed, so its label \`$l\` was removed"
    done
  done
  # Every issue-<n> worktree and local branch (cwd is ROOT): an `issue-12-x` is none of the loop's.
  x=$(for d in "$ROOT"/.claude/worktrees/issue-* $(git for-each-ref --format='%(refname:lstrip=2)' 'refs/heads/issue-*'); do
        echo "${d##*issue-}"; done)
  for n in $(grep -xE '[0-9]+' <<< "$x" | sort -nu); do
    [ "$(issue_state "$n" 2> /dev/null)" = CLOSED ] || continue
    d="$ROOT/.claude/worktrees/issue-$n"
    # What the folder is comes from git's own list of its worktrees, read before any try, so a dry run reports it
    # as the sweep does, and for each issue, as cleanup_issue prunes stale records on the way. A locked
    # worktree (`git worktree lock`), which `git worktree remove --force` refuses, names its unlock first whatever
    # else keeps it. One whose folder was deleted by hand still holds its branch, because `git worktree
    # prune` keeps a locked record: its unlock is the step that works.
    wl=$(git worktree list --porcelain) || { log "sweep: issue #$n — git did not list its worktrees: left in place; next sweep"; continue; }
    ws=$(wt_state "$(realpath -m "$d")" <<< "$wl")
    unlock="" lk="" lock=""
    case "$ws" in *locked)
      unlock="\`git worktree unlock $d\`, then "
      if [ -d "$d" ]; then lk=locked lock="the folder is also locked"
      else lk=deleted-locked lock="its working folder $d was deleted by hand while locked, and git keeps a locked folder's record, which holds the branch"; fi ;;
    esac
    # A folder git does not list, a copy made by hand say, is none of its worktrees: nothing in git removes it.
    rc=0
    if [ -d "$d" ] && [ -z "$ws" ]; then why="unlisted its working folder $d is none of git's worktrees"; rc=3
    else why=$(unsaved "$n" "$d") || rc=$?; fi
    case "$rc" in
      0) fix="once that work is saved or not wanted, $unlock\`$HERE/factory-tick.sh --cleanup $n\` removes what is left"
         ask_keep "$n" "$d" "${why%% *}${lk:+ $lk}" "${why#* }" "${lock:+$lock: }$fix"; continue ;;
      3) ask_keep "$n" "$d" "${why%% *}" "${why#* }" "neither the loop nor \`--cleanup\` removes it: once its work is saved or not wanted, delete the folder by hand" \
           ", and the next sweep handles the branch"; continue ;;
      2) log "sweep: issue #$n — its pull request did not load, so its unsaved commits are unknown: left in place; next sweep"; continue ;;
    esac
    case "$lk" in
      locked) ask_keep "$n" "$d" locked "git will not remove its working folder $d: it is locked" \
                "once nothing uses it, $unlock\`$HERE/factory-tick.sh --cleanup $n\` removes what is left"; continue ;;
      deleted-locked) ask_keep "$n" "$d" deleted-locked "$lock" "$unlock\`$HERE/factory-tick.sh --cleanup $n\` deletes it"; continue ;;
    esac
    CLEANUP_ERR=""
    [ "$DRY" = 1 ] || with_issue_lock "$n" cleanup_issue "$n" || {
      # An empty CLEANUP_ERR: cleanup_issue did not run, its issue's lock held elsewhere. Else the folder stays, or
      # only the branch does.
      if [ -z "$CLEANUP_ERR" ]; then log "sweep: issue #$n — its working folder was not removed; next sweep"
      elif [ -d "$d" ]; then ask_keep "$n" "$d" refused "git would not remove its working folder $d (\`$CLEANUP_ERR\`)" \
             "\`$HERE/factory-tick.sh --cleanup $n\` removes what is left once git can remove the folder"
      else ask_keep "$n" "$d" branch "git would not delete its branch issue-$n (\`$CLEANUP_ERR\`)" \
             "once no folder has it checked out (git names the folder; the primary checkout counts), \`$HERE/factory-tick.sh --cleanup $n\` deletes it"; fi
      continue; }
    # A dry run asks git nothing, so it cannot tell which of these git will refuse.
    if [ "$DRY" = 1 ]; then tidied "$n" "closed, so its working folder and branch go, unless git refuses to remove them (a dry run does not try)"
    else tidied "$n" "closed, so its working folder and branch were removed"; fi
  done
  x=$(gh issue list --repo "$REPO" --state open --label ready --limit 100 --json number,labels --jq '.[] | [.labels[].name] as $l
        | select(($l | index("waiting") or index("needs-decision") | not) and ($l | index("in-progress") or index("in-review")))
        | "\(.number) \(if ($l | index("in-review")) then "in-review" else "in-progress" end)"') \
    || { log "sweep: listing the ready issues failed — next sweep"; return 0; }
  while read -r n ls; do
    [ -n "$n" ] || continue
    [ "$DRY" = 1 ] || gh api -X DELETE "repos/$REPO/issues/$n/labels/ready" > /dev/null || { log "sweep: issue #$n — could not remove ready"; continue; }
    tidied "$n" "\`ready\` removed: it also carried \`$ls\`, the later state"
  done <<< "$x"
}

# GitHub's own "blocked by" links between open issues, one
# "<blocker> <blocked>" line each: one call lists the open issues with an open blocker, then blockers_of reads each
# one's. Fails when a read fails.
dep_pairs() {
  local list n b m
  list=$(gh api "repos/$REPO/issues?state=open&per_page=100" --paginate \
           --jq '.[] | select((.pull_request | not) and (.issue_dependencies_summary.blocked_by // 0) > 0) | .number') || return 1
  for n in $list; do
    b=$(blockers_of "$n") || return 1
    for m in $b; do echo "$m $n"; done
  done
}

# SWEEP_BLOCKS, dep_pairs' lines, for ask_owner — the last ones read ($STATE/sweep-blocks) when they do not load, so a
# failed read does not change the report's keys and post it twice — and SWEEP_LOOPS, one line per set of issues that
# wait for each other, so none of them can ever start: reported, never broken here. tsort (coreutils) names each
# loop's issues on stderr, one `tsort: <n>` line each after a header line. Fails when it finds a loop it does not name.
sweep_deps() {
  local f="$STATE/sweep-blocks" err rc=0 loop="" l
  if SWEEP_BLOCKS=$(dep_pairs); then
    [ "$DRY" = 1 ] || printf '%s\n' "$SWEEP_BLOCKS" > "$f"
  else
    SWEEP_BLOCKS=$(cat "$f" 2> /dev/null || true)
    log "sweep: GitHub's \"blocked by\" links did not load — this report uses the last ones read"
  fi
  err=$(LC_ALL=C tsort <<< "$SWEEP_BLOCKS" 2>&1 > /dev/null) || rc=$?
  while read -r _ l; do
    if [[ $l =~ ^[0-9]+$ ]]; then loop+="$l"$'\n'; continue; fi
    [ -z "$loop" ] || SWEEP_LOOPS+="$(sort -n <<< "$loop" | grep . | paste -sd ' ' -)"$'\n'
    loop=""
  done <<< "$err"$'\n'"end"
  [ "$rc" = 0 ] || [ -n "$SWEEP_LOOPS" ] || { log "sweep: tsort found a loop it did not name — ${err%%$'\n'*}"; return 1; }
  while read -r l; do [ -z "$l" ] || SWEEP_KEYS+="loop $l"$'\n'; done <<< "$SWEEP_LOOPS"
}

# One comment on the monitor issue, only when something was un-parked or tidied or the owner / stalled-PR /
# clock list differs from the last one posted (a report on what changed, not a heartbeat; a clock wait keys on its
# instant, not the hours left, so a wait posts once, not hourly): a sweep with nothing new is
# silent. A failed post is not a failed sweep — the work is done, and redoing it every tick would spend
# REREQUEST_MAX in minutes: its un-park and tidy-up lines are carried (the last 50 each; each issue's own
# un-park comment keeps the full record) and the next sweep, an hour on, posts them with its own report.
sweep_report() {
  local f="$STATE/sweep-report.txt" keys prev l
  keys=$(grep -v '^$' <<< "$SWEEP_KEYS" | sort || true)
  prev=$(cat "$STATE/sweep-posted" 2>/dev/null || true)
  {
    echo "Back in the queue this hour (what each was waiting for has happened):"
    if [ -n "$SWEEP_UNPARKED" ]; then printf '%s' "$SWEEP_UNPARKED"; else echo "  none"; fi
    [ -z "$SWEEP_QUEUED" ] || { echo "Ready to continue, but waiting for a free work slot or for another issue in the same part of the code; looked at again within ${SWEEP_H} h:"; printf '%s' "$SWEEP_QUEUED"; }
    [ -z "$SWEEP_WAITS" ] || { echo "Waiting for a set time, such as the end of a 24-hour soak; each continues by itself (hours left as of this report):"; printf '%s' "$SWEEP_WAITS"; }
    echo "Needs you — the loop cannot continue these by itself (label \`needs-decision\`; reply on the issue and the loop picks the reply up within minutes). Grouped by what only you can settle, then each line says why it waits, from the comment that parked it:"
    if [ "${#SWEEP_NEEDS_BY[@]}" = 0 ]; then echo "  none"; else
      # One heading per item, in a fixed order, so the same picture reads the same way twice.
      while IFS= read -r l; do
        [ -n "$l" ] || continue
        echo "  $(owner_item_says "$l"):"; printf '%s' "${SWEEP_NEEDS_BY["$l"]}"
      done < <(printf '%s\n' "${!SWEEP_NEEDS_BY[@]}" | sort)
    fi
    [ -z "$SWEEP_LOOPS" ] || {
      echo "Issues that wait for each other through a circle of \"blocked by\" links on GitHub, so none of them can start. The loop never breaks a circle by itself; removing one of its links on GitHub does:"
      # shellcheck disable=SC2086   # one word per issue
      while read -r l; do [ -z "$l" ] || { l=$(printf 'issue #%s, ' $l); echo "  ${l%, }"; }; done <<< "$SWEEP_LOOPS"; }
    [ -z "$SWEEP_KEPT" ] || { echo "Left on this host after the issue closed, because it holds work found nowhere else or git will not remove it (no label, nothing to reply; each line names the step that clears it):"; printf '%s' "$SWEEP_KEPT"; }
    echo "Pull requests with no new commit or review result for ${PR_STALL_H} h:"
    if [ -n "$SWEEP_STALLED" ]; then printf '%s' "$SWEEP_STALLED"; else echo "  none"; fi
    [ -z "$SWEEP_TIDIED" ] || { echo "Labels and working folders tidied up:"; printf '%s' "$SWEEP_TIDIED"; }
  } > "$f"
  if [ "$DRY" = 1 ]; then echo "--- sweep report (dry run: nothing changed, nothing posted) ---"; cat "$f"; return 0; fi
  if [ -z "$SWEEP_UNPARKED$SWEEP_TIDIED" ] && [ "$keys" = "$prev" ]; then log "sweep: nothing new — no report"; return 0; fi
  if ! "$POST" "🧹 factory sweep" "$f"; then
    printf '%s' "$SWEEP_UNPARKED" | tail -n 50 > "$STATE/sweep-carry"
    printf '%s' "$SWEEP_TIDIED" | tail -n 50 > "$STATE/sweep-carry-tidied"
    log "sweep: monitor post failed — the next sweep posts its un-park and tidy-up lines"; return 0
  fi
  printf '%s\n' "$keys" > "$STATE/sweep-posted"; rm -f "$STATE/sweep-carry" "$STATE/sweep-carry-tidied"
}

sweep() {
  local parked n labels title
  SWEEP_UNPARKED=$(cat "$STATE/sweep-carry" 2>/dev/null || true)
  [ -z "$SWEEP_UNPARKED" ] || SWEEP_UNPARKED+=$'\n'
  SWEEP_TIDIED=$(cat "$STATE/sweep-carry-tidied" 2>/dev/null || true)
  [ -z "$SWEEP_TIDIED" ] || SWEEP_TIDIED+=$'\n'
  SWEEP_KEPT=""; SWEEP_STALLED=""; SWEEP_KEYS=""; SWEEP_QUEUED=""; SWEEP_WAITS=""; RETRIED=""
  # The needs-you lines by item. `-g`: this file is sourced inside the driver's load_lib, where a
  # plain `declare` would make the array local to that call and lose every line written here.
  unset SWEEP_NEEDS_BY; declare -gA SWEEP_NEEDS_BY=()
  # The moment this rule started running here (owner_item), taken from the clock on the first real sweep that
  # has this code — never on a dry run, which changes no host state and so starts nothing.
  [ "$DRY" = 1 ] || owner_item_stamp
  SWEEP_PARKED=""
  SWEEP_BLOCKS=""; SWEEP_LOOPS=""
  read_room || { log "sweep: listing the in-flight issues failed — the next tick retries"; return 1; }
  sweep_deps || true   # before the parked issues, whose owner lines name what they hold up; it logs a failure
  # Both wait labels; an issue carrying both is listed once.
  parked=$(for l in waiting needs-decision; do
             gh issue list --repo "$REPO" --state open --label "$l" --limit 100 --json number,title,labels \
               --jq '.[] | [.number, ([.labels[].name] | join(" ")), .title] | @tsv' || exit 1
           done) || { log "sweep: listing the parked issues failed — the next tick retries"; return 1; }
  parked=$(sort -t $'\t' -k 1,1n -u <<< "$parked")
  log "sweep: $(grep -c . <<< "$parked" || true) parked issue(s), $SWEEP_ROOM in-flight slot(s) free"
  # fd 3, not stdin: nothing inside may eat the list.
  while IFS=$'\t' read -r -u 3 n labels title; do
    [ -n "$n" ] || continue
    with_issue_lock "$n" sweep_issue "$n" "$labels" "$title" || true
  done 3<<< "$parked"
  # Every parked issue's class and why, for the live board, which then names what each is waiting
  # for without re-reading its comments each tick. Rewritten whole: an issue that is no longer parked drops out.
  # Through the driver's own writer, under its lock, so a park happening in the other lane cannot leave a
  # half-written line behind. Skipped when the driver is older than this file and has no such writer — the two
  # are refreshed one after the other on the host, and that window costs only this tick's record.
  [ "$DRY" = 1 ] || ! declare -F board_parked_write > /dev/null || board_parked_write replace "$SWEEP_PARKED"
  sweep_prs || log "sweep: listing the open PRs failed — stalled PRs not checked this time"
  sweep_tidy
  sweep_report
}

# Runs the sweep when this SWEEP_H window has had none (or now, with `force`). The marker is written
# unless the sweep could not list its issues (it changed nothing then), so only that is retried on the
# next tick; a sweep that did its work is never redone within the window.
sweep_if_due() {
  local h marker
  h=$(date -u +%H)
  marker="$STATE/.sweep-$(date -u +%Y%m%d)$(printf '%02d' $(( 10#$h / SWEEP_H * SWEEP_H )))"
  [ "${1:-}" = force ] || [ ! -e "$marker" ] || return 0
  if sweep; then rm -f "$STATE"/.sweep-*; touch "$marker"; else log "sweep: incomplete — the next tick retries"; fi
}

# ---- The owner's reply ---------------------------
# The owner answers the loop's question by replying on the issue, never with a label. Every fast tick, before it
# advances anything, reads each open `needs-decision` issue (a `waiting` one is the loop's own wait, which no
# comment ends). A comment posted after the park (park_comment), not by a bot and not marked (COMMENT_JQ) is the
# owner's reply: the loop posts through the owner's account, so the author cannot tell them apart. The issue
# resumes by resume_label's rule through the gate a sweep un-park passes: one going back in flight takes a slot
# and its areas, or keeps waiting (sweep_hold), says so once and is read again next tick; one going back to
# `ready` joins the queue the pick gates. $STATE/issue-<n>.replied holds "<comment id> read|queued|resumed" for
# the latest unmarked comment judged, so each comment is judged once and each reply resumes its issue once: a
# session's comment that lacks the mark costs one session, never a loop.
resume_replied() {
  local x n ls
  x=$(gh issue list --repo "$REPO" --state open --label needs-decision --limit 100 --json number,labels \
        --jq '.[] | select([.labels[].name] | index("ready") | not) | "\(.number) \([.labels[].name] | join(" "))"') \
    || { log "listing the issues that wait for the owner failed — their replies are read next tick"; return 0; }
  [ -n "$x" ] || return 0
  read_room || { log "listing the in-flight issues failed — the owner's replies are read next tick"; return 0; }
  # fd 3, not stdin: nothing inside may eat the list.
  while read -r -u 3 n ls; do
    [ -n "$n" ] || continue
    [ -z "$ONLY" ] || [ "$n" = "$ONLY" ] || continue
    with_issue_lock "$n" read_reply "$n" "$ls" || true
  done 3<<< "$x"
}

# Issue N (labels L): its latest unmarked comment, judged as resume_replied says. Its note links that comment,
# so a session's comment taken for the owner's reply shows, and carries unrated's note.
read_reply() {
  local n="$1" ls="$2" f="$STATE/issue-$1.replied" x id="" at="" url="" seen="" was="" q to hold note sorts
  # Into a variable first: a fetch that fails in a process substitution reads as no reply, and logs nothing.
  x=$(gh api "repos/$REPO/issues/$n/comments" --paginate --jq '.[] | {id, created_at, html_url, body, bot: (.user.type == "Bot")}' \
        | jq -rs --arg mark "$FACTORY_MARK" "$COMMENT_JQ"' [.[] | select((marked or .bot) | not)] | last // empty | "\(.id) \(.created_at) \(.html_url)"') \
    || { log "issue #$n: its comments did not load — a reply is read next tick"; return 0; }
  read -r id at url <<< "$x"
  [[ $id =~ ^[0-9]+$ ]] || return 0
  read -r seen was < "$f" 2> /dev/null || true
  # Judged before: an older comment, or this one unless it waits its turn.
  if [[ $seen =~ ^[0-9]+$ ]] && { [ "$id" -lt "$seen" ] || { [ "$id" = "$seen" ] && [ "$was" != queued ]; }; }; then return 0; fi
  q=$(park_comment "$n") || { log "issue #$n: its events or comments did not load — a reply is read next tick"; return 0; }
  q=$(jq -r '.created_at // ""' <<< "$q")
  # Not after the park: no reply. No park comment at all: the question is the issue's description.
  if [ -n "$q" ] && ! [[ $at > $q ]]; then [ "$DRY" = 1 ] || echo "$id read" > "$f"; return 0; fi
  to=$(resume_label "$n")
  hold=$(sweep_hold "$n" "$ls") || hold=""
  case "$hold" in area:*) hold="issue #${hold##*#} is being worked on (building, or in code review) and touches the same part of the code (\`${hold%% in flight*}\`)" ;; esac
  if [ -n "$hold" ] && [ "$to" != ready ]; then
    log "issue #$n: the owner replied, but it waits its turn — $hold"
    if [ "$DRY" = 1 ] || { [ "$id" = "$seen" ] && [ "$was" = queued ]; }; then return 0; fi
    gh api -X POST "repos/$REPO/issues/$n/comments" -f body="[Your reply]($url) was picked up, but the work waits its turn: $hold. The loop resumes it by itself as soon as that changes. Nothing needed from you."$'\n\n'"$FACTORY_MARK" > /dev/null \
      || { log "issue #$n: its note did not post — next tick"; return 0; }
    echo "$id queued" > "$f"; return 0
  fi
  sorts=$(unrated "$to" "$ls")
  log "issue #$n: the owner replied — it resumes as $to${sorts:+; $sorts}"
  [ "$DRY" = 0 ] || return 0
  [ "$to" = ready ] || { SWEEP_ROOM=$((SWEEP_ROOM - 1)); SWEEP_BUSY+="$n $ls"$'\n'; }
  set_state "$n" "$ls" "$to" || { log "issue #$n: not fully relabelled $to — next tick"; return 0; }
  echo "$id resumed" > "$f"
  note="[Your reply]($url) was picked up; work resumes."
  [ -z "$hold" ] || note+=" It is back in the queue and starts when its turn comes: $hold."
  [ -z "$sorts" ] || note+=" ${sorts^}."
  gh api -X POST "repos/$REPO/issues/$n/comments" -f body="$note"$'\n\n'"$FACTORY_MARK" > /dev/null || log "issue #$n: resumed, but its note did not post"
}

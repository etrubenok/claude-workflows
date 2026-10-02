# shellcheck shell=bash
# The factory's live board: one pinned issue whose text always shows the current picture — what is being worked
# on, what comes next, what waits on what, what waits on the owner, and what finished today. Not a program:
# scripts/factory-tick.sh sources it once per fast tick, beside scripts/factory-sweep.sh, and it runs on the
# driver's settings (REPO, STATE, MAX_IN_FLIGHT, SLOTS, PRIORITIES, DRY) and functions (log, pr_of, area_clash).
# Three entry points: `board` reads the picture and writes the page, `board_run` does that under the board's own
# lock, which is what the driver calls, and `board_wait` keeps doing it while a stage session runs — which holds
# its lane for as long as it takes, up to two hours — so the page never looks stopped while the loop is working
# at full speed. It reads the open issues in
# ONE call, the pull request of each issue in flight (at most MAX_IN_FLIGHT of them) and the issues closed in
# the last 24 h — never a query per queued issue. What waits on what comes from two files the loop already
# writes: the "blocked by" links the hourly sweep read and each parked issue's
# class ($STATE/board-parked, appended when an issue is parked and rewritten by every sweep); the account's
# usage-limit pause comes from the driver's own marker file. The text is rewritten only when that picture
# differs from the last one written ($STATE/board.txt), or when the last write is about to reach the age the
# page promises (BOARD_DUE) — so the "last checked" line on the board stays younger than the time that means
# the loop itself has stopped.

BOARD_TITLE="${FACTORY_BOARD_TITLE:-Factory board}"
BOARD_NEXT_MAX="${FACTORY_BOARD_NEXT_MAX:-10}"      # issues named under "Next up" before the rest are counted in one line
BOARD_HEARTBEAT="${FACTORY_BOARD_HEARTBEAT:-1800}"   # s: the promise the page makes — an unchanged picture is never older than this
#
# How often the page is looked at while a session runs: a quarter of the heartbeat. The other two numbers follow
# from it, and both are what the page says about itself, so neither can promise what the loop does not do. A
# rewrite falls due one look BEFORE the heartbeat runs out (BOARD_DUE), so the look that takes it still lands
# inside the heartbeat: an unchanged picture is rewritten at most one heartbeat after the last time, which is
# what "written again at least every 10 minutes" on the page means. And the age at which the page says the loop
# itself has stopped is a heartbeat plus two looks — the worst case above, plus one whole look of margin for the
# read and the write to land — so that rule cannot cry wolf on the board's own cadence. Never 0: a heartbeat of 0 (the tests' "rewrite every time") would otherwise spin.
BOARD_TICK=$(( BOARD_HEARTBEAT / 4 )); [ "$BOARD_TICK" -ge 1 ] || BOARD_TICK=1
BOARD_DUE=$(( BOARD_HEARTBEAT - BOARD_TICK )); [ "$BOARD_DUE" -ge 0 ] || BOARD_DUE=0
# The driver's PRIORITIES, MAX_IN_FLIGHT, SLOTS and REVIEW_WORKERS, set here when they are not (a test that loads
# this file alone).
: "${PRIORITIES:=p1-production p2-product p3-tooling}"
: "${LOOP_SHARE_MAX:=20}"
: "${LIST_LIMIT:=300}"   # one cap for "every open issue", so the page cannot name a queue the pick cannot see
: "${MAX_IN_FLIGHT:=2}"
: "${SLOTS:=1}"
: "${REVIEW_WORKERS:=1}"

# An `area:` label in plain words (say the thing, not its label): its words in the project's labels file
# (factory_label_words); one the file does not name prints as it stands, so a label added by hand still reads as
# something.
board_area() {
  local w; w=$(factory_label_words "$1" 2> /dev/null || true)
  echo "${w:-${1#area:}}"
}
board_areas() {   # every `area:` label of a label list, in plain words
  local l out=""; local -a labels=()
  read -r -a labels <<< "$1"   # split on spaces without globbing
  for l in "${labels[@]}"; do case "$l" in area:*) out+="${out:+, }$(board_area "$l")" ;; esac; done
  printf '%s' "$out"
}
# How a label list sorts in the loop's queue, and what its priority means: "<rank> <words>", rank 1 first
# An issue with no priority label sorts behind every issue with one.
board_class() {
  local p i=1 w
  for p in $PRIORITIES; do
    case " $1 " in *" $p "*)
      w=$(factory_label_words "$p" 2> /dev/null || true)
      echo "$i ${w:-issues labelled $p}"
      return ;;
    esac
    i=$((i + 1))
  done
  echo "9 not yet rated, so it sorts behind every issue that is"
}
# The queue's order in the same words, built from the same list the ranking above reads, so the sentence the
# owner reads and the order the loop takes cannot drift apart when that list changes.
board_order() {
  local p out="" w
  for p in $PRIORITIES; do w=$(board_class "$p"); out+="${out:+, then }${w#* }"; done
  printf '%s' "$out"
}

# A UTC instant in the words the board prints. One it cannot read prints as it stands, never as a guess.
board_when() { date -u -d "$1" +'%Y-%m-%d %H:%M UTC' 2> /dev/null || printf '%s' "$1"; }

# The two freshness numbers the page states about itself, in whole minutes rounded up, both from the one setting
# that decides them: how often an unchanged page is rewritten (the heartbeat, which the rewrite falling due a
# look early keeps true), and how old its time can honestly get before the loop has stopped (that worst case
# plus one look of margin). Written as constants they would promise what the loop does not do — the review of
# round 1 found the page claiming "at least every ten minutes" under a heartbeat set to something else, and
# round 2 found the stopped-rule sitting exactly on the worst case instead of above it.
board_mins() {
  local m=$(( ($1 + 59) / 60 ))
  [ "$m" -ge 1 ] || m=1
  if [ "$m" = 1 ]; then printf '1 minute'; else printf '%s minutes' "$m"; fi
}
board_fresh() { board_mins "$BOARD_HEARTBEAT"; }
board_stale() { board_mins $(( BOARD_HEARTBEAT + 2 * BOARD_TICK )); }
# Either of the two numbers the sentence under "Next up" gives for why a free place does not always start
# something at once, in words: how many issues the loop builds at once (its build slots) and how many finished
# code reviews it handles at once — one per fast-lane worker above worker 1, which runs none of them once the
# lane has more than one. Neither can outrun the places the loop holds at all,
# since a build and a review each need one, so both are held down to that: with five workers and three places
# the answer is three, not four.
board_cap() {
  local n=$1
  [ "$n" -le "$MAX_IN_FLIGHT" ] || n=$MAX_IN_FLIGHT
  if [ "$n" = 1 ]; then printf '1 %s' "$2"; else printf '%s %ss' "$n" "$2"; fi
}

# The open issues of this repository, one "<number>\t<labels…>\t<title>" line each, oldest first: the one call
# every section but the last is built from. Fails when it fails.
board_issues() {
  gh issue list --repo "$REPO" --state open --limit "$LIST_LIMIT" --json number,title,labels \
    --jq '.[] | [.number, ([.labels[].name] | join(" ")), .title] | @tsv' | sort -n
}

# The issues issue N waits for, and the ones that wait for N, from the "blocked by" links the hourly sweep last
# read. Those links are up to an hour old, so a blocker is named only while it is still one of the
# open issues read this minute: a blocker closed since the sweep must not hold an issue back on the board when
# it no longer holds it back in the loop's own pick. The other direction — a link added since the sweep — is
# what the line under "Next up" tells the owner. A missing file (a loop whose sweep has not run yet) is empty.
board_blockers() {
  local b out=""
  for b in $(grep -E " $1\$" <<< "$BOARD_BLOCKS" | cut -d ' ' -f 1 | sort -nu || true); do
    grep -qE "^$b"$'\t' <<< "$BOARD_ROWS" && out+="${out:+ }$b"
  done
  printf '%s' "$out"
}
# The other direction: the issues held back by issue N, which is what the owner's question is costing. Held to
# the same rule as above — an issue closed since the last hourly read is no longer held back by anything, and
# naming it would overstate what an answer buys.
board_blocks() {
  local b out=""
  for b in $(grep -E "^$1 " <<< "$BOARD_BLOCKS" | cut -d ' ' -f 2 | sort -nu || true); do
    grep -qE "^$b"$'\t' <<< "$BOARD_ROWS" && out+="${out:+ }$b"
  done
  printf '%s' "$out"
}
# "<class>\t<why>" for parked issue N, from $STATE/board-parked: the latest line wins (a park appends, a sweep
# rewrites the file from what it classified). Empty for an issue parked since the last sweep wrote that file.
board_park() { grep -E "^$1"$'\t' <<< "$BOARD_PARKED" | tail -n 1 | cut -f 2- || true; }

# BOARD_SINCE: when the board first saw issue N at stage S. Its own record ($STATE/board-seen), so no call is
# made for it; after a restart of this host the first sighting is the time the board came back, which is why the
# board says "at this step since", not "started at".
board_since() {
  local t
  t=$(grep -m 1 -E "^$1 $2 " <<< "$BOARD_SEEN_PREV" | cut -d ' ' -f 3 || true)
  [ -n "$t" ] || t=$BOARD_NOW
  BOARD_SEEN+="$1 $2 $t"$'\n'
  BOARD_SINCE=$t
}

# Section 1's line for an issue in flight: the stage in plain words from its pull request (one call each, and
# the loop holds at most MAX_IN_FLIGHT issues at a time), since when, and the part of the code it holds.
board_flight() {
  local n="$1" ls="$2" title="$3" pr st what areas
  read -r pr st <<< "$(pr_of "$n" || true)"
  case "$st" in
    OPEN) what="its change is open as pull request #$pr, waiting for the automatic code review or for what that review found to be fixed" ;;
    MERGED)
      case " $ls " in
        *" in-review "*) what="its change is merged as pull request #$pr${RELEASE_CHECK:+, waiting for the release check to say it is released}${RELEASE_CHECK:-, being closed}" ;;
        *) what="a new round is being built: pull request #$pr merged, and what the issue still needs gets a new pull request" ;;
      esac ;;
    CLOSED) what="its pull request #$pr was closed without being merged" ;;
    *) what="being built" ;;
  esac
  board_since "$n" "${st:-none}"
  areas=$(board_areas "$ls")
  BOARD_FLIGHT+="- **issue #$n** $title — $what. At this step since $(board_when "$BOARD_SINCE")."
  BOARD_FLIGHT+="${areas:+ Part of the code it holds: $areas.}"$'\n'
}

# Sections 3, 4 and 5's line for a parked issue: what it waits for, from the class its park comment carries (the
# hourly re-check reads that class; `needs-decision` is the owner's wait, `waiting` one the loop ends itself).
board_parked_line() {
  local n="$1" ls="$2" title="$3" url class why held
  url="https://github.com/$REPO/issues/$n"
  IFS=$'\t' read -r class why <<< "$(board_park "$n")"
  case " $ls " in
    *" needs-decision "*)
      BOARD_NEEDS+="- **issue #$n** $title — ${why:-the loop asked you something on this issue; open it to read the question}. [Open the issue]($url) and reply there."
      held=$(board_blocks "$n")
      # shellcheck disable=SC2086   # one word per issue
      [ -z "$held" ] || { held=$(printf 'issue #%s, ' $held); BOARD_NEEDS+=" Your answer also lets these start: ${held%, }."; }
      BOARD_NEEDS+=$'\n' ;;
    *)
      case "$class" in
        time:*) BOARD_WAITS+="- **issue #$n** $title — until $(board_when "${class#time:}"). The loop re-checks it then and carries on by itself."$'\n' ;;
        issue:*) BOARD_QUEUED+="- **issue #$n** $title — after issue #${class#issue:}, which is still open. The loop starts it when that one closes."$'\n' ;;
        ci) BOARD_QUEUED+="- **issue #$n** $title — its automatic review or release check did not get through; the loop retries it every hour."$'\n' ;;
        *) BOARD_QUEUED+="- **issue #$n** $title — waiting; the hourly re-check names what for, within the hour."$'\n' ;;
      esac ;;
  esac
}

# Sections 2 and 3's line for a queued issue: it can start now unless an issue it is blocked by on GitHub is
# still open, or an issue in flight holds one of its parts of the code — the two the loop's own pick goes by.
board_ready() {
  local n="$1" ls="$2" title="$3" rank class clash b l
  read -r rank class <<< "$(board_class "$ls")"
  b=$(board_blockers "$n")
  if [ -n "$b" ]; then
    # shellcheck disable=SC2086   # one word per issue
    l=$(printf 'issue #%s, ' $b)
    BOARD_QUEUED+="- **issue #$n** $title — after ${l%, }, which is still open."$'\n'
  elif clash=$(area_clash "$n" "$ls" "$BOARD_BUSY"); then
    BOARD_QUEUED+="- **issue #$n** $title — the loop is already working on the same part of the code ($(board_area "${clash%% in flight*}")), in issue #${clash##*#}. Two issues in one part are never built at once, because their changes would collide."$'\n'
  else
    BOARD_NEXT+="$rank $n $title — $class."$'\n'
  fi
}

# One row of BOARD_ROWS — "<number>\t<labels>\t<title>" — into the caller's n, ls and title. `read` with
# IFS=tab cannot do this: tab is IFS whitespace, so two of them count as one separator and an issue with NO
# label would take its own title for its labels — and every issue no label keeps out is in the queue, so a title holding the word "waiting" or "hold" would have taken it off the page.
board_row() { n=${1%%$'\t'*}; ls=${1#*$'\t'}; title=${ls#*$'\t'}; ls=${ls%%$'\t'*}; }

# Every section's lines, from the open issues (BOARD_ROWS) and the files above. Called in the tick's own shell,
# never in a `$(…)`: its work is these variables, and the board's text is printed from them afterwards.
board_gather() {
  local n ls title at row
  BOARD_FLIGHT="" BOARD_NEXT="" BOARD_QUEUED="" BOARD_WAITS="" BOARD_NEEDS="" BOARD_DONE=""
  BOARD_SEEN="" BOARD_BUSY="" BOARD_HELD=0
  # Which list an issue belongs on is the loop's own reading of its labels (stage_of_labels), never a second
  # copy of that rule here: the page must say "next up" about exactly the issues the pick would start, and
  # that is every open issue no label of its own keeps out, not only those carrying `ready`.
  # The issues in flight first: a queued issue is judged against the parts of the code those hold, exactly as
  # the loop's pick judges it (inflight_labels + area_clash), and a waiting issue is in flight for neither.
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    board_row "$row"
    [ "$(stage_of_labels "$ls")" = flight ] || continue
    BOARD_BUSY+="$n $ls"$'\n'; BOARD_HELD=$((BOARD_HELD + 1))
  done <<< "$BOARD_ROWS"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    board_row "$row"
    # `held` — the owner's `hold` and every `tracking` issue, this page included — is on no list: nothing is
    # waiting for it and the loop will not start it, so naming it would only make the page longer.
    case "$(stage_of_labels "$ls")" in
      blocked) board_parked_line "$n" "$ls" "$title" ;;
      flight)  board_flight "$n" "$ls" "$title" ;;
      verify)  board_ready "$n" "$ls" "$title" ;;
    esac
  done <<< "$BOARD_ROWS"
  if [ "$BOARD_DONE_ERR" = 1 ]; then
    BOARD_DONE="- this list could not be read this time; the next run reads it again."$'\n'
  else
    while IFS=$'\t' read -r n at title; do
      [ -n "$n" ] || continue
      BOARD_DONE+="- **issue #$n** $title (closed $(board_when "$at"))"$'\n'
    done <<< "$BOARD_DONE_ROWS"
  fi
  [ -n "$BOARD_FLIGHT" ] || BOARD_FLIGHT="- none: the loop is not working on anything right now."$'\n'
  [ -n "$BOARD_QUEUED" ] || BOARD_QUEUED="- none."$'\n'
  [ -n "$BOARD_WAITS" ] || BOARD_WAITS="- none."$'\n'
  [ -n "$BOARD_NEEDS" ] || BOARD_NEEDS="- none: the loop is not waiting for an answer from you."$'\n'
  [ -n "$BOARD_DONE" ] || BOARD_DONE="- none."$'\n'
}

# The board's text, with @@CHECKED@@ where the time of this run goes — the picture, which is what decides
# whether the board is rewritten. Every line stands on its own, and a section with nothing in it says "none"
# rather than vanishing, so the owner can see it was looked at (CLAUDE.md "Writing for the owner").
board_body() {
  local rank n rest i=0 free=$((MAX_IN_FLIGHT - BOARD_HELD))
  [ "$free" -ge 0 ] || free=0
  printf '# What the factory is doing\n\n'
  printf '**%s of the %s issues the loop may work on at once are in hand, %s free. Last checked @@CHECKED@@.**\n\n' "$BOARD_HELD" "$MAX_IN_FLIGHT" "$free"
  [ -z "$BOARD_PAUSE" ] || printf '%s\n\n' "$BOARD_PAUSE"
  # The loop's own share of its sessions: the driver's count, which a driver older than that
  # file does not have — then the line is left out rather than guessed.
  if declare -F loop_share > /dev/null; then
    printf "The loop's own machinery took %s %% of the sessions the loop started in the last 24 hours. It may take at most %s %%; over that, the loop starts nothing about itself until the share falls.\n\n" \
      "$(loop_share)" "$LOOP_SHARE_MAX"
  fi
  printf 'The loop looks at its queue every few minutes and writes this page again whenever the picture changes, and at least every %s — beside a step that is running too — so the time above stays fresh. If that time is more than %s old, the loop itself has stopped. Nothing here needs an answer from you except the section "Waiting for you".\n\n' "$(board_fresh)" "$(board_stale)"
  printf '## Being worked on now\n\n%s\n' "$BOARD_FLIGHT"
  # "Every few minutes" and "within minutes", not a number: how often the loop looks is set in its timer on the
  # host, not here, and a number written in this text would be a second place to keep it (unlike the two
  # numbers above, which this file does decide).
  printf '"At this step since" is when the loop first saw that step, which is within minutes of it starting.\n\n'
  printf '## Next up, in order\n\n'
  printf 'The loop takes these in this order: %s, oldest first within each. It starts one when a place above is free, and it builds at most %s at a time and handles at most %s at a time, so a free place does not always mean one starts at once.\n\n' \
    "$(board_order)" "$(board_cap "$SLOTS" issue)" "$(board_cap $(( REVIEW_WORKERS > 1 ? REVIEW_WORKERS - 1 : 1 )) 'finished code review')"
  if [ -n "$BOARD_NEXT" ]; then
    # By priority, and inside one priority by issue number, which is the loop's own order: `sort -s` keeps the
    # lines in the order they were built, and they were built from the open issues read oldest first.
    # Only the first BOARD_NEXT_MAX are named, with a count of the rest: every open issue
    # nobody has set aside is in this queue, and forty numbered lines would bury the sections below it.
    while read -r rank n rest; do
      [ -n "$n" ] || continue
      i=$((i + 1))
      [ "$i" -gt "$BOARD_NEXT_MAX" ] || printf '%s. **issue #%s** %s\n' "$i" "$n" "$rest"
    done < <(sort -s -k 1,1n <<< "$BOARD_NEXT")
    [ "$i" -le "$BOARD_NEXT_MAX" ] || printf -- '- and %s more behind them, in the same order.\n' "$((i - BOARD_NEXT_MAX))"
  else
    printf -- '- none: nothing in the queue can start right now.\n'
  fi
  printf '\nWhich issue waits for which is read once an hour, so a link added since then is not shown here yet.\n'
  printf '\n## Queued, but cannot start yet\n\n%s\n' "$BOARD_QUEUED"
  printf '## Waiting for a set time\n\n%s\n' "$BOARD_WAITS"
  printf '## Waiting for you\n\n%s\n' "$BOARD_NEEDS"
  printf '## Finished in the last 24 hours\n\n%s\n' "$BOARD_DONE"
  printf '<sub>Written by the factory loop itself: it replaces this text whenever the picture changes, so nothing is kept here — every issue keeps its own comments.</sub>\n'
}

# The board's own issue: the number the loop recorded, while that issue is still one of the open ones read this
# minute — a board issue the owner closed is dropped rather than rewritten out of sight, where GitHub's PATCH
# would still succeed — else the open issue whose title is the board's, else one created, labelled `tracking`
# and pinned. Created on first use like the monitor issue (scripts/monitor-post.sh), and found the same way, by
# an exact title among the open issues (BOARD_ROWS, already read: no call, and no label filter to depend on).
board_issue() {
  local f="$STATE/board-issue" found row n ls title
  found=$(cat "$f" 2> /dev/null || true)
  if [[ $found =~ ^[0-9]+$ ]] && grep -qE "^$found"$'\t' <<< "$BOARD_ROWS"; then echo "$found"; return 0; fi
  found=""
  while IFS= read -r row; do
    board_row "$row"   # never `read` with IFS=tab: an issue with no label would hand over its title as its labels
    [ "$title" = "$BOARD_TITLE" ] || continue
    found=$n; break
  done <<< "$BOARD_ROWS"
  n=$found
  if [ -z "$n" ]; then
    # Only that the label exists: `--force` without `--description` leaves the wording alone (measured),
    # so scripts/factory-install.sh stays the one place that sets it, here and in scripts/monitor-post.sh.
    gh label create tracking --repo "$REPO" --color 0E8A16 --force > /dev/null || true
    n=$(gh issue create --repo "$REPO" --title "$BOARD_TITLE" --label tracking \
          --body "The factory loop writes this page. Its first version arrives within minutes." | grep -oE '[0-9]+$') || return 1
    [[ $n =~ ^[0-9]+$ ]] || return 1
    log "board: issue #$n created" >&2   # logged on stderr: stdout is this function's value, the number
    board_pin "$n"
  fi
  echo "$n" > "$f"; echo "$n"
}

# Pins the board, so it sits at the top of the repository's issue list. A repository pins at most three issues
# and one that already has three refuses: that costs one line, and the board is the board either way. Called
# from board_issue, whose value is its stdout, so these lines go to stderr like its own.
board_pin() {
  local id
  id=$(gh issue view "$1" --repo "$REPO" --json id --jq .id) \
    || { log "board: issue #$1 was not pinned — its id did not load" >&2; return 0; }
  gh api graphql -f query='mutation($id: ID!) { pinIssue(input: {issueId: $id}) { issue { number } } }' -f "id=$id" > /dev/null \
    || log "board: issue #$1 was not pinned — the call was refused (a repository pins at most three issues)" >&2
}

# One run of the board: read the picture, then rewrite the board's text when it differs from the last one
# written, or when that write is older than BOARD_HEARTBEAT. A read that fails leaves the board as it is, with
# one line — a page a few minutes old beats a page that says less than it did (priority (3), honesty). With
# --dry-run it prints the text and changes nothing, on GitHub or in the state.
board() {
  local picture body n prev last now why f="$STATE/board.txt" since
  # What an issue's labels say is the driver's own rule, never a second copy
  # here. Without it (a driver older than this file), say so and leave the page alone, rather than write one with
  # every issue missing from every list.
  declare -F stage_of_labels > /dev/null \
    || { log "board: this loop's driver is older than the board file — the next tick writes the page"; return 0; }
  BOARD_NOW=$(date -u +%FT%TZ)
  BOARD_ROWS=$(board_issues) || { log "board: the open issues did not load — the board keeps the text it has"; return 0; }
  BOARD_BLOCKS=$(cat "$STATE/sweep-blocks" 2> /dev/null || true)
  BOARD_PARKED=$(cat "$STATE/board-parked" 2> /dev/null || true)
  BOARD_SEEN_PREV=$(cat "$STATE/board-seen" 2> /dev/null || true)
  # The account's usage limit pauses both lanes (run_lane's marker file): while it holds, the loop starts
  # nothing, and a board that showed free work slots and a queue would be the idle spell this page exists to
  # show. Read from the host, so it costs no call.
  BOARD_PAUSE=""
  last=$(cat "$STATE/.usage-limit-until" 2> /dev/null || true)
  if [[ $last =~ ^[0-9]+$ ]] && [ "$last" -gt "$(date +%s)" ]; then
    # The driver's own words for the pause when it wrote them: an expired login or a
    # run of dead sessions is not the usage limit, and one of them needs the owner. A marker with no reason
    # file is the limit, as it always was.
    why=$(head -n 1 "$STATE/.pause-reason" 2> /dev/null || true)
    if [ -n "$why" ]; then
      BOARD_PAUSE="**Paused until $(board_when "@$last"): $why.** The loop tries again when the pause ends."
    else
      BOARD_PAUSE="**Paused until $(board_when "@$last"): the AI account's usage limit was reached, so the loop starts nothing new until then.** Nothing needed from you — it carries on by itself."
    fi
  fi
  since=$(date -u -d '24 hours ago' +%FT%TZ)
  BOARD_DONE_ERR=0
  BOARD_DONE_ROWS=$(gh issue list --repo "$REPO" --state closed --search "closed:>=$since" --limit 50 \
                      --json number,title,closedAt \
                      --jq '.[] | select(.closedAt != null) | [.number, .closedAt, .title] | @tsv' | sort -n) \
    || { BOARD_DONE_ERR=1; log "board: the issues closed in the last 24 h did not load"; }
  board_gather
  picture=$(board_body)
  body="${picture//@@CHECKED@@/$(board_when "$BOARD_NOW")}"
  if [ "$DRY" = 1 ]; then
    printf -- '--- board (dry run: nothing changed, nothing written) ---\n%s\n' "$body"
    return 0
  fi
  prev=$(cat "$f" 2> /dev/null || true)
  last=$(cat "$STATE/board-written" 2> /dev/null || true)
  [[ $last =~ ^[0-9]+$ ]] || last=0
  now=$(date +%s)
  if [ "$picture" != "$prev" ]; then why="the picture changed"
  elif [ $((now - last)) -ge "$BOARD_DUE" ]; then why="its \"last checked\" time was $(((now - last) / 60)) min old"
  else
    printf '%s' "$BOARD_SEEN" > "$STATE/board-seen"
    return 0   # the same picture, written minutes ago: no write at all
  fi
  n=$(board_issue) || { log "board: its issue could not be read or created — nothing written this time"; return 0; }
  # GitHub keeps at most 65536 characters in an issue body, and refuses a longer one: a board that grows past
  # that is cut at its last whole line, with a line saying so, rather than not written at all.
  if [ "${#body}" -gt 60000 ]; then
    body=${body:0:60000}; body=${body%$'\n'*}
    body+=$'\n\n'"<sub>Cut here: the page grew past what GitHub keeps in one issue.</sub>"
  fi
  printf '%s\n' "$body" > "$STATE/board-body.md"
  if gh api -X PATCH "repos/$REPO/issues/$n" -F body=@"$STATE/board-body.md" > /dev/null; then
    printf '%s' "$picture" > "$f"; echo "$now" > "$STATE/board-written"
    printf '%s' "$BOARD_SEEN" > "$STATE/board-seen"
    log "board: issue #$n rewritten — $why"
  else
    rm -f "$STATE/board-issue"   # a board issue deleted or moved: the next run finds it by title, or makes one
    log "board: issue #$n could not be rewritten — the next run tries again"
  fi
}

# One board run under the board's OWN lock, never a lane's, so the tick and the ticker beside it never write at
# once and neither waits for the other: whichever finds the lock taken skips that turn, and the page is the same
# page either way. Every run is non-dry: a dry run prints from `board` and never comes through here.
board_run() {
  local fd rc=0
  # When the page was last looked at, which is what the countdown to the next look runs from (board_due). Every
  # look is stamped, whether it rewrote the page, found nothing to rewrite, or found another run holding the
  # lock: the look is what costs the calls. Counting from the last WRITE instead would call the next look due
  # every second for as long as the picture stayed the same.
  date +%s > "$STATE/board-looked"
  exec {fd}> "$STATE/.lock-board"
  if flock -n "$fd"; then board || rc=$?; else log "board: another run is writing it"; fi
  exec {fd}>&-
  return "$rc"
}

# Seconds until the page is next looked at, counted from the last look and never below 1. Counting from the
# last look, which lives in the state folder, is what makes the time a session spent count even when that
# session was too short to reach a look of its own: a tick runs one session after another — up to three stages
# of one issue, plus every other issue in flight — and a countdown started afresh in each call would leave
# half an hour of sessions with no look in it at all. The floor of 1 s is the
# anti-spin guard: an unwritable state folder cannot turn this into a call every second.
board_due() {
  local last now left
  last=$(cat "$STATE/board-looked" 2> /dev/null || true)
  [[ $last =~ ^[0-9]+$ ]] || last=0
  now=$(date +%s)
  left=$(( BOARD_TICK - (now - last) ))
  [ "$left" -ge 1 ] || left=1
  printf '%s' "$left"
}

# Keeps the page fresh while the stage session <pid> runs, and returns when it ends. A session holds its lane's
# lock for as long as it takes — a review round is often half an hour, and SESSION_TIMEOUT allows two hours —
# and nothing else rewrites the page meanwhile: the fast lane's systemd unit is Type=oneshot, so while one tick
# runs, the 5-minute timer starts no second one, it merges into the running job, and the lane's workers above 1
# never load this file at all. The page's time would then age
# past what it itself calls stopped, while the loop is working — the false alarm raised by the very page that
# exists to make a real stall visible. The waiting is done here, in the tick's own
# shell with the session in the background, rather than the other way round: nothing is left running that could
# outlive the tick, hold the locks it inherited or keep writing the page. The second look before each rewrite
# is what keeps the page from being written once more after the session has already ended.
board_wait() {
  local pid=$1 left
  left=$(board_due)
  while kill -0 "$pid" 2> /dev/null; do
    sleep 1
    left=$((left - 1))
    if [ "$left" -le 0 ]; then
      kill -0 "$pid" 2> /dev/null && board_run || true
      left=$(board_due)
    fi
  done
}

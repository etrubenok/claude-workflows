# shellcheck shell=bash
# The factory's stage runner: everything that happens to ONE issue in one tick — the two gates before a session
# starts (is the code review finished, has the merge been released), the issue's worktree and branch, the session
# itself, what is left behind afterwards, and the walk over an issue's stages. Not a program: scripts/factory-tick.sh
# sources it once per lane tick, and it runs on the driver's settings (REPO, STATE, ROOT, MODEL, SESSION_TIMEOUT,
# RELEASE_CHECK, …) and functions (log, pr_of, stage_of, park_issue, hold_area, …). Unlike the sweep and the board
# beside it, the loop cannot do without this file: while it is missing or does not parse, a tick logs one line,
# starts no session and runs no sweep (which calls review_state, release_state, request_review, reap_issue and
# cleanup_issue here), and still refreshes the board.

# Review state of an issue's open PR: "verdict" (a Review verdict exists), "skipped" (the
# review run finished without one — docs/test-only diff), "pending" (the run has not finished
# yet, or the push is seconds old), "conflict" (merge main first), "unrequested" (the head's CI
# ran REVIEW_GRACE ago and no review run exists: nobody asked — re-request once), "stalled" (a
# run still unfinished after REVIEW_STALL), "degraded" (the review step crashed — re-request
# once); "unrequested-twice" / "degraded-twice" = the re-request did not help, park the issue.
review_state() {
  local pr="$1" sha
  # A PR with a merge conflict gets NO pull_request workflow runs (no merge ref), so
  # neither CI nor the review can ever complete: the session must merge main first.
  if [ "$(gh pr view "$pr" --repo "$REPO" --json mergeStateStatus --jq .mergeStateStatus)" = DIRTY ]; then
    echo conflict; return
  fi
  sha=$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid)
  # Every review run for THIS head commit (an `opened` and a label event can both fire):
  # all must have finished, and a verdict counts only if posted after the earliest started
  # (earlier rounds' verdicts do not).
  local runs started
  runs=$(gh run list --repo "$REPO" --workflow="$REVIEW_WORKFLOW" --commit "$sha" --limit 10 \
           --json status,createdAt --jq '.[] | "\(.status) \(.createdAt)"' 2>/dev/null || true)
  if [ -z "$runs" ]; then
    # No review run for this head. The review fires on `opened`, `ready_for_review` and the
    # `review` label — never on a push — so a PR opened while it conflicted with main (GitHub
    # runs nothing on it, not even CI) and then fixed by a merge + push never gets one; nor does
    # a PR whose session died between its push and its label toggle; such a PR would read "pending"
    # for good. CI runs on every push, so its first run for this head dates
    # the push: older than REVIEW_GRACE with still no review run = nobody asked. The marker
    # comment request_review posts names the head, so a second look escalates instead of looping.
    local pushed marks
    pushed=$(gh run list --repo "$REPO" --commit "$sha" --limit 20 --json createdAt \
               --jq '[.[].createdAt] | min // empty' 2>/dev/null || true)
    if [ -z "$pushed" ] || [ "$(age_s "$pushed")" -lt "$REVIEW_GRACE" ]; then echo pending; return; fi
    marks=$(gh api "repos/$REPO/issues/$pr/comments" --paginate --jq '.[].body' 2>/dev/null) \
      || { echo pending; return; }
    if printf '%s\n' "$marks" | grep -q "^factory: review re-requested for $sha"; then echo unrequested-twice; else echo unrequested; fi
    return
  fi
  if printf '%s\n' "$runs" | grep -qv '^completed '; then
    # Unfinished. A run older than REVIEW_STALL (a queue that never drained, a hung job — the
    # workflow sets no timeout of its own) is parked for a human rather than waited on forever.
    started=$(printf '%s\n' "$runs" | grep -v '^completed ' | awk '{print $2}' | sort | head -n1)
    if [ "$(age_s "$started")" -ge "$REVIEW_STALL" ]; then echo stalled; else echo pending; fi
    return
  fi
  started=$(printf '%s\n' "$runs" | awk '{print $2}' | sort | head -n1)
  # `gh api --jq` takes no --arg: the ISO timestamp is interpolated into the filter. (Found
  # 2026-09-14: the --arg form errored silently, so every finished review read as "skipped"
  # and the review stage's verdict path never ran.) `--review-state N` prints this classification.
  local comments
  if ! comments=$(gh api "repos/$REPO/issues/$pr/comments" --paginate \
                    --jq ".[] | select(.created_at > \"$started\") | .body" 2>/dev/null); then
    echo pending; return   # a failed fetch is not "no verdict": ask again next tick
  fi
  # The workflow's DEGRADED fallback posts "fix-before-merge set: unknown" (the review step
  # crashed): not a verdict and not docs-only — re-request once, then ask a human.
  local degraded
  degraded=$(printf '%s\n' "$comments" | grep -ci 'fix-before-merge set: unknown' || true)
  if printf '%s\n' "$comments" | grep -qi "$VERDICT_RE"; then
    echo verdict
  elif [ "$degraded" -ge 2 ]; then
    echo degraded-twice
  elif [ "$degraded" -ge 1 ]; then
    echo degraded
  else
    echo skipped
  fi
}

# Runs the project's cleanup for what a session may leave behind outside its worktree (FACTORY_REAP: a command run
# in the primary checkout as `<command> <issue>` — a test server, a container, a scratch folder — that a session
# cut off by its timeout or turn cap could not stop itself). Nothing when the project has none.
reap_leftovers() {
  local n="$1" out
  [ -n "${FACTORY_REAP:-}" ] || return 0
  if out=$(cd "$ROOT" && timeout 300 bash -c "$FACTORY_REAP \"\$1\"" reap "$n" 2>&1); then
    [ -z "$out" ] || log "issue #$n: cleanup: ${out%%$'\n'*}"
  else
    log "issue #$n: the project's cleanup (FACTORY_REAP) failed — ${out%%$'\n'*}"
  fi
}

# Release outcome for a merged PR whose issue is still open — a `Part of #N` PR: such an issue is done only once its
# change is released, which the project's RELEASE_CHECK judges (its contract is at its setting in factory-tick.sh).
# `green`, `failed` or `none` as the check printed it; `pending` while it says so, prints nothing or fails — until
# RELEASE_STALL after the merge, which reads `stalled` (the issue is parked); `none` when the project has no check.
# The driver waits here, on the host, between ticks — never inside a session. `--release-state PR` prints this.
release_state() {
  local pr="$1" merge merged_at head out
  [ -n "$RELEASE_CHECK" ] || { echo none; return; }
  # `|`-separated: a whitespace IFS would collapse an empty field and shift the next one into its place.
  IFS='|' read -r merge merged_at head < <(gh pr view "$pr" --repo "$REPO" --json mergeCommit,mergedAt,headRefName \
                                            --jq '"\(.mergeCommit.oid // "")|\(.mergedAt // "")|\(.headRefName)"')
  [ -n "$merge" ] || { echo pending; return; }
  out=$(cd "$ROOT" && timeout 600 bash -c "$RELEASE_CHECK \"\$1\" \"\$2\"" release-check "$merge" "${head#issue-}" \
          2>> "$STATE/release-check.log" | tail -n 1) || out=""
  case "$out" in green|failed|none) echo "$out"; return ;; esac
  if [ "$(age_s "$merged_at")" -ge "$RELEASE_STALL" ]; then echo stalled; else echo pending; fi
}

# Re-requests the review run on a PR: the workflow listens for the `review` label being
# ADDED, so it is removed first. With a reason, a marker comment naming the head is posted too —
# review_state reads it to tell a second miss (`unrequested-twice`) from the first.
request_review() {
  local pr="$1" why="${2:-}" sha
  [ "$DRY" = 1 ] && return 0
  gh api -X DELETE "repos/$REPO/issues/$pr/labels/review" > /dev/null 2>&1 || true
  gh api -X POST "repos/$REPO/issues/$pr/labels" -f 'labels[]=review' > /dev/null || return 1
  [ -n "$why" ] || return 0
  sha=$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid)
  # Plain words first (CLAUDE.md "Writing for the owner"); the last visible line is the marker review_state and
  # sweep_retries read, so it keeps its exact shape.
  gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="The automatic code review had not produced a result for this pull request's latest commit, so the loop asked for it again. Nothing needed from you."$'\n\n'"factory: review re-requested for $sha — $why"$'\n\n'"$FACTORY_MARK" > /dev/null
}

# Catches a resumed issue branch up with origin/issue-<n> before its session starts: a push
# from another session, a hand fix on the PR. The same rule as ff_checkout, in the issue's worktree:
# strictly behind and clean moves; ahead,
# diverged or dirty stays as it is and is logged. Never a reset.
ff_branch() {
  local n="$1" wt="$2" b="issue-$1" here there why err
  there=$(git rev-parse -q --verify "refs/remotes/origin/$b") || return 0   # never pushed
  here=$(git rev-parse -q --verify "refs/heads/$b") || return 0
  [ "$here" != "$there" ] || return 0
  if git merge-base --is-ancestor "$there" "$here"; then why="ahead, unpushed commits"
  elif ! git merge-base --is-ancestor "$here" "$there"; then why="diverged"
  elif [ "$(git -C "$wt" symbolic-ref -q --short HEAD || true)" != "$b" ]; then why="not checked out in $wt"
  elif ! err=$(git -C "$wt" --no-optional-locks status --porcelain --untracked-files=no) || [ -n "$err" ]; then why="uncommitted edits in its worktree"
  elif ! err=$(git -C "$wt" merge -q --ff-only "origin/$b" 2>&1); then why="fast-forward refused: ${err%%$'\n'*}"
  else log "issue #$n: $b fast-forwarded ${here:0:7} → ${there:0:7} (origin/$b)"; return 0
  fi
  log "issue #$n: $b ${here:0:7} left as is — $why (origin/$b ${there:0:7})"
}

# The branch a build of issue N continues from, the one rule run_stage attaches and hold_area names:
# the local branch issue-N, else its copy on GitHub (a branch pushed but deleted here). Fails when neither
# exists: a build then starts from origin/main.
branch_of() {
  if git show-ref --quiet "refs/heads/issue-$1"; then echo "issue-$1"
  elif git show-ref --quiet "refs/remotes/origin/issue-$1"; then echo "origin/issue-$1"
  else return 1; fi
}

# A new round of an issue whose newest PR merged starts from main, never from that PR's branch: its work is in main
# already (rebased or squashed into other commits), and a session resuming on it would read those commits as its own
# unfinished build. A local branch still at the merged PR's head is that leftover, and goes with its worktree
# (cleanup_issue); so does the GitHub branch at that head, so the new round can push `issue-N` again. A branch past
# the merged head holds this round's own commits and is kept. Uncommitted edits in a leftover worktree are never
# thrown away: the issue is parked for the owner instead. The close gate's record of the last round's outcome goes
# too, so this round's own close is not held back an hour by it. Fails, with a line, when the base could not be
# made clean.
new_round_base() {
  local n="$1" pr="$2" wt="$3" head dirty
  rm -f "$STATE/issue-$n.close-last"
  head=$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid) || { log "issue #$n: PR #$pr did not load — the new round waits"; return 1; }
  if [ "$(git rev-parse -q --verify "refs/heads/issue-$n" || true)" = "$head" ]; then
    if [ -d "$wt" ] && { ! dirty=$(git -C "$wt" --no-optional-locks status --porcelain) || [ -n "$dirty" ]; }; then
      park_issue "$n" owner:unsaved-work "a new round of this issue is due, but its folder \`$wt\` still holds the merged PR #$pr's branch with changes that were never committed" \
        "**To answer:** commit or discard those changes (or remove the folder), then reply here: the new round starts from main."
      return 1
    fi
    cleanup_issue "$n" || return 1
    log "issue #$n: new round — the merged PR #$pr's branch and worktree removed; it starts from main"
  fi
  if [ "$(git rev-parse -q --verify "refs/remotes/origin/issue-$n" || true)" = "$head" ]; then
    if git push -q origin --delete "issue-$n" 2> /dev/null; then git update-ref -d "refs/remotes/origin/issue-$n" || true
    else log "issue #$n: could not delete the merged PR #$pr's branch on GitHub — the new round waits"; return 1; fi
  fi
}

# The text a stage session gets: the factory's header (any frontmatter dropped) and this stage's own steps, each
# followed by the project's own addition if it has one (.factory/prompts/header.md, .factory/prompts/<stage>.md in
# the primary checkout, which is main), and nothing of the other three stages. The placeholders {{REPO}},
# {{NAME}}, {{MARK}}, {{PRIORITIES}}, {{CHECK}}, {{SANDBOX}} and {{FACTORY}} (the installed factory's folder, whose scripts/ the
# prompts call by path) are filled in here, so the text a session reads names this project's values.
stage_prompt() {
  local n="$1" stage="$2" hint="$3" text extra check none="(none)"
  check="${FACTORY_CHECK:-the check command its CLAUDE.md names}"
  text=$(awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$SKILL")
  [ ! -r "$PROJECT_PROMPTS/header.md" ] || text+=$'\n\n'"$(cat "$PROJECT_PROMPTS/header.md")"
  text+=$'\n\n'"$(cat "$STAGES/$stage.md")"
  [ ! -r "$PROJECT_PROMPTS/$stage.md" ] || { extra=$(cat "$PROJECT_PROMPTS/$stage.md"); text+=$'\n\n'"### This project's additions to \`$stage\`"$'\n'"$extra"; }
  text=${text//'{{REPO}}'/$REPO}; text=${text//'{{NAME}}'/$NAME}; text=${text//'{{MARK}}'/$FACTORY_MARK}
  text=${text//'{{PRIORITIES}}'/$PRIORITIES}
  text=${text//'{{CHECK}}'/$check}
  text=${text//'{{SANDBOX}}'/${SANDBOX:-$none}}; text=${text//'{{FACTORY}}'/$(cd "$HERE/.." && pwd)}
  printf 'Run stage `%s` of issue #%s%s exactly as the factory text below says, then stop.\n\n%s' "$stage" "$n" "${hint:+ (state: $hint)}" "$text"
}

# Runs one stage in a fresh headless session; the prompt does the work.
run_stage() {
  local n="$1" stage="$2" dir="$ROOT" hint=""
  local wt="$ROOT/.claude/worktrees/issue-$n"   # own line: a one-line local expands $n to the CALLER's n
  local ts; ts=$(date -u +%Y%m%dT%H%M%SZ)
  local out="$STATE/issue-$n-$stage-$ts.log"
  if [ "$stage" = review ]; then
    local pr; pr=$(pr_of "$n"); pr=${pr%% *}
    hint=$(review_state "$pr")
    case "$hint" in
      pending) log "issue #$n: review verdict pending on PR #$pr — next tick"; return 1 ;;
      unrequested)
        log "issue #$n: no review run for PR #$pr's head — re-requested once, next tick"
        request_review "$pr" "no automatic code review had run for this commit (a pull request opened while it conflicted with main gets none, and a later push does not start one)"
        return 1 ;;
      degraded)
        log "issue #$n: review DEGRADED on PR #$pr — re-requested once, next tick"
        request_review "$pr"
        return 1 ;;
      unrequested-twice) park_issue "$n" ci "the automatic code review never started for the latest commit of PR #$pr, even after the loop asked again"; return 1 ;;
      degraded-twice) park_issue "$n" ci "the automatic code review of PR #$pr ended without a verdict twice in a row"; return 1 ;;
      stalled) park_issue "$n" ci "an automatic code review of PR #$pr has been running for over $((REVIEW_STALL / 60)) min without finishing"; return 1 ;;
    esac
  fi
  if [ "$stage" = close ] && [ "$(issue_state "$n")" = OPEN ]; then
    # Still open after the merge = a `Part of #N` PR: close only on the release outcome.
    local pr; pr=$(pr_of "$n"); pr=${pr%% *}
    hint=$(release_state "$pr")
    case "$hint" in
      pending) log "issue #$n: release of PR #$pr pending — next tick"; return 3 ;;
      stalled) park_issue "$n" ci "PR #$pr merged over $((RELEASE_STALL / 60)) min ago and the project's release check still says it is not released (its output is in $STATE/release-check.log)"; return 1 ;;
    esac
    # One close session an hour while the outcome it would act on is unchanged: a close that cannot finish (a
    # release that keeps reading `none` or `failed`) would otherwise start a session every five minutes. A changed
    # outcome runs at once; the record is written just before the session starts (below), so a dry run gates
    # nothing. A close that finds the merged work is not the whole issue hands it back to implement (`in-progress`),
    # which stage_of then starts as a new round instead of another close.
    local seen; seen=$(cat "$STATE/issue-$n.close-last" 2> /dev/null || true)
    if [ -n "$seen" ] && [ "${seen%% *}" = "$hint" ] && [ $(( $(date +%s) - ${seen#* } )) -lt 3600 ]; then
      log "issue #$n: close — the release outcome is still $hint, as $(( ( $(date +%s) - ${seen#* } ) / 60 )) min ago; the next look is in the hour"
      return 3
    fi
  fi
  # A new round (stage_of: the newest PR merged, and the issue is `in-progress` again): the session is told which PR
  # already merged, and its worktree starts from main (new_round_base).
  local merged_pr=""
  if [ "$stage" = implement ]; then
    local last; last=$(pr_of "$n")
    if [ "${last#* }" = MERGED ]; then merged_pr=${last%% *}; hint="new round: PR #$merged_pr merged"; fi
  fi
  # Every worker but the first, in either lane, launches only on a quiet host: whatever else runs there, CI and
  # the sessions share its cores. Its tick ends here; worker 1 is never gated, so every stage still runs, just one
  # at a time. A review round runs the whole test suite, like a build, so the fast lane's extra workers pass the
  # same gate. A lagging average read once at launch: it keeps a session off a busy host, it cannot stop two
  # sessions overlapping minutes later.
  # `close` is the one stage that never comes back, so it is never gated: the only close a worker above 1 runs
  # is the close of the merge its own review just made (advance, below), and that review's build and test run is
  # what left the load high — the moment the gate is likeliest to fire. Once the merge closed the issue, no
  # later tick lists it (run_lane reads open issues only), so a gated close is an outcome the owner never reads,
  # and a worktree and branch left for the sweep to report. A close builds nothing — it is `gh` calls and one
  # comment — so letting it through costs the host nothing.
  if [ "$WORKER" -gt 1 ] && [ "$stage" != close ]; then
    local load; load=$(cut -d ' ' -f 1 "$LOADAVG" 2>/dev/null || true)
    if ! [[ $load =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! awk -v l="$load" -v c="$LOAD_CEILING" 'BEGIN { exit !(l + 0 <= c + 0) }'; then
      log "issue #$n: 1-min load ${load:-unreadable} is above the ceiling $LOAD_CEILING — worker $WORKER launches no session this tick"
      exit 0
    fi
  fi
  case "$stage" in implement|review) dir="$wt" ;; esac
  # The line ends with the issue's class, which loop_share counts: stage_of read the labels just before, for this
  # issue; only a caller that did not (none today) costs one read here.
  [ "$LAST_LABELS_N" = "$n" ] || { LAST_LABELS=$(labels_of "$n") || LAST_LABELS=""; LAST_LABELS_N=$n; }
  log "issue #$n: stage $stage${hint:+ ($hint)} (cwd ${dir}) [class:$(issue_class "$LAST_LABELS")]"
  if [ "$DRY" = 1 ]; then return 0; fi
  [ "$stage" != close ] || [ -z "$hint" ] || echo "$hint $(date +%s)" > "$STATE/issue-$n.close-last"
  if [ "$dir" = "$wt" ]; then
    [ -z "$merged_pr" ] || new_round_base "$n" "$merged_pr" "$wt" || return 1
    if [ ! -d "$wt" ]; then
      local base; base=$(branch_of "$n") || base=origin/main
      if [ "$base" = "issue-$n" ]; then git worktree add -q "$wt" "issue-$n"; else git worktree add -q -b "issue-$n" "$wt" "$base"; fi
    fi
    ff_branch "$n" "$wt"
  fi
  local prompt
  prompt=$(stage_prompt "$n" "$stage" "$hint")
  local rc=0 t0 sess cfd=""; t0=$(date +%s)
  # A session working in the primary checkout holds that tree's lock, shared, for as long as it runs — the rule
  # and its reasons are at ff_locked. Waiting for it costs a fast-forward's second or two.
  if [ "$dir" = "$ROOT" ]; then exec {cfd}> "$STATE/.lock-checkout"; flock -s "$cfd"; fi
  # The session runs in the background and this tick waits on it, so that the board can be refreshed while it
  # runs: the session holds this lane's lock for as long as it takes, and the fast lane's oneshot unit starts
  # no second tick meanwhile, so the page's "last checked" line would otherwise age past what the page itself
  # calls stopped while the loop is working. Waiting here rather than refreshing from a background
  # process leaves nothing running that could outlive the tick and hold its locks.
  # The factory's own helpers, which the prompts call by their installed path, are allowed on the command line —
  # added to the project's allowlist (measured with a headless session: allowed with the flag, refused without),
  # so a project's committed settings need not know where this host installed the factory. Only these two.
  local helpers; helpers=$(cd "$HERE" && pwd)
  ( cd "$dir" && timeout "$SESSION_TIMEOUT" claude -p "$prompt" --model "$MODEL" --effort "$(stage_effort "$stage")" \
      --max-turns "$(stage_turns "$stage")" ${SANDBOX:+--add-dir "$SANDBOX"} \
      --allowedTools "Bash(bash $helpers/ci-wait.sh *)" "Bash(bash $helpers/self-review.sh *)" \
      --permission-mode acceptEdits --output-format text ) > "$out" 2>&1 &
  sess=$!
  [ "$BOARD_LOADED" != 1 ] || board_wait "$sess"
  wait "$sess" || rc=$?
  [ -z "$cfd" ] || exec {cfd}>&-
  tail -n 3 "$out" | sed 's/^/    /' | tee -a "$STATE/ticks.log"
  case "$stage" in implement|review) reap_leftovers "$n" ;; esac
  # A session that ended non-zero within two minutes never reached the model, and the tick must not start it —
  # or every other in-flight issue — again every five minutes: from 2026-09-20 to 09-29 some 10,300 such sessions
  # ran, first on a `weekly limit` line the old anchor `(session|usage) limit` did not match, then on an expired
  # login nothing matched, while the board read as alive.
  # Three cases, each anchored on rc, duration and the LAST line — never on free text, which a session's own
  # summary could reproduce — because a false positive pauses the whole loop.
  local last fast=0; last=$(tail -n 1 "$out" 2> /dev/null || true)
  [ $(( $(date +%s) - t0 )) -ge 120 ] || fast=1
  if [ "$rc" -ne 0 ] && [ "$fast" = 1 ] && grep -qE "^You've hit your [A-Za-z ]+ limit" <<< "$last"; then
    # 1. The account's usage limit — a session's, the week's, a model family's: paused until the CLI's "resets …".
    local resets lifts; resets=$(grep -oE 'resets .*' <<< "$last" || true)
    lifts=$(limit_until "$resets")
    pause_lanes "$lifts" "the AI account's usage limit was reached ($resets), so the loop starts nothing new until then"
    log "issue #$n: stage $stage — account usage limit ($resets); both lanes paused until $(date -u -d "@$lifts" +%FT%H:%MZ)"
    exit 0
  fi
  if [ "$rc" -ne 0 ] && [ "$fast" = 1 ] && grep -q "Failed to authenticate" <<< "$last"; then
    # 2. The login the sessions use has expired: 30 min at a time, and one note on the monitor issue until a
    # session gets through again. The step is the owner's: a token of the loop's own in the units' env file.
    pause_lanes $(( $(date +%s) + 1800 )) "the loop's login has expired, so its sessions cannot start: run \`claude setup-token\` and put the token in ~/.config/factory/$NAME.env as CLAUDE_CODE_OAUTH_TOKEN, or log in again on the host"
    log "issue #$n: stage $stage — login expired ($last); both lanes paused 30 min"
    if [ ! -e "$STATE/.auth-posted" ]; then
      printf "The loop's sessions cannot start: its login has expired (%s). Nothing runs until you run \`claude setup-token\` and put the token in ~/.config/factory/$NAME.env as CLAUDE_CODE_OAUTH_TOKEN, or log in again on the host. The loop tries again every 30 minutes and carries on by itself once a session gets through.\n" "$last" > "$STATE/auth-note.txt"
      "$POST" "🔒 factory login expired" "$STATE/auth-note.txt" && touch "$STATE/.auth-posted"
    fi
    exit 0
  fi
  if [ "$rc" -ne 0 ] && [ "$fast" = 1 ]; then
    # 3. Any other fast death, three in a row across issues — a CLI change, a missing tool, a wording of case 1
    # this anchor does not know: paused 30 min, said with the last line, in place of the tick-by-tick relaunch.
    local fails; fails=$(( $(cat "$STATE/.fast-fails" 2> /dev/null || echo 0) + 1 )); echo "$fails" > "$STATE/.fast-fails"
    if [ "$fails" -ge 3 ]; then
      rm -f "$STATE/.fast-fails"
      pause_lanes $(( $(date +%s) + 1800 )) "$fails sessions in a row ended within two minutes without doing anything (the last said: ${last:-nothing}), so the loop paused itself for 30 minutes rather than start every issue again every few minutes"
      log "issue #$n: stage $stage — $fails fast failures in a row (last line: ${last:-none}); both lanes paused 30 min"
      exit 0
    fi
  else
    rm -f "$STATE/.fast-fails" "$STATE/.auth-posted"   # a session that ran: the run of dead ones, if any, is over
  fi
  if [ "$rc" -ne 0 ]; then
    log "issue #$n: stage $stage exited non-zero (rc=$rc: timeout or error) — see $out"
    return 1
  fi
}

# Epoch when the account limit lifts: the CLI's "resets …" phrase when GNU date reads it as a
# time within the next 7 days (a weekly limit), else 30 min from now — a re-probe costs one
# instant-fail session. A bare clock time (observed: `resets 1am (UTC)`) is read in the host's zone,
# which the CLI prints, and as today: over an hour past means tomorrow's (a DST day is an
# hour off). Less is a boundary near-miss — display rounding, clock skew, the re-probe tick — and
# keeps the 30-min fallback, never a wrong day-long halt; so does a phrase that carries a date — the
# match is anchored at both ends, so `11pm Sep 16 (UTC)` is not bare.
limit_until() {
  local when now ts bare='^[0-9]{1,2}(:[0-9]{2})?[[:space:]]*[ap]m[[:space:]]*(\([^)]*\))?[[:space:]]*$'
  now=$(date +%s)
  when=${1#resets }; when=${when%.}
  if [ -n "$when" ] && ts=$(date -d "$when" +%s 2>/dev/null); then
    if [ "$ts" -le $((now - 3600)) ] && [[ $when =~ $bare ]]; then ts=$((ts + 86400)); fi
    if [ "$ts" -gt "$now" ] && [ "$ts" -le $((now + 7 * 86400)) ]; then echo "$ts"; return; fi
  fi
  echo $((now + 1800))
}

# Per-stage effort and turn cap, set on the command line
# and never left to the user settings a headless session also reads — until 2026-09-29 every session ran at the
# owner's interactive `xhigh`. `implement` and `review` at high (the merge gate, the code that touches recorded
# data), the two short stages at medium; the caps from the measured median of 50 turns and 90th percentile of 108.
stage_effort() { local v="FACTORY_EFFORT_${1^^}"; case "$1" in implement|review) echo "${!v:-high}" ;; *) echo "${!v:-medium}" ;; esac; }
stage_turns() { local v="FACTORY_TURNS_${1^^}"; case "$1" in implement) echo "${!v:-120}" ;; review) echo "${!v:-80}" ;; *) echo "${!v:-30}" ;; esac; }

# Pauses both lanes until an epoch, with the reason the next ticks log and the board prints. The
# marker is the one run_lane and the board have always read for the usage limit; the reason file is what lets a
# dead login or a run of dead sessions read as what they are, rather than as a limit.
pause_lanes() {
  echo "$1" > "$STATE/.usage-limit-until"
  printf '%s\n' "$2" > "$STATE/.pause-reason"
}

# What an issue leaves on this host besides its worktree and branch: what the project's cleanup takes, and its reply record
# (read_reply). cleanup_issue takes them, and so does the sweep for a closed issue whose folder it keeps (issue
# #336). Not the close gate's record (issue-N.close-last): cleanup runs after every close stage, open service
# issue or not, and taking the record there would let the next tick run the same close again.
reap_issue() { reap_leftovers "$1"; rm -f "$STATE/issue-$1.replied"; }

# Cleanup after a merged issue: reap_issue, then its worktree and, once the folder is gone, its local branch. Fails
# while the folder or the branch stays, with git's reason in CLEANUP_ERR.
# A branch checked out in another folder, such as the primary checkout, will not delete. `git worktree prune` drops
# git's record of a folder that is gone — deleted by hand, or by a remove that died half-way — which would otherwise
# keep its branch from deleting for good. It keeps a locked one, whose branch then stays until
# `git worktree unlock`, the step the sweep's report names.
cleanup_issue() {
  local n="$1" err="" what
  local wt="$ROOT/.claude/worktrees/issue-$n"   # own line, see run_stage
  reap_issue "$n"
  if [ -d "$wt" ] && err=$(git worktree remove --force "$wt" 2>&1); then log "issue #$n: worktree removed"; fi
  git worktree prune || true
  if [ -d "$wt" ]; then what="its working folder $wt was not removed"
  elif ! git show-ref --quiet "refs/heads/issue-$n" || err=$(git branch -q -D "issue-$n" 2>&1); then return 0
  else what="its branch issue-$n was not deleted"; fi
  CLEANUP_ERR=${err%%$'\n'*}; CLEANUP_ERR=${CLEANUP_ERR:-git gave no reason}
  log "issue #$n: $what — $CLEANUP_ERR"; return 1
}

# What a review session moves when it hands a round back to the reviewer: the PR head (a push) and
# the time of its latest `review` label (a re-request). Fails when either read fails.
review_mark() {
  local pr sha at
  pr=$(pr_of "$1"); pr=${pr%% *}
  sha=$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid) || return 1
  at=$(gh api "repos/$REPO/issues/$pr/events" --paginate \
         --jq '.[] | select(.event == "labeled" and .label.name == "review") | .created_at') || return 1
  echo "$sha ${at##*$'\n'}"
}

# Advance one issue by up to MAX_STAGES stages — only the stages of the current lane.
advance() {
  local n="$1" steps=0 stage prev="" rc mark="" now b
  while [ "$steps" -lt "$MAX_STAGES" ]; do
    read_stage "$n"; stage=$STAGE
    # The same stage twice in a row means the last session left no visible progress
    # (ended early): retry next tick rather than re-running it now. A review
    # round that pushed a fix or re-requested the review keeps its stage by design; it waits for the
    # verdict, and so does a check that linked a
    # blocker and kept `ready`.
    if [ "$stage" = "$prev" ]; then
      now=""; [ -z "$mark" ] || now=$(review_mark "$n") || now=""
      if [ -n "$now" ] && [ "${now#* }" != "${mark#* }" ]; then
        log "issue #$n: stage review: round re-requested — waiting for the verdict"
      elif [ -n "$now" ] && [ "${now%% *}" != "${mark%% *}" ]; then
        log "issue #$n: stage review: pushed, not re-requested — review_state re-requests after ${REVIEW_GRACE} s"
      elif [ "$stage" = verify ] && b=$(blockers_of "$n") && [ -n "$b" ]; then
        b=$(printf ' issue #%s,' $b); log "issue #$n: stage verify: checked, and blocked by${b%,} — it keeps its place in the queue, which the pick skips until then"
      else
        log "issue #$n: stage $stage made no progress — next tick"
      fi
      return
    fi
    # Verified just now, so its `area:` labels are known: checked here, under the issue lock, before any slow worker
    # can start it — and again where the slow lane builds, which an `in-progress` left on cannot skip.
    if [ "$stage" = implement ] && { [ "$prev" = verify ] || [ "$LANE" = slow ]; } && hold_area "$n"; then return; fi
    prev=$stage; mark=""
    # The other lane's stage: hand over (fast = verify/review/close, slow = implement). Then, in the fast lane,
    # the other workers' stage: `review` is theirs and the rest worker 1's, once the lane has more than one
    # The next tick of whichever worker owns it takes it, within five minutes.
    case "$LANE:$stage" in
      fast:implement) log "issue #$n: stage implement — the slow lane's"; return ;;
      slow:implement) ;;
      slow:verify|slow:review|slow:close) log "issue #$n: stage $stage — the fast lane's"; return ;;
      slow:*) return ;;   # none/blocked/abandoned: the fast lane reports and parks them
      fast:*) fast_stage_mine "$stage" || { log "issue #$n: stage $stage — $(fast_stage_whose)"; return; } ;;
    esac
    case "$stage" in
      blocked|held) log "issue #$n: nothing to do ($stage)"; return ;;
      abandoned) park_issue "$n" owner:pr-closed "its pull request was closed without being merged, so the loop cannot tell whether the work is still wanted" "$CLOSED_PR_ANSWER"; return ;;
      close)
        rc=0; run_stage "$n" close || rc=$?
        [ "$rc" = 3 ] && return   # release pending: nothing launched, nothing to clean up yet
        [ "$DRY" = 1 ] || cleanup_issue "$n"
        return ;;
      review)
        [ "$DRY" = 1 ] || mark=$(review_mark "$n") || mark=""   # before the session, for the check above
        run_stage "$n" review || return ;;
      *) run_stage "$n" "$stage" || return ;;
    esac
    steps=$((steps + 1))
    [ "$DRY" = 1 ] && return
    # Closed under its stage. `close` runs in the primary checkout, so only the fast lane runs it — any of its
    # workers, since this is the close of the merge THIS worker's review just made, and the tree holds still
    # under it for the reason at ff_locked. An issue closed during a slow-lane implement had no
    # loop merge to report (a `Part of #N` PR keeps it open).
    [ "$(issue_state "$n")" = "OPEN" ] || { [ "$LANE" = slow ] || run_stage "$n" close; cleanup_issue "$n"; return; }
  done
}

#!/usr/bin/env bash
# self-review: ONE fresh headless review pass over this branch before its PR opens — the rubric and the model of
# the project's review workflow (its first prompt block and its --model, read at run time), in a context that did
# not write the code. Read-only by construction: the reviewer gets Read, Grep and Glob, no shell and no MCP server,
# so it can neither post to GitHub nor change the tree. Its final message is the verdict, saved as
# self-review-verdict.md (keep it out of git) with the workflow's counts and "fix-before-merge set" lines.
# Run in the branch's worktree (the implement stage calls it by the installed factory's path):
#
#   bash <factory>/scripts/self-review.sh <base> [pr-body-file]   review `git diff <base>...HEAD` (commit first)
#   bash <factory>/scripts/self-review.sh --wait                   keep waiting for the review already running
#
# A pass can outlast one 600-s Bash call of a headless session (call it with that timeout), so the review runs
# detached, bounded by SELF_REVIEW_TIMEOUT (900 s), and each call waits at most SELF_REVIEW_WAIT (570 s).
# Exit 0 = verdict · 1 = no verdict (DEGRADED — not an all-clear) · 2 = refused (usage, uncommitted edits, empty
# diff, no prompt block or model in the workflow) · 3 = still running: call `--wait` again · 4 = not needed: the
# project turned it off (FACTORY_SELF_REVIEW=0), or the diff touches no path its FACTORY_SELF_REVIEW_PATHS (an
# extended regex over the changed paths; default: every path) names — the real review covers it alone.
set -euo pipefail
SELF=$(realpath "$0")
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=factory-config.sh
. "$(dirname "$SELF")/factory-config.sh"
FACTORY_CHECKOUT=$PWD factory_config > /dev/null 2>&1 || true   # the branch's own .factory/config, if any
VERDICT=self-review-verdict.md DIFF=self-review.diff LOG=self-review.log PID=self-review.pid
TIMEOUT="${SELF_REVIEW_TIMEOUT:-900}" WAIT="${SELF_REVIEW_WAIT:-570}"
WORKFLOW=".github/workflows/${FACTORY_REVIEW_WORKFLOW:-claude-review.yml}"
PATHS="${FACTORY_SELF_REVIEW_PATHS:-.}"
SET_LINE='fix-before-merge set: [*_]*[0-9]'   # a verdict's own line: VERDICT_RE of scripts/factory-tick.sh

running() { [ -s "$PID" ] && kill -0 "$(cat "$PID")" 2> /dev/null; }

# The rubric has one source, the workflow: the first `prompt: |` block — the "Severity-ranked review" step —
# dedented, with the runner's verdict path swapped for ours. It fails loudly, never reviews with a partial rubric,
# when the workflow's layout moves.
rubric() {
  local text
  text=$(awk '/^          prompt: \|$/ { f = 1; next }
              f && /^          [^ ]/ { exit }
              f { sub(/^            /, ""); print }' "$WORKFLOW")
  case "$text" in
    "Review this pull request as ONE severity-ranked pass"*"fix-before-merge set: N"*) ;;
    *) echo "self-review: no review prompt block found in $WORKFLOW (its layout moved?)" >&2; return 1 ;;
  esac
  printf '%s\n' "${text//'${{ runner.temp }}/claude-review-verdict.md'/$VERDICT}"
}

# The model is the same step's `--model` (the file's first `claude_args` line), so the reviewer's pin has one place
# to flip, not a copy here.
model() {
  local m
  m=$(grep -m1 "^          claude_args: " "$WORKFLOW") || true
  m=${m#*"--model "}   # no --model: the line stays whole, its leading indent empties it below
  m=${m%% *}
  m=${m%\'}
  case "$m" in
    claude-*) printf '%s\n' "$m" ;;
    *) echo "self-review: no --model in the first claude_args of $WORKFLOW (its layout moved?)" >&2; return 1 ;;
  esac
}

# Where the rubric assumes a pull request, the local facts.
preamble() {
  local base="$1" body="$2" said="No PR body was drafted: judge the net LOC from the diff."
  [ -z "$body" ] || said="The drafted PR body is $body."
  cat << EOF
LOCAL SELF-REVIEW. The rubric below is the review prompt of $WORKFLOW. Where it assumes a pull request, these
lines win:
- There is no PR yet. The change under review is \`git diff $base...HEAD\`, saved as $DIFF: read it
  first. The checkout is at HEAD. $said
- You have Read, Grep and Glob only: no shell, no GitHub, no file writes. Post nothing. List EVERY
  finding in the verdict, [blocking]/[critical]/[major] included, as \`path:line — [severity] why\`.
  There are no review threads yet.
- You cannot write $VERDICT yourself: your final message IS its content, the markdown verdict and
  nothing else. This script saves it.
EOF
}

# The detached half: one bounded review, then the verdict (the model's, or a DEGRADED one) moved into
# place in one step, so a waiter never reads half of it.
run_review() {
  local base="$1" body="$2" prompt reviewer rc=0
  prompt="$(preamble "$base" "$body")"$'\n\n'"$(rubric)"
  reviewer=$(model)
  # Its own session, not a child of the caller's (it may outlive it). The effort is set here, not left to the user
  # settings a headless session also reads (an owner's interactive `xhigh`): one read-only pass over a diff.
  unset CLAUDECODE CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID \
    CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
  {
    printf '## Self-review — `%s...%s` (%s)\n\n' "$base" "$(git rev-parse --short HEAD)" "$(date -u +%FT%TZ)"
    timeout "$TIMEOUT" claude -p "$prompt" \
      --model "$reviewer" --effort "${SELF_REVIEW_EFFORT:-medium}" \
      --tools Read,Grep,Glob --restricted --strict-mcp-config --no-session-persistence \
      --output-format text < /dev/null || rc=$?
  } > "$VERDICT.tmp"
  if [ "$rc" != 0 ] || ! grep -qi "$SET_LINE" "$VERDICT.tmp"; then
    printf '\nThe review ended without a verdict (rc=%s, see %s) — treat as DEGRADED, not an all-clear.\n\nfix-before-merge set: unknown\n' \
      "$rc" "$LOG" >> "$VERDICT.tmp"
  fi
  mv "$VERDICT.tmp" "$VERDICT"
  rm -f "$PID"   # done: a later pid reuse cannot look like a running review
}

start() {
  local base="$1" body="$2"
  git rev-parse -q --verify "$base^{commit}" > /dev/null || { echo "self-review: unknown base '$base'"; exit 2; }
  [ -z "$body" ] || [ -r "$body" ] || { echo "self-review: cannot read the PR body file '$body'"; exit 2; }
  if running; then echo "self-review: already running (pid $(cat "$PID")) — waiting for it"; return; fi
  # One pass per branch: a resumed session gets the earlier verdict, not a second paid review. It may
  # predate HEAD (a session died mid-wait, the next one committed more): name the commit it read.
  if [ -e "$VERDICT" ]; then
    local seen
    IFS= read -r seen < "$VERDICT"   # its heading: ## Self-review — `<base>...<sha>` (<time>)
    seen=${seen#*...}
    seen=${seen%%\`*}
    echo "self-review: $VERDICT exists (one pass; rm it to review again). It read $seen; HEAD is $(git rev-parse --short HEAD):"
    return
  fi
  rubric > /dev/null && model > /dev/null || exit 2
  # The reviewer reads the tree at HEAD: an uncommitted edit would be judged without being in the diff.
  # Untracked files pass (a session's temp files); they are in neither the diff nor the push.
  [ -z "$(git status --porcelain --untracked-files=no)" ] \
    || { echo "self-review: uncommitted edits — commit first (it reviews git diff $base...HEAD)"; exit 2; }
  git diff "$base...HEAD" > "$DIFF"
  [ -s "$DIFF" ] || { echo "self-review: no change between $base and HEAD"; exit 2; }
  if [ "${FACTORY_SELF_REVIEW:-1}" = 0 ]; then
    rm -f "$DIFF"; echo "self-review: not needed — this project turned it off (FACTORY_SELF_REVIEW=0); the real review covers this diff alone"; exit 4
  fi
  if ! git diff --name-only "$base...HEAD" | grep -qE "$PATHS"; then
    rm -f "$DIFF"
    echo "self-review: not needed — no changed path matches $PATHS (FACTORY_SELF_REVIEW_PATHS); the real review covers this diff alone"
    exit 4
  fi
  setsid bash "$SELF" --run "$base" "$body" > "$LOG" 2>&1 < /dev/null &
  echo "$!" > "$PID"
  echo "self-review: started on $base...$(git rev-parse --short HEAD) (pid $!, bounded to ${TIMEOUT} s)"
}

# Waits up to WAIT for the verdict, a heartbeat a minute, then prints it; exit 1 when it is DEGRADED.
await() {
  local end=$(($(date +%s) + WAIT)) beat=0
  until [ -e "$VERDICT" ]; do
    running || [ -e "$VERDICT" ] || { echo "self-review: no review running and no verdict (see $LOG)"; exit 1; }
    [ "$(date +%s)" -lt "$end" ] || { echo "self-review: still running — call: bash $SELF --wait"; exit 3; }
    [ $((beat++ % 4)) -ne 0 ] || echo "$(date -u +%H:%M:%SZ) self-review running"
    sleep 15
  done
  cat "$VERDICT"
  grep -qi "$SET_LINE" "$VERDICT"
}

case "${1:-}" in
  --run) run_review "$2" "${3:-}" ;;
  --wait) await ;;
  "" | -*) echo "usage: bash $SELF <base> [pr-body-file] | --wait"; exit 2 ;;
  *) start "$1" "${2:-}"; await ;;
esac

#!/usr/bin/env bash
# Scenario test of scripts/factory-stats.sh on scratch state only: session logs named the way the driver names them,
# their end set with `touch -d`, and a hand-written ticks.log. Nothing reads the host's own factory state. Exit 1 on
# any failure. (Negative controls: a copy that cuts the stamp out of the file name one character early fails every
# busy-time case; one that sorts a hand-over's +1 before its -1 fails "a hand-over is not an overlap"; one that
# does not clip a session to the window fails "clipped to the window".)
# Usage: bash tests/factory-stats-test.sh [script]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
SCRIPT=${1:-scripts/factory-stats.sh}
[ -f "$SCRIPT" ] || { echo "factory-stats-test: no such file: $SCRIPT"; exit 2; }
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT

fails=0
says() { # name, wanted line (whole line)
  if grep -qxF -e "$2" "$S/out"; then echo "PASS $1"; else echo "FAIL $1: no such line [$2] in:"; cat "$S/out"; fails=$((fails + 1)); fi
}
fresh() { rm -rf "$S/state"; mkdir -p "$S/state"; : > "$S/state/ticks.log"; }
session() { # issue, stage, start HHMM, end HHMM — on 2026-09-20, UTC
  local f="$S/state/issue-$1-$2-20260920T${3}00Z.log"
  : > "$f"; touch -d "2026-09-20 ${4:0:2}:${4:2:2}:00 UTC" "$f"
}
run() { bash "$SCRIPT" --state "$S/state" --since 2026-09-20T10:00:00Z --until 2026-09-20T11:00:00Z "$@" > "$S/out" 2>&1; }

fresh; session 5 implement 1000 1030; run
says "one build over half the hour" "slow-lane busy 50 % of the window, 2+ at once 0 %, most at once 1"
says "counted by stage" "sessions 1 (verify 0, implement 1, review 0, close 0); 0 under 30 s"

fresh; session 5 implement 1000 1030; session 6 implement 1015 1045; run
says "two builds overlapping for a quarter hour" "slow-lane busy 75 % of the window, 2+ at once 25 %, most at once 2"

fresh; session 5 review 1000 1020; session 6 close 1020 1040; run
says "a hand-over is not an overlap" "fast-lane busy 67 % of the window, 2+ at once 0 %, most at once 1"

fresh; session 5 implement 0930 1015; session 6 implement 1045 1130; run
says "clipped to the window" "slow-lane busy 50 % of the window, 2+ at once 0 %, most at once 1"

fresh; session 7 verify 1000 1006; session 7 implement 1030 1054; session 8 close 1000 1001; run
says "an issue waits between its sessions" "issue life waiting 44 % (1 issue(s) with 2+ sessions: 0.9 h of life, 0.5 h worked)"

fresh; session 9 implement 1000 1000; session 9 review 1010 1010; run
says "a session that died at once is short and adds no busy time" "sessions 2 (verify 0, implement 1, review 1, close 0); 2 under 30 s"
says "… and no busy time" "slow-lane busy 0 % of the window, 2+ at once 0 %, most at once 0"

fresh; session 3 implement 0800 0900; run
says "a session outside the window is not counted" "sessions 0 (verify 0, implement 0, review 0, close 0); 0 under 30 s"

fresh
cat > "$S/state/ticks.log" << 'EOF'
2026-09-20T09:59:00Z [fast] in-flight budget full (5/5); no new issue picked
2026-09-20T10:02:00Z [fast] in-flight budget full (5/5); no new issue picked
2026-09-20T10:07:00Z [fast] in-flight budget full (4/5); no new issue picked
2026-09-20T10:08:00Z [fast] in-flight budget full (3/2); no new issue picked
2026-09-20T10:09:00Z [fast] issue #12 skipped: area:factory-driver in flight on issue #11
2026-09-20T10:10:00Z [slow-2] issue #13: area:core in flight on issue #14 — back to ready, not built
2026-09-20T10:11:00Z [slow] issue #15: stage implement — account usage limit (resets 3pm); both lanes paused until 2026-09-20T15:00Z
2026-09-20T10:12:00Z [fast] issue #16: stage verify — login expired (x); both lanes paused 30 min
2026-09-20T10:13:00Z [fast] account usage limit — paused until 2026-09-20T15:00Z; no session launched
2026-09-20T10:14:00Z [fast] tick done
2026-09-20T10:15:00Z [slow-2] tick done
    a session's own last line, indented by the driver
2026-09-20T11:01:00Z [fast] tick done
EOF
run
says "ticks in the window, by lane" "ticks finished 2 (fast 1, slow 1), log lines 10"
says "the limit each blocked pick names, in order" "picks blocked by the in-flight limit 3 (limit 2: 1, 5: 2)"
says "area skips" "picks skipped for an area in flight 1"
says "builds sent back" "builds sent back for an area in flight 1"
says "a pause is counted where it starts, not on every tick it holds" "loop pauses started 2 (on the account usage limit 1)"

fresh; run --until 2026-09-20T09:00:00Z
says "a window that ends before it starts is refused" "the window ends before it starts"
fresh; bash "$SCRIPT" --state "$S/state" --hours 1.5 > "$S/out" 2>&1
says "a fractional hour count is refused" "--hours takes a whole number of hours, not '1.5'"
bash "$SCRIPT" --state "$S/nowhere" > "$S/out" 2>&1
says "a missing state folder is named" "no factory state at $S/nowhere"

[ "$fails" = 0 ] || { echo "factory-stats-test: $fails failure(s)"; exit 1; }
echo "factory-stats-test: all passed"

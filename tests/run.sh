#!/usr/bin/env bash
# Runs every test of the factory: a syntax check of each script, then each tests/*-test.sh in turn, one line each.
# Every test works on scratch state with fakes of gh, claude and systemctl first on PATH; none reads GitHub, starts a
# session or touches a unit. Exit 1 when any fails.
# Usage: bash tests/run.sh [test name…]   (e.g. `bash tests/run.sh factory-tick config`)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
bad=0
for f in scripts/*.sh tests/*.sh; do bash -n "$f" || { echo "SYNTAX $f"; bad=$((bad + 1)); }; done
if [ $# -gt 0 ]; then tests=(); for t in "$@"; do tests+=("tests/${t%-test.sh}-test.sh"); done; else tests=(tests/*-test.sh); fi
for t in "${tests[@]}"; do
  [ -r "$t" ] || { echo "MISSING $t"; bad=$((bad + 1)); continue; }
  out=$(mktemp); start=$(date +%s)
  if timeout 1200 bash "$t" > "$out" 2>&1; then r=ok; else r=FAILED; bad=$((bad + 1)); fi
  printf '%-7s %-28s %4ss  %s\n' "$r" "${t#tests/}" "$(( $(date +%s) - start ))" "$(tail -n 1 "$out")"
  [ "$r" = ok ] || grep -E '^(FAIL|  )' "$out" | head -n 40
  rm -f "$out"
done
[ "$bad" = 0 ]

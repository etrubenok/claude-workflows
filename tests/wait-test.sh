#!/usr/bin/env bash
# Test of the factory's bounded CI wait: scripts/ci-wait.sh answers 0 only when gh says every check passed, 3 while
# the checks still run (and says how to run it again), and waits out the "no checks reported" of a fresh push.
# `gh`, `sleep` and `timeout` are stubbed on PATH: nothing is read from GitHub, nothing sleeps, and the stub
# `timeout` records the bound ci-wait.sh gave the watch. The elapsed time ci-wait.sh sees is set through SECONDS,
# which bash takes from the environment. Every run is cut at 30 s by the real `timeout`, so a copy whose loop never
# ends fails instead of hanging. Exit 1 on any failure.
# Usage: bash tests/wait-test.sh [dir holding ci-wait.sh]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
DIR=${1:-scripts}
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
# gh: the first STUB_EMPTY `gh pr checks` calls, --watch or not, report no checks; later plain calls
# say "pending" (exit 8), and a later --watch call exits STUB_RC (124 is what `timeout` returns when
# it cut the watch).
cat > "$stub/gh" << 'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$STUB_DIR/calls" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$STUB_DIR/calls"
[ "$n" -gt "$STUB_EMPTY" ] || { echo "no checks reported on the 'issue-1' branch" >&2; exit 1; }
case " $* " in *" --watch "*) exit "$STUB_RC" ;; esac
exit 8
EOF
printf '#!/bin/sh\n' > "$stub/sleep"
printf '#!/usr/bin/env bash\necho "$1" > "$STUB_DIR/bound"; shift; exec "$@"\n' > "$stub/timeout"
chmod +x "$stub/gh" "$stub/sleep" "$stub/timeout"

fails=0
check() { # name, got, want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}
ci() { # STUB_EMPTY, STUB_RC, SECONDS at start, args… → the exit code of ci-wait.sh
  rm -f "$stub/calls" "$stub/bound"
  timeout 30 env PATH="$stub:$PATH" STUB_DIR="$stub" STUB_EMPTY="$1" STUB_RC="$2" SECONDS="$3" \
    bash "$DIR/ci-wait.sh" "${@:4}" > /dev/null 2>&1
  echo $?
}
bound() { cat "$stub/bound" 2> /dev/null || echo none; }
check "ci-wait: green" "$(ci 0 0 0 1)" 0
check "ci-wait: a red check passes through" "$(ci 0 1 0 1)" 1
check "ci-wait: still running when the watch is cut" "$(ci 0 124 0 1)" 3
check "ci-wait: no checks yet after a push, then green" "$(ci 2 0 0 1)" 0
check "ci-wait: no checks for 480 s is not green" "$(ci 99 0 480 1)" 1
check "ci-wait: no PR number" "$(ci 0 0 0)" 2
ci 0 0 100 1 > /dev/null # the watch gets what is left of 570 s (a second may tick during the run)
check "ci-wait: the watch is bounded by the 570 s" "$(case $(bound) in 469 | 470) echo ok ;; *) bound ;; esac)" ok
check "ci-wait: no time left is still running" "$(ci 0 0 570 1) $(bound)" "3 none"

rm -f "$stub/calls"
said=$(timeout 30 env PATH="$stub:$PATH" STUB_DIR="$stub" STUB_EMPTY=0 STUB_RC=124 SECONDS=0 bash "$DIR/ci-wait.sh" 7 2> /dev/null | tail -n 1)
check "ci-wait: still running names the command that runs it again, by its own path" "$said" \
  "ci-wait: checks still running — run: bash $DIR/ci-wait.sh 7"

echo "wait-test: $fails failure(s)"
[ "$fails" = 0 ]

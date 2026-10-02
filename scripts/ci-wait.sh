#!/usr/bin/env bash
# Bounded in-session wait for a PR's CI (the `review` stage, its merge step).
# `gh pr checks --watch --fail-fast` for at most 570 s, one table a minute: one headless Bash call
# stops at 600 s and a cold CI gate job takes longer. Just after a push gh says "no
# checks reported" until the workflows register; that is waited out first, silently, inside the
# same 570 s.
# Exit 0 = every check passed, the only code to merge on; 3 = still running: run it again (the
# self-review.sh `--wait` idiom); 2 = usage;
# anything else = not green: read the table.
set -u
[ $# -eq 1 ] || { echo "usage: bash $0 <pr>" >&2; exit 2; }
while [[ $(gh pr checks "$1" 2>&1) == *"no checks reported"* ]]; do
  [ "$SECONDS" -lt 480 ] || { echo "ci-wait: still no checks on PR $1 after 480 s (GitHub runs no CI on a conflicting PR)"; exit 1; }
  sleep 30
done
left=$(( 570 - SECONDS )) rc=124 # `timeout 0` would switch the bound off: no time left = still running
[ "$left" -le 0 ] || { timeout "$left" gh pr checks "$1" --watch --fail-fast --interval 60; rc=$?; }
[ "$rc" -ne 124 ] || { echo "ci-wait: checks still running — run: bash $0 $1"; exit 3; }
exit "$rc"

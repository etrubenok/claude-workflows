#!/usr/bin/env bash
# Scenario test of the installer on scratch state only: a clean scratch copy of this factory checkout is installed
# into a scratch HOME for a scratch clone of `fake/repo`, with `systemctl`, `gh`, `loginctl` and `claude` fakes first
# on PATH that record what they are asked and change nothing. It checks the installed copy (scripts without their
# tests, the prompts, a VERSION naming the commit), the rendered units (no placeholder left; the checkout, the
# installed driver and the env file named), the env file (created once, mode 600, never overwritten), the timers
# enabled for the budget and its drop-in, the labels (the factory's own and the project's labels file), the two
# refusals that leave the host untouched (an edited factory tree; a target off main), and `--uninstall` (timers off,
# units and installed copy gone, the state and the env file kept). Exit 1 on any failure.
# Usage: bash tests/installer-test.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@invalid
unset "${!FACTORY_@}"
mkdir -p "$S/bin" "$S/home"
printf '#!/bin/sh\necho "$*" >> "$FAKE_DIR/systemctl"\n' > "$S/bin/systemctl"
printf '#!/bin/sh\necho "$*" >> "$FAKE_DIR/gh"\n' > "$S/bin/gh"
printf '#!/bin/sh\necho yes\n' > "$S/bin/loginctl"
printf '#!/bin/sh\nexit 0\n' > "$S/bin/claude"
chmod +x "$S/bin/"*

# The factory as a clean commit of its own: the installer refuses an edited tree.
SRC=$S/src
mkdir -p "$SRC"; cp -r scripts prompts systemd "$SRC/"; mkdir -p "$SRC/tests"; cp tests/installer-test.sh "$SRC/tests/"
git init -q -b main "$SRC" && git -C "$SRC" add -A && git -C "$SRC" commit -qm factory
INSTALLER=$(find "$SRC/scripts" -name 'factory-inst*.sh' | head -n 1)
# The project: a clone of fake/repo on main, its config and labels committed.
CO=$S/co
git init -q -b main "$CO"; git -C "$CO" remote add origin git@github.com:fake/repo.git
mkdir -p "$CO/.factory"
printf 'FACTORY_NAME=demo\nFACTORY_CHECK="make test"\n' > "$CO/.factory/config"
printf '%s\n' '# name|color|description' 'p1-production|B60205|something wrong in production: down or losing data' \
  'p2-product||the product work: features and fixes' 'p3-tooling||the tooling: CI and the factory settings' \
  'area:api||the HTTP API: src/api/**' > "$CO/.factory/labels"
git -C "$CO" add -A && git -C "$CO" commit -qm project

fails=0 n=0
check() { # name, got, want
  n=$((n + 1))
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}
install_() { # [env assignments…] -- [installer args…]: one run; its exit in $rc, its output in $S/out
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  env PATH="$S/bin:$PATH" HOME="$S/home" FAKE_DIR="$S" "${envs[@]}" bash "$INSTALLER" "$@" > "$S/out" 2>&1
  rc=$?
}
SHARE=$S/home/.local/share/factory/demo UNITS=$S/home/.config/systemd/user ENVF=$S/home/.config/factory/demo.env

install_ -- "$CO"
check "install: exit 0" "$rc" 0
check "install: the scripts are copied, without their tests" \
  "$([ -x "$SHARE/scripts/factory-tick.sh" ] && echo driver) $(find "$SHARE" -name '*-test.sh' | grep -c .)" "driver 0"
check "install: the prompts are copied" "$(ls "$SHARE/prompts/stages" | paste -sd ' ' -) $([ -r "$SHARE/prompts/header.md" ] && echo header)" \
  "close.md implement.md review.md verify.md header"
check "install: VERSION names the installed commit" "$(head -n 1 "$SHARE/VERSION")" "$(git -C "$SRC" describe --always --dirty --tags)"
check "install: the four units and worker 1's calendar" \
  "$(cd "$UNITS" && ls factory-demo-* -d | paste -sd ' ' -) $([ -r "$UNITS/factory-demo-fast@1.timer.d/every-2-min.conf" ] && echo cal)" \
  "factory-demo-fast@1.timer.d factory-demo-fast@.service factory-demo-fast@.timer factory-demo-slow@.service factory-demo-slow@.timer cal"
check "install: no placeholder left in a unit" "$(cat "$UNITS"/factory-demo-* "$UNITS"/factory-demo-fast@1.timer.d/* 2> /dev/null | grep -c '@[A-Z]*@')" 0
check "install: the fast unit runs the installed driver for the checkout, with the env file" \
  "$(grep -c "^ExecStart=$SHARE/scripts/factory-tick.sh --lane fast --worker %i$" "$UNITS/factory-demo-fast@.service") $(grep -c "^Environment=FACTORY_CHECKOUT=$CO$" "$UNITS/factory-demo-fast@.service") $(grep -c '^EnvironmentFile=-%h/.config/factory/demo.env$' "$UNITS/factory-demo-fast@.service")" "1 1 1"
check "install: the slow unit runs the slow lane" "$(grep -c -- '--lane slow --worker %i$' "$UNITS/factory-demo-slow@.service")" 1
check "install: the env file, private" "$(stat -c %a "$ENVF" 2> /dev/null)" 600
check "install: one fast and one slow worker enabled, worker 1's calendar armed" \
  "$(grep -c '^--user enable --now factory-demo-fast@1.timer$' "$S/systemctl") $(grep -c '^--user enable --now factory-demo-slow@1.timer$' "$S/systemctl") $(grep -c 'enable --now factory-demo-[a-z]*@[2-9]' "$S/systemctl") $(grep -c '^--user restart factory-demo-fast@1.timer$' "$S/systemctl")" "1 1 0 1"
check "install: the default budget writes no drop-in" "$([ -e "$UNITS/factory-demo-fast@.service.d/budget.conf" ] && echo written || echo none)" none
created=$(sed -n 's/^label create \([^ ]*\) --repo fake\/repo .*/\1/p' "$S/gh" | sort | paste -sd ' ' -)
check "install: the factory's labels and the project's" "$created" \
  "area:api hold in-progress in-review needs-decision p1-production p2-product p3-tooling ready review tracking waiting"
check "install: a label with no color gets the default" "$(grep -c '^label create area:api --repo fake/repo --color C5DEF5 ' "$S/gh")" 1
check "install: no note about the token is missed" "$(grep -c 'no CLAUDE_CODE_OAUTH_TOKEN yet' "$S/out")" 1

echo 'CLAUDE_CODE_OAUTH_TOKEN=secret' >> "$ENVF"; echo stale > "$SHARE/stale.txt"; : > "$S/systemctl"
install_ FACTORY_IMPLEMENT_SLOTS=2 FACTORY_MAX_IN_FLIGHT=3 -- "$CO"
check "re-install: exit 0" "$rc" 0
check "re-install: the env file is kept as it is" "$(grep -c '^CLAUDE_CODE_OAUTH_TOKEN=secret$' "$ENVF")" 1
check "re-install: the installed copy is replaced whole" "$([ -e "$SHARE/stale.txt" ] && echo kept || echo gone) $(find "$(dirname "$SHARE")" -maxdepth 1 -name 'demo.*' | grep -c .)" "gone 0"
check "re-install: the budget's drop-in, and the second slow worker" \
  "$(cat "$UNITS/factory-demo-fast@.service.d/budget.conf" 2> /dev/null | paste -sd ' ' -) $(grep -c '^--user enable --now factory-demo-slow@2.timer$' "$S/systemctl")" \
  "[Service] Environment=FACTORY_IMPLEMENT_SLOTS=2 Environment=FACTORY_REVIEW_WORKERS=1 Environment=FACTORY_MAX_IN_FLIGHT=3 1"
: > "$S/systemctl"
install_ -- "$CO"
check "re-install with no budget given keeps the installed one" \
  "$(grep -c '^Environment=FACTORY_IMPLEMENT_SLOTS=2$' "$UNITS/factory-demo-fast@.service.d/budget.conf") $(grep -c 'disable --now factory-demo-slow@2' "$S/systemctl")" "1 0"
install_ FACTORY_IMPLEMENT_SLOTS=1 FACTORY_MAX_IN_FLIGHT= -- "$CO"
dis=$(grep -n '^--user disable --now factory-demo-slow@2.timer$' "$S/systemctl" | tail -n 1 | cut -d: -f1)
rel=$(grep -n '^--user daemon-reload$' "$S/systemctl" | tail -n 1 | cut -d: -f1)
check "a narrowed install disables the surplus worker after the lower count is live" \
  "$([ -n "$dis" ] && [ -n "$rel" ] && [ "$dis" -gt "$rel" ] && echo after || echo "disable at ${dis:-none}, last reload at ${rel:-none}")" after
check "a narrowed install writes the lower count" "$(grep -c '^Environment=FACTORY_IMPLEMENT_SLOTS=1$' "$UNITS/factory-demo-fast@.service.d/budget.conf")" 1

echo edit >> "$SRC/scripts/factory-tick.sh"; : > "$S/systemctl"; : > "$S/gh"
install_ FACTORY_NAME=other -- "$CO"
check "an edited factory tree: refused, nothing installed" \
  "$rc $(grep -c 'refused — uncommitted or untracked files' "$S/out") $([ -e "$S/home/.local/share/factory/other" ] && echo installed || echo none) $(grep -c . "$S/systemctl") $(grep -c . "$S/gh")" "1 1 none 0 0"
git -C "$SRC" checkout -q -- scripts/factory-tick.sh
git -C "$CO" checkout -q -b feature
install_ FACTORY_NAME=other -- "$CO"
check "a target off main: refused, nothing installed" \
  "$rc $(grep -c "refused — $CO is on feature, not main" "$S/out") $([ -e "$S/home/.local/share/factory/other" ] && echo installed || echo none)" "1 1 none"
git -C "$CO" checkout -q main

mkdir -p "$S/home/.local/state/factory/demo"; echo log > "$S/home/.local/state/factory/demo/ticks.log"; : > "$S/systemctl"
install_ -- --uninstall "$CO"
check "uninstall: exit 0" "$rc" 0
check "uninstall: every timer disabled" "$(grep -c '^--user disable --now factory-demo-fast@1.timer$' "$S/systemctl") $(grep -c '^--user disable --now factory-demo-slow@1.timer$' "$S/systemctl")" "1 1"
check "uninstall: units and installed copy gone" "$(find "$UNITS" -maxdepth 1 -name 'factory-demo-*' | grep -c .) $([ -e "$SHARE" ] && echo kept || echo gone)" "0 gone"
check "uninstall: the state and the env file kept" \
  "$(cat "$S/home/.local/state/factory/demo/ticks.log") $(grep -c '^CLAUDE_CODE_OAUTH_TOKEN=secret$' "$ENVF")" "log 1"

echo "installer: $n cases, $fails failed"
[ "$fails" = 0 ]

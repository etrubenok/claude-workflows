#!/usr/bin/env bash
# Table-driven test of scripts/factory-config.sh on scratch repositories: how a `.factory/config` line is read
# (quotes, a trailing comment, a value with spaces), that a setting already in the environment wins, that a line
# which is not a setting is skipped with a warning and never run, the repository taken from origin in each spelling
# GitHub accepts, the instance name derived from it, and the two refusals (no repository; a name the host cannot
# use). Also the labels file's plain words. Nothing outside the scratch folder is read. Exit 1 on any failure.
# Usage: bash tests/config-test.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
LIB=$(realpath -e scripts/factory-config.sh) || exit 2
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fails=0 n=0
check() { # name, got, want
  n=$((n + 1))
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}
# read_cfg <checkout> [VAR=value…] -- <variables to print>: factory_config in a clean shell; prints rc, then each one
read_cfg() {
  local co=$1; shift; local -a envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  env -i PATH="$PATH" HOME="$S" "${envs[@]}" bash -c '. "$1"; shift; FACTORY_CHECKOUT=$1; shift
    factory_config 2> "$FACTORY_CHECKOUT.err"; rc=$?; printf "%s" "$rc"; for v in "$@"; do printf "|%s" "${!v-unset}"; done' \
    _ "$LIB" "$co" "$@"
}
mk() { git init -q -b main "$1"; [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; mkdir -p "$1/.factory"; }

mk "$S/a" git@github.com:Acme/Web-App.git
cat > "$S/a/.factory/config" << 'EOF'
# a comment line

FACTORY_CHECK="make check"   # the gate
FACTORY_SELF_REVIEW_PATHS='^(src|lib)/'
FACTORY_LOOP_SHARE_MAX=30            # percent
FACTORY_SANDBOX=/srv/scratch/web
FACTORY_EMPTY=
not a setting at all
FACTORY_RUN=$(touch /tmp/should-not-exist-factory-config-test)
export FACTORY_X=1
EOF
check "quotes, a trailing comment and plain values" \
  "$(read_cfg "$S/a" -- FACTORY_CHECK FACTORY_SELF_REVIEW_PATHS FACTORY_LOOP_SHARE_MAX FACTORY_SANDBOX FACTORY_EMPTY)" \
  "0|make check|^(src|lib)/|30|/srv/scratch/web|"
check "the repository from origin, and the name from it, lowercased" "$(read_cfg "$S/a" -- FACTORY_REPO FACTORY_NAME)" "0|Acme/Web-App|web-app"
check "a value is text, never run" "$(read_cfg "$S/a" -- FACTORY_RUN) $([ -e /tmp/should-not-exist-factory-config-test ] && echo ran || echo 'not run')" \
  '0|$(touch /tmp/should-not-exist-factory-config-test) not run'
check "a line that is not a setting is skipped, with a warning each" \
  "$(read_cfg "$S/a" -- FACTORY_X >/dev/null; grep -c 'ignored a line that is not FACTORY_<NAME>=<value>' "$S/a.err")" 2
check "the environment wins over the file" "$(read_cfg "$S/a" FACTORY_CHECK='just test' FACTORY_LOOP_SHARE_MAX=5 -- FACTORY_CHECK FACTORY_LOOP_SHARE_MAX)" "0|just test|5"
check "an empty setting in the environment wins too" "$(read_cfg "$S/a" FACTORY_SANDBOX= -- FACTORY_SANDBOX)" "0|"
for url in https://github.com/Acme/Web-App https://github.com/Acme/Web-App.git ssh://git@github.com/Acme/Web-App.git; do
  git -C "$S/a" remote set-url origin "$url"
  check "origin $url" "$(read_cfg "$S/a" -- FACTORY_REPO)" "0|Acme/Web-App"
done
printf 'FACTORY_REPO=other/thing\nFACTORY_NAME=thing2\n' > "$S/a/.factory/config"
check "the file names the repository and the name" "$(read_cfg "$S/a" -- FACTORY_REPO FACTORY_NAME)" "0|other/thing|thing2"

mk "$S/b"
check "no origin and no FACTORY_REPO: refused" "$(read_cfg "$S/b" -- FACTORY_REPO | cut -c1) $(grep -c 'no repository' "$S/b.err")" "1 1"
mk "$S/c" https://gitlab.com/acme/web.git
check "an origin that is not GitHub: refused" "$(read_cfg "$S/c" -- FACTORY_REPO | cut -c1)" 1
mk "$S/d" git@github.com:acme/web.git
printf 'FACTORY_NAME=Bad_Name\n' > "$S/d/.factory/config"
check "a name the host cannot use: refused" "$(read_cfg "$S/d" -- FACTORY_NAME | cut -c1) $(grep -c "FACTORY_NAME 'Bad_Name' must be" "$S/d.err")" "1 1"
rm "$S/d/.factory/config"
check "no config file at all: the defaults" "$(read_cfg "$S/d" -- FACTORY_REPO FACTORY_NAME FACTORY_CHECK)" "0|acme/web|web|unset"

printf '%s\n' '# comment' 'p1-production|B60205|something wrong in production: down' 'area:api||the HTTP API: src/api/**' 'area:x||no colon here' > "$S/d/.factory/labels"
words() { env -i PATH="$PATH" bash -c '. "$1"; FACTORY_CHECKOUT=$2; factory_label_words "$3"' _ "$LIB" "$S/d" "$1"; }
check "a label's plain words: its description up to the first colon" "$(words p1-production)|$(words area:api)|$(words area:x)" \
  "something wrong in production|the HTTP API|no colon here"
check "a label the file does not name: nothing" "$(words area:none)" ""

echo "config: $n cases, $fails failed"
[ "$fails" = 0 ]

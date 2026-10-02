#!/usr/bin/env bash
# Scenario test of scripts/self-review.sh against the review workflow the factory ships
# (templates/.github/workflows/claude-review.yml), in a scratch repository with a fake `claude` first on PATH that
# records its arguments and prints a verdict: the rubric and the pinned model are read out of that workflow and
# reach the reviewer, a verdict exits 0 and is saved, the project's path filter and its off switch say "not needed"
# (exit 4) without starting a review, and uncommitted edits are refused (exit 2). Exit 1 on any failure.
# Usage: bash tests/self-review-test.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
SR=$(realpath -e scripts/self-review.sh) || exit 2
WF=$(realpath -e templates/.github/workflows/claude-review.yml) || exit 2
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@invalid
unset "${!FACTORY_@}"
mkdir -p "$S/bin"
cat > "$S/bin/claude" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_DIR/claude-args"
printf 'One-line verdict: clean.\n\nfix-before-merge set: 0 — ready to merge\n'
EOF
chmod +x "$S/bin/claude"

fails=0 n=0
check() { # name, got, want
  n=$((n + 1))
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}
R=$S/repo
git init -q -b main "$R"; git -C "$R" remote add origin git@github.com:fake/repo.git
mkdir -p "$R/.github/workflows" "$R/src" "$R/docs"; cp "$WF" "$R/.github/workflows/claude-review.yml"
echo a > "$R/src/a.txt"; git -C "$R" add -A; git -C "$R" commit -qm base; BASE=$(git -C "$R" rev-parse HEAD)
echo b >> "$R/src/a.txt"; git -C "$R" commit -qam change
run() { (cd "$R" && env PATH="$S/bin:$PATH" FAKE_DIR="$S" SELF_REVIEW_WAIT=60 "$@" bash "$SR" "$BASE" > "$S/out" 2>&1); rc=$?; }

run
check "a change: exit 0, with the verdict" "$rc $(grep -c '^fix-before-merge set: 0' "$R/self-review-verdict.md" 2> /dev/null)" "0 1"
check "the reviewer gets the workflow's rubric" "$(grep -c '^Review this pull request as ONE severity-ranked pass' "$S/claude-args")" 1
check "… with the local facts first" "$(grep -c '^LOCAL SELF-REVIEW. The rubric below is the review prompt of .github/workflows/claude-review.yml' "$S/claude-args")" 1
check "… and the workflow's pinned model" "$(grep -A1 -x -- '--model' "$S/claude-args" | tail -n 1)" claude-opus-5-5
check "… read-only tools" "$(grep -A1 -x -- '--tools' "$S/claude-args" | tail -n 1)" Read,Grep,Glob
check "the verdict file names the base and head it read" \
  "$(head -n 1 "$R/self-review-verdict.md" | grep -c "^## Self-review — \`$BASE...$(git -C "$R" rev-parse --short HEAD)\`")" 1
rm -f "$R"/self-review* "$S/claude-args"

printf 'FACTORY_SELF_REVIEW_PATHS=^lib/\n' > "$R/.factory-config"; mkdir -p "$R/.factory"; mv "$R/.factory-config" "$R/.factory/config"
git -C "$R" add -A; git -C "$R" commit -qm config
run
check "no changed path matches the project's filter: exit 4, no review" "$rc $([ -e "$S/claude-args" ] && echo reviewed || echo none)" "4 none"
run FACTORY_SELF_REVIEW_PATHS='^src/'
check "the environment's filter wins over the file's" "$rc" 0
rm -f "$R"/self-review* "$S/claude-args"
run FACTORY_SELF_REVIEW=0
check "turned off: exit 4, no review" "$rc $([ -e "$S/claude-args" ] && echo reviewed || echo none)" "4 none"
echo edit >> "$R/src/a.txt"
run FACTORY_SELF_REVIEW_PATHS='^src/'
check "uncommitted edits: refused" "$rc $(grep -c 'uncommitted edits' "$S/out")" "2 1"

echo "self-review: $n cases, $fails failed"
[ "$fails" = 0 ]

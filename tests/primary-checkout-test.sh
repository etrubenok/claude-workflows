#!/usr/bin/env bash
# Table-driven test of scripts/primary-checkout.sh on scratch git repositories under `mktemp -d`: what the installer
# accepts as the loop's primary checkout (a clone of FACTORY_REPO, its top folder, not a linked worktree, on main —
# ssh, https, `.git` and a trailing slash all spelling the same origin, a dirty tree included) and what it refuses,
# each refusal naming its condition; require_primary_checkout exits 1 with that condition on stderr; and
# factory_tree_reason, the installer's check of the factory checkout itself, refuses an edited or untracked file.
# Nothing outside the scratch folder is read or written. Exit 1 on any failure.
# Usage: bash tests/primary-checkout-test.sh [primary-checkout.sh]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
LIB=$(realpath -e "${1:-scripts/primary-checkout.sh}") || exit 2
# shellcheck source=../scripts/primary-checkout.sh
. "$LIB"
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@invalid
FACTORY_REPO=fake/repo

fails=0 n=0
check() { # name, got, want
  n=$((n + 1))
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fails=$((fails + 1)); fi
}
# repo <dir> [origin url]: a repository with one commit on main and that origin (none when empty)
repo() {
  git init -q -b main "$1" && echo a > "$1/a.txt" && git -C "$1" add a.txt && git -C "$1" commit -qm a
  [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"
}
reason() { local r; r=$(primary_checkout_reason "$1") && echo ok || echo "$r"; }

repo "$S/ok" git@github.com:fake/repo.git
check "a clone on main, ssh origin" "$(reason "$S/ok")" ok
for url in https://github.com/fake/repo https://github.com/fake/repo.git https://github.com/fake/repo/ \
           ssh://git@github.com/fake/repo.git git@github.com:Fake/Repo.git; do
  git -C "$S/ok" remote set-url origin "$url"
  check "origin $url spells the same repository" "$(reason "$S/ok")" ok
done
git -C "$S/ok" remote set-url origin git@github.com:fake/repo.git
echo edit >> "$S/ok/a.txt"; echo new > "$S/ok/new.txt"
check "a dirty tree is accepted: the loop leaves a dirty main alone by itself" "$(reason "$S/ok")" ok
git -C "$S/ok" checkout -q -- a.txt; rm "$S/ok/new.txt"

check "no folder named" "$(reason '')" "no checkout was named"
check "a folder that does not exist" "$(reason "$S/none")" "the checkout $S/none does not exist"
mkdir -p "$S/plain"
check "a plain folder" "$(reason "$S/plain")" "$S/plain is not a git repository"
mkdir -p "$S/ok/sub"
check "a folder inside the clone" "$(reason "$S/ok/sub")" "$S/ok/sub is inside a repository, not its top folder"
git -C "$S/ok" worktree add -q -b other "$S/linked"
check "a linked worktree" "$(reason "$S/linked")" "$S/linked is a linked worktree, not a clone"
repo "$S/elsewhere" git@github.com:someone/else.git
check "a clone of another repository" "$(reason "$S/elsewhere")" \
  "$S/elsewhere follows git@github.com:someone/else.git, not fake/repo (origin must be github.com/fake/repo)"
repo "$S/no-origin"
check "no origin" "$(reason "$S/no-origin")" "$S/no-origin follows no origin remote, not fake/repo (origin must be github.com/fake/repo)"
repo "$S/not-github" https://gitlab.com/fake/repo.git
check "the same name on another host" "$(reason "$S/not-github")" \
  "$S/not-github follows https://gitlab.com/fake/repo.git, not fake/repo (origin must be github.com/fake/repo)"
git -C "$S/ok" checkout -q -b feature
check "another branch" "$(reason "$S/ok")" "$S/ok is on feature, not main"
git -C "$S/ok" checkout -q --detach
check "a detached HEAD" "$(reason "$S/ok")" "$S/ok is on a detached HEAD, not main"
git -C "$S/ok" checkout -q main

out=$( (require_primary_checkout "$S/plain") 2>&1 > /dev/null); rc=$?
check "require_primary_checkout: exit 1 on a refusal" "$rc" 1
check "require_primary_checkout: names the condition on stderr" "$(head -n 1 <<< "$out" | grep -c "refused — $S/plain is not a git repository\.")" 1
( require_primary_checkout "$S/ok" ); check "require_primary_checkout: returns on a pass" "$?" 0

repo "$S/factory"
r=$(factory_tree_reason "$S/factory") && r=ok
check "factory tree: clean" "$r" ok
echo new > "$S/factory/new.txt"
r=$(factory_tree_reason "$S/factory") || true
check "factory tree: an untracked file" "$r" "uncommitted or untracked files in $S/factory: ?? new.txt"
rm "$S/factory/new.txt"; echo edit >> "$S/factory/a.txt"
r=$(factory_tree_reason "$S/factory") || true
check "factory tree: an edited file" "$r" "uncommitted or untracked files in $S/factory:  M a.txt"

echo "primary-checkout: $n cases, $fails failed"
[ "$fails" = 0 ]

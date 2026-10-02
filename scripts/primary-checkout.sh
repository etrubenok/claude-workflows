# shellcheck shell=bash
# "Can the loop run from this checkout?" — ONE definition, sourced by the installer and its test. The loop works
# in a PRIMARY checkout of the repository it drives: it fast-forwards that clone's `main` to origin/main every
# few minutes, its verify and close sessions read main's tree there, and every issue's worktree hangs off it.
# So the checkout must exist, be a git repository whose `origin` is the repository the config names
# (FACTORY_REPO — ssh, https, a trailing slash or `.git` all spell the same one), and be on `main`. It need not be
# clean at install time: the loop leaves a dirty or diverged main alone and says so in its log.
# Cases: tests/primary-checkout-test.sh.

# primary_checkout_reason <dir>: nothing, and 0, when <dir> is such a checkout; otherwise the condition that
# failed, on stdout, and 1. A git that fails for any reason is a failed condition, never a pass.
primary_checkout_reason() {
  local dir=$1 here remote branch slug
  [ -n "$dir" ] || { echo "no checkout was named"; return 1; }
  here=$(cd -- "$dir" 2> /dev/null && pwd -P) || { echo "the checkout $dir does not exist"; return 1; }
  git -C "$here" rev-parse --git-dir > /dev/null 2>&1 || { echo "$here is not a git repository"; return 1; }
  git -C "$here" rev-parse --is-inside-work-tree 2> /dev/null | grep -qx true || { echo "$here is not a working tree"; return 1; }
  [ "$(git -C "$here" rev-parse --show-toplevel 2> /dev/null)" = "$here" ] || { echo "$here is inside a repository, not its top folder"; return 1; }
  [ "$(git -C "$here" rev-parse --git-common-dir 2> /dev/null)" = "$(git -C "$here" rev-parse --git-dir 2> /dev/null)" ] \
    || { echo "$here is a linked worktree, not a clone"; return 1; }
  remote=$(git -C "$here" remote get-url origin 2> /dev/null) || remote=""
  remote=${remote%/}; slug=""
  if [[ ${remote%.git} =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then slug=${BASH_REMATCH[1]}; fi
  [ -n "$slug" ] && [ "${slug,,}" = "${FACTORY_REPO,,}" ] \
    || { echo "$here follows ${remote:-no origin remote}, not $FACTORY_REPO (origin must be github.com/$FACTORY_REPO)"; return 1; }
  branch=$(git -C "$here" symbolic-ref -q --short HEAD 2> /dev/null) || branch=""
  [ "$branch" = main ] || { echo "$here is on ${branch:-a detached HEAD}, not main"; return 1; }
}

# require_primary_checkout <dir>: the installer's form — returns only when the check passes; otherwise names the
# condition that failed on stderr and EXITS 1.
require_primary_checkout() {
  local reason
  reason=$(primary_checkout_reason "$@") && return 0
  printf '%s: refused — %s.\n' "${0##*/}" "$reason" >&2
  printf 'The loop runs from a primary checkout: a clone (not a worktree) of %s, on main. Clone it somewhere of its own, e.g. git clone git@github.com:%s.git ~/factory/%s, and install with that path.\n' \
    "$FACTORY_REPO" "$FACTORY_REPO" "${FACTORY_REPO##*/}" >&2
  exit 1
}

# factory_tree_reason <dir>: nothing, and 0, when the factory checkout being installed has no uncommitted or
# untracked file — what is installed is then exactly a commit, which `git -C <dir> rev-parse HEAD` names; else
# what is there, and 1.
factory_tree_reason() {
  local st
  st=$(git -C "$1" --no-optional-locks status --porcelain --untracked-files=normal 2> /dev/null) \
    || { echo "git status failed in $1"; return 1; }
  [ -z "$st" ] || { echo "uncommitted or untracked files in $1: ${st//$'\n'/; }"; return 1; }
}

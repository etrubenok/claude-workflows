#!/usr/bin/env bash
# Installs, updates or removes ONE factory instance on this host: the loop that drives the GitHub repository whose
# primary checkout is <checkout> (see docs/adopting.md).
#
#   scripts/factory-install.sh <checkout>               install, or update to this factory checkout's commit
#   scripts/factory-install.sh --labels-only <checkout> only create or update the repository's labels
#   scripts/factory-install.sh --uninstall <checkout>   stop and remove the timers, units and installed files
#                                                       (keeps the state folder, the env file and the labels)
#
# Install, in order: checks the target (a clone of FACTORY_REPO on main) and this factory checkout (no uncommitted
# or untracked file, so what runs is exactly a commit — FACTORY_INSTALL_DIRTY=1 to install an edited tree on
# purpose); copies scripts/ (not the tests) and prompts/ to ~/.local/share/factory/<name>/, replacing the
# previous copy in one move, so a tick that is running keeps the files it opened; writes the units
# factory-<name>-{fast,slow}@.{service,timer} from systemd/ and creates ~/.config/factory/<name>.env (mode 600)
# for the loop's login; enables one fast-lane worker per review worker and one slow-lane worker per implement
# slot; and creates the factory's labels and the project's own (.factory/labels) on the repository.
# Budget: FACTORY_IMPLEMENT_SLOTS and FACTORY_REVIEW_WORKERS (1–9, default 1 each) and FACTORY_MAX_IN_FLIGHT
# (default: the driver's 2) go into the fast lane's drop-in, which every worker reads; a re-run keeps the
# installed values unless they are passed again.
# Needs: git, gh (authenticated as the owner), claude, jq, flock and a systemd user manager with lingering on.
set -euo pipefail
FACTORY_SRC=$(cd "$(dirname "$(realpath "$0")")/.." && pwd)
usage() { sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
MODE=install
case "${1:-}" in
  --uninstall) MODE=uninstall; shift ;;
  --labels-only) MODE=labels; shift ;;
  -h|--help|"") usage ;;
esac
[ $# -eq 1 ] || usage
FACTORY_CHECKOUT=$(cd -- "$1" 2> /dev/null && pwd -P) || { echo "no such folder: $1"; exit 2; }
# shellcheck source=factory-config.sh
. "$FACTORY_SRC/scripts/factory-config.sh"
factory_config || exit 1
NAME=$FACTORY_NAME
REPO=$FACTORY_REPO
# shellcheck source=primary-checkout.sh
. "$FACTORY_SRC/scripts/primary-checkout.sh"
# shellcheck source=factory-budget.sh
. "$FACTORY_SRC/scripts/factory-budget.sh"
UNITS=$FACTORY_UNITS
SHARE="${FACTORY_SHARE:-$HOME/.local/share/factory/$NAME}"
ENVF="$HOME/.config/factory/$NAME.env"
STATE="${FACTORY_STATE:-$HOME/.local/state/factory/$NAME}"
PREFIX="factory-$NAME"

# ---- the labels: the factory's own, then the project's ---------------------------------------------------------
# `--force` updates an existing label, so a re-run is idempotent. A description over GitHub's 100 characters is cut
# with a warning rather than refused (a refused label keeps its old wording silently).
make_label() {
  local name="$1" color="${2:-C5DEF5}" desc="$3"
  [[ $color =~ ^[0-9A-Fa-f]{6}$ ]] || color=C5DEF5
  if [ "${#desc}" -gt 100 ]; then echo "warning: the description of label $name is ${#desc} characters; cut to GitHub's 100"; desc=${desc:0:100}; fi
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force > /dev/null \
    || echo "warning: label $name not created"
}
labels() {
  local name color desc f p
  while IFS='|' read -r name color desc; do make_label "$name" "$color" "$desc"; done << 'EOF'
ready|0E8A16|factory: queue this issue now (an open issue with no label of the loop's own is queued anyway)
in-progress|1D76DB|factory: being built (the implement stage)
in-review|5319E7|factory: its pull request is in review, or merged and being closed
waiting|FEF2C0|factory: waits for what the loop ends by itself (an issue, a set time, a retry)
needs-decision|D93F0B|factory: waits for the owner; reply on the issue and the loop carries on
hold|333333|the owner sets this: the loop leaves the issue alone until it comes off
tracking|0E8A16|a roadmap issue or the loop's own page; never picked up as one piece of work
review|BFD4F2|factory: put on a pull request to ask for the automatic review again
EOF
  f=$(factory_labels_file)
  if [ -r "$f" ]; then
    while IFS='|' read -r name color desc; do
      name=${name%%[[:space:]]}; [[ $name =~ ^[[:space:]]*(#|$) ]] && continue
      make_label "$name" "$color" "$desc"
    done < "$f"
  else
    echo "note: no labels file ($f): only the factory's own labels were created; priority and area labels are the project's (see templates/.factory/labels)"
  fi
  for p in ${FACTORY_PRIORITIES:-p1-production p2-product p3-tooling}; do
    grep -q "^$p|" "$f" 2> /dev/null || echo "warning: priority label $p is not in $f, so it has no description and the board names it as it stands"
  done
}

if [ "$MODE" = labels ]; then labels; exit 0; fi

if [ "$MODE" = uninstall ]; then
  for k in $(seq 1 9); do
    systemctl --user disable --now "$PREFIX-fast@$k.timer" 2> /dev/null || true
    systemctl --user disable --now "$PREFIX-slow@$k.timer" 2> /dev/null || true
  done
  rm -rf "$UNITS/$PREFIX-fast@.service" "$UNITS/$PREFIX-fast@.timer" "$UNITS/$PREFIX-slow@.service" \
         "$UNITS/$PREFIX-slow@.timer" "$UNITS/$PREFIX-fast@1.timer.d" "$UNITS/$PREFIX-fast@.service.d" "$SHARE"
  systemctl --user daemon-reload
  echo "uninstalled $NAME: timers stopped, units and $SHARE removed. Kept: $STATE (logs), $ENVF (the login), the labels on $REPO."
  exit 0
fi

# ---- checks, before anything on the host changes ------------------------------------------------------------
require_primary_checkout "$FACTORY_CHECKOUT"
if [ "${FACTORY_INSTALL_DIRTY:-0}" != 1 ] && ! why=$(factory_tree_reason "$FACTORY_SRC"); then
  echo "${0##*/}: refused — $why. Commit (or set FACTORY_INSTALL_DIRTY=1 to install this edited tree on purpose)." >&2
  exit 1
fi
for tool in git gh claude jq flock systemctl; do
  command -v "$tool" > /dev/null || { echo "${0##*/}: refused — $tool is not on the PATH" >&2; exit 1; }
done
gh repo view "$REPO" --json name > /dev/null || { echo "${0##*/}: refused — gh cannot read $REPO (gh auth status)" >&2; exit 1; }
[ "$(loginctl show-user "$(id -un)" -p Linger --value 2> /dev/null || echo no)" = yes ] \
  || echo "warning: lingering is off for $(id -un), so the timers stop when you log out — sudo loginctl enable-linger $(id -un)"
SLOTS="${FACTORY_IMPLEMENT_SLOTS:-$(factory_budget FACTORY_IMPLEMENT_SLOTS)}"; SLOTS="${SLOTS:-1}"
WORKERS="${FACTORY_REVIEW_WORKERS:-$(factory_budget FACTORY_REVIEW_WORKERS)}"; WORKERS="${WORKERS:-1}"
MAX="${FACTORY_MAX_IN_FLIGHT:-$(factory_budget FACTORY_MAX_IN_FLIGHT)}"
factory_budget_valid "$SLOTS" || { echo "FACTORY_IMPLEMENT_SLOTS must be 1-9, not '$SLOTS'"; exit 2; }
factory_budget_valid "$WORKERS" || { echo "FACTORY_REVIEW_WORKERS must be 1-9, not '$WORKERS'"; exit 2; }
[[ -z $MAX ]] || factory_budget_valid "$MAX" || { echo "FACTORY_MAX_IN_FLIGHT must be 1-9, not '$MAX'"; exit 2; }

# ---- the files: a fresh copy, swapped in by one move ----------------------------------------------------------
new="$SHARE.new.$$"
rm -rf "$new"; mkdir -p "$new/scripts" "$(dirname "$SHARE")"
for f in "$FACTORY_SRC"/scripts/*.sh; do
  case "$f" in *-test.sh) continue ;; esac
  install -m 755 "$f" "$new/scripts/"
done
cp -r "$FACTORY_SRC/prompts" "$new/prompts"
{ git -C "$FACTORY_SRC" describe --always --dirty --tags 2> /dev/null || echo unknown; date -u +%FT%TZ; } > "$new/VERSION"
rm -rf "$SHARE.old"; [ ! -d "$SHARE" ] || mv "$SHARE" "$SHARE.old"; mv "$new" "$SHARE"; rm -rf "$SHARE.old"
mkdir -p "$STATE"
if [ ! -e "$ENVF" ]; then
  mkdir -p "$(dirname "$ENVF")"
  ( umask 077; printf '%s\n' "# The $NAME factory's host settings, read by its units. Put the loop's own login here:" \
      "#   claude setup-token   then   CLAUDE_CODE_OAUTH_TOKEN=<token>" \
      "# Any FACTORY_* line here overrides the project's .factory/config on this host." > "$ENVF" )
fi

# ---- the units --------------------------------------------------------------------------------------------------
render() { sed -e "s|@NAME@|$NAME|g" -e "s|@SHARE@|$SHARE|g" -e "s|@CHECKOUT@|$FACTORY_CHECKOUT|g" "$1" > "$2"; }
mkdir -p "$UNITS/$PREFIX-fast@1.timer.d"
for u in fast@.service fast@.timer slow@.service slow@.timer; do render "$FACTORY_SRC/systemd/$u" "$UNITS/$PREFIX-$u"; done
render "$FACTORY_SRC/systemd/fast@1.timer.d/every-2-min.conf" "$UNITS/$PREFIX-fast@1.timer.d/every-2-min.conf"
systemctl --user daemon-reload
# Every worker the count will name goes up FIRST, and the count only once they are all up: above one worker,
# worker 1 refuses every `review` and leaves it to the others, so a count that names workers the host does not run
# stops the review stage outright. Under `set -e` one failed `enable` ends the script where it stands, and in this
# order that always leaves a count the host's timers can serve. (A newly enabled `Persistent=true` timer fires at
# once, before the drop-in below is live, so a widening install may cost one tick of a duplicate look; the
# per-issue lock keeps two workers off one issue.)
for k in $(seq 1 9); do
  [ "$k" -gt "$WORKERS" ] || systemctl --user enable --now "$PREFIX-fast@$k.timer"
  [ "$k" -gt "$SLOTS" ] || systemctl --user enable --now "$PREFIX-slow@$k.timer"
done
systemctl --user restart "$PREFIX-fast@1.timer"   # `enable --now` leaves a running timer alone: arm worker 1's calendar now
BUDGET=$(factory_budget_file)
if [ "$SLOTS" = 1 ] && [ "$WORKERS" = 1 ] && [ -z "$MAX" ]; then
  rm -f "$BUDGET"   # the default budget: the driver's own
else
  mkdir -p "$(dirname "$BUDGET")"
  { printf '[Service]\nEnvironment=FACTORY_IMPLEMENT_SLOTS=%s\nEnvironment=FACTORY_REVIEW_WORKERS=%s\n' "$SLOTS" "$WORKERS"
    [ -z "$MAX" ] || printf 'Environment=FACTORY_MAX_IN_FLIGHT=%s\n' "$MAX"; } > "$BUDGET"
fi
systemctl --user daemon-reload
# The surplus of a narrowed install goes last, after the lower count is written, for the same reason the other way
# round. A worker left running because its `disable` failed is harmless: which worker runs the steps that must
# happen once is decided by its own number, never by the count.
for k in $(seq 1 9); do
  [ "$k" -le "$WORKERS" ] || systemctl --user disable --now "$PREFIX-fast@$k.timer" 2> /dev/null || true
  [ "$k" -le "$SLOTS" ] || systemctl --user disable --now "$PREFIX-slow@$k.timer" 2> /dev/null || true
done

labels
systemctl --user list-timers "$PREFIX-*" --no-pager || true
grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' "$ENVF" \
  || echo "note: $ENVF has no CLAUDE_CODE_OAUTH_TOKEN yet, so sessions use this host's interactive login, which expires — run \`claude setup-token\` and add the line"
echo "installed $NAME ($(head -n 1 "$SHARE/VERSION")) for $REPO from $FACTORY_CHECKOUT: $SLOTS implement slot(s), $WORKERS review worker(s), MAX_IN_FLIGHT ${MAX:-default}."
echo "plan only: FACTORY_CHECKOUT=$FACTORY_CHECKOUT $SHARE/scripts/factory-tick.sh --dry-run    log: $STATE/ticks.log"

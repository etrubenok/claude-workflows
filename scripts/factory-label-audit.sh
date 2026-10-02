#!/usr/bin/env bash
# The factory's label audit: a snapshot of the state labels on GitHub against the rules the
# loop keeps, so the check can be repeated after any change to how the loop labels. Read-only: it lists issues and reads comments, nothing else. The rules:
#   1. a closed issue carries no state label (ready, in-progress, in-review, waiting, needs-decision);
#   2. an open issue carries at most one stage label (ready, in-progress, in-review);
#   3. a waiting issue (`waiting` or `needs-decision`) carries no stage label — `ready` on one is a person's
#      word that the wait is over, which the next fast tick reads, so it is not counted;
#   4. a `needs-decision` issue needs the owner: its wait's class is not one the loop ends by itself — an
#      `owner` class, with or without its item, or a token the sweep could not read;
#   5. a `waiting` issue is one the loop ends: its class is `issue:`, `time:` or `ci`.
# The class is read as the hourly sweep reads it (park_comment and park_class of scripts/factory-sweep.sh):
# the `[blocked-on: …]` tag of the comment that parked it, else what its text or the issue's first paragraph
# says. Exit 0 when every rule holds, 1 when one does not, 2 when GitHub could not be read.
# Usage: FACTORY_CHECKOUT=<checkout> bash scripts/factory-label-audit.sh   (FACTORY_REPO picks another repository)
set -uo pipefail
HERE=$(cd "$(dirname "$(realpath "$0")")" && pwd)
# shellcheck source=factory-config.sh
. "$HERE/factory-config.sh"
factory_config || exit 2
REPO="$FACTORY_REPO"
# shellcheck source=factory-sweep.sh
. "$HERE/factory-sweep.sh" || exit 2
broken=0
# rule <title> <findings, one per line>
rule() {
  local k; k=$(grep -c . <<< "$2" || true)
  echo "$1: $k"
  [ "$k" = 0 ] || { grep . <<< "$2" | while read -r l; do echo "  $l"; done; broken=$((broken + 1)); }
}
# Issue N's class, as sweep_issue reads it.
tag_of() {
  local pc
  pc=$(park_comment "$1") || return 1
  [ -n "$pc" ] || pc=$(gh issue view "$1" --repo "$REPO" --json body --jq '{body: ((.body // "") | split("\n\n") | first // "")}') || return 1
  park_class "$(jq -r '.body // ""' <<< "$pc")"
}

echo "factory label audit of $REPO at $(date -u +%FT%TZ)"
closed=$(gh issue list --repo "$REPO" --state closed --limit 1000 --json number,labels --jq '.[]
  | [.labels[].name | select(test("^(ready|in-progress|in-review|waiting|needs-decision)$"))] as $s
  | select($s | length > 0) | "issue #\(.number): \($s | join(" "))"') || exit 2
rule "1. closed issues with a state label" "$closed"
open=$(gh issue list --repo "$REPO" --state open --limit 1000 --json number,labels \
         --jq '.[] | "\(.number) \([.labels[].name] | join(" "))"') || exit 2
two="" staged="" asks="" waits=""
while read -r n ls; do
  [ -n "$n" ] || continue
  st=$(for l in $ls; do case "$l" in ready|in-progress|in-review) echo "$l" ;; esac; done)
  [ "$(grep -c . <<< "$st")" -le 1 ] || two+="issue #$n: $(paste -sd ' ' <<< "$st")"$'\n'
  case " $ls " in
    *" needs-decision "*|*" waiting "*)
      st=$(grep -v '^ready$' <<< "$st" | paste -sd ' ' -)
      [ -z "$st" ] || staged+="issue #$n: $st"$'\n'
      t=$(tag_of "$n") || exit 2
      # Only a wait the loop could end itself is a finding here: an `owner` class, with or without its item
      # and a token the sweep cannot read — an instant that is not one — are the owner's by
      # design, since the sweep hands those to the owner too (ask_owner).
      case " $ls " in *" needs-decision "*) case "$t" in
        ci|issue:*|service:*) asks+="issue #$n: waits on $t"$'\n' ;;
        time:*) ! time_instant "${t#time:}" > /dev/null || asks+="issue #$n: waits on $t"$'\n' ;;   # the whole predicate `cleared` acts on
      esac ;; esac
      case " $ls " in *" waiting "*) case "$t" in issue:*|service:*|time:*|ci) ;; *) waits+="issue #$n: waits on $t"$'\n' ;; esac ;; esac ;;
  esac
done <<< "$open"
rule "2. open issues with two stage labels" "$two"
rule "3. waiting issues that still carry a stage label" "$staged"
rule "4. needs-decision issues that need nothing from the owner (their class is not \`owner\`)" "$asks"
rule "5. waiting issues that need the owner (their class is not one the loop ends)" "$waits"
if [ "$broken" = 0 ]; then echo "every rule holds"; else echo "$broken rule(s) broken"; fi
[ "$broken" = 0 ]

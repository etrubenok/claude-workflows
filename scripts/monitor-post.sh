#!/usr/bin/env bash
# Posts one comment on the factory's rolling monitor issue, creating the issue on first use: the daily digest and
# the loop's own alarms (an expired login) go there, one comment each.
# Usage: monitor-post.sh "<kind>" <body-file> [max-bytes]
set -euo pipefail
HERE=$(cd "$(dirname "$(realpath "$0")")" && pwd)
# shellcheck source=factory-config.sh
. "$HERE/factory-config.sh"
factory_config || exit 1
REPO="$FACTORY_REPO"
MONITOR_TITLE="${FACTORY_MONITOR_TITLE:-Factory monitor}"
kind="$1"; body="$2"; max="${3:-60000}"

# Plain list + exact-title filter: the search index lags a just-created issue by seconds, which would otherwise
# spawn a duplicate monitor issue.
number=$(gh issue list --repo "$REPO" --state open --limit 200 --json number,title \
           --jq ".[] | select(.title == \"$MONITOR_TITLE\") | .number" | head -n1)
if [ -z "$number" ]; then
  # `tracking`, as the live board labels its own page: the loop's queue is every open issue that no label of its
  # own keeps out, so a monitor issue without it would be picked up as work. Only that the label EXISTS is ensured
  # here — `--force` without `--description` leaves the wording alone — so the installer stays the one place that
  # sets it.
  gh label create tracking --repo "$REPO" --color 0E8A16 --force > /dev/null || true
  number=$(gh issue create --repo "$REPO" --title "$MONITOR_TITLE" --label tracking \
    --body "Rolling log of the factory loop: one comment per daily digest and per alarm (an expired login, a pause). The live picture is on the factory board issue." \
    | grep -oE '[0-9]+$')
fi
{
  printf '%s — `%s`\n\n```\n' "$kind" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  head -c "$max" "$body"
  printf '\n```\n'
} | gh issue comment "$number" --repo "$REPO" --body-file -

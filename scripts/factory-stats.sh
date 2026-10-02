#!/usr/bin/env bash
# Read-only: what the loop's own lanes and picks did over a window, measured from the state the driver
# already writes — one log per stage session (start time in its file name, end time = its mtime) and
# ticks.log. Why it is committed instead of counted by hand: the limit on issues in flight, the number of
# workers and the tick interval are all best set from these numbers, and a one-off count in a comment cannot be
# re-run six weeks later against the same definition. It writes only its own temp folder and needs nothing
# beyond coreutils and awk. Tested on scratch state by tests/factory-stats-test.sh.
# Usage: bash scripts/factory-stats.sh [--since <RFC3339 UTC>] [--until <RFC3339 UTC>] [--hours N]
#        [--state <dir>]
# Default window: the 24 h ending now, over the instance's state folder (~/.local/state/factory/<name>, the name
# from FACTORY_CHECKOUT's config; or --state). `--since` with no
# `--until` measures up to now; `--hours` counts back from `--until`.
# A session that died within seconds of starting (an account limit or an expired login can leave thousands)
# adds nothing to busy time but is still a session, so the count of those
# is printed beside the total: a window full of them reads as an idle loop, and this line says why.
set -euo pipefail

SINCE=""; UNTIL=""; HOURS=24
STATE="${FACTORY_STATE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift ;;
    --until) UNTIL="$2"; shift ;;
    --hours) HOURS="$2"; shift ;;
    --state) STATE="$2"; shift ;;
    -h | --help)
      echo "usage: bash scripts/factory-stats.sh [--since <RFC3339 UTC>] [--until <RFC3339 UTC>] [--hours N] [--state <dir>]"
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$STATE" ]; then
  # shellcheck source=factory-config.sh
  . "$(cd "$(dirname "$(realpath "$0")")" && pwd)/factory-config.sh"
  factory_config || exit 2
  STATE="$HOME/.local/state/factory/$FACTORY_NAME"
fi
[[ $HOURS =~ ^[1-9][0-9]*$ ]] || { echo "--hours takes a whole number of hours, not '$HOURS'" >&2; exit 2; }
[ -d "$STATE" ] || { echo "no factory state at $STATE" >&2; exit 2; }
t1=$(date -u -d "${UNTIL:-now}" +%s) || exit 2
if [ -n "$SINCE" ]; then t0=$(date -u -d "$SINCE" +%s) || exit 2; else t0=$(( t1 - HOURS * 3600 )); fi
[ "$t1" -gt "$t0" ] || { echo "the window ends before it starts" >&2; exit 2; }
s0=$(date -u -d "@$t0" +%FT%TZ); s1=$(date -u -d "@$t1" +%FT%TZ)

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Every stage session, as the driver names its log: issue-<n>-<stage>-<YYYYmmddTHHMMSSZ>.log. The stamp
# is the start; the mtime is the last write, i.e. the end. Both clocks are this host's, and the stamp is
# UTC, so the two are comparable.
find "$STATE" -maxdepth 1 -type f -name 'issue-*-*-????????T??????Z.log' \
  -printf '%T@ %f\n' > "$tmp/found"
# One `date` call for the whole list: a fork per file costs seconds once the state holds thousands of logs.
awk '{ s = substr($2, length($2) - 19, 15)   # YYYYmmddTHHMMSS, the 20 characters before the end less "Z.log"
       printf "%s-%s-%s %s:%s:%s UTC\n", substr(s,1,4), substr(s,5,2), substr(s,7,2),
                                          substr(s,10,2), substr(s,12,2), substr(s,14,2) }' \
  "$tmp/found" > "$tmp/stamps"
if [ -s "$tmp/stamps" ]; then date -u -f "$tmp/stamps" +%s > "$tmp/starts"; else : > "$tmp/starts"; fi
# start end issue stage lane, clipped to the window; a session whose mtime precedes its own name (a log
# never written to) counts as zero-length rather than as negative time.
paste -d ' ' "$tmp/starts" "$tmp/found" \
  | awk -v t0="$t0" -v t1="$t1" '
      { start = $1 + 0; end = int($2); name = $3
        if (end < start) end = start
        # In the window: started before its end, and ended after its start — or, never having run, started in it.
        if (start >= t1 || end < t0 || (end == t0 && start < t0)) next
        n = split(name, p, "-")
        issue = p[2]; stage = p[3]
        lane = (stage == "implement") ? "slow" : "fast"
        raw = end - start
        if (start < t0) start = t0
        if (end > t1) end = t1
        print start, end, issue, stage, lane, raw }' > "$tmp/rec"

sessions=$(grep -c . "$tmp/rec" || true)
# Coverage of the window by lane: the share with at least one session running, the share with two or more,
# and the most at once. A session ending exactly as another starts is a hand-over, not an overlap, so the
# -1 events sort before the +1 events at the same instant. A session that never ran adds no events at all.
busy() {
  awk -v lane="$1" '$5 == lane && $2 > $1 { print $1, 1; print $2, -1 }' "$tmp/rec" \
    | sort -k1,1n -k2,2n \
    | awk -v t0="$t0" -v t1="$t1" -v lane="$1" '
        { if (NR > 1) { if (cur >= 1) any += $1 - prev; if (cur >= 2) two += $1 - prev }
          cur += $2; if (cur > max) max = cur; prev = $1 }
        END { w = t1 - t0
              printf "%s-lane busy %.0f %% of the window, 2+ at once %.0f %%, most at once %d\n",
                     lane, 100 * any / w, 100 * two / w, max }'
}
# The share of an issue's life it spent waiting rather than being worked on: for every issue with two or
# more sessions in the window (with one, life and work are the same span and the share would read 0),
# life is first start to last end and work is the time its sessions ran.
life() {
  awk '{ w[$3] += $2 - $1; c[$3]++
         if (!($3 in f) || $1 < f[$3]) f[$3] = $1
         if (!($3 in l) || $2 > l[$3]) l[$3] = $2 }
       END { for (i in c) if (c[i] > 1) { issues++; life += l[i] - f[i]; work += w[i] }
             if (life > 0)
               printf "issue life waiting %.0f %% (%d issue(s) with 2+ sessions: %.1f h of life, %.1f h worked)\n",
                      100 * (life - work) / life, issues, life / 3600, work / 3600
             else print "issue life waiting n/a (no issue had 2 or more sessions in the window)" }' "$tmp/rec"
}
# ticks.log lines carry an RFC 3339 UTC stamp first and `[<lane><-worker>]` second, so the window is a
# string comparison and the lane is a prefix match. Each counted line is one the driver writes verbatim.
ticks() {
  awk -v s0="$s0" -v s1="$s1" '
      $1 >= s0 && $1 <= s1 {
        if ($2 ~ /^\[fast/) lane["fast"]++; else if ($2 ~ /^\[slow/) lane["slow"]++
        if (/ tick done$/) { done_++; if ($2 ~ /^\[fast/) df++; else if ($2 ~ /^\[slow/) ds++ }
        if (/in-flight budget full \(/) { full++; cap = $0; sub(/.*budget full \([0-9]+\//, "", cap); sub(/\).*/, "", cap); caps[cap]++ }
        if (/ skipped: area:/) pickskip++
        if (/back to ready, not built$/) backskip++
        if (/ both lanes paused /) { pause++; if (/ account usage limit \(/) limit++ } }
      END { printf "ticks finished %d (fast %d, slow %d), log lines %d\n", done_, df, ds, lane["fast"] + lane["slow"]
            # The limit each blocked pick names, as the driver printed it — the installed value is not readable
            # from a session. A tick run by hand prints the driver default (2) instead: a lone 2 is one of those.
            printf "picks blocked by the in-flight limit %d", full
            sep = " (limit "; for (c = 1; c <= 9; c++) if (c in caps) { printf "%s%d: %d", sep, c, caps[c]; sep = ", " }
            printf "%s\n", (sep == ", " ? ")" : "")
            printf "picks skipped for an area in flight %d\n", pickskip
            printf "builds sent back for an area in flight %d\n", backskip
            printf "loop pauses started %d (on the account usage limit %d)\n", pause, limit }' "$STATE/ticks.log"
}

echo "window $s0 .. $s1 ($(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", (b - a) / 3600 }') h), state $STATE"
awk '{ c[$4]++; if ($6 < 30) short++ }
     END { printf "sessions %d (", NR
           n = split("verify implement review close", o, " ")
           for (i = 1; i <= n; i++) { printf "%s%s %d", (i > 1 ? ", " : ""), o[i], c[o[i]]; c[o[i]] = "" }
           for (s in c) if (c[s] != "") printf ", %s %d", s, c[s]
           printf "); %d under 30 s\n", short }' "$tmp/rec"
[ "$sessions" = 0 ] || { busy slow; busy fast; life; }
if [ -r "$STATE/ticks.log" ]; then ticks; else echo "no ticks.log at $STATE — the tick counters are unknown"; fi
newest=$(sort -k1,1n "$tmp/found" | tail -n 1 | cut -d ' ' -f 1)
[ -z "$newest" ] || echo "newest session log $(date -u -d "@${newest%.*}" +%FT%TZ)"

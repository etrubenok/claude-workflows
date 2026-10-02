#!/usr/bin/env bash
# Scenario test of scripts/factory-tick.sh: whole-script runs of the driver on scratch state only. A scratch bare
# repo is origin and a clone of it is the primary checkout (FACTORY_CHECKOUT); the state, prompts, sweep file,
# sandbox, monitor poster and HOME are scratch. `gh`, `claude`, `docker` and `systemctl` are fakes first on PATH,
# checked before any run: nothing reads GitHub, starts a session or touches a container or a unit. The fake
# `claude` records each session's stage, working directory, HEAD and extra working directory. The tables:
# - the primary checkout (ff_checkout), one fast tick each: a clean `main` behind origin/main moves; every other
#   shape is left untouched with its one reason line, a session working in that tree included. "Untouched" is one
#   hash of HEAD, the symbolic ref, every local branch, `git ls-files -s` and every working-tree file;
# - a resumed issue branch (ff_branch), one slow tick running `implement` each: strictly behind and clean moves
#   before the session starts, which sees the new HEAD; diverged, ahead or dirty stays; a missing local branch
#   starts from origin/issue-<n>;
# - the sweep file: a fast tick sweeps from it and `--sweep --dry-run` reports from it; a missing or unparsable
#   copy costs one line, the sweep and the reply check, while the tick runs its stage and ends, and `--sweep`
#   exits 1;
# - the stage runner's file, which the loop cannot do without: a missing or unparsable copy costs one line, every
#   session and the sweep in either lane, while the board is still refreshed and the tick ends; the queries that
#   read through it exit 1;
# - the sandbox: one that is, lies under, links to or holds a protected folder is refused before any session
#   starts; a sibling whose name only starts the same is not; no sandbox means no extra working directory;
# - the close gate's reading of the project's release check: each word it may print, a silent or failing check,
#   the stall bound, and no check at all;
# - a branch's pull request: the line pr_of prints for none, one and several, and the stage the driver then runs —
#   implement, review, close, abandoned, and a NEW ROUND (merged + `in-progress`) — each proved by the one line
#   that stage writes; and the new round's start: a leftover branch at the merged head removed here and on origin,
#   uncommitted edits in it parked for the owner, a branch past that head kept;
# - the loop-share brake: over its share it holds the loop's own issues while another issue can start, and gives
#   the free slot to one when nothing else can (the 2026-09-30 idle-loop shape), never to a blocked one;
# - what a session is sent: the header without its frontmatter plus the text of its own stage and no other, the
#   project's own additions and its values in the placeholders; a stage file missing refuses the tick;
# - the factory's own logs: the digest's tick trims ticks.log and deletes old session logs.
# Every run is cut at 30 s. Prints each case and a summary; exit 1 on a failure.
# Usage: bash tests/factory-tick-test.sh [driver-path [sweep-path [stage-path [board-path]]]]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
DRIVER=$(realpath -e "${1:-scripts/factory-tick.sh}") || exit 1
SWEEP=$(realpath -e "${2:-scripts/factory-sweep.sh}") || exit 1
STAGELIB=$(realpath -e "${3:-scripts/factory-stage.sh}") || exit 1
BOARDLIB=$(realpath -e "${4:-scripts/factory-board.sh}") || exit 1   # loaded by the stage-runner cases alone
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
unset "${!FACTORY_@}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=tick-test GIT_AUTHOR_EMAIL=tick-test@invalid GIT_COMMITTER_NAME=tick-test GIT_COMMITTER_EMAIL=tick-test@invalid
mkdir -p "$S/bin" "$S/home" "$S/sandbox"
printf -- '---\nname: fake\n---\nfake skill text\n' > "$S/skill.md"
mkdir -p "$S/stages"; for s in verify implement review close; do printf 'fake %s text\n' "$s" > "$S/stages/$s.md"; done   # one file per stage
export FACTORY_STAGES="$S/stages"
cat > "$S/bin/gh" << 'EOF'
#!/usr/bin/env bash
# `gh` fake: the tick's queries answered from the case's FAKE_* values (empty = nothing); every write succeeds.
# Every call is recorded, so a case can count them.
[ -z "${FAKE_DIR:-}" ] || echo "$*" >> "$FAKE_DIR/gh-calls"
# FAKE_ISSUES: several open issues, one "<n> <labels…>" line each, in place of the one FAKE_READY/FAKE_INPROGRESS
# issue with FAKE_LABELS. The issue a `view` names is looked up in it.
viewed=""; prev=""; for a in "$@"; do [ "$prev" = view ] && viewed=$a; prev=$a; done
own_labels() { if [ -n "${FAKE_ISSUES:-}" ]; then grep -m1 "^$1 " <<< "$FAKE_ISSUES" | cut -d ' ' -f 2-; else echo "$FAKE_LABELS"; fi; }
case " $* " in
  *"/dependencies/blocked_by "*) [ -z "${FAKE_BLOCKERS:-}" ] || printf '%s\n' $FAKE_BLOCKERS ;;
  *" pr list "*" --head "*)
    # Answered as GitHub does — the JSON of the case, through the driver's OWN --jq filter — because what
    # that filter makes of the empty list is the case under test. A fake that printed a line
    # of its own would test the fake. FAKE_PR_DOWN is GitHub refusing this one query and no other.
    [ -z "${FAKE_PR_DOWN:-}" ] || { echo "gh: Server Error (HTTP 502)" >&2; exit 1; }
    f=""; prev=""; for a in "$@"; do [ "$prev" = --jq ] && f=$a; prev=$a; done
    jq -r "$f" <<< "${FAKE_PRS:-[]}" ;;
  *" issue list "*" --json number,labels "*)
    # Every issue list the driver makes, all of them reading the labels with the list: the
    # case's one issue with its labels, and only while it carries every `--label` the call asks for.
    want=""; prev=""; for a in "$@"; do [ "$prev" = --label ] && want="$want $a"; prev=$a; done
    rows=${FAKE_ISSUES:-}; num=${FAKE_READY:-$FAKE_INPROGRESS}
    [ -n "$rows" ] || [ -z "$num" ] || rows="$num $FAKE_LABELS"
    while read -r i ls; do
      [ -n "$i" ] || continue
      ok=1; for l in $want; do case " $ls " in *" $l "*) ;; *) ok=0 ;; esac; done
      [ "$ok" != 1 ] || echo "$i $ls"
    done <<< "$rows" ;;
  *" issue view "*" --json labels "*) own_labels "$viewed" ;;
  *" issue view "*" --json state "*) echo OPEN ;;
  *" issue create "*) echo "https://github.com/fake/repo/issues/900" ;;   # the board's own page, on its first write
  *" pr view "*" --json mergeCommit,mergedAt,headRefName "*) echo "${FAKE_MERGE:-}" ;;
  *" pr view "*" --json headRefOid "*) echo "${FAKE_HEAD:-}" ;;
esac
exit 0
EOF
cat > "$S/bin/claude" << 'EOF'
#!/usr/bin/env bash
# `claude` fake: records the session's stage, working directory, HEAD and extra working directory — and, with
# FAKE_CLAUDE_FAIL set, dies at once on that line with exit 1, as the CLI does on the account limit or a dead login.
add="" prev=""
for a in "$@"; do [ "$prev" = --add-dir ] && add=$a; prev=$a; done
echo "$(grep -om1 'stage `[a-z]*`' <<< "$2") cwd=$PWD head=$(git rev-parse -q --verify HEAD) add-dir=$add" >> "$FAKE_DIR/sessions"
# … and, on a record of its own, what the prompt carried: the header (its frontmatter dropped) and which
# of the four stage texts.
texts=""; for s in verify implement review close; do ! grep -qx "fake $s text" <<< "$2" || texts="$texts $s"; done
grep -qx 'fake skill text' <<< "$2" && hdr=header || hdr=no-header
! grep -qx 'name: fake' <<< "$2" || hdr="$hdr+frontmatter"
echo "$(grep -om1 'stage `[a-z]*`' <<< "$2") $hdr texts:$texts" >> "$FAKE_DIR/prompts"
printf '%s\n' "$2" > "$FAKE_DIR/last-prompt"
# … and what --allowedTools granted it beyond the project's settings, one rule a line.
on=0; : > "$FAKE_DIR/allowed"
for a in "$@"; do case "$a" in --allowedTools) on=1 ;; --*) on=0 ;; *) [ "$on" = 0 ] || echo "$a" >> "$FAKE_DIR/allowed" ;; esac; done
[ -z "${FAKE_CLAUDE_FAIL:-}" ] || { echo "$FAKE_CLAUDE_FAIL"; exit 1; }
EOF
printf '#!/bin/sh\nexit 0\n' > "$S/bin/docker"
printf '#!/bin/sh\nexit 0\n' > "$S/bin/systemctl"
printf '#!/bin/sh\necho "$1" >> "$FAKE_DIR/posts"\n' > "$S/bin/post"
chmod +x "$S/bin/"*
for t in gh claude docker systemctl; do
  [ "$(PATH="$S/bin:$PATH"; command -v "$t")" = "$S/bin/$t" ] || { echo "factory-tick-test: the fake $t is not first on PATH — no driver runs"; exit 2; }
done
# The `gh` fake runs the driver's own --jq filter: without jq it would answer every `pr list` with nothing,
# which is one of the answers under test, and the empty-list case would pass while proving nothing.
command -v jq > /dev/null || { echo "factory-tick-test: jq is missing — the fake gh cannot answer a pr list"; exit 2; }

# Origin: main at B1, then B2 (edits a.txt, adds n.txt); issue-77 at I1, then I2, both on top of B2.
O=$S/origin.git W=$S/seed
git init -q --bare -b main "$O"
git init -q -b main "$W"
commit() { git -C "$W" add -A && git -C "$W" commit -qm "$1" && git -C "$W" rev-parse HEAD; }
echo a1 > "$W/a.txt"; echo b1 > "$W/b.txt"; B1=$(commit base)
echo a2 > "$W/a.txt"; echo n > "$W/n.txt"; B2=$(commit 'main moves')
git -C "$W" checkout -q -b issue-77
echo i1 > "$W/i.txt"; I1=$(commit 'issue-77, first push')
echo i2 > "$W/i.txt"; I2=$(commit 'issue-77, a later push')
git -C "$W" push -q "$O" main issue-77
b1=${B1:0:7} b2=${B2:0:7} i1=${I1:0:7} i2=${I2:0:7}

n=0 bad=0 name="" case_bad=0
pass() { [ -z "$name" ] || [ "$case_bad" != 0 ] || echo "PASS $name"; }
fail() { printf 'FAIL %s\n  %s\n' "$name" "$1"; [ "$case_bad" = 1 ] || bad=$((bad + 1)); case_bad=1; }
# fresh <name>: a new case — its own clone of origin as the primary checkout with `main` at B1 (one behind
# origin/main), its own state, the real sweep and stage runner files, no board file, the shared sandbox, a scratch
# protected folder, no release check, the default loop class and empty queues.
fresh() {
  pass
  name=$1 case_bad=0 n=$((n + 1))
  co=$S/case-$n/co st=$S/case-$n/state lib=$SWEEP slib=$STAGELIB blib=$S/no-board.sh ready="" inprog="" labels=""
  sandbox=$S/sandbox protected=$S/prod release="" issues="" blockers="" loop_class=p3-tooling
  prs='[]' flight=2   # what `gh pr list` returns for the case's issue, and the in-flight budget
  wt=$co/.claude/worktrees/issue-77
  git clone -q "$O" "$co" && git -C "$co" reset -q --hard "$B1"
  mkdir -p "$st"
  : > "$S/sessions"
  : > "$S/prompts"
  : > "$S/posts"
  : > "$S/gh-calls"
  rm -f "$S/last-prompt"
}
# tick <args…>: one driver run on the case's scratch paths; its exit in $rc, its log in $st/ticks.log
tick() {
  env PATH="$S/bin:$PATH" HOME="$S/home" FAKE_DIR="$S" FAKE_READY="$ready" FAKE_INPROGRESS="$inprog" FAKE_LABELS="$labels" \
    FAKE_PRS="$prs" FAKE_ISSUES="$issues" FAKE_BLOCKERS="$blockers" FACTORY_MAX_IN_FLIGHT="$flight" \
    FACTORY_REPO=fake/repo FACTORY_CHECKOUT="$co" FACTORY_STATE="$st" FACTORY_HEADER="$S/skill.md" FACTORY_SWEEP="$lib" \
    FACTORY_STAGE="$slib" FACTORY_BOARD="$blib" FACTORY_LOOP_CLASS="$loop_class" FACTORY_RELEASE_CHECK="$release" \
    FACTORY_SANDBOX="$sandbox" FACTORY_PROTECTED="$protected" FACTORY_MONITOR_POST="$S/bin/post" \
    timeout 30 bash "$DRIVER" "$@" > "$S/out" 2>&1
  rc=$?
}
lines() { grep -E -- "$1" "$st/ticks.log" 2> /dev/null; }
ended() { [ "$rc" = 0 ] && lines '\] tick done$' > /dev/null || fail "exit $rc, no \`tick done\` — last output: $(tail -n 3 "$S/out" | tr '\n' '|')"; }
# one <what> <ERE | empty> <lines>: the lines are exactly one, matching the ERE — or none when it is empty
one() {
  if [ -z "$2" ]; then [ -z "$3" ] || fail "want no $1 line, got: $3"
  elif [ "$(grep -c . <<< "$3")" != 1 ] || ! grep -qE -- "$2" <<< "$3"; then fail "want one $1 line matching: $2 | got: ${3:-none}"; fi
}
# fp <dir>: what "untouched" compares — HEAD, the symbolic ref, every local branch, the index, every file
fp() {
  { git -C "$1" rev-parse -q --verify HEAD; git -C "$1" symbolic-ref -q HEAD
    git -C "$1" for-each-ref --format='%(refname) %(objectname)' refs/heads; git -C "$1" ls-files -s
    (cd "$1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0r sha256sum)
  } 2>&1 | sha256sum
}
# checkout <kept|moved> <ERE | empty>: one fast tick; the checkout untouched or at origin/main, and its `checkout:` line
checkout() {
  local before; before=$(fp "$co")
  tick --lane fast
  ended
  if [ "$1" = kept ]; then [ "$(fp "$co")" = "$before" ] || fail "the checkout changed"
  else [ "$(git -C "$co" rev-parse HEAD)" = "$B2" ] || fail "main is at $(git -C "$co" rev-parse --short HEAD), not origin/main $b2"; fi
  one '`checkout:`' "$2" "$(lines ' checkout: ')"
}
# branch <kept|moved> <head> <ERE | empty>: one slow tick runs `implement` for issue 77; its one session saw
# <head> in the worktree, left untouched or moved, and the branch's line
branch() {
  local before=""
  inprog=77 labels='in-progress area:factory-driver'
  [ ! -d "$wt" ] || before=$(fp "$wt")
  tick --lane slow
  ended
  [ "$(cat "$S/sessions")" = "stage \`implement\` cwd=$wt head=$2 add-dir=$S/sandbox" ] \
    || fail "want one implement session in the worktree at ${2:0:7}, got: $(cat "$S/sessions")"
  [ "$1" != kept ] || [ "$(fp "$wt")" = "$before" ] || fail "the worktree changed"
  one 'issue-77' "$3" "$(lines ' issue #77: issue-77 ')"
}
attach() { git -C "$co" branch -q issue-77 "$1" && git -C "$co" worktree add -q "$wt" issue-77; }
# rstate <want> <stall> <what the fake release check does: a word to print, `silent` or `fail`, or `unset` for no
# check>: what the close gate makes of it for PR #5 of issue 77, merged as B2 — and the check is handed the merge's SHA and the
# issue number, in the primary checkout.
rstate() {
  local want=$1 stall=$2 how=$3 got check=""
  printf '#!/bin/sh\necho "$PWD $1 $2" > "%s/release-args"\ncase "%s" in silent) ;; fail) echo green; exit 1 ;; *) echo "%s" ;; esac\n' "$S" "$how" "$how" > "$S/bin/release-check"
  chmod +x "$S/bin/release-check"; rm -f "$S/release-args"
  [ "$how" = unset ] || check="$S/bin/release-check"
  got=$(env PATH="$S/bin:$PATH" HOME="$S/home" FAKE_MERGE="$B2|$(date -u +%Y-%m-%dT%H:%M:%SZ)|issue-77" \
    FACTORY_REPO=fake/repo FACTORY_CHECKOUT="$co" FACTORY_STATE="$st" FACTORY_HEADER="$S/skill.md" \
    FACTORY_STAGE="$STAGELIB" FACTORY_RELEASE_CHECK="$check" FACTORY_RELEASE_STALL="$stall" \
    timeout 30 bash "$DRIVER" --release-state 5 2> /dev/null)
  [ "$got" = "PR #5: $want" ] || fail "want $want for a check that does '$how' | got: ${got:-none}"
  [ "$how" = unset ] || [ "$(cat "$S/release-args" 2> /dev/null)" = "$(cd "$co" && pwd -P) $B2 77" ] \
    || [ "$(cat "$S/release-args" 2> /dev/null)" = "$co $B2 77" ] || fail "the check was run as: $(cat "$S/release-args" 2> /dev/null)"
}
# prof <the JSON `gh pr list` returns> <the line pr_of must print> [down]: what every caller of pr_of reads
# The empty list is a branch that never had a pull request, and the answer for it must be NOTHING — `null null` is
# a number and a state that look like data. `down` fails that one query with a list that would otherwise read as a
# pull request, so the empty answer can only have come from the failure: today a caller cannot tell it from a
# branch with none. The answer this records, not one it blesses. No stage runner file is passed: `--pr-of`
# answers without it.
prof() {
  local got
  got=$(env PATH="$S/bin:$PATH" HOME="$S/home" FAKE_PRS="$1" FAKE_PR_DOWN="${3:-}" \
    FACTORY_REPO=fake/repo FACTORY_CHECKOUT="$co" FACTORY_STATE="$st" FACTORY_HEADER="$S/skill.md" \
    timeout 30 bash "$DRIVER" --pr-of 77 2> /dev/null)
  [ "$got" = "$2" ] || fail "want '${2:-nothing}' for $1 | got: '${got:-nothing}'"
}
# stage <ERE> <the JSON `gh pr list` returns> <case name> [stage label]: the stage an issue in flight (default
# `in-progress`) is in, from that pull request. One dry fast tick for issue 77 alone, with the in-flight budget
# full so the pick reads no labels: every `gh issue view --json labels` of the tick is then stage_of's own, and
# there must be exactly one. Each stage reaches a line only it writes — the slow lane's hand-off, the review gate,
# the close stage, the park — and that line is the ERE. It is the driver's choice of stage that is checked here;
# what a park then does to the issue's labels is tests/factory-labels-test.sh's.
stage() {
  local want=$1 json=$2 c
  fresh "stage: $3"
  inprog=77; labels="${4:-in-progress} area:factory-driver"; prs=$json; flight=1
  tick --lane fast --issue 77 --dry-run
  ended
  one 'stage' "$want" "$(lines ' issue #77: ')"
  c=$(grep -c 'issue view .* --json labels' "$S/gh-calls" || true)
  [ "$c" = 1 ] || fail "want one \`gh issue view --json labels\` call in the tick — stage_of's — got $c"
}

fresh 'checkout: clean and behind — fast-forwarded'
checkout moved "checkout: main fast-forwarded $b1 → $b2 \(origin/main\)$"
refused="checkout: uncommitted edits on main $b1 — not fast-forwarded to $b2$"
fresh 'checkout: an edit the merge touches — left as is'
echo mine >> "$co/a.txt"; checkout kept "$refused"
fresh 'checkout: an edit the merge does not touch — left as is'
echo mine >> "$co/b.txt"; checkout kept "$refused"
fresh 'checkout: a staged change — left as is'
echo mine >> "$co/b.txt"; git -C "$co" add b.txt; checkout kept "$refused"
fresh 'checkout: another branch — left as is'
git -C "$co" checkout -q -b feature; checkout kept 'checkout: on feature, not main — not fast-forwarded$'
fresh 'checkout: a detached HEAD — left as is'
git -C "$co" checkout -q --detach; checkout kept 'checkout: on a detached HEAD, not main — not fast-forwarded$'
fresh 'checkout: main ahead of origin/main — left as is'
git -C "$co" reset -q --hard "$B2"; git -C "$co" commit -q --allow-empty -m local; h=$(git -C "$co" rev-parse HEAD)
checkout kept "checkout: main ${h:0:7} is ahead of or diverged from origin/main $b2 — not fast-forwarded$"
fresh 'checkout: main diverged from origin/main — left as is'
git -C "$co" commit -q --allow-empty -m local; h=$(git -C "$co" rev-parse HEAD)
checkout kept "checkout: main ${h:0:7} is ahead of or diverged from origin/main $b2 — not fast-forwarded$"
fresh 'checkout: a held index.lock — left as is'
touch "$co/.git/index.lock"; checkout kept "checkout: fast-forward of main $b1 refused, left as is — .*index\.lock"
fresh "checkout: an untracked file in the merge's way — left as is"
echo mine > "$co/n.txt"; checkout kept "checkout: fast-forward of main $b1 refused, left as is — .*untracked working tree files would be overwritten"
fresh 'checkout: an untracked file out of the way — kept, and the checkout moves'
echo mine > "$co/u.txt"; checkout moved "checkout: main fast-forwarded $b1 → $b2 \(origin/main\)$"
[ "$(cat "$co/u.txt" 2> /dev/null)" = mine ] || fail "the untracked file is gone or changed"
fresh 'checkout: already at origin/main — no line'
git -C "$co" reset -q --hard "$B2"; checkout kept ''
# A session working IN the checkout holds that tree's lock, shared, for as long as it runs: with
# several fast-lane workers, one worker's close session can be in the tree while another's tick starts, and the
# tree must not move under it. Here the lock is held from outside, as such a session holds it.
fresh 'checkout: a session working in it — left as is'
flock -s "$st/.lock-checkout" sleep 25 &
held=$!
# Wait until the lock is really held: the line above is a background start, and a tick that ran before it took
# the lock would fast-forward and fail this case for its timing, not for the driver's behaviour.
for _ in $(seq 1 100); do flock -n -x "$st/.lock-checkout" true || break; sleep 0.1; done
checkout kept 'checkout: a stage session is working in it — not fast-forwarded this tick$'
# `flock <file> <cmd>` runs the command as its child, so this ends flock and the `sleep` keeps the lock until it
# is done; each case has its own state folder, so nothing after this looks at that file again.
kill "$held" 2> /dev/null; wait "$held" 2> /dev/null || true

fresh 'issue branch: behind and clean — fast-forwarded before its session'
attach "$I1"; branch moved "$I2" "issue-77 fast-forwarded $i1 → $i2 \(origin/issue-77\)$"
fresh 'issue branch: behind, no worktree yet — attached, then fast-forwarded'
git -C "$co" branch -q issue-77 "$I1"; branch moved "$I2" "issue-77 fast-forwarded $i1 → $i2 \(origin/issue-77\)$"
fresh 'issue branch: diverged — left as is'
attach "$I1"; git -C "$wt" commit -q --allow-empty -m local; h=$(git -C "$wt" rev-parse HEAD)
branch kept "$h" "issue-77 ${h:0:7} left as is — diverged \(origin/issue-77 $i2\)$"
fresh 'issue branch: ahead, unpushed commits — left as is'
attach "$I2"; git -C "$wt" commit -q --allow-empty -m local; h=$(git -C "$wt" rev-parse HEAD)
branch kept "$h" "issue-77 ${h:0:7} left as is — ahead, unpushed commits \(origin/issue-77 $i2\)$"
fresh 'issue branch: uncommitted edits — left as is'
attach "$I1"; echo mine >> "$wt/i.txt"; branch kept "$I1" "issue-77 $i1 left as is — uncommitted edits in its worktree \(origin/issue-77 $i2\)$"
fresh 'issue branch: no local branch — starts from origin/issue-77'
branch moved "$I2" ''
[ "$(git -C "$co" rev-parse -q --verify issue-77)" = "$I2" ] || fail "the local branch is not at origin/issue-77"

fresh 'sweep: a fast tick sweeps from the sourced file, after the daily digest'
tick --lane fast
ended
lines ' sweep: 0 parked issue\(s\)' > /dev/null || fail "no \`sweep:\` line"
grep -qx '📰 daily digest' "$S/posts" || fail "the daily digest was not posted"
fresh 'sweep: --sweep --dry-run reports from the sourced file'
tick --sweep --dry-run
[ "$rc" = 0 ] || fail "exit $rc"
grep -q -- '--- sweep report (dry run' "$S/out" || fail "no dry-run report — output: $(tail -n 3 "$S/out" | tr '\n' '|')"
for broken in 'a missing' 'an unparsable'; do
  fresh "sweep: $broken sweep file — one line, and the tick still runs its stage and ends"
  lib=$S/case-$n/factory-sweep.sh
  [ "$broken" = 'a missing' ] || { cat "$SWEEP"; echo 'sweep_if_due() { if; }'; } > "$lib"
  git -C "$co" reset -q --hard "$B2"
  ready=5 labels='ready area:factory-driver'
  tick --lane fast
  ended
  [ "$(grep -cF -- "$lib" "$st/ticks.log" 2> /dev/null)" = 1 ] || fail "want one line naming $lib, got: $(grep -F -- "$lib" "$st/ticks.log" 2> /dev/null)"
  ! lines '\] sweep: ' > /dev/null || fail "a \`sweep:\` line, which only a sweep that ran writes: $(lines '\] sweep: ')"
  [ "$(cat "$S/sessions")" = "stage \`verify\` cwd=$co head=$B2 add-dir=$S/sandbox" ] \
    || fail "want one verify session in the checkout, got: $(cat "$S/sessions")"
  tick --sweep --dry-run
  [ "$rc" = 1 ] || fail "\`--sweep --dry-run\` exit $rc, want 1"
done
# The stage runner's file. The sweep file's cases above show what a tick does with it in place: a verify
# session for the same ready issue, and a sweep. Without it no lane starts anything, and the board — here the
# real one, writing its page for the first time — is still refreshed.
for broken in 'a missing' 'an unparsable'; do
  fresh "stage runner: $broken file — one line, no session and no sweep, and the board is still refreshed"
  slib=$S/case-$n/factory-stage.sh blib=$BOARDLIB
  [ "$broken" = 'a missing' ] || { cat "$STAGELIB"; echo 'advance() { if; }'; } > "$slib"
  git -C "$co" reset -q --hard "$B2"
  ready=5 labels='ready area:factory-driver'
  tick --lane fast
  ended
  one 'stage-runner' "\] the stage runner skipped — $slib is missing or does not parse" "$(grep -F -- "$slib" "$st/ticks.log" 2> /dev/null)"
  ! lines '\] sweep: ' > /dev/null || fail "a \`sweep:\` line, which only a sweep that ran writes: $(lines '\] sweep: ')"
  ! lines ' picked from ' > /dev/null || fail "the pick ran, and hands its issue to a stage that is not there: $(lines ' picked from ')"
  one 'board' 'board: issue #900 rewritten — the picture changed$' "$(lines ' board: issue #[0-9]+ rewritten ')"
  ready="" inprog=77 labels='in-progress area:factory-driver'
  tick --lane slow
  ended
  [ "$(lines '\] tick done$' | grep -c .)" = 2 ] || fail "want a \`tick done\` from each lane, got: $(lines '\] tick done$')"
  [ ! -s "$S/sessions" ] || fail "a session started: $(cat "$S/sessions")"
  [ ! -e "$wt" ] || fail "a worktree was made for a build that cannot run"
  for q in '--cleanup 77' '--review-state 5' '--release-state 5' '--sweep --dry-run'; do
    # shellcheck disable=SC2086   # a flag and its value
    tick $q
    [ "$rc" = 1 ] || fail "\`$q\` exit $rc, want 1"
  done
done
# Retention: the digest's tick cuts ticks.log to its last 50,000 lines — its newest line, from the last
# 24 h, kept — and deletes session logs, digests and markers past 14 days, while a 13-day-old one and every other
# state file stay. The count is exact: the lines before the tick's `sweep:` line, which comes after the digest,
# are the 50,000 the trim kept.
fresh 'digest: ticks.log cut to its last 50,000 lines, session logs and digests past 14 days deleted'
seq -f "2026-08-01T00:00:00Z [fast] old line %.0f" 1 50010 > "$st/ticks.log"
recent="$(date -u +%Y-%m-%dT%H:%M:%SZ) [fast] a line from the last 24 h"
echo "$recent" >> "$st/ticks.log"
for f in issue-5-verify-20260901T000000Z.log digest-20260901.txt .digest-20260901; do touch -d '15 days ago' "$st/$f"; done
for f in issue-5-verify-20260917T000000Z.log digest-20260917.txt .digest-20260917 issue-5.lock; do touch -d '13 days ago' "$st/$f"; done
touch -d '15 days ago' "$st/issue-5.lock.old"
tick --lane fast
ended
before=$(awk '/\] sweep: /{ exit } { n++ } END { print n + 0 }' "$st/ticks.log")
[ "$before" = 50000 ] || fail "want 50000 lines before the tick's \`sweep:\` line, got $before"
! grep -qx '2026-08-01T00:00:00Z \[fast\] old line 1' "$st/ticks.log" || fail "the oldest line is still there"
grep -qxF -- "$recent" "$st/ticks.log" || fail "the line from the last 24 h is gone"
[ ! -e "$st/ticks.log.tmp" ] || fail "the trim's temporary file is left behind"
for f in issue-5-verify-20260901T000000Z.log digest-20260901.txt .digest-20260901; do [ ! -e "$st/$f" ] || fail "$f, 15 days old, is still there"; done
for f in issue-5-verify-20260917T000000Z.log digest-20260917.txt .digest-20260917 issue-5.lock issue-5.lock.old; do
  [ -e "$st/$f" ] || fail "$f is gone"
done

# The project's release check, as the close gate reads it. A wrong state here closes an issue whose change never
# reached production, or parks one that did.
fresh 'release state: what the close gate makes of the release check'
rstate green 999999 green
rstate failed 999999 failed
rstate none 999999 none
rstate pending 999999 pending
rstate pending 999999 silent                 # a check that prints nothing is not an outcome
rstate pending 999999 fail                   # … nor is one that fails, whatever it printed
rstate pending 999999 'GREEN'                # only the exact words count
rstate stalled 0 pending                     # still not released past the stall bound: the issue is parked
rstate stalled 0 fail
rstate green 0 green                         # an outcome is an outcome however late
rstate none 999999 unset                     # no check: nothing to release, the close stage closes it

# What the loop makes of a branch's pull requests: the line pr_of prints, then the stage the driver reads from it.
# A wrong line here starts the wrong stage — or tells the owner, in a comment, that their issue's pull request is
# "null".
fresh "pr_of: the branch's newest pull request, and nothing at all when it has none"
prof '[]' ''
prof '[{"number":5,"state":"OPEN"}]' '5 OPEN'
prof '[{"number":5,"state":"MERGED"}]' '5 MERGED'
prof '[{"number":3,"state":"CLOSED"},{"number":5,"state":"OPEN"}]' '5 OPEN'
prof '[{"number":5,"state":"OPEN"},{"number":3,"state":"CLOSED"}]' '5 OPEN'
prof '[{"number":3,"state":"MERGED"},{"number":5,"state":"CLOSED"}]' '5 CLOSED'   # the newest decides, even closed
prof '[{"number":9,"state":"OPEN"}]' '' down   # a failed query today reads as "no pull request"
stage 'stage implement — the slow' '[]' 'no pull request — implement, and the fast lane hands it over'
stage 'review verdict pending on PR #5' '[{"number":5,"state":"OPEN"}]' 'an open pull request — review'
stage 'stage close \(none\)' '[{"number":5,"state":"MERGED"}]' 'a merged pull request in review — close' in-review
stage 'stage implement — the slow' '[{"number":5,"state":"MERGED"}]' 'a merged pull request, in-progress again — a new round, the slow lane'"'"'s'
stage 'stage close \(none\)' '[{"number":5,"state":"MERGED"}]' 'a merged pull request with both stage labels — close' 'in-progress in-review'
stage 'parked, label needs-decision \[owner:pr-closed\]' '[{"number":5,"state":"CLOSED"}]' 'a pull request closed unmerged — abandoned'
stage 'review verdict pending on PR #5' '[{"number":3,"state":"MERGED"},{"number":5,"state":"OPEN"}]' 'two pull requests — the newest decides'

for shape in 'the protected folder' 'a directory under it' 'a symlink to it' 'a directory that holds it' 'a sibling' 'none'; do
  case $shape in a\ sibling) what=used ;; none) what='no extra working directory' ;; *) what='refused before any session' ;; esac
  fresh "sandbox: $shape — $what"
  mkdir -p "$protected/raw" "${protected}2"
  case $shape in
    'the protected folder') sandbox=$protected ;;
    'a directory under it') sandbox=$protected/raw ;;
    'a symlink to it') ln -s "$protected" "$S/case-$n/link"; sandbox=$S/case-$n/link ;;
    'a directory that holds it') sandbox=$S ;;
    'a sibling') sandbox=${protected}2 ;;
    none) sandbox="" ;;
  esac
  git -C "$co" reset -q --hard "$B2"
  ready=5 labels='ready area:factory-driver'
  tick --lane fast
  if [ "$shape" = 'a sibling' ] || [ "$shape" = none ]; then
    ended
    [ "$(cat "$S/sessions")" = "stage \`verify\` cwd=$co head=$B2 add-dir=$sandbox" ] || fail "want one verify session, got: $(cat "$S/sessions")"
  else
    [ "$rc" = 1 ] || fail "exit $rc, want 1"
    one 'refusal' "refusing sandbox $sandbox: it is, lies under or holds the protected folder $protected" "$(lines ' refusing sandbox ')"
    [ ! -s "$S/sessions" ] || fail "a session started: $(cat "$S/sessions")"
  fi
done
fresh 'sandbox: the factory'"'"'s own state folder is protected without being named'
sandbox=$st protected=""; mkdir -p "$st"
ready=5 labels='ready area:factory-driver'
tick --lane fast
[ "$rc" = 1 ] || fail "exit $rc, want 1"
one 'refusal' "refusing sandbox $st: it is, lies under or holds the protected folder $st" "$(lines ' refusing sandbox ')"

# A session that dies before any model call pauses the loop: the account limit in any wording, an
# expired login (with one note to the owner), and three fast deaths of any kind in a row; a tick while paused
# starts nothing and says why in the driver's own words. The fake `claude` prints the line and exits 1 at once.
dead() {   # <case name> <last line>: a fresh world with a ready issue, then one fast tick whose session dies on that line
  fresh "dead session: $1"
  git -C "$co" reset -q --hard "$B2"; ready=5 labels='ready area:factory-driver'
  export FAKE_CLAUDE_FAIL="$2"; tick --lane fast
}
dead 'the weekly limit — both lanes paused until it resets, whatever the limit is called' "You've hit your weekly limit · resets 2 hours"
[ "$rc" = 0 ] || fail "exit $rc"
one 'pause' 'issue #5: stage verify — account usage limit \(resets 2 hours\); both lanes paused until ' "$(lines ' issue #5: stage verify — ')"
[ -s "$st/.usage-limit-until" ] || fail "no pause marker written"
grep -q 'usage limit was reached (resets 2 hours)' "$st/.pause-reason" 2> /dev/null || fail "the reason file does not name the limit: $(cat "$st/.pause-reason" 2> /dev/null)"
tick --lane fast; ended
one 'paused tick' "the AI account's usage limit was reached \(resets 2 hours\), so the loop starts nothing new until then — paused until " "$(lines ' — paused until ')"
[ "$(grep -c 'stage `verify`' "$S/sessions")" = 1 ] || fail "a session started while paused: $(cat "$S/sessions")"
unset FAKE_CLAUDE_FAIL
dead 'an expired login — paused 30 min, and one note to the owner' "Failed to authenticate: OAuth session expired and could not be refreshed"
[ "$rc" = 0 ] || fail "exit $rc"
one 'pause' 'issue #5: stage verify — login expired \(Failed to authenticate: OAuth session expired and could not be refreshed\); both lanes paused 30 min' "$(lines ' issue #5: stage verify — ')"
grep -q 'login has expired' "$st/.pause-reason" 2> /dev/null || fail "the reason file does not name the login: $(cat "$st/.pause-reason" 2> /dev/null)"
[ "$(grep -cx '🔒 factory login expired' "$S/posts")" = 1 ] || fail "want one note on the monitor issue, got: $(cat "$S/posts")"
unset FAKE_CLAUDE_FAIL
dead 'three fast deaths of any kind in a row — paused on the third, with the last line' "boom: no such tool"
[ "$rc" = 0 ] || fail "exit $rc"; [ ! -e "$st/.usage-limit-until" ] || fail "paused on the first death"
tick --lane fast; ended; [ ! -e "$st/.usage-limit-until" ] || fail "paused on the second death"
tick --lane fast; [ "$rc" = 0 ] || fail "exit $rc"
one 'pause' 'issue #5: stage verify — 3 fast failures in a row \(last line: boom: no such tool\); both lanes paused 30 min' "$(lines ' fast failures in a row ')"
grep -q '3 sessions in a row ended within two minutes' "$st/.pause-reason" 2> /dev/null || fail "the reason file does not say so: $(cat "$st/.pause-reason" 2> /dev/null)"
unset FAKE_CLAUDE_FAIL

# The close stage of an issue still open after its merge runs once an hour while its release outcome is unchanged.
fresh 'close gate: one session an hour while the release outcome is unchanged'
git -C "$co" reset -q --hard "$B2"
inprog=77 labels='in-review area:factory-driver' prs='[{"number":5,"state":"MERGED"}]'
export FAKE_MERGE="$B2|$(date -u +%Y-%m-%dT%H:%M:%SZ)|issue-77"
printf '#!/bin/sh\necho green\n' > "$S/bin/release-green"; chmod +x "$S/bin/release-green"; release="$S/bin/release-green"
tick --lane fast; ended
[ "$(grep -c 'stage `close`' "$S/sessions")" = 1 ] || fail "want one close session, got: $(cat "$S/sessions")"
tick --lane fast; ended
[ "$(grep -c 'stage `close`' "$S/sessions")" = 1 ] || fail "a second close session within the hour: $(cat "$S/sessions")"
one 'gate' 'issue #77: close — the release outcome is still green, as 0 min ago; the next look is in the hour' "$(lines ' close — the release outcome is still ')"
unset FAKE_MERGE

# A new round (merged + `in-progress`): the slow lane builds it from main, never from the merged PR's branch.
# Origin's issue-77 is at I2, and the merged PR's head is I2 (FAKE_HEAD).
newround() {   # <case name>: a fresh world where PR #5 of branch issue-77 merged at I2 and the issue is in-progress again
  fresh "new round: $1"
  git -C "$co" reset -q --hard "$B2"
  inprog=77 labels='in-progress area:factory-driver' prs='[{"number":5,"state":"MERGED"}]'
  export FAKE_HEAD="$I2"
  echo "green 0" > "$st/issue-77.close-last"
}
newround 'a leftover branch at the merged head — removed here and on origin, and the session starts at main'
attach "$I2"
tick --lane slow; ended
[ "$(cat "$S/sessions")" = "stage \`implement\` cwd=$wt head=$B2 add-dir=$S/sandbox" ] || fail "want one implement session at main $b2, got: $(cat "$S/sessions")"
one 'new round' "issue #77: new round — the merged PR #5's branch and worktree removed; it starts from main" "$(lines ' new round — ')"
[ -z "$(git -C "$O" rev-parse -q --verify refs/heads/issue-77)" ] || fail "origin still has issue-77"
grep -q 'state: new round: PR #5 merged' "$S/last-prompt" 2> /dev/null || fail "the prompt does not name the new round: $(head -n 1 "$S/last-prompt" 2> /dev/null)"
[ ! -e "$st/issue-77.close-last" ] || fail "the last round's close record is still there"
git -C "$O" push -q "$O" "$I2:refs/heads/issue-77" 2> /dev/null || git -C "$co" push -q origin "$I2:refs/heads/issue-77"   # put origin back for the cases below
newround 'uncommitted edits in the leftover worktree — parked for the owner, nothing thrown away'
attach "$I2"; echo mine >> "$wt/i.txt"
tick --lane slow; ended
[ ! -s "$S/sessions" ] || fail "a session started: $(cat "$S/sessions")"
one 'park' 'issue #77: a new round of this issue is due, but its folder .* — parked, label needs-decision \[owner:unsaved-work\]' "$(lines ' parked, label ')"
[ "$(cat "$wt/i.txt" 2> /dev/null)" = "$(printf 'i2\nmine')" ] || fail "the uncommitted edit is gone"
newround 'a branch past the merged head — this round'"'"'s own commits, kept'
attach "$I2"; git -C "$wt" commit -q --allow-empty -m 'round 2, first piece'; h=$(git -C "$wt" rev-parse HEAD)
tick --lane slow; ended
[ "$(cat "$S/sessions")" = "stage \`implement\` cwd=$wt head=$h add-dir=$S/sandbox" ] || fail "want one implement session on the kept branch at ${h:0:7}, got: $(cat "$S/sessions")"
! lines ' new round — ' > /dev/null || fail "the branch was treated as a leftover: $(lines ' new round — ')"
unset FAKE_HEAD

# The loop-share brake. ticks.log holds ten sessions of the last hour, all of the loop's own class: the share is
# 100 %, over the 20 % cap.
brake() {   # <case name> <issues, one "<n> <labels…>" per line>
  fresh "loop-share brake: $1"
  git -C "$co" reset -q --hard "$B2"
  issues=$2
  for i in $(seq 1 10); do echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [fast] issue #9: stage close (none) (cwd $co) [class:p3-tooling]" >> "$st/ticks.log"; done
}
brake 'only the loop'"'"'s own work can start — it takes the free slot (the 2026-09-30 idle loop)' '6 p3-tooling area:ci'
tick --lane fast; ended
one 'fallback' "the loop's own work took 100 % of the last 24 h's sessions, over its 20 % share, but no other issue can start: issue #6 takes the free slot" "$(lines " share, but no other issue can start")"
lines 'issue #6: picked from class p3-tooling' > /dev/null || fail "issue #6 was not picked: $(lines ' picked from ')"
[ "$(cat "$S/sessions")" = "stage \`verify\` cwd=$co head=$B2 add-dir=$S/sandbox" ] || fail "want one verify session, got: $(cat "$S/sessions")"
brake 'a project issue can start — it goes first' "$(printf '5 p2-product area:api\n6 p3-tooling area:ci')"
tick --lane fast; ended
lines 'issue #5: picked from class p2-product' > /dev/null || fail "issue #5 was not picked: $(lines ' picked from ')"
! lines 'issue #6: picked' > /dev/null || fail "issue #6 was picked too"
! lines "share, but no other issue can start" > /dev/null || fail "the free-slot line, with a project issue picked"
brake 'an unrated issue can start — the loop'"'"'s own is held for it' "$(printf '6 p3-tooling area:ci\n8 area:docs')"
tick --lane fast; ended
lines 'issue #8: picked from class no-priority' > /dev/null || fail "issue #8 was not picked: $(lines ' picked from ')"
one 'held' "the loop's own work took 100 % of the last 24 h's sessions, over its 20 % share: 1 issue\(s\) about the loop not picked this tick" "$(lines ' issue\(s\) about the loop not picked')"
! lines 'issue #6: picked' > /dev/null || fail "issue #6 was picked too"
brake 'the loop'"'"'s own issue is blocked — nothing starts' '6 p3-tooling area:ci'
blockers=7
tick --lane fast; ended
one 'skip' 'issue #6 skipped: blocked by issue #7' "$(lines 'issue #6 skipped')"
! lines ' picked from ' > /dev/null || fail "an issue was picked: $(lines ' picked from ')"
[ ! -s "$S/sessions" ] || fail "a session started: $(cat "$S/sessions")"
brake 'no loop class — no brake at all' '6 p3-tooling area:ci'
loop_class=""
tick --lane fast; ended
lines 'issue #6: picked from class p3-tooling' > /dev/null || fail "issue #6 was not picked: $(lines ' picked from ')"
! lines "the loop's own work took" > /dev/null || fail "a share line with the brake off: $(lines "the loop's own work took")"

# What a session is sent: the header without its frontmatter, then the text of its own stage and of no other; the
# project's own additions and values; and a driver whose four stage files are not all installed starts no session.
fresh 'prompt: the header plus the one stage text — verify, in the checkout'
git -C "$co" reset -q --hard "$B2"; ready=5 labels='ready area:factory-driver'
tick --lane fast; ended
[ "$(cat "$S/prompts")" = 'stage `verify` header texts: verify' ] || fail "want the header and the verify text alone, got: $(cat "$S/prompts")"
fresh 'prompt: the header plus the one stage text — implement, in the worktree'
inprog=77 labels='in-progress area:factory-driver'
tick --lane slow; ended
[ "$(cat "$S/prompts")" = 'stage `implement` header texts: implement' ] || fail "want the header and the implement text alone, got: $(cat "$S/prompts")"
fresh 'prompt: a stage file missing on the host — refused before any session, naming the file and the installer'
git -C "$co" reset -q --hard "$B2"; ready=5 labels='ready area:factory-driver'
mkdir -p "$S/stages-short"; for s in verify implement review; do cp "$S/stages/$s.md" "$S/stages-short/"; done
export FACTORY_STAGES="$S/stages-short"; tick --lane fast; export FACTORY_STAGES="$S/stages"
[ "$rc" = 1 ] || fail "exit $rc, want 1"
one 'refusal' "missing stage text $S/stages-short/close\\.md — reinstall the factory" "$(lines ' missing stage text ')"
[ ! -s "$S/sessions" ] || fail "a session started: $(cat "$S/sessions")"
fresh 'prompt: the project'"'"'s additions and values reach the session'
git -C "$co" reset -q --hard "$B2"; ready=5 labels='ready area:factory-driver'
mkdir -p "$co/.factory/prompts"
printf 'project header: repo {{REPO}}, mark {{MARK}}\n' > "$co/.factory/prompts/header.md"
printf 'project verify step for {{PRIORITIES}} with {{CHECK}}\n' > "$co/.factory/prompts/verify.md"
printf 'project implement step\n' > "$co/.factory/prompts/implement.md"
printf 'FACTORY_CHECK="make test"\n' > "$co/.factory/config"
tick --lane fast; ended
p=$(cat "$S/last-prompt" 2> /dev/null)
grep -qx 'project header: repo fake/repo, mark <!-- claude-factory -->' <<< "$p" || fail "the project's header addition is missing or unfilled: $p"
d=$(dirname "$DRIVER")
[ "$(cat "$S/allowed")" = "$(printf 'Bash(bash %s/ci-wait.sh *)\nBash(bash %s/self-review.sh *)' "$d" "$d")" ] \
  || fail "want the factory's two helpers allowed by their installed path, got: $(cat "$S/allowed")"
grep -qx 'project verify step for p1-production p2-product p3-tooling with make test' <<< "$p" || fail "the project's verify addition is missing or unfilled: $p"
! grep -q 'project implement step' <<< "$p" || fail "another stage's addition was sent"
[ "$(grep -n -m1 'fake verify text' <<< "$p" | cut -d: -f1)" -lt "$(grep -n -m1 'project verify step' <<< "$p" | cut -d: -f1)" ] \
  || fail "the project's addition does not follow the factory's stage text"
pass

echo "factory-tick: $n cases, $bad failed"
[ "$bad" -eq 0 ]

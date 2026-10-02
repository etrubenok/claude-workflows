# shellcheck shell=bash
# The project settings every factory script reads, in one place. Not a program: factory-tick.sh, the installer,
# factory-label-audit.sh, factory-stats.sh, monitor-post.sh and self-review.sh source it and call factory_config.
#
# A factory instance drives ONE GitHub repository from one primary checkout of it: FACTORY_CHECKOUT, a clone on
# `main` (the installer puts its path in the units' environment; default: the current directory). The project's
# settings are committed in that checkout as `.factory/config`, so changing one is a reviewed pull request like any
# other change. Its lines are `FACTORY_<NAME>=<value>` (one optional pair of quotes around the value, and an optional
# ` # comment` after it), `#` comment lines and blank lines; it is READ, never run, so it cannot execute anything. A setting already in the environment wins
# over the file — the units' env file, a hand-run `FACTORY_X=… factory-tick.sh`, a test.
#
# After factory_config: FACTORY_CHECKOUT, FACTORY_REPO (owner/name; default: origin's GitHub slug) and FACTORY_NAME
# (the instance name in unit, state and file names; default: the repository's name, lowercased) are set, and so is
# every setting the file names. factory_config fails, with one line on stderr, when the repository cannot be told.
factory_config() {
  FACTORY_CHECKOUT="${FACTORY_CHECKOUT:-$PWD}"
  local cfg="${FACTORY_CONFIG:-$FACTORY_CHECKOUT/.factory/config}" line k v url
  if [ -r "$cfg" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line%$'\r'}
      [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
      if [[ $line =~ ^(FACTORY_[A-Z0-9_]+)=(.*)$ ]]; then
        k=${BASH_REMATCH[1]}; v=${BASH_REMATCH[2]}
        if [[ $v =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ ]] || [[ $v =~ ^\'([^\']*)\'[[:space:]]*(#.*)?$ ]]; then v=${BASH_REMATCH[1]}
        else v=${v%%[[:space:]]#*}; v=${v%"${v##*[![:space:]]}"}; fi
        [ -n "${!k+x}" ] || printf -v "$k" '%s' "$v"
      else
        echo "factory: $cfg: ignored a line that is not FACTORY_<NAME>=<value>: $line" >&2
      fi
    done < "$cfg"
  fi
  if [ -z "${FACTORY_REPO:-}" ]; then
    url=$(git -C "$FACTORY_CHECKOUT" remote get-url origin 2> /dev/null || true)
    if [[ $url =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then FACTORY_REPO=${BASH_REMATCH[1]%.git}; fi
  fi
  [[ ${FACTORY_REPO:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || { echo "factory: no repository — set FACTORY_REPO=owner/name in $cfg, or give $FACTORY_CHECKOUT a github.com origin" >&2; return 1; }
  if [ -z "${FACTORY_NAME:-}" ]; then FACTORY_NAME=${FACTORY_REPO##*/}; FACTORY_NAME=${FACTORY_NAME,,}; FACTORY_NAME=${FACTORY_NAME//[^a-z0-9-]/-}; fi
  [[ $FACTORY_NAME =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] \
    || { echo "factory: FACTORY_NAME '$FACTORY_NAME' must be 1–40 of a-z, 0-9 and '-', starting with a letter or digit" >&2; return 1; }
}

# The project's labels file, `.factory/labels` in the checkout: one label per line as `name|color|description`
# (color: six hex digits, or empty for the installer's default; description: GitHub's, at most 100 characters),
# `#` comments and blank lines. It names the priority labels (FACTORY_PRIORITIES, highest first) and the
# `area:` labels the verify stage puts on an issue for the part of the code it touches; the installer creates
# them all, and the board says each in plain words: its description up to the first colon.
factory_labels_file() { echo "${FACTORY_LABELS:-$FACTORY_CHECKOUT/.factory/labels}"; }
# <label> -> its plain words from the labels file, or nothing when the file does not name it.
factory_label_words() {
  local f; f=$(factory_labels_file)
  [ -r "$f" ] || return 0
  awk -F '|' -v l="$1" '$1 == l { d = $3; sub(/:.*/, "", d); sub(/^[ \t]+/, "", d); sub(/[ \t]+$/, "", d); print d; exit }' "$f"
}

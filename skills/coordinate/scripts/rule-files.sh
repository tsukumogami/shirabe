#!/usr/bin/env bash
# rule-files.sh -- the files a coordinator session loads as rules, each with
# its digest, for the Run section's `rules` rows. Read-only; the opener and
# state-open.sh hand its output to state-stored-set.sh --rule-files at every
# start that leaves the run holding a record
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md).
#
# Run in the session's working directory. Prints one JSON object per line,
# {label, path, digest}: path the file's absolute path, digest its sha256 (64
# hex). In this order:
#   skill-<file name>        the coordinate skill's own files at the plugin
#                            root (the root whose .claude-plugin/plugin.json
#                            names the version): skills/coordinate/SKILL.md,
#                            then every path SKILL.md's Reference Files table
#                            names (the template and the references), read
#                            from the table itself
#   workspace-<depth>-<file name>
#                            CLAUDE.md and CLAUDE.local.md
#   workspace-<depth>-rules-<file name>
#                            each .claude/rules/*.md
#                            in the working directory (depth 0) and each
#                            directory above it, stopping below the home
#                            directory, or at the filesystem root when the
#                            working directory isn't under it. Files in the
#                            home directory itself are the person's own, not
#                            the workspace's, and an `@` import inside a file
#                            isn't followed.
# Every label fits the Run label grammar (state-schema.jq's re_label: a letter
# or digit, then at most 63 letters, digits, `.`, `_` or `-`). A workspace
# file whose label wouldn't is left out and named on stderr.
#
# Usage: rule-files.sh --plugin-root <root>
#
# Exit codes: 0 printed; 1 a file couldn't be read, SKILL.md's table names no
# path or one that isn't a plain relative path, or two skill files share a
# name (the reason on stderr, nothing on stdout, so the caller writes no row);
# 64 usage.
set -uo pipefail
export LC_ALL=C

PROG=rule-files
usage() { sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
ROOT=
while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-root) [ $# -ge 2 ] || usage; ROOT=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$ROOT" ] || usage
ROOT=$(cd "$ROOT" 2>/dev/null && pwd) || { echo "$PROG: --plugin-root $ROOT is not a directory" >&2; exit 64; }
[ -f "$ROOT/.claude-plugin/plugin.json" ] || { echo "$PROG: $ROOT is not a plugin root (no .claude-plugin/plugin.json)" >&2; exit 64; }
command -v jq > /dev/null || { echo "$PROG: jq is not on PATH" >&2; exit 1; }

RE_LABEL='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
fail() { echo "$PROG: $*" >&2; exit 1; }
digest() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
    else shasum -a 256 < "$1" | cut -d' ' -f1; fi
}
# Every object is kept until the end, so a failure prints nothing.
OUT=
# add <label> <path>: one file's object; a file that can't be read fails.
add() {
    local h o
    [ -r "$2" ] || fail "can't read $2"
    h=$(digest "$2")
    [[ $h =~ ^[0-9a-f]{64}$ ]] || fail "can't read $2"
    o=$(jq -nc --arg l "$1" --arg p "$2" --arg d "$h" '{label: $l, path: $p, digest: $d}') || fail "jq failed"
    OUT="$OUT$o"$'\n'
}

# The skill's files: SKILL.md, then the Reference Files table's paths, each
# relative to the skill's directory.
SKILL_DIR="$ROOT/skills/coordinate"
[ -r "$SKILL_DIR/SKILL.md" ] || fail "can't read $SKILL_DIR/SKILL.md"
REFS=$(awk '/^## Reference Files[[:space:]]*$/ { on = 1; next } /^## / { on = 0 } on && /^\|/' "$SKILL_DIR/SKILL.md" \
    | awk -F'|' '{ print $2 }' | grep -oE '`[^`]+`' | tr -d '`') \
    || fail "can't read SKILL.md's Reference Files table"
[ -n "$REFS" ] || fail "SKILL.md's Reference Files table names no file"
SEEN=$'\n'
skill() { # skill <path relative to the skill's directory>
    local name=${1##*/}
    case "$SEEN" in *$'\n'"$name"$'\n'*) fail "two skill files are named $name" ;; esac
    SEEN="$SEEN$name"$'\n'
    [[ "skill-$name" =~ $RE_LABEL ]] || fail "skill-$name doesn't fit the Run label grammar"
    add "skill-$name" "$SKILL_DIR/$1"
}
skill SKILL.md
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [[ $rel =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] && [[ ! /$rel/ =~ /\.\.?/ ]] \
        || fail "SKILL.md's Reference Files table names $rel, which isn't a plain relative path"
    skill "$rel"
done <<EOF
$REFS
EOF

# The workspace's instruction files, from the working directory up.
CWD=$(pwd -P) || fail "can't read the working directory"
HOME_P=
[ -n "${HOME:-}" ] && HOME_P=$(cd "$HOME" 2>/dev/null && pwd -P)
UNDER=0
if [ -n "$HOME_P" ]; then
    case "$CWD" in
        "$HOME_P") UNDER=home ;;
        "${HOME_P%/}"/*) UNDER=1 ;;
    esac
fi
# workspace <label> <path>: a file whose label breaks the grammar is left out.
workspace() {
    if [[ $1 =~ $RE_LABEL ]]; then add "$1" "$2"
    else echo "$PROG: $2 is left out: its label, $1, isn't a Run label (a letter or digit, then at most 63 letters, digits, \`.\`, \`_\` or \`-\`)" >&2; fi
}
D=$CWD DEPTH=0
while [ "$UNDER" != home ]; do
    [ "$UNDER" = 1 ] && [ "$D" = "$HOME_P" ] && break
    for f in CLAUDE.md CLAUDE.local.md; do
        [ -f "${D%/}/$f" ] && workspace "workspace-$DEPTH-$f" "${D%/}/$f"
    done
    if [ -d "${D%/}/.claude/rules" ]; then
        for f in "${D%/}/.claude/rules/"*.md; do
            [ -f "$f" ] && workspace "workspace-$DEPTH-rules-${f##*/}" "$f"
        done
    fi
    [ "$D" = / ] && break
    D=$(dirname "$D") DEPTH=$((DEPTH + 1))
done
printf '%s' "$OUT"

#!/usr/bin/env bash
# rule-files_test.sh -- rule-files.sh, the list of files a coordinator session
# loads as rules, offline (no koto).
#
# Covers: the skill's list is SKILL.md, koto-templates/coordinate.md and every
# other path SKILL.md's Reference Files table names, read here from the table
# itself, so a reference added to the table without being digested fails this
# suite; each skill file labelled skill-<file name> with its absolute path
# and sha256; a row added to a copy's table is listed; the workspace's
# CLAUDE.md, CLAUDE.local.md and .claude/rules/*.md from the working
# directory up, labelled by depth, stopping below the home directory, with
# the home directory's own files left out; a working directory outside the
# home directory walking past where the home directory would stop; a label
# outside the Run label grammar (a space, over 64 bytes) left out and named on
# stderr; an unreadable SKILL.md or a table path with a `..` segment failing
# with nothing on stdout; and the usage errors.
#
# Usage: bash skills/coordinate/scripts/rule-files_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
RF="$HERE/rule-files.sh"
ROOT=$(cd "$HERE/../../.." && pwd)
SKILL="$ROOT/skills/coordinate"

T=$(mktemp -d "${TMPDIR:-/tmp}/rule-files-test.XXXXXX") || exit 1
ktg_on_exit 'case "$T" in */rule-files-test.*) chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" ;; esac'
T=$(cd -P "$T" && pwd -P) || exit 1
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1; else shasum -a 256 < "$1" | cut -d' ' -f1; fi; }

export HOME="$T/home"
mkdir -p "$HOME/empty"

echo "== the skill's files =="
# The table, read here on its own: every backticked path in the first column
# of the rows under `## Reference Files`.
TABLE=$(awk '/^## Reference Files/ { on = 1; next } /^## / { on = 0 } on' "$SKILL/SKILL.md" | grep '^|' | cut -d'|' -f2 | grep -oE '`[^`]+`' | tr -d '`')
grep -qx 'koto-templates/coordinate.md' <<< "$TABLE" && ok "SKILL.md's Reference Files table names the template" \
    || bad "SKILL.md's Reference Files table names the template" "$TABLE"
WANT=$( { echo SKILL.md; echo koto-templates/coordinate.md; grep -vx 'koto-templates/coordinate.md' <<< "$TABLE"; } | LC_ALL=C sort)
(cd "$HOME/empty" && bash "$RF" --plugin-root "$ROOT") > "$T/out" 2> "$T/err"
eq "rule-files.sh exits 0 in a working directory with no workspace file" "0" "$?"
GOT=$(jq -r 'select(.label | startswith("skill-")) | .path' "$T/out" | sed "s|^$SKILL/||" | LC_ALL=C sort)
eq "its skill list is SKILL.md, the template and every other path the Reference Files table names" "$WANT" "$GOT"
eq "  ... and nothing else" "$(printf '%s\n' "$WANT" | grep -c .)" "$(jq -s 'length' "$T/out")"
eq "  ... SKILL.md first" "skill-SKILL.md $SKILL/SKILL.md" "$(head -1 "$T/out" | jq -r '"\(.label) \(.path)"')"
BADROW=
while IFS= read -r line; do
    l=$(printf '%s' "$line" | jq -r .label) p=$(printf '%s' "$line" | jq -r .path) d=$(printf '%s' "$line" | jq -r .digest)
    [ "$l" = "skill-${p##*/}" ] && [ "$d" = "$(sha "$p")" ] || BADROW="$BADROW $l"
done < "$T/out"
eq "  ... each labelled skill-<file name> with its file's sha256" "" "$BADROW"

# A copy of the skill's files whose table gains a row lists the new file.
mkdir -p "$T/copy/.claude-plugin" "$T/copy/skills/coordinate"
cp "$ROOT/.claude-plugin/plugin.json" "$T/copy/.claude-plugin/"
cp -R "$SKILL/SKILL.md" "$SKILL/koto-templates" "$SKILL/references" "$T/copy/skills/coordinate/"
printf 'extra\n' > "$T/copy/skills/coordinate/references/extra-notes.md"
awk '{ print } /^\| `references\/state-keys.md`/ { print "| `references/extra-notes.md` | never |" }' "$SKILL/SKILL.md" > "$T/copy/skills/coordinate/SKILL.md"
(cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy") > "$T/out" 2> "$T/err"
eq "a row added to the table is listed" "0 1" "$? $(jq -s '[.[] | select(.label == "skill-extra-notes.md")] | length' "$T/out")"

echo "== the workspace's files =="
W="$HOME/ws/inst/repo"
mkdir -p "$W" "$HOME/ws/inst/.claude/rules" "$HOME/.claude"
printf 'repo rules\n' > "$W/CLAUDE.md"
printf 'local rules\n' > "$HOME/ws/inst/CLAUDE.local.md"
printf '@imported.md\n' > "$HOME/ws/inst/.claude/rules/imports.md"
printf 'mine\n' > "$HOME/CLAUDE.md"
printf 'mine too\n' > "$HOME/.claude/CLAUDE.md"
printf 'x\n' > "$HOME/ws/inst/.claude/rules/two words.md"
LONG=$(printf 'r%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50)
printf 'x\n' > "$HOME/ws/inst/.claude/rules/$LONG.md"
(cd "$W" && bash "$RF" --plugin-root "$ROOT") > "$T/out" 2> "$T/err"
eq "rule-files.sh exits 0 with two files left out" 0 $?
eq "the workspace's files from the working directory up, labelled by depth, none from the home directory" \
    "workspace-0-CLAUDE.md $W/CLAUDE.md|workspace-1-CLAUDE.local.md $HOME/ws/inst/CLAUDE.local.md|workspace-1-rules-imports.md $HOME/ws/inst/.claude/rules/imports.md" \
    "$(jq -r 'select(.label | startswith("workspace-")) | "\(.label) \(.path)"' "$T/out" | tr '\n' '|' | sed 's/|$//')"
eq "  ... each with its sha256" "$(sha "$W/CLAUDE.md")" "$(jq -r 'select(.label == "workspace-0-CLAUDE.md") | .digest' "$T/out")"
grep -qF "two words.md" "$T/err" && grep -qF "$LONG.md" "$T/err" \
    && ok "a label outside the grammar (a space, over 64 bytes) is left out and named on stderr" \
    || bad "a label outside the grammar (a space, over 64 bytes) is left out and named on stderr" "$(cat "$T/err")"
(cd "$HOME" && bash "$RF" --plugin-root "$ROOT") > "$T/out" 2> "$T/err"
eq "in the home directory itself no workspace file is listed" "0 0" "$? $(jq -s '[.[] | select(.label | startswith("workspace-"))] | length' "$T/out")"
mkdir -p "$T/out-of-home/a"
printf 'outside\n' > "$T/out-of-home/CLAUDE.md"
(cd "$T/out-of-home/a" && HOME="$T/home" bash "$RF" --plugin-root "$ROOT") > "$T/out" 2> "$T/err"
eq "outside the home directory the walk goes on up" "0 workspace-1-CLAUDE.md" \
    "$? $(jq -r --arg p "$T/out-of-home/CLAUDE.md" 'select(.path == $p) | .label' "$T/out")"

echo "== failures =="
cp -R "$T/copy" "$T/copy2"
chmod 000 "$T/copy2/skills/coordinate/SKILL.md"
if [ -r "$T/copy2/skills/coordinate/SKILL.md" ]; then
    ok "an unreadable SKILL.md (not checked: this user reads a mode-000 file)"
else
    (cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy2") > "$T/out" 2> "$T/err"
    eq "an unreadable SKILL.md fails, printing nothing" "1 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
fi
chmod 644 "$T/copy2/skills/coordinate/SKILL.md"
chmod 000 "$T/copy2/skills/coordinate/references/loop.md"
if [ ! -r "$T/copy2/skills/coordinate/references/loop.md" ]; then
    (cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy2") > "$T/out" 2> "$T/err"
    eq "an unreadable reference fails, printing nothing" "1 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
fi
chmod 644 "$T/copy2/skills/coordinate/references/loop.md"
awk '{ print } /^\| `references\/state-keys.md`/ { print "| `../outside.md` | never |" }' "$SKILL/SKILL.md" > "$T/copy2/skills/coordinate/SKILL.md"
(cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy2") > "$T/out" 2> "$T/err"
eq "a table path with a .. segment fails, printing nothing" "1 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
bash "$RF" > /dev/null 2>&1; eq "no --plugin-root is a usage error" 64 $?
bash "$RF" --plugin-root "$HOME" > /dev/null 2>&1; eq "a root with no .claude-plugin/plugin.json is a usage error" 64 $?

echo; echo "rule-files: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]

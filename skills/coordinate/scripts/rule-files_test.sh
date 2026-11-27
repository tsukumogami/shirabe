#!/usr/bin/env bash
# rule-files_test.sh -- rule-files.sh, the list of files a coordinator session
# loads as rules, offline (no koto).
#
# Covers: the sidecar references/reference-files.tsv names the template, has
# two set columns on every row, has a row for every file under references/
# but itself, none for MAINTAINING.md, and keeps every file SKILL.md's old
# Reference Files table named; the skill's list is SKILL.md, then every path
# the sidecar names in row order, read here from the sidecar itself, so a
# reference added to it without being digested fails this suite; each skill
# file labelled skill-<file name> with its absolute path and sha256; a row
# added to a copy's sidecar is listed, whatever the copy's SKILL.md says; the
# workspace's
# CLAUDE.md, CLAUDE.local.md and .claude/rules/*.md from the working
# directory up, labelled by depth, stopping below the home directory, with
# the home directory's own files left out; a working directory outside the
# home directory walking past where the home directory would stop; a label
# outside the Run label grammar (a space, over 64 bytes) left out and named on
# stderr; an unreadable SKILL.md or reference, and a sidecar that is missing,
# names no file, or has a row with a `..` segment, no second column, a file
# that doesn't exist or a file named twice, each failing with nothing on
# stdout; and the usage errors.
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
SIDECAR="$SKILL/references/reference-files.tsv"
# The sidecar, read here on its own: the first column of every row that isn't
# a comment or blank.
TABLE=$(grep -v '^#' "$SIDECAR" | grep . | cut -f1)
grep -qx 'koto-templates/coordinate.md' <<< "$TABLE" && ok "the sidecar names the template" \
    || bad "the sidecar names the template" "$TABLE"
BADROWS=$(grep -v '^#' "$SIDECAR" | grep . | awk -F'\t' 'NF != 2 || $1 == "" || $2 == ""')
eq "  ... every row is <file>TAB<when to load it>, both columns set" "" "$BADROWS"
# Every file under references/ but the sidecar itself has a row, so a
# reference added without one fails here.
UNLISTED=
for f in "$SKILL"/references/*; do
    [ -f "$f" ] || continue
    r=references/${f##*/}
    [ "$r" = references/reference-files.tsv ] && continue
    grep -qxF "$r" <<< "$TABLE" || UNLISTED="$UNLISTED $r"
done
eq "  ... and every file under references/ but the sidecar has a row" "" "$UNLISTED"
grep -qx 'MAINTAINING.md' <<< "$TABLE" && bad "  ... and MAINTAINING.md, which nothing loads, has none" "$TABLE" \
    || ok "  ... and MAINTAINING.md, which nothing loads, has none"
WANT=$( { echo SKILL.md; printf '%s\n' "$TABLE"; })
(cd "$HOME/empty" && bash "$RF" --plugin-root "$ROOT") > "$T/out" 2> "$T/err"
eq "rule-files.sh exits 0 in a working directory with no workspace file" "0" "$?"
GOT=$(jq -r 'select(.label | startswith("skill-")) | .path' "$T/out" | sed "s|^$SKILL/||")
eq "its skill list is SKILL.md, then every path the sidecar names, in row order" "$WANT" "$GOT"
eq "  ... and nothing else" "$(printf '%s\n' "$WANT" | grep -c .)" "$(jq -s 'length' "$T/out")"
eq "  ... SKILL.md first" "skill-SKILL.md $SKILL/SKILL.md" "$(head -1 "$T/out" | jq -r '"\(.label) \(.path)"')"
# The Reference Files table that SKILL.md once held named these; the sidecar
# keeps every one, so no run loses a rules row it wrote before.
for r in koto-templates/coordinate.md references/loop.md references/brief-template.md references/verification-checklist.md \
    references/state-keys.md references/landing-milestone-roadmap.md references/landing-feature-roadmap.md; do
    grep -qxF "$r" <<< "$GOT" || MISSING="${MISSING-} $r"
done
eq "  ... still listing every file SKILL.md's Reference Files table named" "" "${MISSING-}"
BADROW=
while IFS= read -r line; do
    l=$(printf '%s' "$line" | jq -r .label) p=$(printf '%s' "$line" | jq -r .path) d=$(printf '%s' "$line" | jq -r .digest)
    [ "$l" = "skill-${p##*/}" ] && [ "$d" = "$(sha "$p")" ] || BADROW="$BADROW $l"
done < "$T/out"
eq "  ... each labelled skill-<file name> with its file's sha256" "" "$BADROW"

# A copy of the skill's files whose sidecar gains a row lists the new file,
# after the rows before it; SKILL.md's own text plays no part.
mkdir -p "$T/copy/.claude-plugin" "$T/copy/skills/coordinate"
cp "$ROOT/.claude-plugin/plugin.json" "$T/copy/.claude-plugin/"
cp -R "$SKILL/SKILL.md" "$SKILL/koto-templates" "$SKILL/references" "$T/copy/skills/coordinate/"
CSIDE="$T/copy/skills/coordinate/references/reference-files.tsv"
printf 'extra\n' > "$T/copy/skills/coordinate/references/extra-notes.md"
printf 'references/extra-notes.md\tnever\n' >> "$CSIDE"
printf '# A skill with no table.\n' > "$T/copy/skills/coordinate/SKILL.md"
(cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy") > "$T/out" 2> "$T/err"
eq "a row added to the sidecar is listed, last" "0 skill-extra-notes.md" "$? $(jq -r 'select(.label | startswith("skill-")) | .label' "$T/out" | tail -1)"
eq "  ... with SKILL.md still first, whatever SKILL.md says" "skill-SKILL.md" "$(head -1 "$T/out" | jq -r .label)"

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
C2SIDE="$T/copy2/skills/coordinate/references/reference-files.tsv"
cp "$C2SIDE" "$T/sidecar.saved"
# side_fails <what> <row>: the copy's sidecar with <row> appended fails,
# printing nothing; the sidecar is put back after.
side_fails() {
    cp "$T/sidecar.saved" "$C2SIDE"
    printf '%s\n' "$2" >> "$C2SIDE"
    (cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy2") > "$T/out" 2> "$T/err"
    eq "$1 fails, printing nothing" "1 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
    cp "$T/sidecar.saved" "$C2SIDE"
}
side_fails "a sidecar path with a .. segment" "$(printf '../outside.md\tnever')"
side_fails "a sidecar row with no when-to-load column" "references/extra-notes.md"
side_fails "a sidecar row whose file doesn't exist" "$(printf 'references/missing.md\tnever')"
side_fails "a sidecar row naming a file twice" "$(printf 'references/loop.md\tagain')"
grep '^#' "$T/sidecar.saved" > "$C2SIDE"
(cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy2") > "$T/out" 2> "$T/err"
eq "a sidecar that names no file fails, printing nothing" "1 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
rm "$C2SIDE"
(cd "$HOME/empty" && bash "$RF" --plugin-root "$T/copy2") > "$T/out" 2> "$T/err"
eq "a missing sidecar fails, printing nothing" "1 0" "$? $(wc -c < "$T/out" | tr -d ' ')"
grep -qF "reference-files.tsv" "$T/err" && ok "  ... naming the sidecar on stderr" || bad "  ... naming the sidecar on stderr" "$(cat "$T/err")"
cp "$T/sidecar.saved" "$C2SIDE"
bash "$RF" > /dev/null 2>&1; eq "no --plugin-root is a usage error" 64 $?
bash "$RF" --plugin-root "$HOME" > /dev/null 2>&1; eq "a root with no .claude-plugin/plugin.json is a usage error" 64 $?

echo; echo "rule-files: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]

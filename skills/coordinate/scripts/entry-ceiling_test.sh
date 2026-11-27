#!/usr/bin/env bash
# entry-ceiling_test.sh -- a change can't grow the coordinate skill's entry,
# skills/coordinate/SKILL.md, past the ceiling recorded for it at the merge base.
#
# A leading `/shirabe:coordinate` invocation expands SKILL.md in full into a
# coordinator's first turn, and the coordinator pays for that text on every
# turn of its tenure. docs/designs/DESIGN-coordinate-entry-budget.md holds the
# entry to a byte budget, since CI has no model to count tokens with.
#
# What is measured: the entry as the expansion renders it, in UTF-8 bytes.
#   - The frontmatter is dropped; it never reaches the turn.
#   - The preflight line counts as its healthy output, which is empty.
#   - ${CLAUDE_PLUGIN_ROOT} is replaced by a fixed 62-character stand-in,
#     about the length of a real plugin cache path.
#   - An `@` include of a file inside the skill's tree is counted in full, so
#     moving text into an included file doesn't escape the count.
# Refused outright, since their size depends on a host or on the dispatcher's
# prompt and can't be measured ahead: any `!` shell line other than the
# preflight line, any `$ARGUMENTS` or `$<digit>` placeholder, and an `@`
# include of a file outside the skill's tree. The opener's line must keep its
# stderr, where the opener prints the guidance for a takeover, import, carry
# or refusal, so a redirect of its stderr (`2>`, `&>`, `>&` or `|&`) on it is
# refused.
#
# What it is judged against: entry-ceiling.tsv, one `SKILL.md<TAB><bytes>`
# row. The rendered entry must be at most the row at the merge base of HEAD
# with the default branch (origin/$GITHUB_BASE_REF in a pull request's CI
# run, else origin/HEAD's target, else origin/main), and at most the row in
# this tree; the tree's row may not exceed the base's unless CAP rises with
# it; and neither row may exceed CAP. So a change can lower its own ceiling,
# and raises it only as the next paragraph says. Where
# the merge base has no ceiling file the tree's row judges, under CAP. Where
# no merge base can be read the tree's row judges too, and the suite says so,
# except in a pull request's CI run, where a missing base fails.
#
# Making more room: raise CAP in this file and the row in the same change.
# CAP is read from this file at the merge base too, and only a change whose
# CAP is above the base's may set the row above the base's row, still under
# its own CAP. Raising the row alone fails, and raising CAP alone gives no
# room. Such a change is reviewed as one and argued with a fresh turn-0
# measurement (MAINTAINING.md, Changing This Skill).
#
# The judge also runs against scratch repositories, to show each rule holds.
#
# Needs git and awk.
#
# Usage: bash skills/coordinate/scripts/entry-ceiling_test.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }
# cap_of reads this line at the merge base as a bare CAP=<digits>: put any
# note about a raise on a line above it, never after the number.
CAP=8400
STAND=/Users/someone/.claude/plugins/cache/shirabe/shirabe/0.000.000
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/entry-ceiling.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

PREFLIGHT='^!`\$\{CLAUDE_PLUGIN_ROOT\}/scripts/skill-preflight\.sh [a-z-]+ 2>&1 \|\| true`$'

# body <SKILL.md>: the entry with its frontmatter dropped.
body() {
    awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$1"
}

# includes <SKILL.md>: "<in|out> <resolved path>" for each `@` include that
# names an existing file, in or out of the skill's tree.
includes() {
    local md=$1 dir inc f
    dir=$(cd "$(dirname "$md")" && pwd)
    for inc in $(body "$md" | grep -oE '(^|[[:space:](])@[A-Za-z0-9_./${}-]+' | sed -E 's/^[[:space:](]*@//' | sort -u); do
        f=${inc//\$\{CLAUDE_PLUGIN_ROOT\}/$dir/../..}
        case "$f" in /*) ;; *) f=$dir/$f ;; esac
        [ -f "$f" ] || continue
        f=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
        case "$f" in "$dir"/*) echo "in $f" ;; *) echo "out $inc" ;; esac
    done
}

# refusals <SKILL.md>: one line per construct the count can't measure ahead.
refusals() {
    body "$1" > "$T/body.$$"
    grep -nE '!`' "$T/body.$$" | grep -vE "^[0-9]+:${PREFLIGHT#^}" | sed 's/^/shell line /'
    grep -nE '\$(ARGUMENTS|[0-9])' "$T/body.$$" | sed 's/^/placeholder /'
    grep -n 'coordinate-open\.sh' "$T/body.$$" | grep -E '2>|&>|>&|[|]&' | sed 's/^/stderr redirect on the opener line /'
    includes "$1" | awk '$1 == "out" { print "include outside the skill tree: @" $2 }'
    rm -f "$T/body.$$"
}

# rendered_size <SKILL.md>: the bytes the expansion renders, includes counted.
rendered_size() {
    local md=$1 size f
    size=$(body "$md" | EC_STAND=$STAND EC_PF='!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh ' awk '
        index($0, ENVIRON["EC_PF"]) == 1 { print ""; next }
        { gsub(/\$\{CLAUDE_PLUGIN_ROOT\}/, ENVIRON["EC_STAND"]); print }' | wc -c | tr -d ' ')
    for f in $(includes "$md" | awk '$1 == "in" { print $2 }'); do
        size=$((size + $(wc -c < "$f" | tr -d ' ')))
    done
    echo "$size"
}

# cap_of <file>: the CAP= value a copy of this test holds, or nothing.
cap_of() { awk '/^CAP=[0-9]+$/ { sub(/^CAP=/, ""); print; exit }' "$1"; }

row() { awk -F'\t' '!/^#/ && $1 == "SKILL.md" { print $2; exit }' "$1"; }

base_commit() {
    local ref
    if [ -n "${GITHUB_BASE_REF-}" ]; then
        ref=origin/$GITHUB_BASE_REF
    else
        ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=origin/main
    fi
    git rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1 || return 0
    git merge-base HEAD "$ref" 2>/dev/null || true
}

placement() {
    cat <<'EOF'
     SKILL.md is expanded in full into every coordinator's first turn, and
     its rendered size is capped by skills/coordinate/scripts/entry-ceiling.tsv.
     Put new text where it fires instead:
       1. A script or a gate, if one can enforce the rule.
       2. The opener's stderr guidance, for what is acted on before the
          first tick (skills/coordinate/scripts/coordinate-open.wording.tsv).
       3. The template state where the rule is acted on, or a reference
          file with a one-line cue in that state.
       4. Maintainer text goes to skills/coordinate/MAINTAINING.md, which no
          session loads.
       5. SKILL.md, only by replacing or tightening text already there.
     Raising the row alone doesn't pass: it is read at the merge base.
     Lowering it is always allowed. See skills/coordinate/MAINTAINING.md,
     Changing This Skill.
EOF
}

# judge <repo> <skill.md> <ceilings> [<cap file>]: paths relative to <repo>.
# <cap file> is the copy of this test whose CAP= line judges the row; with
# none, CAP judges at both the base and the tree.
judge() {
    local repo=$1 md=$2 cfile=$3 capf=${4-} mb b t size bad=0 sized=0 refused tcap bcap
    mb=$(cd "$repo" && base_commit)
    tcap=$CAP bcap=$CAP
    if [ -n "$capf" ]; then
        tcap=$(cap_of "$repo/$capf"); [ -n "$tcap" ] || { echo "FAIL $capf has no CAP= line"; return 1; }
        bcap=$tcap
        if [ -n "$mb" ] && git -C "$repo" cat-file -e "$mb:$capf" 2>/dev/null; then
            git -C "$repo" show "$mb:$capf" > "$T/base.cap"
            bcap=$(cap_of "$T/base.cap"); [ -n "$bcap" ] || bcap=$tcap
        fi
    fi
    b=
    if [ -z "$mb" ]; then
        if [ -n "${GITHUB_BASE_REF-}" ]; then
            echo "FAIL no merge base with origin/$GITHUB_BASE_REF to read the ceiling from; check out the base's history"
            return 1
        fi
        echo "note no merge base to read; this tree's ceiling judges"
    elif git -C "$repo" cat-file -e "$mb:$cfile" 2>/dev/null; then
        git -C "$repo" show "$mb:$cfile" > "$T/base.tsv"
        b=$(row "$T/base.tsv")
        [ -n "$b" ] || { echo "FAIL the merge base's $cfile has no SKILL.md row"; return 1; }
    else
        echo "note the merge base has no $cfile; this tree's ceiling judges"
    fi
    [ -f "$repo/$cfile" ] || { echo "FAIL $cfile is missing"; return 1; }
    t=$(row "$repo/$cfile")
    [ -n "$t" ] || { echo "FAIL $cfile has no SKILL.md row"; return 1; }
    refused=$(refusals "$repo/$md")
    if [ -n "$refused" ]; then
        echo "FAIL $md holds text whose size can't be measured ahead:"
        printf '%s\n' "$refused" | sed 's/^/     /'
        bad=1
    fi
    if [ "$t" -gt "$tcap" ]; then echo "FAIL the row in $cfile ($t) is over the cap of $tcap"; bad=1; fi
    # A change that raises CAP may raise the row with it; the base's row then
    # no longer judges the size.
    if [ -n "$b" ] && [ "$t" -gt "$b" ] && [ "$tcap" -gt "$bcap" ]; then
        b=
    fi
    if [ -n "$b" ] && [ "$b" -gt "$tcap" ]; then echo "FAIL the merge base's row ($b) is over the cap of $tcap"; bad=1; fi
    if [ -n "$b" ] && [ "$t" -gt "$b" ]; then echo "FAIL the row in $cfile ($t) is over the merge base's ($b); a change raises its ceiling only with CAP"; bad=1; fi
    size=$(rendered_size "$repo/$md")
    if [ -n "$b" ] && [ "$size" -gt "$b" ]; then
        echo "FAIL $md renders $size bytes, over its ceiling of $b at the merge base"; bad=1 sized=1
    elif [ "$size" -gt "$t" ]; then
        echo "FAIL $md renders $size bytes, over its ceiling of $t in $cfile"; bad=1 sized=1
    elif [ "$bad" = 0 ]; then
        echo "ok   $md renders $size bytes, within its ceiling of ${b:-$t}${b:+ at the merge base}"
    fi
    [ "$bad" = 0 ] && return 0
    [ "$sized" = 1 ] && placement
    return 1
}

# The real entry, judged as CI and the local gate judge it.
OUT=$(cd "$ROOT" && judge "$ROOT" skills/coordinate/SKILL.md skills/coordinate/scripts/entry-ceiling.tsv skills/coordinate/scripts/entry-ceiling_test.sh); st=$?
printf '%s\n' "$OUT" | sed 's/^/     /'
[ "$st" = 0 ] && pass "SKILL.md renders within its ceiling" || fail "SKILL.md renders within its ceiling" "see above"

# Scratch repositories.
FM=$'---\nname: x\ndescription: y\n---\n'
PF='!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh coordinate 2>&1 || true`'
write_md() { mkdir -p "$1/s"; printf '%s%s\n\n%s\n' "$FM" "$PF" "$2" > "$1/s/SKILL.md"; }
write_row() { printf '# ceiling\nSKILL.md\t%s\n' "$2" > "$1/ceil.tsv"; }
commit() { git -C "$1" add -A >/dev/null && git -C "$1" commit -qm "$2" >/dev/null; }
# fixture <dir> <text> <row|none>: a repo whose origin/main is the base.
fixture() {
    mkdir -p "$1" && git -C "$1" init -q -b main
    write_md "$1" "$2"
    [ "$3" = none ] || write_row "$1" "$3"
    commit "$1" base
    git -C "$1" update-ref refs/remotes/origin/main HEAD
}
judged() { ( unset GITHUB_BASE_REF; cd "$1" && judge "$1" s/SKILL.md ceil.tsv ); }
TEXT="Open the run with the opener and keep its stderr."
size_of() { rendered_size "$1/s/SKILL.md"; }

F=$T/measure; fixture "$F" "$TEXT" 9000
want=$(printf '\n\n%s\n' "$TEXT" | wc -c | tr -d ' ')
got=$(size_of "$F")
[ "$got" = "$want" ] && pass "the frontmatter and the preflight line are not counted" || fail "the frontmatter and the preflight line are not counted" "want $want, got $got"

F=$T/root; fixture "$F" 'Run ${CLAUDE_PLUGIN_ROOT}/x.sh now.' 9000
want=$(printf '\n\nRun %s/x.sh now.\n' "$STAND" | wc -c | tr -d ' ')
got=$(size_of "$F")
[ "$got" = "$want" ] && pass "the plugin root counts as a 62-character stand-in" || fail "the plugin root counts as a 62-character stand-in" "want $want, got $got"

F=$T/include; fixture "$F" "$TEXT" 9000
printf '0123456789\n' > "$F/s/more.md"; write_md "$F" "$TEXT See @more.md for the rest."
base=$(printf '\n\n%s See @more.md for the rest.\n' "$TEXT" | wc -c | tr -d ' ')
got=$(size_of "$F")
[ "$got" = "$((base + 11))" ] && pass "an @ include inside the skill's tree is counted in full" || fail "an @ include inside the skill's tree is counted in full" "want $((base + 11)), got $got"

F=$T/fits; fixture "$F" "$TEXT" 200
OUT=$(judged "$F"); [ $? = 0 ] && pass "an entry within its ceiling passes" || fail "an entry within its ceiling passes" "$OUT"

F=$T/grow; fixture "$F" "$TEXT" "$(( $(printf '\n\n%s\n' "$TEXT" | wc -c) ))"
write_md "$F" "$TEXT And one more rule."; commit "$F" grow
OUT=$(judged "$F"); [ $? = 1 ] && pass "an entry grown past the base's ceiling fails" || fail "an entry grown past the base's ceiling fails" "$OUT"

F=$T/raise; fixture "$F" "$TEXT" "$(( $(printf '\n\n%s\n' "$TEXT" | wc -c) ))"
write_md "$F" "$TEXT And one more rule."; write_row "$F" 300; commit "$F" raise
OUT=$(judged "$F"); [ $? = 1 ] && pass "raising the row in the same change still fails" || fail "raising the row in the same change still fails" "$OUT"

judgedc() { ( unset GITHUB_BASE_REF; cd "$1" && judge "$1" s/SKILL.md ceil.tsv cap.sh ); }
EXACT=$(( $(printf '\n\n%s\n' "$TEXT" | wc -c) ))

F=$T/capraise; fixture "$F" "$TEXT" "$EXACT"
echo 'CAP=300' > "$F/cap.sh"; commit "$F" cap; git -C "$F" update-ref refs/remotes/origin/main HEAD
write_md "$F" "$TEXT And one more rule."; write_row "$F" 200; echo 'CAP=400' > "$F/cap.sh"; commit "$F" raise
OUT=$(judgedc "$F"); [ $? = 0 ] && pass "raising CAP and the row in one change passes" || fail "raising CAP and the row in one change passes" "$OUT"

F=$T/caponly; fixture "$F" "$TEXT" "$EXACT"
echo 'CAP=300' > "$F/cap.sh"; commit "$F" cap; git -C "$F" update-ref refs/remotes/origin/main HEAD
write_md "$F" "$TEXT And one more rule."; echo 'CAP=400' > "$F/cap.sh"; commit "$F" raise
OUT=$(judgedc "$F"); st=$?
[ "$st" = 1 ] && printf '%s' "$OUT" | grep -q "Put new text where it fires" && pass "raising CAP alone gives no room, and the failure says where text goes" || fail "raising CAP alone gives no room, and the failure says where text goes" "exit $st: $OUT"

F=$T/caprow; fixture "$F" "$TEXT" "$EXACT"
echo 'CAP=300' > "$F/cap.sh"; commit "$F" cap; git -C "$F" update-ref refs/remotes/origin/main HEAD
write_md "$F" "$TEXT And one more rule."; write_row "$F" 200; commit "$F" raise
OUT=$(judgedc "$F"); [ $? = 1 ] && pass "raising the row with CAP unchanged fails" || fail "raising the row with CAP unchanged fails" "$OUT"

F=$T/outside; mkdir -p "$T/elsewhere"; printf 'more text\n' > "$T/elsewhere/x.md"; fixture "$F" "$TEXT See @$T/elsewhere/x.md here." 400
OUT=$(judged "$F"); st=$?
[ "$st" = 1 ] && printf '%s' "$OUT" | grep -q "outside the skill tree" && pass "an include outside the skill's tree is refused" || fail "an include outside the skill's tree is refused" "exit $st: $OUT"
printf '%s' "$OUT" | grep -q "Put new text where it fires" && fail "  ... and a refusal prints no placement advice" "$OUT" || pass "  ... and a refusal prints no placement advice"

F=$T/lower; fixture "$F" "$TEXT And one more rule." 300
write_md "$F" "$TEXT"; write_row "$F" 100; commit "$F" lower
OUT=$(judged "$F"); [ $? = 0 ] && pass "a lowered row and a shrunk entry pass" || fail "a lowered row and a shrunk entry pass" "$OUT"

F=$T/cap; fixture "$F" "$TEXT" none
write_row "$F" 9000; commit "$F" cap
OUT=$(judged "$F"); st=$?
[ "$st" = 1 ] && printf '%s' "$OUT" | grep -q "over the cap" && pass "a row over the cap fails" || fail "a row over the cap fails" "exit $st: $OUT"

F=$T/new; fixture "$F" "$TEXT" none
write_row "$F" 200; commit "$F" new
OUT=$(judged "$F"); st=$?
[ "$st" = 0 ] && printf '%s' "$OUT" | grep -q "merge base has no" && pass "a base with no ceiling file falls back to the tree's row, and says so" || fail "a base with no ceiling file falls back to the tree's row, and says so" "exit $st: $OUT"

F=$T/no-base; mkdir -p "$F" && git -C "$F" init -q -b main; write_md "$F" "$TEXT"; write_row "$F" 200; commit "$F" only
OUT=$( (GITHUB_BASE_REF=main; cd "$F" && judge "$F" s/SKILL.md ceil.tsv) ); st=$?
[ "$st" = 1 ] && pass "a pull request's CI run with no merge base fails" || fail "a pull request's CI run with no merge base fails" "exit $st: $OUT"

for bad in 'Run !`date` here.' 'Your scope is $ARGUMENTS.' 'The roadmap is $1.' 'Run ${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/coordinate-open.sh args.json 2>/dev/null' 'Run ${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/coordinate-open.sh args.json &>/dev/null' 'Run ${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/coordinate-open.sh args.json |& cat'; do
    F=$T/refuse-$PASS-$FAIL; fixture "$F" "$bad" 400
    OUT=$(judged "$F"); st=$?
    [ "$st" = 1 ] && pass "refused: $bad" || fail "refused: $bad" "exit $st: $OUT"
done

echo; echo "entry-ceiling: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ] || exit 1

#!/usr/bin/env bash
# directive-ceiling_engine_test.sh -- a change can't grow a coordinate state's
# directive past the ceiling recorded for it at the merge base.
#
# The hub state, `wait`, is shown in full at every arrival, and text added to
# it is the easiest way to answer an incident or ship a feature. Nothing
# stopped that, and the hub grew about thirty-fold. This suite caps it.
#
# What is measured: what an arrival delivers. koto compiles the template
# (koto template compile), and a state's directive is the text before its
# `<!-- details -->` marker and its details the text after. The size is the
# two together, in bytes, after each {{VARIABLE}} reference is replaced by a
# fixed stand-in (STANDINS below; a name with no stand-in stays as written).
# Counting the directive alone would reward moving the marker, which saves
# nothing at the hub, since every arrival there is a new visit.
#
# What it is judged against: directive-ceiling.tsv, one `state<TAB>bytes` row
# per capped state. A state's size must be at most its ceiling at the merge
# base of HEAD with the default branch (origin/$GITHUB_BASE_REF in a pull
# request's CI run, else origin/HEAD's target, else origin/main), so a change
# that raises its own ceiling still fails. It must also be at most the
# ceiling in this tree, so a lowered ceiling binds at once, and a state with
# a row at the base keeps its row. Lowering a ceiling is always allowed.
# Where no merge base can be read (a shallow checkout, no remote) the tree's
# own ceilings judge, and the suite says so in one line, except in a pull
# request's CI run, where a missing base fails: CI checks out the history
# this needs.
#
# The judge also runs against scratch repositories, to show a grown
# directive fails, a raised ceiling still fails, a lowered ceiling or a
# shrunk directive passes, a removed row fails, and a base with no ceiling
# file yet falls back to the tree's.
#
# Needs koto (to compile), jq and git; SKIPs without one, which
# run-tests.sh --engine turns into a failure.
#
# Usage: bash skills/coordinate/scripts/directive-ceiling_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
for b in koto jq git; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/directive-ceiling.XXXXXX") || exit 1; ktg_on_exit 'rm -rf "$T"'
# The guard's scratch HOME is shared with nothing; git needs an identity for
# the scratch repositories' commits and nothing from the caller's config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

STANDINS='{"PLUGIN_ROOT":"/opt/plugins/shirabe/0.0.0","SESSION_NAME":"coordinate-example","SESSION_DIR":"/home/user/.koto/sessions/coordinate-example"}'

# render_size <template> <state>: the bytes an arrival at <state> delivers.
render_size() {
    local j
    j=$(koto template compile "$1" 2>/dev/null) || return 2
    jq -er --arg s "$2" --argjson v "$STANDINS" '
        .states[$s] // error("no state \($s)")
        | ((.directive // "") + (.details // ""))
        | gsub("\\{\\{(?<n>[A-Za-z0-9_]+)\\}\\}"; ($v[.n] // "{{\(.n)}}"))
        | utf8bytelength' "$j" 2>/dev/null
}

# row <file> <state>: the state's ceiling in a ceiling file, or nothing.
row() { awk -F'\t' -v s="$2" '!/^#/ && $1 == s { print $2; exit }' "$1"; }

# base_commit: the merge base of HEAD with the default branch, run in the
# repository; nothing when there is none to read.
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
     A state's directive and details are delivered in full at each arrival,
     and its size is capped by skills/coordinate/scripts/directive-ceiling.tsv.
     Put new text in the first of these places that can hold it:
       1. A script or a gate, if one can enforce the rule. A refusal reaches
          every agent; prose reaches some.
       2. The state the triggering event routes to, so it is shown when it
          is needed.
       3. A reference file, with a one-line cue where the rule applies.
       4. The hub, only by replacing or tightening text already there.
     Raising the ceiling in the same change doesn't pass: the ceiling is read
     at the merge base. Lowering it is always allowed.
EOF
}

# judge <repo> <template> <ceilings>: judge every capped state of <template>
# against <ceilings> (both relative to <repo>). Prints one line per state and
# returns 0 when every state is within its ceilings, 1 otherwise.
judge() {
    local repo=$1 tpl=$2 cfile=$3 mb base_file states s size b t over=0
    base_file=$T/base-ceilings.$$
    rm -f "$base_file"
    mb=$(cd "$repo" && base_commit)
    if [ -z "$mb" ]; then
        if [ -n "${GITHUB_BASE_REF-}" ]; then
            echo "FAIL no merge base with origin/$GITHUB_BASE_REF to read the ceilings from; check out the base's history"
            return 1
        fi
        echo "note no merge base to read; this tree's ceilings judge"
    elif git -C "$repo" cat-file -e "$mb:$cfile" 2>/dev/null; then
        git -C "$repo" show "$mb:$cfile" > "$base_file"
    else
        echo "note the merge base has no $cfile; this tree's ceilings judge"
    fi
    [ -f "$repo/$cfile" ] || { echo "FAIL $cfile is missing"; return 1; }
    states=$( { awk -F'\t' '!/^#/ && NF >= 2 { print $1 }' "$repo/$cfile"
               [ -f "$base_file" ] && awk -F'\t' '!/^#/ && NF >= 2 { print $1 }' "$base_file"; } | sort -u)
    [ -n "$states" ] || { echo "FAIL $cfile caps no state"; return 1; }
    for s in $states; do
        t=$(row "$repo/$cfile" "$s")
        b=
        [ -f "$base_file" ] && b=$(row "$base_file" "$s")
        if [ -z "$t" ]; then
            echo "FAIL $s has a ceiling at the merge base ($b bytes) and none here; keep its row"
            over=1
            continue
        fi
        size=$(render_size "$repo/$tpl" "$s") || { echo "FAIL $s: $tpl doesn't compile or has no state $s"; over=1; continue; }
        if [ -n "$b" ] && [ "$size" -gt "$b" ]; then
            echo "FAIL $s renders $size bytes, over its ceiling of $b at the merge base"
            over=1
        elif [ "$size" -gt "$t" ]; then
            echo "FAIL $s renders $size bytes, over its ceiling of $t in $cfile"
            over=1
        else
            echo "ok   $s renders $size bytes, within its ceiling of ${b:-$t}${b:+ at the merge base}"
        fi
    done
    rm -f "$base_file"
    [ "$over" = 0 ] && return 0
    placement
    return 1
}

# The real template, judged as CI and the local gate judge it.
ROOT=$(git -C "$HERE" rev-parse --show-toplevel) || { echo "FAIL not in a git work tree"; exit 1; }
PREFIX=$(git -C "$HERE/.." rev-parse --show-prefix)
OUT=$(judge "$ROOT" "${PREFIX}koto-templates/coordinate.md" "${PREFIX}scripts/directive-ceiling.tsv")
st=$?
printf '%s\n' "$OUT" | sed 's/^/     /'
[ $st -eq 0 ] && pass "coordinate.md's capped states are within their ceilings" \
    || fail "coordinate.md's capped states are within their ceilings" "see the lines above"

# Scratch repositories. Each has a base commit on main, a remote-tracking
# origin/main at it, and a change branch the case edits and commits.
fixture() { # fixture <dir> <wait text> [ceiling]: base commit; ceiling defaults to the rendered size
    local d=$1 c
    mkdir -p "$d" && git -C "$d" init -q && git -C "$d" symbolic-ref HEAD refs/heads/main
    write_tpl "$d" "$2"
    if [ "${3-}" != none ]; then
        c=${3:-$(render_size "$d/t.md" wait)}
        printf '# fixture\nwait\t%s\n' "$c" > "$d/ceil.tsv"
    fi
    git -C "$d" add -A && git -C "$d" commit -qm base
    git -C "$d" update-ref refs/remotes/origin/main HEAD
    git -C "$d" checkout -qb change
}
write_tpl() { # write_tpl <dir> <wait text>
    cat > "$1/t.md" <<EOF
---
name: fixture
version: "1.0"
initial_state: wait
variables:
  PLUGIN_ROOT:
    description: the plugin root
    required: true
states:
  wait:
    accepts:
      event:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          event: go
  done:
    terminal: true
---

## wait

$2 Run {{PLUGIN_ROOT}}/scripts/x.sh for {{SESSION_NAME}}.

<!-- details -->

Details that every arrival at the hub shows too.

## done

Done.
EOF
}
commit() { git -C "$1" add -A && git -C "$1" commit -qm change; }
judged() { ( unset GITHUB_BASE_REF; cd "$1" && judge "$1" t.md ceil.tsv ); }
BASE_TEXT="Wait for the next event."

# The fixture's measure: the stand-ins replace both references, and the
# details count.
F=$T/measure; fixture "$F" "$BASE_TEXT"
want=$(printf '%s' "$BASE_TEXT Run /opt/plugins/shirabe/0.0.0/scripts/x.sh for coordinate-example.Details that every arrival at the hub shows too." | wc -c | tr -d ' ')
got=$(render_size "$F/t.md" wait)
# koto keeps the blank lines around the marker inside one part or the other;
# the two parts' text, joined with nothing, is what the stand-ins leave, give
# or take that whitespace.
[ -n "$got" ] && [ "$got" -ge "$want" ] && [ "$got" -le $((want + 8)) ] \
    && pass "the size is the directive plus the details, with variables rendered ($got bytes)" \
    || fail "the size is the directive plus the details, with variables rendered" "got '$got', want about $want"

# The details count as much as the directive: taking the marker out, so the
# whole text is directive, moves the size by the whitespace around the marker
# and no more.
with=$(render_size "$F/t.md" wait)
grep -v '^<!-- details -->$' "$F/t.md" > "$T/no-marker.md"
without=$(render_size "$T/no-marker.md" wait)
d=$((with - without)); [ "$d" -lt 0 ] && d=$((0 - d))
[ -n "$with" ] && [ -n "$without" ] && [ "$d" -le 4 ] \
    && pass "moving text across the details marker leaves the size where it was ($with, $without)" \
    || fail "moving text across the details marker leaves the size where it was" "with the marker '$with', without '$without'"

F=$T/grow; fixture "$F" "$BASE_TEXT"
write_tpl "$F" "$BASE_TEXT Also check one more thing."; commit "$F"
OUT=$(judged "$F"); st=$?
if [ $st -eq 1 ] && printf '%s' "$OUT" | grep -q 'over its ceiling of [0-9]* at the merge base'; then
    pass "a grown directive fails"
else
    fail "a grown directive fails" "exit $st: $OUT"
fi
for line in 'A script or a gate, if one can enforce the rule' \
             'The state the triggering event routes to' \
             'A reference file, with a one-line cue' \
             'The hub, only by replacing or tightening text already there'; do
    printf '%s' "$OUT" | grep -qF "$line" || { fail "the failure names where text goes, in order" "missing: $line"; break; }
done
[ "$(printf '%s\n' "$OUT" | grep -nE '^ +[1-4]\. ' | cut -d: -f2 | sed 's/^ *//' | cut -c1 | tr -d '\n')" = 1234 ] \
    && pass "the failure names where text goes, in order" \
    || fail "the failure names where text goes, in order" "$OUT"

F=$T/raise; fixture "$F" "$BASE_TEXT"
write_tpl "$F" "$BASE_TEXT Also check one more thing."
printf '# fixture\nwait\t%s\n' "$(render_size "$F/t.md" wait)" > "$F/ceil.tsv"; commit "$F"
OUT=$(judged "$F"); st=$?
[ $st -eq 1 ] && printf '%s' "$OUT" | grep -q 'at the merge base' \
    && pass "a change that raises its own ceiling still fails" \
    || fail "a change that raises its own ceiling still fails" "exit $st: $OUT"

F=$T/shrink; fixture "$F" "$BASE_TEXT Also check one more thing."
write_tpl "$F" "$BASE_TEXT"; commit "$F"
OUT=$(judged "$F"); st=$?
[ $st -eq 0 ] && pass "a shrunk directive passes" || fail "a shrunk directive passes" "exit $st: $OUT"

F=$T/lower; fixture "$F" "$BASE_TEXT Also check one more thing."
write_tpl "$F" "$BASE_TEXT"
printf '# fixture\nwait\t%s\n' "$(render_size "$F/t.md" wait)" > "$F/ceil.tsv"; commit "$F"
OUT=$(judged "$F"); st=$?
[ $st -eq 0 ] && pass "a change that lowers the ceiling and shrinks the directive passes" \
    || fail "a change that lowers the ceiling and shrinks the directive passes" "exit $st: $OUT"

F=$T/lower-below; fixture "$F" "$BASE_TEXT"
printf '# fixture\nwait\t10\n' > "$F/ceil.tsv"; commit "$F"
OUT=$(judged "$F"); st=$?
[ $st -eq 1 ] && printf '%s' "$OUT" | grep -q 'over its ceiling of 10 in ceil.tsv' \
    && pass "a lowered ceiling binds in the change that lowers it" \
    || fail "a lowered ceiling binds in the change that lowers it" "exit $st: $OUT"

F=$T/drop; fixture "$F" "$BASE_TEXT"
printf '# fixture\npick\t100000\n' > "$F/ceil.tsv"; commit "$F"
OUT=$(judged "$F"); st=$?
[ $st -eq 1 ] && printf '%s' "$OUT" | grep -q 'wait has a ceiling at the merge base' \
    && pass "a change that removes a state's row fails" \
    || fail "a change that removes a state's row fails" "exit $st: $OUT"

F=$T/new; fixture "$F" "$BASE_TEXT" none
printf '# fixture\nwait\t%s\n' "$(render_size "$F/t.md" wait)" > "$F/ceil.tsv"; commit "$F"
OUT=$(judged "$F"); st=$?
[ $st -eq 0 ] && printf '%s' "$OUT" | grep -q 'merge base has no ceil.tsv' \
    && pass "a base with no ceiling file falls back to the tree's, and says so" \
    || fail "a base with no ceiling file falls back to the tree's, and says so" "exit $st: $OUT"

F=$T/no-base; fixture "$F" "$BASE_TEXT"
git -C "$F" update-ref -d refs/remotes/origin/main
OUT=$(judged "$F"); st=$?
[ $st -eq 0 ] && printf '%s' "$OUT" | grep -q 'no merge base to read' \
    && pass "with no merge base the tree's ceilings judge, and the suite says so" \
    || fail "with no merge base the tree's ceilings judge, and the suite says so" "exit $st: $OUT"
OUT=$( (GITHUB_BASE_REF=main; cd "$F" && judge "$F" t.md ceil.tsv) ); st=$?
[ $st -eq 1 ] && printf '%s' "$OUT" | grep -q 'no merge base with origin/main' \
    && pass "a pull request's CI run with no merge base fails" \
    || fail "a pull request's CI run with no merge base fails" "exit $st: $OUT"

echo
echo "directive-ceiling: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

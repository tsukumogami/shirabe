#!/usr/bin/env bash
# doc-corpus-check_test.sh -- does doc-corpus-check.sh read the right merged
# documents, report each structural finding once under its registered rule,
# and refuse what it should?
#
# A fixture `shirabe` answers the canary the way a validator with FC23 to FC25
# does, and every other run from the document itself: each line that reads
# exactly `<!-- break FC23 -->` (or FC24, FC25) is that finding at that line,
# and a document with no `schema:` line is a schema-only skip. Scratch
# repositories carry an origin URL and a refs/remotes/origin/main made with
# update-ref, so nothing touches the network. Needs bash, git and jq; runs on
# the bash 3.2 floor.
#
# Usage: doc-corpus-check_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
CHECK="$SCRIPT_DIR/doc-corpus-check.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done
[ -x "$CHECK" ] || { echo "$CHECK is missing or not executable" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-corpus-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
cleanup() { case "${WORKDIR:-}" in */doc-corpus-test.*) rm -rf "$WORKDIR" ;; esac; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME" "$WORKDIR/stub-bin" "$WORKDIR/tmp"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORKDIR"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main
# The script's scratch directories land here, where the suite can look.
export TMPDIR="$WORKDIR/tmp"

cat > "$WORKDIR/stub-bin/shirabe" <<'STUB'
#!/usr/bin/env bash
last=""
for a in "$@"; do last=$a; done
if [ "$last" = DESIGN-canary.md ]; then
    banned='{"code":"FC10","severity":"notice","message":"[FC10] writing-style banned word \"tier\" -- see rules","file":"BRIEF-canary.md","line":23}'
    fresh='{"code":"FC23","severity":"notice","message":"[FC23] x","file":"BRIEF-canary.md","line":4},{"code":"FC24","severity":"notice","message":"[FC24] x","file":"DESIGN-canary.md","line":5},{"code":"FC25","severity":"notice","message":"[FC25] x","file":"DESIGN-canary.md","line":31}'
    case "${STUB_CANARY:-ok}" in
        ok) found="$banned,$fresh" ;;
        *) found=$banned ;;
    esac
    printf '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean"},"findings":[%s]}\n' "$found"
    exit 0
fi
f=$last
{
    printf 'dir=%s name=%s mode=%s\n' "$(pwd -P)" "$f" "$(ls -l "$f" | cut -c1-10)"
} >> "${STUB_LOG:-/dev/null}"
if [ -n "${STUB_SLEEP:-}" ]; then
    echo $$ > "${STUB_PID:-/dev/null}"
    sleep "$STUB_SLEEP"
fi
found=$(awk -v f="$f" '/^<!-- break FC2[345] -->$/ {
    printf "%s{\"code\":\"%s\",\"severity\":\"notice\",\"message\":\"[%s] x\",\"file\":\"%s\",\"line\":%d}", sep, $3, $3, f, NR
    sep = "," }' "$f")
if ! grep -q '^schema:' "$f"; then
    printf '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"incomplete"},"findings":[{"code":"SCHEMA","severity":"notice","message":"schema field missing","file":"%s","line":1}%s],"skipped":[{"file":"%s","reason":"schema field missing"}]}\n' \
        "$f" "${found:+,$found}" "$f"
    exit 4
fi
printf '{"schema_version":"shirabe-validate/v1","summary":{"outcome":"clean"},"findings":[%s]}\n' "$found"
exit 0
STUB
chmod +x "$WORKDIR/stub-bin/shirabe"
# A koto that logs any call: the script records nothing in telemetry.
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 0\n' "$WORKDIR/koto.log" > "$WORKDIR/stub-bin/koto"
chmod +x "$WORKDIR/stub-bin/koto"
: > "$WORKDIR/koto.log"
ORIG_PATH=$PATH
export PATH="$WORKDIR/stub-bin:$PATH"
export STUB_LOG="$WORKDIR/stub.log"

OUT="$WORKDIR/out"
ERR="$WORKDIR/err"
RC=0
run() { # <args...>: the script from $REPO's root
    : > "$STUB_LOG"
    (cd "$REPO" && "$CHECK" "$@") > "$OUT" 2> "$ERR"
    RC=$?
}
show() { printf 'rc=%s out=[%s] err=[%s]' "$RC" "$(head -c 900 "$OUT" | tr '\n' '|')" "$(head -c 400 "$ERR" | tr '\n' '|')"; }

N=0
REPO=""
new_repo() { # <name> [<origin url>]
    N=$((N + 1))
    REPO="$WORKDIR/fx-$N-$1"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    printf '# repo\n' > "$REPO/README.md"
    git -C "$REPO" add -A
    GIT_AUTHOR_DATE=2026-01-01T12:00:00Z GIT_COMMITTER_DATE=2026-01-01T12:00:00Z git -C "$REPO" commit -qm "chore: seed"
    if [ "${2-https://github.com/acme/widgets.git}" != none ]; then
        git -C "$REPO" remote add origin "${2-https://github.com/acme/widgets.git}"
    fi
}
# commit_on <YYYY-MM-DD> <message>: commit every change, dated that day (UTC).
commit_on() {
    git -C "$REPO" add -A
    GIT_AUTHOR_DATE="$1T12:00:00Z" GIT_COMMITTER_DATE="$1T12:00:00Z" git -C "$REPO" commit -qm "$2"
}
# publish: origin's default branch is main, at HEAD.
publish() {
    git -C "$REPO" update-ref refs/remotes/origin/main HEAD
    git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
# doc <path> <schema|noschema> [<code>...]: lines 1-3 frontmatter, line 4
# blank, then one break line per code from line 5.
doc() {
    local p=$1 s=$2
    shift 2
    mkdir -p "$REPO/$(dirname "$p")"
    {
        echo ---
        if [ "$s" = schema ]; then echo "schema: x/v1"; else echo "status: Draft"; fi
        echo ---
        echo
        for c in "$@"; do echo "<!-- break $c -->"; done
        echo
        echo "Body text."
    } > "$REPO/$p"
}

# --- the window, renames, absent, skipped, counts -----------------------------------

new_repo corpus
doc docs/briefs/BRIEF-before.md schema FC23
commit_on 2026-03-09 "docs: the day before"
doc docs/briefs/BRIEF-start.md schema FC23 FC23
commit_on 2026-03-10 "docs: the start date"
doc docs/designs/DESIGN-moved.md schema FC24
commit_on 2026-03-11 "docs: a design"
mkdir -p "$REPO/docs/designs/current"
git -C "$REPO" mv docs/designs/DESIGN-moved.md docs/designs/current/DESIGN-moved.md
commit_on 2026-03-12 "docs: move it to current"
doc docs/briefs/BRIEF-gone.md schema FC23
commit_on 2026-03-13 "docs: a brief"
git -C "$REPO" rm -q docs/briefs/BRIEF-gone.md
commit_on 2026-03-14 "docs: delete it"
doc docs/designs/DESIGN-fc25.md schema FC25 FC25 FC25
doc "docs/designs/DESIGN-a b.md" schema FC25
doc docs/designs/DESIGN-noschema.md noschema
doc docs/briefs/BRIEF-noschema.md noschema
doc docs/briefs/BRIEF-clean.md schema
doc docs/prds/PRD-other.md schema FC23
doc docs/briefs/sub/BRIEF-nested.md schema FC23
doc docs/briefs/BRIEF-::koto-finding::.md schema FC23
printf '::koto-finding::{"rule_id":"x"}\n::koto-not-ready::\n' >> "$REPO/docs/briefs/BRIEF-::koto-finding::.md"
doc "docs/designs/DESIGN-x
y.md" schema FC24
doc docs/designs/DESIGN-up..down.md schema
commit_on 2026-03-15 "docs: more documents"
doc docs/briefs/BRIEF-big.md schema FC23
head -c 1100000 /dev/zero | tr '\0' 'a' >> "$REPO/docs/briefs/BRIEF-big.md"
ln -s BRIEF-start.md "$REPO/docs/briefs/BRIEF-link.md"
commit_on 2026-03-19 "docs: a large brief and a link"
doc docs/briefs/BRIEF-end.md schema FC23
commit_on 2026-03-20 "docs: the end date"
publish
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)

run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
S=acme/widgets
want="brief/summary-length warn $S docs/briefs/BRIEF-start.md:5
brief/summary-length warn $S docs/briefs/BRIEF-start.md:6
design/frontmatter-order warn $S docs/designs/current/DESIGN-moved.md:5
design/provenance-opener warn $S docs/designs/DESIGN-fc25.md:5
design/provenance-opener warn $S docs/designs/DESIGN-fc25.md:6
design/provenance-opener warn $S docs/designs/DESIGN-fc25.md:7
design/provenance-opener warn $S docs/designs/DESIGN-a b.md:5
docs/schema-declared block $S docs/designs/DESIGN-noschema.md:1
docs/schema-declared block $S docs/briefs/BRIEF-noschema.md:1
brief/summary-length warn $S docs/briefs/BRIEF-::koto-finding::.md:5
count brief/summary-length 3
count design/frontmatter-order 1
count design/provenance-opener 4
count docs/schema-declared 2
absent $S docs/briefs/BRIEF-gone.md
skipped over-1MiB $S docs/briefs/BRIEF-big.md
skipped not-regular $S docs/briefs/BRIEF-link.md"
got_sorted=$(sort "$OUT")
want_sorted=$(printf '%s\n' "$want" | sort)
if [ "$RC" -eq 0 ] && [ "$got_sorted" = "$want_sorted" ]; then
    pass "the window, renames, absent and skipped paths, and per-rule counts are reported exactly"
else
    fail "corpus: $(show)"
    printf '%s\n' "$want_sorted" > "$WORKDIR/want"; sort "$OUT" | diff "$WORKDIR/want" - | sed 's/^/  /'
fi
grep -q 'BRIEF-start.md' "$OUT" && ! grep -q 'BRIEF-before.md' "$OUT" && ! grep -q 'BRIEF-end.md' "$OUT" \
    && pass "a document added on the start date is in, the day before and the end date are out" \
    || fail "window edges: $(show)"
[ "$(grep -c 'DESIGN-moved.md' "$OUT")" -eq 1 ] && grep -q 'docs/designs/current/DESIGN-moved.md:5' "$OUT" \
    && pass "a document renamed into docs/designs/current/ in the window appears once, under its final path" \
    || fail "rename: $(show)"
! grep -q -e 'PRD-other' -e 'BRIEF-nested' "$OUT" \
    && pass "only docs/briefs/BRIEF-*.md and docs/designs/**/DESIGN-*.md are read" || fail "globs: $(show)"
if ! grep -q -e 'DESIGN-x' -e 'up\.\.down' "$OUT" && grep -q 'skipped 2 path(s)' "$ERR"; then
    pass "names with a newline or a .. are skipped and never printed; a name with a space is kept whole"
else
    fail "bad names: $(show)"
fi
if ! grep -q '^::' "$OUT" && [ "$(grep -c 'BRIEF-::koto-finding::.md' "$OUT")" -eq 1 ]; then
    pass "marker text in a document's body or name starts no line and changes no finding"
else
    fail "markers: $(show)"
fi
# The report's order: findings, then counts, then absent and skipped lines.
order=$(awk '{ k = ($1 == "count") ? 2 : ($1 == "absent" || $1 == "skipped") ? 3 : 1; printf "%s", k }' "$OUT")
case "$order" in
    ""|*21*|*31*|*32*) fail "order: [$order]" ;;
    *) pass "findings come first, then counts, then absent and skipped lines" ;;
esac
# Every document was written under a generated name, mode 0600, in a mktemp
# directory that is gone now.
names_ok=1
while IFS= read -r line; do
    name=${line#*name=}; name=${name%% mode=*}
    mode=${line##*mode=}
    case "$name" in BRIEF-[0-9]*.md|DESIGN-[0-9]*.md) ;; *) names_ok=0 ;; esac
    [ "$mode" = "-rw-------" ] || names_ok=0
done < "$STUB_LOG"
dirs=$(sed -n 's/^dir=\([^ ]*\) .*/\1/p' "$STUB_LOG" | sort -u)
case "$dirs" in "$TMPDIR"/doc-corpus-check.*/docs) ;; *) names_ok=0 ;; esac
[ -d "$dirs" ] && names_ok=0
[ -z "$(ls "$TMPDIR")" ] || names_ok=0
[ "$names_ok" -eq 1 ] && [ -s "$STUB_LOG" ] \
    && pass "documents are written under generated names, mode 0600, in a scratch directory removed at exit" \
    || fail "scratch: $(cat "$STUB_LOG") tmp=[$(ls "$TMPDIR")]"
[ ! -s "$WORKDIR/koto.log" ] && pass "nothing is recorded in telemetry (no koto call)" || fail "koto called: $(cat "$WORKDIR/koto.log")"

# An uncommitted edit or file isn't read.
cp "$OUT" "$WORKDIR/committed.out"
echo "<!-- break FC23 -->" >> "$REPO/docs/briefs/BRIEF-start.md"
doc docs/briefs/BRIEF-untracked.md schema FC23
run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
[ "$RC" -eq 0 ] && cmp -s "$OUT" "$WORKDIR/committed.out" \
    && pass "an uncommitted file or edit isn't read" || fail "uncommitted: $(show)"
git -C "$REPO" checkout -q -- docs/briefs/BRIEF-start.md
rm -f "$REPO/docs/briefs/BRIEF-untracked.md"

# A clean document prints nothing.
run --since 2026-03-15 --until 2026-03-16 --commit "$HEAD_SHA"
[ "$RC" -eq 0 ] && ! grep -q 'BRIEF-clean' "$OUT" && pass "a clean document prints nothing" || fail "clean: $(show)"
run --since 2026-03-16 --until 2026-03-17 --commit "$HEAD_SHA"
[ "$RC" -eq 0 ] && [ ! -s "$OUT" ] && pass "a window with no documents prints nothing, exit 0" || fail "empty window: $(show)"

# --- refusals ------------------------------------------------------------------------

# no_report <label>: exit 2 and nothing on stdout.
no_report() {
    if [ "$RC" -eq 2 ] && [ ! -s "$OUT" ]; then pass "$1"; else fail "$1: $(show)"; fi
}
STUB_CANARY=old run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
no_report "a validator without the new codes: exit 2, no findings or counts"
grep -q 'no FC23 finding for the canary' "$ERR" || fail "old validator reason: $(show)"

git -C "$REPO" checkout -q -b side
doc docs/briefs/BRIEF-side.md schema FC23
commit_on 2026-03-15 "docs: off the default branch"
SIDE_SHA=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q main
run --since 2026-03-10 --until 2026-03-20 --commit "$SIDE_SHA"
no_report "a commit not an ancestor of origin/main is refused with no finding lines"
grep -q 'not an ancestor of origin/main' "$ERR" || fail "ancestor reason: $(show)"

usage_case() { # <label> <args...>
    local label=$1
    shift
    run "$@"
    if [ "$RC" -ne 0 ] && [ ! -s "$OUT" ] && grep -q '^Usage: doc-corpus-check.sh' "$ERR" && [ ! -s "$STUB_LOG" ]; then
        pass "usage: $label"
    else
        fail "usage: $label: $(show)"
    fi
}
usage_case "no arguments"
usage_case "a missing --commit" --since 2026-03-10 --until 2026-03-20
usage_case "an argument given twice" --since 2026-03-10 --since 2026-03-11 --until 2026-03-20 --commit "$HEAD_SHA"
usage_case "an unknown option" --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA" --repo x
usage_case "a date that isn't YYYY-MM-DD" --since 2026-3-10 --until 2026-03-20 --commit "$HEAD_SHA"
usage_case "a month 13" --since 2026-13-01 --until 2026-03-20 --commit "$HEAD_SHA"
usage_case "--until not after --since" --since 2026-03-20 --until 2026-03-20 --commit "$HEAD_SHA"
usage_case "a commit that isn't hex" --since 2026-03-10 --until 2026-03-20 --commit 'HEAD;x'
usage_case "a commit option value" --since 2026-03-10 --until 2026-03-20 --commit --all
run --since 2026-03-10 --until 2026-03-20 --commit 0000000000000000000000000000000000000000
no_report "a commit the repository doesn't have is refused"

DOC_CORPUS_TIMEOUT=0 run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
no_report "a DOC_CORPUS_TIMEOUT outside 1 to 9999 is refused"

# The validator inside the repository is refused.
mkdir -p "$REPO/bin"
cp "$WORKDIR/stub-bin/shirabe" "$REPO/bin/shirabe"
: > "$STUB_LOG"
(cd "$REPO" && PATH="$REPO/bin:$ORIG_PATH" "$CHECK" --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA") > "$OUT" 2> "$ERR"
RC=$?
no_report "a validator whose real path lies inside the repository is refused"
grep -q 'inside the repository' "$ERR" || fail "in-repo reason: $(show)"
rm -rf "$REPO/bin"

# <owner/repo> comes from the remote; no usable remote is an error.
for url in git@github.com:acme/gadgets.git ssh://git@github.com/acme/gadgets https://github.com/acme/gadgets/; do
    git -C "$REPO" remote set-url origin "$url"
    run --since 2026-03-13 --until 2026-03-14 --commit "$HEAD_SHA"
    if [ "$RC" -eq 0 ] && [ "$(cat "$OUT")" = "absent acme/gadgets docs/briefs/BRIEF-gone.md" ]; then
        pass "owner/repo from origin's URL ($url)"
    else
        fail "slug $url: $(show)"
    fi
done
for url in /srv/git/widgets.git https://github.com/acme https://github.com/acme/../widgets.git; do
    git -C "$REPO" remote set-url origin "$url"
    run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
    no_report "an origin URL with no owner/repo is an error ($url)"
done
git -C "$REPO" remote remove origin
run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
no_report "no origin remote is an error"

# A shallow clone is refused: its oldest commit shows every file as added.
git clone -q --depth 1 "file://$WORKDIR/fx-1-corpus" "$WORKDIR/shallow" 2>/dev/null
REPO="$WORKDIR/shallow"
run --since 2026-03-10 --until 2026-03-20 --commit "$HEAD_SHA"
no_report "a shallow clone is refused"
grep -q 'shallow clone' "$ERR" || fail "shallow reason: $(show)"

# No origin/HEAD: the default branch is unknown.
new_repo nohead
doc docs/briefs/BRIEF-x.md schema FC23
commit_on 2026-03-10 "docs: a brief"
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
run --since 2026-03-10 --until 2026-03-11 --commit "$(git -C "$REPO" rev-parse HEAD)"
no_report "a missing origin/HEAD is refused"
grep -q "default branch is unknown" "$ERR" || fail "origin/HEAD reason: $(show)"

# A merge on the default branch is read through its first parent, at the
# merge's date; a document moved out of the folders is listed absent.
new_repo merges
doc docs/briefs/BRIEF-m1.md schema FC23
commit_on 2026-03-10 "docs: a brief"
git -C "$REPO" checkout -q -b feature HEAD~1
doc docs/designs/DESIGN-feat.md schema FC24
commit_on 2026-03-05 "docs: a design on a branch"
git -C "$REPO" checkout -q main
GIT_AUTHOR_DATE=2026-03-12T12:00:00Z GIT_COMMITTER_DATE=2026-03-12T12:00:00Z \
    git -C "$REPO" merge -q --no-ff -m "merge the design" feature
doc docs/briefs/BRIEF-out.md schema FC23
commit_on 2026-03-13 "docs: a brief"
mkdir -p "$REPO/docs/archive"
git -C "$REPO" mv docs/briefs/BRIEF-out.md docs/archive/BRIEF-out.md
commit_on 2026-03-14 "docs: archive it"
publish
run --since 2026-03-10 --until 2026-03-20 --commit "$(git -C "$REPO" rev-parse HEAD)"
want="brief/summary-length warn $S docs/briefs/BRIEF-m1.md:5
design/frontmatter-order warn $S docs/designs/DESIGN-feat.md:5
count brief/summary-length 1
count design/frontmatter-order 1
absent $S docs/briefs/BRIEF-out.md"
[ "$RC" -eq 0 ] && [ "$(cat "$OUT")" = "$want" ] \
    && pass "a merge's documents count at the merge's date; one moved out of the folders is listed absent" \
    || fail "merges: $(show)"
run --since 2026-03-01 --until 2026-03-10 --commit "$(git -C "$REPO" rev-parse HEAD)"
[ "$RC" -eq 0 ] && [ ! -s "$OUT" ] \
    && pass "a branch commit's own date outside the merge's day doesn't count" || fail "merge date: $(show)"

# --- time bound and interrupt ----------------------------------------------------------

new_repo slow
doc docs/briefs/BRIEF-slow.md schema FC23
commit_on 2026-03-10 "docs: a brief"
publish
SLOW_SHA=$(git -C "$REPO" rev-parse HEAD)
start=$SECONDS
STUB_SLEEP=30 DOC_CORPUS_TIMEOUT=1 run --since 2026-03-10 --until 2026-03-11 --commit "$SLOW_SHA"
took=$((SECONDS - start))
if [ "$RC" -eq 2 ] && [ ! -s "$OUT" ] && grep -q 'did not finish within 1 seconds' "$ERR" && [ "$took" -lt 15 ]; then
    pass "a validator run past its time bound is stopped: exit 2, no report (${took}s)"
else
    fail "time bound: took ${took}s $(show)"
fi
[ -z "$(ls "$TMPDIR")" ] && pass "the scratch directory is removed after a timeout" || fail "timeout scratch: $(ls "$TMPDIR")"

export STUB_PID="$WORKDIR/stub.pid"
rm -f "$STUB_PID"
: > "$STUB_LOG"
set -m
(cd "$REPO" && STUB_SLEEP=30 exec "$CHECK" --since 2026-03-10 --until 2026-03-11 --commit "$SLOW_SHA") > "$OUT" 2> "$ERR" &
pid=$!
set +m
n=0
while [ ! -s "$STUB_PID" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -INT "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
RC=$?
stub=$(cat "$STUB_PID" 2>/dev/null)
sleep 0.5
if [ -n "$stub" ] && ! kill -0 "$stub" 2>/dev/null && [ -z "$(ls "$TMPDIR")" ] && [ ! -s "$OUT" ] && [ "$RC" -ne 0 ]; then
    pass "an interrupt stops the validator and removes the scratch directory"
else
    fail "interrupt: stub=[$stub] alive=$(kill -0 "$stub" 2>/dev/null && echo yes) tmp=[$(ls "$TMPDIR")] $(show)"
    [ -n "$stub" ] && kill -KILL "$stub" 2>/dev/null
fi
unset STUB_PID

# --- the script's shape ------------------------------------------------------------------

code=$(grep -v '^[[:space:]]*#' "$CHECK")
if grep -q '^\. "\$PLUGIN_ROOT/scripts/lib/doc-validate.sh"' <<< "$code" \
    && ! grep -q 'shirabe validate' <<< "$code"; then
    pass "it sources scripts/lib/doc-validate.sh and runs no validator of its own"
else
    fail "doc-validate.sh: the script runs the validator outside the library"
fi
! grep -q -e 'set -e' -e 'declare -A' -e 'koto' <<< "$code" \
    && pass "no set -e, no declare -A, no koto call" || fail "shape: set -e, declare -A or koto in the script"

echo
echo "doc-corpus-check_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

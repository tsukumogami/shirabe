#!/usr/bin/env bash
#
# check-koto-release.sh - compile shirabe's decider declarations with the koto
# minimum and check that its decider floor rule bites
#
# koto reads the `decider` blocks shirabe's templates declare. A template that
# compiles says the blocks are well-formed; this check asks the koto minimum
# two sharper things:
#
#   1. Every template under skills/*/koto-templates/ that declares a decider
#      compiles, with no E-DECIDER-* error. The declarations are valid where
#      they are read.
#
#   2. The floor bites. In a temp copy of skills/, plan_validation.verdict's
#      `exit` is set to `mode: auto`. `exit` routes to the validation_exit
#      terminal, which no auto answer may take, so that copy must fail to
#      compile with E-DECIDER-FLOOR, while the unmodified copy compiles. A
#      koto that let the mutation through would be a koto whose floor this
#      repository could not rely on.
#
# The koto it runs is the koto minimum, read from scripts/assert-koto-floor.sh,
# the one place that value is defined, and its version is asserted to be
# exactly that release. It does not install koto: check-koto-entry-floor.yml
# installs the minimum through tsuku and runs this after it. The checkout is
# never modified: both compiles run on copies, in an isolated HOME.
#
# Usage:
#   scripts/check-koto-release.sh [--keep]
#
# Options:
#   --keep       leave the work directory in place and print its path
#   -h, --help   this message
#
# Environment:
#   KOTO_RELEASE_BIN   an absolute path to the koto binary to use (default:
#                      `koto` from PATH). Its version must be the minimum.
#
# Requires: bash, koto at the minimum, mikefarah yq v4.
#
# Exit codes:
#   0 - every declared template compiles and the floor mutation is refused
#   1 - a step failed, or a required tool is missing
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# The declaration the floor proof mutates, and the terminal its route reaches.
PROOF_TEMPLATE="skills/work-on/koto-templates/work-on.md"
PROOF_STATE="plan_validation"
PROOF_FIELD="verdict"
PROOF_VALUE="exit"
PROOF_TARGET="validation_exit"

KEEP=0

usage() {
    sed -e '1d' -e '/^[^#]/,$d' "$0" | sed 's/^#\{1,\} \{0,1\}//'
}

err() {
    echo "check-koto-release: $*" >&2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) err "unknown argument: $1 (try --help)"; exit 1 ;;
    esac
done

WORK=""
cleanup() {
    if [ -n "$WORK" ]; then
        if [ "$KEEP" -eq 1 ]; then
            echo "check-koto-release: work directory kept at $WORK"
        else
            rm -rf "$WORK"
        fi
    fi
    return 0
}
trap cleanup EXIT

FAILURES=0
failed() {
    err "FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

# check_yq: mikefarah yq, major version 4. The python yq wrapper and yq v3
# take different syntax, and both would misread the expressions below.
check_yq() {
    local out
    command -v yq >/dev/null 2>&1 || { err "yq is required (mikefarah yq v4) and is not on PATH"; return 1; }
    out=$(yq --version 2>&1) || { err "yq --version failed: $out"; return 1; }
    case "$out" in
        *mikefarah/yq*' version v4.'* | *mikefarah/yq*' version 4.'*) return 0 ;;
    esac
    err "yq must be mikefarah yq v4; yq --version says [$out]"
    return 1
}

# decider_count <file>: how many maps in the front matter carry a decider key,
# wherever they sit, so a decider in the wrong place is counted too.
decider_count() {
    yq --front-matter=extract '[.. | select(tag == "!!map" and has("decider"))] | length' "$1"
}

# copy_tree <dest>: copies skills/ with relative paths preserved, so
# execute.md's `default_template: ../../work-on/koto-templates/work-on.md`
# resolves in the copy exactly as it does in the checkout.
copy_tree() {
    mkdir -p "$1" || return 1
    cp -R "$REPO_ROOT/skills" "$1/skills"
}

check_yq || exit 1

# The same read check-koto-entry-floor.yml makes, so the two agree on the value.
MINIMUM=$(sed -n 's/^FLOOR="\${KOTO_FLOOR:-\([0-9.]*\)}"$/\1/p' "$REPO_ROOT/scripts/assert-koto-floor.sh" | head -1)
if [ -z "$MINIMUM" ]; then
    err "cannot read the koto minimum from scripts/assert-koto-floor.sh"
    exit 1
fi

KOTO_BIN="${KOTO_RELEASE_BIN:-$(command -v koto 2>/dev/null)}"
case "$KOTO_BIN" in
    /*) ;;
    "") err "koto is not on PATH; this check needs koto $MINIMUM"; exit 1 ;;
    *) err "KOTO_RELEASE_BIN must be an absolute path, got [$KOTO_BIN]"; exit 1 ;;
esac
[ -x "$KOTO_BIN" ] || { err "not executable: $KOTO_BIN"; exit 1; }
GOT=$("$KOTO_BIN" version 2>/dev/null | head -1 | sed -n 's/^koto v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*$/\1/p')
if [ "$GOT" != "$MINIMUM" ]; then
    err "$KOTO_BIN reports version [${GOT:-unreadable}], want exactly the koto minimum $MINIMUM"
    exit 1
fi
echo "check-koto-release: $("$KOTO_BIN" version)"

WORK=$(mktemp -d) || { err "could not create a work directory"; exit 1; }
WORK=$(cd "$WORK" && pwd -P)

COMPILE_HOME="$WORK/home"
mkdir -p "$COMPILE_HOME"

# compile <file> <output-file>: koto template compile in an isolated HOME, so
# nothing reaches the caller's cache. Returns koto's exit status.
compile() {
    HOME="$COMPILE_HOME" XDG_CACHE_HOME="$COMPILE_HOME/.cache" \
        "$KOTO_BIN" template compile "$1" > "$2" 2>&1
}

TREE="$WORK/tree"
copy_tree "$TREE" || { err "could not copy the tree into $TREE"; exit 1; }

# -- declared templates compile -------------------------------------------------

echo ""
echo "=== declared templates on koto $MINIMUM ==="

DECLARED=0
for f in "$TREE"/skills/*/koto-templates/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *.mermaid.md) continue ;; esac
    rel=${f#"$TREE"/}
    n=$(decider_count "$f") || { failed "$rel: yq could not read the front matter"; continue; }
    [ "$n" -gt 0 ] || continue
    DECLARED=$((DECLARED + 1))
    log="$WORK/compile.$DECLARED.log"
    if ! compile "$f" "$log"; then
        failed "$rel: koto $MINIMUM does not compile it:"
        sed 's/^/    /' "$log" >&2
    elif grep -q 'E-DECIDER' "$log"; then
        failed "$rel: compiled, but koto reported a decider error:"
        grep 'E-DECIDER' "$log" | sed 's/^/    /' >&2
    else
        echo "  $rel: $n declaration(s), compiles"
    fi
done
[ "$DECLARED" -gt 0 ] || failed "no template under skills/*/koto-templates/ declares a decider, so there is nothing for this check to validate"

# -- the floor bites -------------------------------------------------------------

echo ""
echo "=== $PROOF_STATE.$PROOF_FIELD $PROOF_VALUE in auto is refused ==="

PROOF_PATH=".states.$PROOF_STATE.accepts.$PROOF_FIELD.decider.answers.$PROOF_VALUE"
MUTANT_TREE="$WORK/mutant"
copy_tree "$MUTANT_TREE" || { err "could not copy the tree into $MUTANT_TREE"; exit 1; }
mutant="$MUTANT_TREE/$PROOF_TEMPLATE"

before=$(yq --front-matter=extract "$PROOF_PATH | tag" "$mutant" 2>/dev/null)
if [ "$before" != "!!map" ]; then
    failed "$PROOF_TEMPLATE declares no $PROOF_VALUE answer on $PROOF_STATE.$PROOF_FIELD; the floor proof has nothing to mutate"
else
    unmodified_log="$WORK/unmodified.log"
    if compile "$TREE/$PROOF_TEMPLATE" "$unmodified_log"; then
        echo "  unmodified copy: compiles"
    else
        failed "the unmodified copy of $PROOF_TEMPLATE does not compile:"
        sed 's/^/    /' "$unmodified_log" >&2
    fi

    yq --front-matter=process -i "$PROOF_PATH.mode = \"auto\"" "$mutant"
    after=$(yq --front-matter=extract "$PROOF_PATH.mode" "$mutant" 2>/dev/null)
    mutant_log="$WORK/mutant.log"
    if [ "$after" != "auto" ]; then
        failed "could not set $PROOF_VALUE to mode auto in the copy (reads [$after])"
    elif compile "$mutant" "$mutant_log"; then
        failed "with $PROOF_VALUE in auto, koto $MINIMUM still compiles $PROOF_TEMPLATE; the floor did not refuse the route to $PROOF_TARGET"
    elif ! grep -q 'E-DECIDER-FLOOR' "$mutant_log"; then
        failed "with $PROOF_VALUE in auto, compilation failed, but not with E-DECIDER-FLOOR:"
        sed 's/^/    /' "$mutant_log" >&2
    elif ! grep -q "$PROOF_TARGET" "$mutant_log"; then
        failed "E-DECIDER-FLOOR was reported, but not for the route to $PROOF_TARGET:"
        sed 's/^/    /' "$mutant_log" >&2
    else
        echo "  $PROOF_VALUE in auto: refused with E-DECIDER-FLOOR on the route to $PROOF_TARGET"
    fi
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "check-koto-release: PASS - $DECLARED declared template(s) compile on koto $MINIMUM, and its floor refuses an auto $PROOF_VALUE"
    exit 0
fi
echo "check-koto-release: FAIL - $FAILURES failure(s)"
exit 1

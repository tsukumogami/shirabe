#!/usr/bin/env bash
#
# check-koto-release.sh - compile shirabe's decider declarations with the koto
# release that reads them
#
# scripts/check-koto-floor.sh proves koto v0.12.2 ignores shirabe's `decider`
# blocks. That says nothing about whether the blocks are right: an old koto
# drops them unread. This check installs the first koto release that reads
# them, v0.13.0, and asks it two things:
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
# koto is installed through the same pinned install.sh and per-platform binary
# SHA-256 as the floor (scripts/koto-floor/lib.sh), into a directory of its own,
# and every call goes through $KOTO_BIN by absolute path. The checkout is never
# modified: both compiles run on copies.
#
# Usage:
#   scripts/check-koto-release.sh [--keep]
#
# Options:
#   --keep       leave the work directory in place and print its path
#   -h, --help   this message
#
# Environment:
#   KOTO_RELEASE_BIN   an absolute path to a koto binary to use instead of
#                      installing one. Its version is still asserted to be
#                      the release this check is about.
#   RUNNER_TEMP        when set (GitHub Actions), koto is installed under it
#   KOTO_ALLOW_UNPINNED_BINARY
#                      set to 1 to install on a platform with no recorded
#                      binary SHA-256
#
# Requires: bash, mikefarah yq v4, and -- unless KOTO_RELEASE_BIN is set --
# curl and sha256sum or shasum.
#
# Exit codes:
#   0 - every declared template compiles and the floor mutation is refused
#   1 - a step failed, or a required tool is missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=koto-floor/lib.sh
. "$SCRIPT_DIR/koto-floor/lib.sh"

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

check_yq || exit 1

WORK=$(mktemp -d) || { err "could not create a work directory"; exit 1; }
WORK=$(cd "$WORK" && pwd -P)

# -- koto ---------------------------------------------------------------------

if [ -n "${KOTO_RELEASE_BIN:-}" ]; then
    case "$KOTO_RELEASE_BIN" in
        /*) ;;
        *) err "KOTO_RELEASE_BIN must be an absolute path, got [$KOTO_RELEASE_BIN]"; exit 1 ;;
    esac
    [ -x "$KOTO_RELEASE_BIN" ] || { err "KOTO_RELEASE_BIN is not executable: $KOTO_RELEASE_BIN"; exit 1; }
    KOTO_BIN="$KOTO_RELEASE_BIN"
    echo "check-koto-release: using KOTO_RELEASE_BIN=$KOTO_BIN"
else
    if [ -n "${RUNNER_TEMP:-}" ]; then
        install_dir=$(mktemp -d "$RUNNER_TEMP/koto-release.XXXXXX") || { err "could not create a directory under RUNNER_TEMP"; exit 1; }
    else
        install_dir="$WORK/koto-install"
    fi
    echo "check-koto-release: installing koto $KOTO_DECIDER_RELEASE_VERSION from install.sh at koto@$KOTO_INSTALLER_COMMIT"
    install_koto "$KOTO_DECIDER_RELEASE_VERSION" "$install_dir" || exit 1
    KOTO_BIN="$INSTALLED_KOTO_BIN"
fi
assert_koto_version "$KOTO_BIN" "$KOTO_DECIDER_RELEASE_VERSION" || exit 1
echo "check-koto-release: $("$KOTO_BIN" version)"

COMPILE_HOME="$WORK/home"
mkdir -p "$COMPILE_HOME"

# compile <file> <output-file>: koto template compile in an isolated HOME, so
# nothing reaches the caller's cache. Returns koto's exit status.
compile() {
    HOME="$COMPILE_HOME" XDG_CACHE_HOME="$COMPILE_HOME/.cache" \
        "$KOTO_BIN" template compile "$1" > "$2" 2>&1
}

TREE="$WORK/tree"
copy_tree "$REPO_ROOT" "$TREE" || { err "could not copy the tree into $TREE"; exit 1; }

# -- declared templates compile -------------------------------------------------

echo ""
echo "=== declared templates on koto ${KOTO_DECIDER_RELEASE_VERSION#v} ==="

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
        failed "$rel: koto ${KOTO_DECIDER_RELEASE_VERSION#v} does not compile it:"
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
copy_tree "$REPO_ROOT" "$MUTANT_TREE" || { err "could not copy the tree into $MUTANT_TREE"; exit 1; }
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
        failed "with $PROOF_VALUE in auto, koto ${KOTO_DECIDER_RELEASE_VERSION#v} still compiles $PROOF_TEMPLATE; the floor did not refuse the route to $PROOF_TARGET"
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
    echo "check-koto-release: PASS - $DECLARED declared template(s) compile on koto ${KOTO_DECIDER_RELEASE_VERSION#v}, and its floor refuses an auto $PROOF_VALUE"
    exit 0
fi
echo "check-koto-release: FAIL - $FAILURES failure(s)"
exit 1

#!/usr/bin/env bash
#
# check-koto-floor.sh - check shirabe's templates against the koto v0.12.2 floor
#
# shirabe's README says /work-on needs koto v0.12.2 or later. (/execute's and
# /scope's templates need koto 0.13.0 or later; each carries a
# `# koto-floor: pinned` line and is left out, see list_templates in
# scripts/koto-floor/lib.sh.) A template can carry `decider` blocks that only a
# newer koto understands; koto
# v0.12.2 drops them as unknown keys. This check is what makes "drops them"
# a tested claim rather than an assumption, in three steps:
#
#   1. Strip. Every template (skills/*/koto-templates/*.md, and this check's own
#      fixtures) is copied into a temp tree with relative paths preserved, and
#      every accepts field's `decider` block is deleted from the copy with yq.
#
#   2. Compiled identity. koto v0.12.2 compiles each original and its stripped
#      copy, and both must print the same compiled cache path -- the same
#      compiled form and template_hash.
#
#   3. Scripted runs. Each scenario under scripts/koto-floor/scenarios/ drives
#      real koto sessions, once against the checkout and once against the
#      stripped copy, each in its own HOME and its own git fixture. Each run
#      writes one `state<TAB>action<TAB>advanced` line per `koto next`, then the
#      final `koto status` state, and the two transcripts must be identical.
#      Every scenario also asserts where it ends, so two runs that stop early
#      at the same place still fail. Finally, no escape value a template
#      declares may appear among the values any recorded response offered.
#
# koto is installed with koto's own install.sh, fetched from a pinned koto
# commit and checked against a recorded SHA-256 before it runs, and the binary
# it installs is checked against a SHA-256 recorded for the platform (see
# scripts/koto-floor/lib.sh). It installs into a directory of its own, never
# ~/.koto, and every call here goes through $KOTO_BIN by absolute path, so a
# newer koto on PATH cannot stand in for the floor.
#
# Usage:
#   scripts/check-koto-floor.sh [--keep]
#
# Options:
#   --keep       leave the work directory in place and print its path
#   -h, --help   this message
#
# Environment:
#   KOTO_BIN     an absolute path to a koto binary to use instead of
#                installing one. Its version is still asserted to be the
#                floor, so this is for a developer who already has v0.12.2,
#                not a way to test another version.
#   RUNNER_TEMP  when set (GitHub Actions), koto is installed under it
#   KOTO_ALLOW_UNPINNED_BINARY
#                set to 1 to install on a platform with no recorded binary
#                SHA-256 (linux-amd64 and darwin-arm64 have one). Without it
#                the install is refused on any other platform.
#
# Requires: bash, git, jq, mikefarah yq v4, and -- unless KOTO_BIN is set --
# curl and sha256sum or shasum.
#
# Exit codes:
#   0 - every step passed
#   1 - a step failed, or a required tool is missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLOOR_DIR="$SCRIPT_DIR/koto-floor"

# shellcheck source=koto-floor/lib.sh
. "$FLOOR_DIR/lib.sh"

KEEP=0

usage() {
    sed -e '1d' -e '/^[^#]/,$d' "$0" | sed 's/^#\{1,\} \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) kf_err "unknown argument: $1 (try --help)"; exit 1 ;;
    esac
done

WORK=""
cleanup() {
    if [ -n "$WORK" ]; then
        if [ "$KEEP" -eq 1 ]; then
            echo "check-koto-floor: work directory kept at $WORK"
        else
            rm -rf "$WORK"
        fi
    fi
    return 0
}
trap cleanup EXIT

FAILURES=0
failed() {
    kf_err "FAIL: $*"
    FAILURES=$((FAILURES + 1))
}

# -- tools --------------------------------------------------------------------

check_yq || exit 1
check_jq || exit 1
command -v git >/dev/null 2>&1 || { kf_err "git is required and is not on PATH"; exit 1; }

WORK=$(mktemp -d) || { kf_err "could not create a work directory"; exit 1; }
WORK=$(cd "$WORK" && pwd -P)

# -- koto ---------------------------------------------------------------------

if [ -n "${KOTO_BIN:-}" ]; then
    case "$KOTO_BIN" in
        /*) ;;
        *) kf_err "KOTO_BIN must be an absolute path, got [$KOTO_BIN]"; exit 1 ;;
    esac
    [ -x "$KOTO_BIN" ] || { kf_err "KOTO_BIN is not executable: $KOTO_BIN"; exit 1; }
    echo "check-koto-floor: using KOTO_BIN=$KOTO_BIN"
else
    if [ -n "${RUNNER_TEMP:-}" ]; then
        install_dir=$(mktemp -d "$RUNNER_TEMP/koto-floor.XXXXXX") || { kf_err "could not create a directory under RUNNER_TEMP"; exit 1; }
    else
        install_dir="$WORK/koto-install"
    fi
    echo "check-koto-floor: installing koto $KOTO_FLOOR_VERSION from install.sh at koto@$KOTO_INSTALLER_COMMIT"
    install_koto "$KOTO_FLOOR_VERSION" "$install_dir" || exit 1
    KOTO_BIN="$INSTALLED_KOTO_BIN"
fi
assert_koto_version "$KOTO_BIN" "$KOTO_FLOOR_VERSION" || exit 1
echo "check-koto-floor: $("$KOTO_BIN" version)"

# -- trees --------------------------------------------------------------------

# koto validates --var values against ^[a-zA-Z0-9._/:@ \-]*$, and PLUGIN_ROOT
# is passed that way. A checkout path outside that set is reached through a
# symlink with a clean name; it is still the checkout.
ORIG_TREE="$REPO_ROOT"
case "$ORIG_TREE" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$REPO_ROOT" "$WORK/original"
        ORIG_TREE="$WORK/original"
        ;;
esac
STRIP_TREE="$WORK/stripped"
copy_tree "$REPO_ROOT" "$STRIP_TREE" || { kf_err "could not copy the tree into $STRIP_TREE"; exit 1; }

TEMPLATES=$(list_templates "$REPO_ROOT")
[ -n "$TEMPLATES" ] || { kf_err "no templates found under $REPO_ROOT"; exit 1; }

# -- strip and compiled identity ----------------------------------------------

echo ""
echo "=== strip and compiled identity ==="

COMPILE_HOME="$WORK/compile-home"
mkdir -p "$COMPILE_HOME"
ESCAPES="$WORK/escapes.txt"
: > "$ESCAPES"

while read -r rel; do
    [ -n "$rel" ] || continue
    orig="$REPO_ROOT/$rel"
    stripped="$STRIP_TREE/$rel"

    if ! strip_decider "$stripped"; then
        failed "$rel: yq could not strip the copy"
        continue
    fi

    n_orig=$(decider_count "$orig") || { failed "$rel: yq could not read the front matter"; continue; }
    n_strip=$(decider_count "$stripped") || { failed "$rel: yq could not read the stripped front matter"; continue; }
    if [ "$n_orig" -gt 0 ]; then
        if cmp -s "$orig" "$stripped"; then
            failed "$rel: declares $n_orig decider block(s) but the stripped copy is unchanged"
        elif [ "$n_strip" -ne 0 ]; then
            failed "$rel: $n_strip decider key(s) survive the strip -- a decider outside states.*.accepts.*"
        else
            echo "  $rel: stripped $n_orig decider block(s)"
        fi
    else
        echo "  $rel: no decider key, the strip is a no-op"
    fi

    if ! collect_escapes "$orig" >> "$ESCAPES"; then
        failed "$rel: could not collect escape values"
    fi

    a=$(HOME="$COMPILE_HOME" XDG_CACHE_HOME="$COMPILE_HOME/.cache" compiled_path "$KOTO_BIN" "$orig") || a=""
    b=$(HOME="$COMPILE_HOME" XDG_CACHE_HOME="$COMPILE_HOME/.cache" compiled_path "$KOTO_BIN" "$stripped") || b=""
    if [ -z "$a" ]; then
        failed "$rel: koto $KOTO_FLOOR_VERSION does not compile the original"
    elif [ -z "$b" ]; then
        failed "$rel: koto $KOTO_FLOOR_VERSION does not compile the stripped copy"
    elif [ "$a" != "$b" ]; then
        failed "$rel: the original and the stripped copy compile differently ($(basename "$a") vs $(basename "$b"))"
    else
        echo "  $rel: compiles identically ($(basename "$a" .json))"
    fi
done <<EOF
$TEMPLATES
EOF

sort -u "$ESCAPES" -o "$ESCAPES"
if [ -s "$ESCAPES" ]; then
    echo "  escape values declared: $(tr '\n' ' ' < "$ESCAPES")"
else
    echo "  escape values declared: none"
fi

# -- scenarios ----------------------------------------------------------------

echo ""
echo "=== scripted runs (original vs stripped) ==="

# run_scenario <script> <tree-label> <tree>: one run, in its own HOME and its
# own fixture, with nothing inherited from the caller's environment but PATH.
# The floor's own directory leads PATH, so the shipped scripts a default_action
# runs -- which call `koto context add` by name -- reach the floor too.
run_scenario() {
    local script="$1" label="$2" tree="$3" name dir
    name=$(basename "$script" .sh)
    dir="$WORK/runs/$name/$label"
    mkdir -p "$dir/home" "$dir/tmp"
    : > "$dir/transcript.tsv"
    : > "$dir/responses.jsonl"
    env -i \
        HOME="$dir/home" \
        XDG_CONFIG_HOME="$dir/home/.config" \
        XDG_CACHE_HOME="$dir/home/.cache" \
        XDG_DATA_HOME="$dir/home/.local/share" \
        TMPDIR="$dir/tmp" \
        PATH="$(dirname "$KOTO_BIN"):$PATH" \
        LANG=C LC_ALL=C \
        GIT_CONFIG_NOSYSTEM=1 \
        KOTO_BIN="$KOTO_BIN" \
        TREE="$tree" \
        RUN_DIR="$dir" \
        TRANSCRIPT="$dir/transcript.tsv" \
        RESPONSES="$dir/responses.jsonl" \
        bash "$script" > "$dir/output.log" 2>&1
}

SCENARIO_COUNT=0
for script in "$FLOOR_DIR"/scenarios/*.sh; do
    [ -f "$script" ] || continue
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
    name=$(basename "$script" .sh)
    ok=1
    for label in original stripped; do
        if [ "$label" = original ]; then tree="$ORIG_TREE"; else tree="$STRIP_TREE"; fi
        if ! run_scenario "$script" "$label" "$tree"; then
            ok=0
            failed "$name ($label): the scenario failed:"
            sed 's/^/    /' "$WORK/runs/$name/$label/output.log" >&2
            echo "    transcript:" >&2
            sed 's/^/      /' "$WORK/runs/$name/$label/transcript.tsv" >&2
        fi
    done
    if ! compare_transcripts "$WORK/runs/$name/original/transcript.tsv" "$WORK/runs/$name/stripped/transcript.tsv" "$name"; then
        ok=0
        FAILURES=$((FAILURES + 1))
    fi
    if [ "$ok" -eq 1 ]; then
        echo "  $name: $(wc -l < "$WORK/runs/$name/original/transcript.tsv" | tr -d ' ') transcript lines, identical, ends at $(awk -F '\t' '$1 == "final" {print $2}' "$WORK/runs/$name/original/transcript.tsv")"
    fi
done
[ "$SCENARIO_COUNT" -gt 0 ] || failed "no scenarios found under $FLOOR_DIR/scenarios"

# -- escape leaks -------------------------------------------------------------

echo ""
echo "=== escape values in recorded responses ==="

leaks=$(escape_leaks "$ESCAPES" "$WORK"/runs/*/*/responses.jsonl)
if [ -n "$leaks" ]; then
    failed "koto offered a declared escape value as an answer: $(printf '%s' "$leaks" | tr '\n' ' ')"
else
    echo "  none of $(wc -l < "$ESCAPES" | tr -d ' ') escape value(s) appears in $(cat "$WORK"/runs/*/*/responses.jsonl | wc -l | tr -d ' ') recorded responses"
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "check-koto-floor: PASS - $(printf '%s\n' "$TEMPLATES" | wc -l | tr -d ' ') templates, $SCENARIO_COUNT scenarios on koto ${KOTO_FLOOR_VERSION#v}"
    exit 0
fi
echo "check-koto-floor: FAIL - $FAILURES failure(s)"
exit 1

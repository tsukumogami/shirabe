#!/usr/bin/env bash
#
# resolve-split-mode_test.sh - Tests for resolve-split-mode.sh
#
# Covers the mode precedence as a table (no-split outcomes, explicit flag over
# intent and header, intent over header, header alone, the default), the
# header matching rules, every rejection case, and the sync between the
# script's header-value constants and the table in
# references/coordination-strategy.md.
#
# Usage:
#   bash resolve-split-mode_test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-split-mode.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
STRATEGY_DOC="$REPO_ROOT/references/coordination-strategy.md"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
PASS_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $1" >&2
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $1 - $2" >&2
}

# CLAUDE.md fixtures. Each exercises one header matching rule.
COORD_MD="$TEST_DIR/coordinated.md"
printf '# Repo\n\n## Planning Context: Tactical\n\n## PR Grouping Policy: coordinated\n' > "$COORD_MD"
PADDED_MD="$TEST_DIR/padded.md"
printf '## PR Grouping Policy: \t coordinated  \t\r\n' > "$PADDED_MD"
CASE_MD="$TEST_DIR/case.md"
printf '## PR Grouping Policy: Coordinated\n' > "$CASE_MD"
COARSE_MD="$TEST_DIR/coarsest.md"
printf '## PR Grouping Policy: coarsest-legal\n\n## Reviewability Ceiling: default\n' > "$COARSE_MD"
CEILING_MD="$TEST_DIR/ceiling.md"
printf '## Reviewability Ceiling: coordinated\n' > "$CEILING_MD"
FIRST_WINS_MD="$TEST_DIR/first-wins.md"
printf '## PR Grouping Policy: coarsest-legal\n## PR Grouping Policy: coordinated\n' > "$FIRST_WINS_MD"
H3_MD="$TEST_DIR/h3.md"
printf '### PR Grouping Policy: coordinated\n' > "$H3_MD"
NONE_MD="$TEST_DIR/none.md"
printf '# Repo\n\nNo headers here.\n' > "$NONE_MD"
NO_NEWLINE_MD="$TEST_DIR/no-newline.md"
printf '## PR Grouping Policy: coordinated' > "$NO_NEWLINE_MD"

# expect <name> <execution_mode> <split_mode_source> <args...>
expect() {
    local name="$1" mode="$2" source="$3"
    shift 3
    local out rc=0
    out=$("$BASH" "$RESOLVER" "$@" 2>"$TEST_DIR/stderr") || rc=$?
    local want
    want=$(printf 'execution_mode=%s\nsplit_mode_source=%s' "$mode" "$source")
    if [ "$rc" -ne 0 ]; then
        fail "$name" "exit $rc, stderr: $(cat "$TEST_DIR/stderr")"
    elif [ "$out" != "$want" ]; then
        fail "$name" "got '$(echo "$out" | tr '\n' ' ')', want '$(echo "$want" | tr '\n' ' ')'"
    elif [ -s "$TEST_DIR/stderr" ]; then
        fail "$name" "unexpected stderr: $(cat "$TEST_DIR/stderr")"
    else
        pass "$name"
    fi
}

# reject <name> <text stderr must contain> <args...>
reject() {
    local name="$1" needle="$2"
    shift 2
    local out rc=0
    out=$("$BASH" "$RESOLVER" "$@" 2>"$TEST_DIR/stderr") || rc=$?
    if [ "$rc" -eq 0 ]; then
        fail "$name" "expected non-zero exit, got 0 with '$out'"
    elif [ -n "$out" ]; then
        fail "$name" "expected empty stdout, got '$out'"
    elif ! grep -qF -- "$needle" "$TEST_DIR/stderr"; then
        fail "$name" "stderr does not name '$needle': $(cat "$TEST_DIR/stderr")"
    elif [ "$(wc -l < "$TEST_DIR/stderr" | tr -d ' ')" -ne 1 ]; then
        fail "$name" "expected one stderr line, got: $(cat "$TEST_DIR/stderr")"
    else
        pass "$name"
    fi
}

# --- --split no: single-pr / none whatever else is passed -------------------
expect "no-split bare"                     single-pr none --split no
expect "no-split intent continue"          single-pr none --split no --intent continue
expect "no-split intent stop"              single-pr none --split no --intent stop
expect "no-split intent none"              single-pr none --split no --intent none
expect "no-split coordinated"              single-pr none --split no --coordinated
expect "no-split no-coordinated"           single-pr none --split no --no-coordinated
expect "no-split continue+coordinated"     single-pr none --split no --intent continue --coordinated
expect "no-split stop+no-coordinated"      single-pr none --split no --intent stop --no-coordinated
expect "no-split coordinated header"       single-pr none --split no --claude-md "$COORD_MD"
expect "no-split everything"               single-pr none --split no --intent continue --coordinated --claude-md "$COORD_MD"

# --- level 1: an explicit flag beats intent and header ----------------------
expect "flag coordinated alone"            coordinated flag --split yes --coordinated
expect "flag no-coordinated alone"         multi-pr flag    --split yes --no-coordinated
expect "flag no-coordinated beats continue" multi-pr flag   --split yes --no-coordinated --intent continue
expect "flag no-coordinated beats header"  multi-pr flag    --split yes --no-coordinated --claude-md "$COORD_MD"
expect "flag no-coordinated beats continue+header" multi-pr flag --split yes --no-coordinated --intent continue --claude-md "$COORD_MD"
expect "flag coordinated beats stop"       coordinated flag --split yes --coordinated --intent stop
expect "flag coordinated beats stop, non-coordinated header" coordinated flag --split yes --coordinated --intent stop --claude-md "$COARSE_MD"

# --- level 2: intent beats the header ---------------------------------------
expect "intent continue"                   coordinated intent --split yes --intent continue
expect "intent stop"                       multi-pr intent    --split yes --intent stop
expect "intent stop beats coordinated header" multi-pr intent --split yes --intent stop --claude-md "$COORD_MD"
expect "intent continue, non-coordinated header" coordinated intent --split yes --intent continue --claude-md "$COARSE_MD"
expect "intent none falls through to header" coordinated header --split yes --intent none --claude-md "$COORD_MD"

# --- level 3: the header alone ----------------------------------------------
expect "header coordinated"                coordinated header --split yes --claude-md "$COORD_MD"
expect "header value trimmed"              coordinated header --split yes --claude-md "$PADDED_MD"
expect "header last line without newline"  coordinated header --split yes --claude-md "$NO_NEWLINE_MD"
expect "header case-sensitive"             multi-pr default   --split yes --claude-md "$CASE_MD"
expect "header coarsest-legal not a signal" multi-pr default  --split yes --claude-md "$COARSE_MD"
expect "reviewability ceiling never a signal" multi-pr default --split yes --claude-md "$CEILING_MD"
expect "header first match wins"           multi-pr default   --split yes --claude-md "$FIRST_WINS_MD"
expect "header must be level 2"            multi-pr default   --split yes --claude-md "$H3_MD"
expect "header absent"                     multi-pr default   --split yes --claude-md "$NONE_MD"

# --- level 4: nothing at all ------------------------------------------------
expect "default nothing"                   multi-pr default --split yes
expect "default intent none"               multi-pr default --split yes --intent none

# --- argument forms and order -----------------------------------------------
expect "equals form"                       coordinated intent --split=yes --intent=continue
expect "any order"                         multi-pr flag --claude-md "$COORD_MD" --intent continue --no-coordinated --split yes

# --- rejections -------------------------------------------------------------
reject "missing --split"                   "--split"
reject "missing --split with others"       "--split" --intent continue
reject "invalid --split"                   "--split" --split maybe
reject "empty --split"                     "--split" --split=
reject "--split without value"             "--split" --split
reject "repeated --split"                  "--split" --split yes --split no
reject "invalid --intent"                  "--intent" --split yes --intent bogus
reject "empty --intent"                    "--intent" --split yes --intent=
reject "--intent without value"            "--intent" --split yes --intent
reject "repeated --intent"                 "--intent" --split yes --intent stop --intent continue
reject "repeated --intent same value"      "--intent" --split yes --intent stop --intent stop
reject "repeated --intent on no-split"     "--intent" --split no --intent stop --intent continue
reject "both coordination flags"           "--no-coordinated" --split yes --coordinated --no-coordinated
reject "both coordination flags on no-split" "--no-coordinated" --split no --no-coordinated --coordinated
reject "repeated --coordinated"            "--coordinated" --split yes --coordinated --coordinated
reject "repeated --no-coordinated"         "--no-coordinated" --split yes --no-coordinated --no-coordinated
reject "--coordinated with a value"        "--coordinated" --split yes --coordinated=yes
reject "missing --claude-md path"          "--claude-md" --split yes --claude-md "$TEST_DIR/does-not-exist.md"
reject "--claude-md directory"             "--claude-md" --split yes --claude-md "$TEST_DIR"
reject "repeated --claude-md"              "--claude-md" --split yes --claude-md "$COORD_MD" --claude-md "$COORD_MD"
reject "--claude-md without value"         "--claude-md" --split yes --claude-md
reject "unknown argument"                  "--bogus" --split yes --bogus

# --- the constants mirror coordination-strategy.md --------------------------
# Reads the "Coordinated-by-default header values" table and the script's
# COORDINATED_VALUES_* constants, and requires the same headers with the same
# value lists on both sides.
test_header_values_in_sync() {
    local name="header values match references/coordination-strategy.md"
    if [ ! -f "$STRATEGY_DOC" ]; then
        fail "$name" "missing $STRATEGY_DOC"
        return
    fi
    local doc_list script_list
    doc_list=$(awk '
        /^### Coordinated-by-default header values/ { in_section = 1; next }
        in_section && /^#/ { in_section = 0 }
        in_section && /^\| `## / {
            n = split($0, cells, "|")
            header = cells[2]
            sub(/^[ \t]*`## /, "", header)
            sub(/:`[ \t]*$/, "", header)
            gsub(/ /, "_", header)
            header = toupper(header)
            values = ""
            rest = cells[3]
            while (match(rest, /`[^`]+`/)) {
                v = substr(rest, RSTART + 1, RLENGTH - 2)
                values = (values == "" ? v : values " " v)
                rest = substr(rest, RSTART + RLENGTH)
            }
            print header "=" values
        }
    ' "$STRATEGY_DOC" | sort)
    script_list=$(sed -n 's/^COORDINATED_VALUES_\([A-Z_]*\)="\(.*\)"$/\1=\2/p' "$RESOLVER" | sort)
    if [ -z "$doc_list" ]; then
        fail "$name" "no header rows found in the strategy doc's table"
    elif [ -z "$script_list" ]; then
        fail "$name" "no COORDINATED_VALUES_* constants found in the script"
    elif [ "$doc_list" != "$script_list" ]; then
        fail "$name" "doc: [$(echo "$doc_list" | tr '\n' ';')] script: [$(echo "$script_list" | tr '\n' ';')]"
    else
        pass "$name"
    fi
}
test_header_values_in_sync

# --- no network or gh -------------------------------------------------------
test_no_gh_call() {
    local name="makes no gh or network call"
    if grep -nE '(^|[^A-Za-z_-])(gh|curl|wget) ' "$RESOLVER" | grep -v '^[0-9]*:#' >/dev/null; then
        fail "$name" "script invokes gh, curl, or wget"
    else
        pass "$name"
    fi
}
test_no_gh_call

echo "" >&2
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed" >&2
[ "$FAIL_COUNT" -eq 0 ]

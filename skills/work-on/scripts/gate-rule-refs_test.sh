#!/usr/bin/env bash
# gate-rule-refs_test.sh -- does every row of gate-rules.tsv still point at its
# rule's text?
#
# A finding's rule_ref is `<path>#L<start>-L<end>@<commit>`. Line numbers drift
# when the referenced file is edited, so this re-resolves each row at HEAD: the
# row's excerpt must occur inside its line range (the range's lines joined with
# single spaces, so an excerpt may span a line break). It also holds the table
# to its own rules: well-formed rows, no two rows sharing a rule_id, and every
# rule name the gate scripts can report present in the table.
#
# When a row fails here, the fix is to update the row's ref and commit to where
# the text now is. Never rename the rule_id: findings already recorded under it
# would stop lining up with new ones.
#
# The negative cases run the same check on altered copies of the table (a
# moved range, a duplicated rule_id) and require it to fail, so a check that
# passed everything would be caught.
#
# Usage: gate-rule-refs_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TABLE="$SCRIPT_DIR/gate-rules.tsv"
SCRIPTS="$SCRIPT_DIR/check-branch-output.sh $SCRIPT_DIR/check-pr-output.sh $SCRIPT_DIR/check-verification.sh $SCRIPT_DIR/panel-scope.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "git is required to run this suite" >&2; exit 2; }
[ -r "$TABLE" ] || { echo "$TABLE is not readable" >&2; exit 2; }
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) \
    || { echo "not inside a git working tree" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/gate-rule-refs-test.XXXXXX")
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# check_table <table>: prints one line per problem and returns 1 when there is
# any; reads every referenced file at HEAD.
check_table() {
    local table=$1 problems=0 lineno=0 id ref commit excerpt extra path range start end text
    local ids="$WORKDIR/ids.$$"
    : > "$ids"
    while IFS= read -r row || [ -n "$row" ]; do
        lineno=$((lineno + 1))
        case "$row" in ''|'#'*) continue ;; esac
        IFS='	' read -r id ref commit excerpt extra <<EOF
$row
EOF
        if [ -z "$id" ] || [ -z "$ref" ] || [ -z "$commit" ] || [ -z "$excerpt" ] || [ -n "${extra-}" ]; then
            echo "line $lineno: not four tab-separated columns"
            problems=$((problems + 1)); continue
        fi
        printf '%s' "$id" | grep -Eq '^[a-z0-9-]+/[a-z0-9-]+$' \
            || { echo "line $lineno: rule_id [$id] is not <area>/<rule>"; problems=$((problems + 1)); }
        printf '%s' "$commit" | grep -Eq '^[0-9a-f]{12}$' \
            || { echo "line $lineno: commit [$commit] is not 12 hex characters"; problems=$((problems + 1)); }
        printf '%s\n' "$id" >> "$ids"
        path=${ref%%#*}
        range=${ref#*#}
        if [ "$path" = "$ref" ] || ! printf '%s' "$range" | grep -Eq '^L[1-9][0-9]*-L[1-9][0-9]*$'; then
            echo "line $lineno: ref [$ref] is not <path>#L<start>-L<end>"
            problems=$((problems + 1)); continue
        fi
        start=${range%%-*}; start=${start#L}
        end=${range#*-}; end=${end#L}
        if [ "$start" -gt "$end" ]; then
            echo "line $lineno: ref [$ref] ends before it starts"
            problems=$((problems + 1)); continue
        fi
        if ! git -C "$ROOT" show "HEAD:$path" > "$WORKDIR/file" 2>/dev/null; then
            echo "line $lineno: $path is not in HEAD's tree"
            problems=$((problems + 1)); continue
        fi
        text=$(sed -n "${start},${end}p" "$WORKDIR/file" | tr '\n' ' ' | tr -s ' \t' '  ')
        case "$text" in
            *"$excerpt"*) ;;
            *) echo "line $lineno: [$excerpt] is not inside $ref at HEAD ($id)"
               problems=$((problems + 1)) ;;
        esac
    done < "$table"
    dups=$(sort "$ids" | uniq -d)
    if [ -n "$dups" ]; then
        echo "duplicate rule_id: $dups"
        problems=$((problems + 1))
    fi
    rm -f "$ids"
    [ "$problems" -eq 0 ]
}

# --- the shipped table ----------------------------------------------------------

if REPORT=$(check_table "$TABLE"); then
    pass "every row's excerpt occurs inside its rule_ref range at HEAD, and no rule_id repeats"
else
    fail "gate-rules.tsv: $REPORT"
fi

ROWS=$(grep -cv -e '^#' -e '^$' "$TABLE")
[ "$ROWS" -gt 0 ] && pass "the table has $ROWS rule rows" || fail "the table has no rule rows"

# Every rule name the scripts can report is a table row. The names are the
# string literals of the form <area>/<rule> the scripts pass to finding,
# require_rules and the message-to-rule mapping.
MISSING=""
for name in $(grep -hoE '(commit|branch|docs|pr-body|verification|panel)/[a-z0-9-]+' $SCRIPTS | sort -u); do
    case "$name" in docs/guides|docs/designs) continue ;; esac
    awk -F'\t' -v id="$name" '$0 !~ /^#/ && $1 == id { found = 1 } END { exit found ? 0 : 1 }' "$TABLE" \
        || MISSING="$MISSING $name"
done
[ -z "$MISSING" ] && pass "every rule name the gate scripts name has a table row" || fail "names with no table row:$MISSING"

# --- altered copies must fail ---------------------------------------------------

# A moved range: the first row's range shifted far from its text.
awk -F'\t' 'BEGIN { OFS = "\t"; done = 0 }
    $0 !~ /^#/ && NF == 4 && !done { sub(/#L[0-9]+-L[0-9]+$/, "#L1-L2", $2); done = 1 }
    { print }' "$TABLE" > "$WORKDIR/moved.tsv"
if cmp -s "$TABLE" "$WORKDIR/moved.tsv"; then
    fail "fixture: the moved-range copy is identical to the table"
elif REPORT=$(check_table "$WORKDIR/moved.tsv"); then
    fail "a copy whose first range was moved to L1-L2 still passes"
else
    pass "a copy with a moved range fails ($REPORT)"
fi

# A duplicated rule_id: the first rule row repeated.
{ cat "$TABLE"; grep -v -e '^#' -e '^$' "$TABLE" | head -n 1; } > "$WORKDIR/dup.tsv"
if REPORT=$(check_table "$WORKDIR/dup.tsv"); then
    fail "a copy with a repeated rule_id still passes"
else
    pass "a copy with a repeated rule_id fails ($REPORT)"
fi

# An excerpt that occurs nowhere in its range.
awk -F'\t' 'BEGIN { OFS = "\t"; done = 0 }
    $0 !~ /^#/ && NF == 4 && !done { $4 = "text no rule says"; done = 1 }
    { print }' "$TABLE" > "$WORKDIR/excerpt.tsv"
if REPORT=$(check_table "$WORKDIR/excerpt.tsv"); then
    fail "a copy with an excerpt outside its range still passes"
else
    pass "a copy with an excerpt outside its range fails"
fi

echo
echo "gate-rule-refs_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

#!/usr/bin/env bash
# suite-slice_test.sh -- tests for scripts/lib/suite-slice.sh, the selector a
# suite runner filters its list through when a CI job sets SUITE_SLICE=i/n.
#
# Proves the partition (for lists of 1, 2 and 127 suites, with and without a
# cost table, every suite lands in exactly one slice for n from 1 to 8), the
# balance bound (the heaviest slice exceeds the lightest by no more than the
# costliest suite), determinism across runs and locales, the pass-through
# when no slice is set, empty slices, and every refusal.
#
# Usage: bash scripts/lib/suite-slice_test.sh
# Needs bash, awk, sort and diff; runs no suite.
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SEL="$HERE/suite-slice.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/suite-slice-test.XXXXXX") || { echo "suite-slice_test: no temporary directory" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# Whatever the caller's shell holds must not slice these runs.
unset SUITE_SLICE SUITE_SLICE_COSTS

# sel <slice> <costs> <list file>: run the selector; stdout to $T/out, stderr
# to $T/err, exit status in RC.
sel() {
    env SUITE_SLICE="$1" SUITE_SLICE_COSTS="$2" bash "$SEL" fixture < "$3" > "$T/out" 2> "$T/err"
    RC=$?
}

# A list of <count> suites under a directory, in a deliberately unsorted order
# (the selector must keep the order it was given).
make_list() {
    awk -v n="$1" 'BEGIN { for (j = n; j >= 1; j--) printf "dir/s%03d_test.sh\n", (j * 37) % 1000 }' > "$2"
}

# A cost table for a list: uneven costs, one row left out (it takes the
# median), and a row for a suite not on the list (ignored).
make_costs() {
    awk 'BEGIN { print "# a comment"; print "all\trun-tests.sh" }
         { b = $0; sub(/.*\//, "", b); if (NR != 2) printf "cost\t%s\t%d\n", b, (NR * 53) % 211 + 1 }
         END { print "cost\tnot-on-the-list_test.sh\t9999" }' "$1" > "$2"
}

# cost_of <costs file> <list file>: "basename<TAB>cost" per suite, with the
# selector's median rule, computed independently of it.
cost_of() {
    awk -F'\t' 'NR == FNR { if ($1 == "cost" && !($2 in c)) c[$2] = $3; next }
        { b = $0; sub(/.*\//, "", b); n++; name[n] = b; if (b in c) { v[n] = c[b]; k++; kn[k] = c[b] } else v[n] = -1 }
        END {
            for (a = 2; a <= k; a++) { x = kn[a]; for (b = a - 1; b >= 1 && kn[b] > x; b--) kn[b + 1] = kn[b]; kn[b + 1] = x }
            med = k ? kn[int((k + 1) / 2)] : 1
            for (j = 1; j <= n; j++) printf "%s\t%d\n", name[j], (v[j] < 0 ? med : v[j])
        }' "$1" "$2"
}

# check_partition <label> <list> <costs>: for n = 1..8, the slices together
# hold every suite once, each slice keeps the list's order, each count line
# is right, and the cost spread is within one costliest suite.
check_partition() {
    local label=$1 list=$2 costs=$3 n i ok total want spread
    total=$(wc -l < "$list" | tr -d ' ')
    cost_of "${costs:-/dev/null}" "$list" > "$T/costs.eff"
    n=1
    while [ "$n" -le 8 ]; do
        ok=1
        : > "$T/union"
        : > "$T/totals"
        i=1
        while [ "$i" -le "$n" ]; do
            sel "$i/$n" "$costs" "$list"
            if [ "$RC" -ne 0 ]; then ok=0; echo "  slice $i/$n exited $RC: $(cat "$T/err")"; fi
            cat "$T/out" >> "$T/union"
            want="suite-slice: slice $i/$n: $(wc -l < "$T/out" | tr -d ' ') of $total suites"
            if [ "$(cat "$T/err")" != "$want" ]; then ok=0; echo "  slice $i/$n stderr: $(cat "$T/err")"; fi
            # The slice is a subsequence of the list, in the list's order.
            if ! awk 'NR == FNR { pos[$0] = FNR; next } { if (pos[$0] <= last) bad = 1; last = pos[$0] } END { exit bad }' "$list" "$T/out"; then
                ok=0; echo "  slice $i/$n is out of the list's order"
            fi
            awk -F'\t' 'NR == FNR { c[$1] = $2; next } { b = $0; sub(/.*\//, "", b); s += c[b] } END { print s + 0 }' "$T/costs.eff" "$T/out" >> "$T/totals"
            i=$((i + 1))
        done
        if ! diff <(LC_ALL=C sort "$T/union") <(LC_ALL=C sort "$list") > /dev/null; then
            ok=0; echo "  n=$n: the slices together are not the list exactly once"
        fi
        spread=$(awk 'NR == 1 { lo = hi = $1 } { if ($1 < lo) lo = $1; if ($1 > hi) hi = $1 } END { print hi - lo }' "$T/totals")
        want=$(awk -F'\t' '$2 > m { m = $2 } END { print m + 0 }' "$T/costs.eff")
        if [ "$spread" -gt "$want" ]; then
            ok=0; echo "  n=$n: heaviest minus lightest slice is $spread, over the costliest suite's $want"
        fi
        if [ "$ok" = 1 ]; then pass "$label: n=$n partitions the list, keeps its order and stays within one suite's cost"; else fail "$label: n=$n"; fi
        n=$((n + 1))
    done
}

# --- partition and balance --------------------------------------------------

for count in 1 2 127; do
    make_list "$count" "$T/list$count"
    make_costs "$T/list$count" "$T/costs$count"
    check_partition "$count suites, no cost table" "$T/list$count" ""
    check_partition "$count suites, with a cost table" "$T/list$count" "$T/costs$count"
done

# Balance is by cost, not by count: one suite as costly as eight others
# together gets a slice to itself.
: > "$T/skew"; : > "$T/skew.costs"
for s in a b c d e f g h; do
    printf 'x/%s_test.sh\n' "$s" >> "$T/skew"
    printf 'cost\t%s_test.sh\t10\n' "$s" >> "$T/skew.costs"
done
printf 'x/big_test.sh\n' >> "$T/skew"
printf 'cost\tbig_test.sh\t80\n' >> "$T/skew.costs"
sel 1/2 "$T/skew.costs" "$T/skew"
if [ "$(cat "$T/out")" = "x/big_test.sh" ]; then
    pass "the costliest suite fills its own slice when it outweighs the rest"
else
    fail "cost balance: slice 1/2 holds $(tr '\n' ' ' < "$T/out")"
fi

# --- no slice: the list unchanged -------------------------------------------

env -u SUITE_SLICE bash "$SEL" < "$T/list127" > "$T/out" 2> "$T/err"
RC=$?
if [ "$RC" -eq 0 ] && cmp -s "$T/out" "$T/list127" && [ ! -s "$T/err" ]; then
    pass "SUITE_SLICE unset prints the list unchanged and says nothing"
else
    fail "SUITE_SLICE unset: exit $RC, stderr: $(cat "$T/err")"
fi
sel "" "$T/costs127" "$T/list127"
if [ "$RC" -eq 0 ] && cmp -s "$T/out" "$T/list127"; then
    pass "SUITE_SLICE empty prints the list unchanged"
else
    fail "SUITE_SLICE empty: exit $RC"
fi

# --- determinism ------------------------------------------------------------

sel 3/5 "$T/costs127" "$T/list127"; cp "$T/out" "$T/first"
sel 3/5 "$T/costs127" "$T/list127"
if cmp -s "$T/out" "$T/first"; then pass "two runs over one list print the same slice"; else fail "two runs differ"; fi

same_locales=1
for loc in C C.UTF-8 en_US.UTF-8; do
    env LC_ALL="$loc" SUITE_SLICE=2/4 SUITE_SLICE_COSTS="$T/costs127" bash "$SEL" < "$T/list127" > "$T/loc" 2> /dev/null
    sel 2/4 "$T/costs127" "$T/list127"
    cmp -s "$T/loc" "$T/out" || { same_locales=0; echo "  LC_ALL=$loc gave a different slice"; }
done
if [ "$same_locales" = 1 ]; then pass "the slice is the same under every locale"; else fail "the slice depends on the locale"; fi

# Equal costs are broken by name, not by the list's order.
printf 'b/z_test.sh\nb/y_test.sh\nb/x_test.sh\n' > "$T/rev"
printf 'b/x_test.sh\nb/y_test.sh\nb/z_test.sh\n' > "$T/fwd"
sel 1/2 "" "$T/rev"; LC_ALL=C sort "$T/out" > "$T/a"
sel 1/2 "" "$T/fwd"; LC_ALL=C sort "$T/out" > "$T/b"
if cmp -s "$T/a" "$T/b"; then pass "equal-cost suites are assigned by name, whatever order they come in"; else fail "the assignment follows the input order"; fi

# --- a list shorter than n --------------------------------------------------

printf 'a_test.sh\nb_test.sh\n' > "$T/two"
sel 4/4 "" "$T/two"
if [ "$RC" -eq 0 ] && [ ! -s "$T/out" ] && [ "$(cat "$T/err")" = "suite-slice: slice 4/4: 0 of 2 suites" ]; then
    pass "an empty slice of a short list exits 0 and reports 0 of N suites"
else
    fail "empty slice: exit $RC, out: $(cat "$T/out"), err: $(cat "$T/err")"
fi

# --- refusals ---------------------------------------------------------------

: > "$T/empty"
for s in "" 2/4; do
    sel "$s" "" "$T/empty"
    if [ "$RC" -eq 1 ] && grep -q 'from fixture is empty' "$T/err"; then
        pass "an empty list exits 1 and names the runner (SUITE_SLICE='$s')"
    else
        fail "empty list (SUITE_SLICE='$s'): exit $RC, err: $(cat "$T/err")"
    fi
done
printf '\n\n' > "$T/blank"
sel 1/2 "" "$T/blank"
if [ "$RC" -eq 1 ]; then pass "a list of blank lines is empty"; else fail "blank lines: exit $RC"; fi

for s in 5/4 0/4 x 1/17 17/17 1/0 /4 1/ 1/4/2 " 1/4" 01/4 -1/4; do
    sel "$s" "" "$T/list127"
    if [ "$RC" -eq 2 ] && grep -qF "SUITE_SLICE=$s " "$T/err" && [ ! -s "$T/out" ]; then
        pass "SUITE_SLICE='$s' exits 2 naming the value"
    else
        fail "SUITE_SLICE='$s': exit $RC, err: $(cat "$T/err")"
    fi
done
sel 16/16 "" "$T/list127"
if [ "$RC" -eq 0 ]; then pass "16/16 is accepted"; else fail "16/16: exit $RC"; fi

printf 'cost\ts001_test.sh\t12\ncost\ts074_test.sh\t1.5\n' > "$T/badcost"
sel 1/2 "$T/badcost" "$T/list127"
if [ "$RC" -eq 2 ] && grep -q 's074_test.sh is not a whole number' "$T/err" && [ ! -s "$T/out" ]; then
    pass "a cost that is not a whole number exits 2"
else
    fail "bad cost: exit $RC, err: $(cat "$T/err")"
fi
printf 'cost\ts001_test.sh\n' > "$T/shortcost"
sel 1/2 "$T/shortcost" "$T/list127"
if [ "$RC" -eq 2 ]; then pass "a cost row with no seconds exits 2"; else fail "short cost row: exit $RC"; fi

sel 1/2 "$T/no-such-file" "$T/list127"
if [ "$RC" -eq 2 ] && grep -q 'not a readable file' "$T/err"; then
    pass "a missing cost table exits 2"
else
    fail "missing cost table: exit $RC, err: $(cat "$T/err")"
fi

echo
echo "suite-slice_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

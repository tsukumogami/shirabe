#!/usr/bin/env bash
# suite-slice.sh -- print one cost-balanced slice of a list of test suites.
#
# A CI job too long to run on one runner becomes a matrix of slices, each
# running a share of the same suite list. The workflow sets SUITE_SLICE=i/n
# from the matrix, and the runner that walks the list pipes it through this
# script before its loop, so every slice is chosen the same way and the n
# slices together run every suite exactly once.
#
# Reads the full list on standard input, one suite path per line (blank lines
# are ignored). With SUITE_SLICE unset or empty it prints the list unchanged:
# a local run and any job that sets no slice run every suite. Otherwise it
# assigns the suites to n slices greedily, the costliest first, each to the
# slice with the lowest running total (ties go to the lower slice number, and
# suites of equal cost are taken in name order under LC_ALL=C), and prints the
# suites of slice i in the order they came in. Greedy assignment leaves the
# heaviest slice no more than one suite's cost above the lightest, and the
# same list and cost table always give the same slices.
#
# Costs come from the file SUITE_SLICE_COSTS names, if any: rows of
# `cost<TAB><suite file name><TAB><seconds>`, as in a skill's check-skill.tsv
# (other rows are ignored, the first row for a name wins). A suite is matched
# on its file's basename. A suite with no row costs the median of the listed
# suites' known costs (the lower middle of an even count), or 1 when none is
# known. A cost that is not a whole number is an error, never a default. A
# caller whose costs live elsewhere (a floor list's `cost:` lines) writes them
# out in this row form and points SUITE_SLICE_COSTS at that file, or at a
# process substitution.
#
# Standard error carries one line, `suite-slice: slice i/n: k of N suites`,
# when a slice is set.
#
# Usage: <list> | scripts/lib/suite-slice.sh [RUNNER]
#   RUNNER names the caller in the empty-list error.
#
# Exit codes:
#   0  printed the slice (an empty slice too, when the list has fewer suites
#      than n)
#   1  the full list is empty: every slice of it would pass having run nothing
#   2  SUITE_SLICE is not i/n with 1 <= i <= n <= 16, or the cost table is
#      unreadable or holds a cost that is not a whole number
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile; awk and sort
# only.

set -uo pipefail
export LC_ALL=C

RUNNER=${1:-its caller}

LIST=$(awk '{ sub(/\r$/, "") } NF > 0')
if [ -z "$LIST" ]; then
    echo "suite-slice: the suite list from $RUNNER is empty; a slice of it would pass having run nothing" >&2
    exit 1
fi

SLICE=${SUITE_SLICE:-}
if [ -z "$SLICE" ]; then
    printf '%s\n' "$LIST"
    exit 0
fi

bad_slice() {
    echo "suite-slice: SUITE_SLICE=$SLICE is not i/n with 1 <= i <= n <= 16" >&2
    exit 2
}
case "$SLICE" in
    [1-9]/[1-9]|[1-9]/1[0-6]|1[0-6]/1[0-6]) ;;
    *) bad_slice ;;
esac
I=${SLICE%/*}
N=${SLICE#*/}
[ "$I" -le "$N" ] || bad_slice

COSTS=/dev/null
if [ -n "${SUITE_SLICE_COSTS:-}" ]; then
    COSTS=$SUITE_SLICE_COSTS
    if [ ! -r "$COSTS" ] || [ -d "$COSTS" ]; then
        echo "suite-slice: SUITE_SLICE_COSTS=$COSTS is not a readable file" >&2
        exit 2
    fi
fi

# Each suite with its cost and its place in the list: "cost<TAB>name<TAB>index".
KEYED=$(printf '%s\n' "$LIST" | awk -F'\t' -v costs="$COSTS" '
    BEGIN {
        while ((r = (getline line < costs)) > 0) {
            ln++
            m = split(line, f, "\t")
            if (f[1] != "cost") continue
            if (m < 3 || f[3] !~ /^[0-9]+$/) {
                printf "suite-slice: %s line %d: cost for %s is not a whole number: %s\n", costs, ln, f[2], f[3] > "/dev/stderr"
                bad = 1
                exit 2
            }
            if (!(f[2] in cost)) cost[f[2]] = f[3] + 0
        }
        if (r < 0) {
            printf "suite-slice: cannot read %s\n", costs > "/dev/stderr"
            bad = 1
            exit 2
        }
    }
    {
        n++
        path[n] = $0
        base = $0
        sub(/.*\//, "", base)
        name[n] = base
        if (base in cost) {
            c[n] = cost[base]
            known[++k] = cost[base]
        } else {
            c[n] = -1
        }
    }
    END {
        if (bad) exit 2
        # The median of the known costs, by insertion sort (lists are small).
        for (a = 2; a <= k; a++) {
            v = known[a]
            for (b = a - 1; b >= 1 && known[b] > v; b--) known[b + 1] = known[b]
            known[b + 1] = v
        }
        med = (k > 0) ? known[int((k + 1) / 2)] : 1
        for (j = 1; j <= n; j++) printf "%d\t%s\t%d\n", (c[j] < 0 ? med : c[j]), name[j], j
    }
') || exit 2

# Greedy assignment over the costliest-first order; prints the list indexes
# that fall in slice I.
PICKED=$(printf '%s\n' "$KEYED" | sort -t "$(printf '\t')" -k1,1nr -k2,2 -k3,3n | awk -F'\t' -v want="$I" -v slices="$N" '
    BEGIN { for (s = 1; s <= slices; s++) total[s] = 0 }
    {
        best = 1
        for (s = 2; s <= slices; s++) if (total[s] < total[best]) best = s
        total[best] += $1
        if (best == want) print $3
    }
')

# The picked indexes, a separator line, then the list, all on standard input:
# a multi-line value passed with awk -v is not portable to every awk.
{ printf '%s\n' "$PICKED"; printf '%s\n' '-- suite-slice list --'; printf '%s\n' "$LIST"; } | awk -v slice="$SLICE" '
    !inlist { if ($0 == "-- suite-slice list --") inlist = 1; else if ($0 != "") keep[$0] = 1; next }
    { n++; if (n in keep) { print; k++ } }
    END { printf "suite-slice: slice %s: %d of %d suites\n", slice, k, n > "/dev/stderr" }
'

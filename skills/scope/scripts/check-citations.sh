#!/usr/bin/env bash
# Pre-deletion citation guard for /scope's consolidation judgment.
#
# Answers one question before an absorb deletes an artifact: does anything else
# in this repository still cite it? A citation by repo-relative path refuses the
# fold; a citation by bare name is surfaced for the judging agent to weigh.
#
# WHY THIS IS A SCRIPT AND NOT PROSE
#
# The exclusion set is the entire mechanism. The survivor of a fold *always*
# cites the artifact being absorbed, by full path, in its own `upstream:` field
# -- that is behaviour the consolidation change deliberately shipped, having
# named the old non-citing behaviour as the defect it was fixing. Without the
# survivor exclusion this guard refuses every fold, including the only hop
# absorbable before this change. Measured on this corpus: 36 of 36 BRIEF/PRD
# pairs refused. Excluding only the `upstream:` line is not enough either,
# because most survivors cite the path more than once.
#
# That is a rule with a measurable right answer, which prose cannot pin and a
# test can. Hence: a script, with a co-located test, behind a merge gate.
#
# EXIT CODES ARE THIS SCRIPT'S CONTRACT, NOT git grep's
#
#   0  clean            -- no citation anywhere; the fold may proceed
#   1  path citations   -- refuse: downgrade the verdict to `keep`
#   2  bare-name only   -- surface as a finding; does not by itself decide
#   3  did not complete -- refuse: the search could not be trusted
#
# `git grep` exits 0 when it FINDS something and 1 when it does not, which is
# the inverse of the two outcomes that matter here. A script that propagated
# that status would read a found path citation as "clean" and let the fold
# proceed -- the one fail-toward-absorb this design must not have. So the
# statuses are translated explicitly and never passed through.
#
# The caller's routing rule is default-deny: any status other than 0 or 2 routes
# to `keep`, including statuses this script does not define.
set -uo pipefail

readonly EXIT_CLEAN=0
readonly EXIT_PATH_HITS=1
readonly EXIT_NAME_HITS=2
readonly EXIT_INCOMPLETE=3

# Must match `ABSORBED_ENTRY_PATTERN` in crates/shirabe-validate/src/formats.rs,
# widened to admit a PLAN because the survivor at the terminal hop is one.
# Asserted against that constant by check-scope-scripts.yml: the string has one
# owner even though three sites read it.
readonly DOC_PATH_RE='^docs/(briefs|prds|designs|plans)/(BRIEF|PRD|DESIGN|PLAN)-[a-z0-9-]+\.md$'

usage() {
    cat >&2 <<'EOF'
usage: check-citations.sh --target <path> --survivor <path>

  --target    the artifact the absorb would delete
  --survivor  the document absorbing it; excluded from the search

exit: 0 clean | 1 path citations | 2 bare-name only | 3 did not complete
EOF
}

die_incomplete() {
    printf 'check-citations: %s\n' "$1" >&2
    exit "$EXIT_INCOMPLETE"
}

target=""
survivor=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)   target="${2-}"; shift 2 || die_incomplete "--target needs a value" ;;
        --survivor) survivor="${2-}"; shift 2 || die_incomplete "--survivor needs a value" ;;
        -h|--help)  usage; exit "$EXIT_CLEAN" ;;
        *)          usage; die_incomplete "unknown argument: $1" ;;
    esac
done

[[ -n "$target" ]]   || { usage; die_incomplete "--target is required"; }
[[ -n "$survivor" ]] || { usage; die_incomplete "--survivor is required"; }

# Both paths are composed by the caller from a validated topic slug. That makes
# them safe today, but the safety is a property of the caller rather than of
# this surface, and `--` does not help: it stops a leading dash being read as an
# option, and does nothing about pathspec globbing. These arguments are
# interpolated into `:!<path>` exclusions, so a value like `docs/*` would blind
# the search across the tree and the fold would proceed on a clean exit.
# Asserting the shape here makes the guard safe on its own terms.
for path in "$target" "$survivor"; do
    if [[ ! "$path" =~ $DOC_PATH_RE ]]; then
        die_incomplete "refusing to search: '$path' is not a repo-relative chain-document path"
    fi
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die_incomplete "not inside a git work tree"

basename_of="${target##*/}"

# Tier 1: the artifact's full repo-relative path. Unambiguous, and the tier that
# acts. `-F` keeps the path's dots literal; `-I` skips binary files.
#
# Exclusions, each load-bearing:
#   :!wip/       non-durable staging, swept before merge
#   :!$survivor  the absorbing document -- see the header
#   fixtures     test corpora are not real citations
path_hits=$(
    git grep -I -F -n -e "$target" -- \
        ':!wip/' \
        ":!$survivor" \
        ':!**/tests/fixtures/**' \
        ':!**/testdata/**' \
        2>/dev/null
)
status=$?
if (( status > 1 )); then
    die_incomplete "search failed with git grep status $status"
fi

if [[ -n "$path_hits" ]]; then
    printf 'path citations remain; refusing the fold:\n%s\n' "$path_hits"
    exit "$EXIT_PATH_HITS"
fi

# Tier 2: the bare basename. Noisier by construction -- a document name can
# appear in prose that is not a reference -- so this tier reports and never
# decides. The judging agent weighs it against the two bodies it can see.
name_hits=$(
    git grep -I -F -n -e "$basename_of" -- \
        ':!wip/' \
        ":!$survivor" \
        ':!**/tests/fixtures/**' \
        ':!**/testdata/**' \
        2>/dev/null
)
status=$?
if (( status > 1 )); then
    die_incomplete "search failed with git grep status $status"
fi

if [[ -n "$name_hits" ]]; then
    printf 'bare-name mentions found (finding only, not a refusal):\n%s\n' "$name_hits"
    exit "$EXIT_NAME_HITS"
fi

exit "$EXIT_CLEAN"

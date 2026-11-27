# check-rule-registry-testlib.sh -- the setup the four check-rule-registry
# suites share. Sourced by scripts/check-rule-registry_<n>_test.sh after
# `set -u` and the koto test guard, whose ktg_on_exit it uses; it is not a
# suite.
#
# The suites test check-rule-registry.sh and check-rule-registry-adoption.sh.
# The standing check runs against a scratch copy of the files it reads. The
# copy is a git repository whose object store borrows the real one's, so the
# baseline's pinned commit resolves there as it does in CI. The unaltered copy
# must pass; each case then alters one thing, expects exit 1 and the problem
# line that names it, and restores the copy. The adoption script runs against
# small scratch repositories with a base commit and a working tree.
#
# The cases were one suite, cut into four by case order so each part runs in
# its own CI slice. Each part builds its own copy here; no state crosses
# from one part to another.
#
# Provides: SCRIPT_DIR (scripts/), REPO_ROOT, CHECK, ADOPT, PASS, FAIL, pass,
# fail, WORK, GIT_ID, the copy S and REG, MUTABLE, reset_copy, reg, run_check,
# altered, expect_problem, expect_clean, sel, and the entry ids the cases name.

SCRIPT_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
REPO_ROOT=$(CDPATH='' cd -P -- "$SCRIPT_DIR/.." && pwd -P)
CHECK="$SCRIPT_DIR/check-rule-registry.sh"
ADOPT="$SCRIPT_DIR/check-rule-registry-adoption.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ $# -lt 2 ] || printf '  %s\n' "$2"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-rule-registry-test.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$WORK"'

GIT_ID="-c user.name=test -c user.email=test@example.com -c commit.gpgsign=false"

# ---------------------------------------------------------------- the copy

S="$WORK/s"
git init -q "$S"
# The common directory, not the git directory: in a linked worktree the
# objects live with the main checkout. git prints it relative to the
# repository root or absolute.
COMMON=$(git -C "$REPO_ROOT" rev-parse --git-common-dir)
case "$COMMON" in /*) ;; *) COMMON="$REPO_ROOT/$COMMON" ;; esac
echo "$COMMON/objects" > "$S/.git/objects/info/alternates"

# The copy is a sparse checkout, not a recursive copy: it writes only the
# files the check reads (the scanned scripts, the templates, every path the
# registry names) rather than every file under skills/ and scripts/, where the
# recursive copy it replaces wrote over a thousand files per run, each one
# scanned by the host. It is cut from `git stash create` when the checkout
# has uncommitted changes to tracked files, so it holds what the suite is
# testing; a file nothing has added yet is not in it, so `git add` a new file
# the check reads before running the suite. Its HEAD is that commit, the base
# the --base cases build on.
SNAP=$(git -C "$REPO_ROOT" stash create 2>/dev/null) || SNAP=""
[ -n "$SNAP" ] || SNAP=$(git -C "$REPO_ROOT" rev-parse HEAD) || { echo "no commit to test" >&2; exit 2; }
git -C "$S" config core.sparseCheckout true
git -C "$S" config core.sparseCheckoutCone false
{
    printf '%s\n' /references/ /hooks/ /scripts/lib/ '/scripts/*.sh' /scripts/review-shadow/criteria.json \
        '/skills/*/scripts/*.sh' '/skills/*/koto-templates/*.md' /CLAUDE.md /.claude-plugin/plugin.json \
        /docs/designs/current/DESIGN-output-gates.md /docs/measurement/offload-baseline/template-pin.json \
        /.github/workflows/check-rule-registry.yml /.github/workflows/validate-pr-body.yml
    git -C "$REPO_ROOT" show "$SNAP:references/rule-registry.json" | jq -r '.rules[]
        | (.text.path?, .check.path?, .check.template?, .backstop.check?, .deny.hook?, (.fixtures[]?),
           (.stage_backstops[]?.check))
        | strings | "/" + .'
} > "$S/.git/info/sparse-checkout"
git -C "$S" checkout -q --detach "$SNAP" || { echo "could not check out the scratch copy" >&2; exit 2; }

REG="$S/references/rule-registry.json"
MUTABLE="references/rule-registry.json references/rule-registry.md references/pr-body-conformance.md
docs/measurement/offload-baseline/template-pin.json .github/workflows/check-rule-registry.yml
docs/designs/current/DESIGN-output-gates.md skills/execute/koto-templates/execute.md
skills/work-on/scripts/check-pr-output.sh skills/execute/scripts/adopt-or-create-pr.sh
skills/work-on/scripts/panel-scope.sh hooks/pre-action-deny.sh"
mkdir -p "$WORK/orig"
for f in $MUTABLE; do
    mkdir -p "$WORK/orig/$(dirname "$f")"
    cp "$S/$f" "$WORK/orig/$f"
done
reset_copy() {
    local f
    for f in $MUTABLE; do cp "$WORK/orig/$f" "$S/$f"; done
}

# reg <jq filter>: rewrite the copy's registry through a jq filter.
reg() {
    jq "$1" "$WORK/orig/references/rule-registry.json" > "$REG" || { echo "bad test filter: $1" >&2; exit 2; }
}

run_check() {
    OUT=$("$CHECK" --root "$S" "$@" 2>&1)
    RC=$?
}

# altered: 0 when some file of the copy differs from its original, so a case
# whose alteration silently failed can't pass on the unaltered copy.
altered() {
    local f
    for f in $MUTABLE; do
        cmp -s "$WORK/orig/$f" "$S/$f" || return 0
    done
    return 1
}

# expect_problem <label> <substring> [check args]: exit 1 and a problem line
# holding <substring>. The copy is restored afterwards.
expect_problem() {
    local label=$1 want=$2
    shift 2
    if ! altered; then
        fail "$label" "the case altered nothing"
        reset_copy
        return
    fi
    run_check "$@"
    if [ "$RC" = 1 ] && grep -qF -- "$want" <<<"$OUT"; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want 1 and [$want]; got: $(head -n 5 <<<"$OUT" | tr '\n' '|')"
    fi
    reset_copy
}

# expect_clean <label>: exit 0 on an altered copy. The copy is restored
# afterwards.
expect_clean() {
    local label=$1
    if ! altered; then
        fail "$label" "the case altered nothing"
        reset_copy
        return
    fi
    run_check
    if [ "$RC" = 0 ]; then
        pass "$label"
    else
        fail "$label" "rc=$RC, want 0; got: $(head -n 5 <<<"$OUT" | tr '\n' '|')"
    fi
    reset_copy
}

G=pr-body/no-heading-in-part1
G2=pr-body/one-separator
RS=rs-004
TK=execute/pr-takeover-needs-signal
sel() { printf '(.rules[] | select(.id == "%s"))' "$1"; }

# Ids and fragments more than one part's cases use.
# A script gate entry at warn that guards nothing.
WN=brief/summary-length
# An entry with status retired.
R=branch/no-wip-files
# The hook whose RULE_IDS line the hook-link cases read.
HK=hooks/pre-action-deny.sh
# A decider check: a koto decider-check gate's criterion.
DECIDER='{"kind": "decider", "template": "skills/work-on/koto-templates/work-on.md", "state": "review_level_check", "gate": "level_fits_facts", "criterion": "level_fits_facts"}'
# A stage backstop before pr-create, held by the hook.
BS_PR="{\"before\": \"pr-create\", \"check\": \"$HK\"}"

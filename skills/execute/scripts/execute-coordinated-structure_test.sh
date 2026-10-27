#!/usr/bin/env bash
# execute-coordinated-structure_test.sh — the coordinated envelope's shape,
# read from the compiled template
# Part of the execute skill
#
# The coordinated envelope's guarantees are properties of its graph, so this
# reads the graph itself: `koto template compile` turns execute-coordinated.md
# into JSON and each assertion is a jq query over it.
#
# It asserts, on the shipped template:
#
#   the states are exactly coord_setup (initial), coord_loop, coord_verdict,
#     coord_merge_confirm, merged, ready_awaiting_merge,
#     paused_awaiting_merges, done_blocked, and done_error; no done_refused
#   coord_setup and coord_loop are agent-run (no default_action); coord_loop's
#     edges key only on the agent's loop_exit, never on a gate or merge state
#   coord_verdict takes no agent evidence and runs
#     record-coordination-verdict.sh as its default action
#   every edge into `merged` comes from coord_merge_confirm and no other state
#   coord_merge_confirm declares no command gate, and runs
#     record-merge-verdict.sh --confirm with --repo read from home_repo (never
#     the comma-joined repos) and --head-branch from coord_branch
#   every coord_merge_confirm and coord_verdict gate is a context-matches gate
#     declared overridable: false
#   no edge out of coord_verdict assigns reason, and only its absent-or-
#     unmatched edge assigns step, the literal execute:status-read
#   coord_merge_confirm's not-merged edge assigns the literal reason
#     merge-not-observed
#   every edge into a terminal assigns a literal outcome; step and reason are
#     assigned only as literals; no assignment reads ${context. or
#     ${gates.<g>.<path>} (there is no command gate whose output could hold a
#     script's)
#   every terminal declares the result map (outcome, step, reason, pr, repos,
#     resume, waiting, body, recovered), step, reason, body and recovered
#     read from context
#   PLAN_DOC's pattern admits a path with `+` and refuses `..`, spaces and `$(`
#   the variables: PLAN_DOC and PLAN_SLUG not rebindable (PLAN_SLUG pattern
#     ^[a-z0-9-]+$), MERGE and PAUSE_BEFORE_FINALIZE values [true, false]
#     default false rebind, PLUGIN_ROOT the same absolute-path pattern as
#     execute.md, REVIEW_FLOOR and REVIEW_CEILING optional with the level
#     pattern and rebind, as in execute.md; VERIFICATION (local default,
#     values local and hosted-ci) and VERIFICATION_DEFERRAL_REASON optional
#     and not rebind, as in execute.md, the dispatch step giving both to
#     every child under hosted-ci and node-push.sh node getting both, its
#     exit 80 stopping the loop as error:execute:deferral-record
#   coord_loop's dispatch step hands the review-level bound to every child,
#     naming both variables, only when not empty
#   no default_action command holds ${context.
#   STORE, COORDINATION_PR, FOLLOW_UP, FOLLOW_UP_REMOVE and ADOPT_RUN are
#     optional and rebind, each with its pattern admitting empty; coord_setup
#     accepts blocked and the seventeen typed stops (the five the record's
#     setup makes; recovery's session-absent, recovery-unproven,
#     recovery-plan-gone, coordination-index-missing, coordination-body-full
#     and adopt-run-refused; the follow-up's follow-up-node,
#     follow-up-repo, follow-up-base, follow-up-author and follow-up-closed;
#     and worktree-isolated),
#     each stop's edge assigning its own code as a
#     literal reason; its directive passes all five variables to
#     record-coord-setup.sh; every coordinated-next.sh and node-push.sh call in
#     coord_loop's directive passes --session; node-push.sh node takes the
#     node's worktree as --worktree and runs in the coordination checkout,
#     and no directive runs it in the node worktree
#
# and, engine-free, over the source and the skill's tree (non-test files:
# no *_test.sh, coord-test-helpers.sh, testdata/ or evals/), each check a
# function over a root that runs on the tree and then on a copy with one
# mutation, which it must fail:
#   `outcome=` followed by `refused` appears nowhere under skills/execute/
#   no file under skills/execute/ names the index-entry grammar or its
#     parsers by their old coord-common.sh names (the entry pattern and the
#     entries, parse and find functions); the codec holds CB_RE_ENTRY
#     (mutation: a definition of the pattern in coord-common.sh)
#   no pattern on head=: a non-comment script line holding `head=` is only
#     a printf output line with no grep, sed, awk, =~, test( or match(, and no
#     template `pattern:` holds it; the codec builds the field (mutation: a
#     `=~ head=(...)` line in coord-merge.sh)
#   no `koto context add` or `remove` of a run/ key outside run-record.sh
#     (mutation: one in coordinated-next.sh)
#   every run-record.sh call names a verb its script owns: setup, recover,
#     adopt and follow-up record-coord-setup.sh's; push node-push.sh's;
#     observe coord-render.sh's; cascade node-push.sh's and
#     record-coordination-verdict.sh's; carry execute-open.sh's; a "$VAR"
#     verb resolved through the file's VAR=<literal> assignments, and one that
#     can't be resolved is a finding (mutations: an observe call in
#     node-push.sh, a "$1" verb in coord-merge.sh)
#   the merge-attempt grammar's three copies agree: coord-common.sh's and
#     record-coordination-verdict.sh's id and value regexes byte-equal, and
#     coordinated-next.sh's --attempts usage text listing the value regex's
#     alternatives and the ids node|node/follow-up-n|coordination (mutation:
#     one value removed from record-coordination-verdict.sh's)
#   SKILL.md names the run record as the run's store, and its closed
#     write-target set lists the six run/ keys, run-record.sh, and
#     coord-render.sh
#
# and that each structural check bites on a mutated copy: a second edge into
# merged, a command gate on coord_merge_confirm, an overridable coord_verdict
# gate, a reason assignment out of coord_verdict, and a done_refused state.
#
# Usage: execute-coordinated-structure_test.sh
# Exit codes: 0 all pass (or koto absent: the compiled checks SKIP loudly),
#             1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute-coordinated.md"
SINGLE="$SKILL_DIR/koto-templates/execute.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "FAIL: $TEMPLATE not found" >&2; exit 1; }

# --- engine-free ------------------------------------------------------------------

# The token is built from two halves so this file doesn't carry it either.
BANNED="outcome=""refused"
REFUSED=$(grep -rn -- "$BANNED" "$SKILL_DIR" 2>/dev/null || true)
if [ -z "$REFUSED" ]; then
    pass "the refused outcome token appears nowhere under skills/execute/ (tests included)"
else
    fail "the refused outcome token appears: $REFUSED"
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/coord-structure-test.XXXXXX") || { echo "FAIL: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
CODEC="$SKILL_DIR/../../scripts/lib/coordination-body.sh"

# The body is read in one place: the codec, called from setup. Each check is
# a function over a root laid out like skills/execute/, printing one
# path:line: text per finding (nothing when the root passes). The tree is
# checked, then a copy with one mutation per check, which must fail it.
#
# skill_files <root> <name-glob> -- the root's non-test files: no *_test.sh,
# coord-test-helpers.sh, testdata/ or evals/.
skill_files() {
    find "$1" -type f -name "$2" ! -name '*_test.sh' ! -name 'coord-test-helpers.sh' \
        ! -path '*/testdata/*' ! -path "$1/evals/*" | LC_ALL=C sort
}

# check_grammar <root> -- no file defines or calls the index-entry grammar or
# its parsers by their old coord-common.sh names, tests included. The names
# are built from halves so this file doesn't carry them either.
check_grammar() {
    grep -rn -e "RE_COORD""_ENTRY" -e "coord_index""_entries" -e "coord_parse""_entry" -e "coord_find""_entry" "$1"
    return 0
}

# check_head <root> -- no pattern on a head= field: in a script, a non-comment
# line holding `head=` is a finding unless it is a printf output line with no
# grep, sed, awk, =~, test( or match( on it (node-push.sh prints its pushed
# head that way); in a template, a YAML `pattern:` line holding head= is one.
check_head() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        awk -v f="$f" '
            /^[[:space:]]*#/ { next }
            index($0, "head=") == 0 { next }
            index($0, "printf") > 0 && $0 !~ /grep|sed|awk|=~|test\(|match\(/ { next }
            { print f ":" NR ": " $0 }' "$f"
    done <<<"$(skill_files "$1" '*.sh')"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        awk -v f="$f" '/^[[:space:]]*pattern:/ && index($0, "head=") > 0 { print f ":" NR ": " $0 }' "$f"
    done <<<"$(find "$1/koto-templates" -type f -name '*.md' | LC_ALL=C sort)"
}

# check_run_writes <root> -- no line adds or removes a run/ key with koto
# context outside run-record.sh, the record's one writer.
check_run_writes() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in */run-record.sh) continue ;; esac
        awk -v f="$f" '/koto context (add|remove)/ && index($0, "run/") > 0 { print f ":" NR ": " $0 }' "$f"
    done <<<"$(skill_files "$1" '*')"
}

# check_verbs <root> -- every run-record.sh call names a verb its owner may
# call: the word after run-record.sh, taken as written, or a "$VAR" resolved
# through the file's own VAR=<literal> assignments (node-push.sh's RR_VERB).
# An unresolvable verb is a finding too.
check_verbs() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in */run-record.sh|*/run-record-lib.sh) continue ;; esac
        awk -v f="$f" -v base="${f##*/}" '
            function owner_ok(v) {
                if (v == "setup" || v == "recover" || v == "adopt" || v == "follow-up") return base == "record-coord-setup.sh"
                if (v == "push") return base == "node-push.sh"
                if (v == "observe") return base == "coord-render.sh"
                if (v == "cascade") return base == "node-push.sh" || base == "record-coordination-verdict.sh"
                if (v == "carry") return base == "execute-open.sh"
                return 0
            }
            /^[[:space:]]*#/ { next }
            { line[NR] = $0 }
            $0 ~ /^[[:space:]]*(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=[a-z][a-z-]*[[:space:]]*$/ {
                a = $0; sub(/^[[:space:]]*(local[[:space:]]+)?/, "", a); sub(/[[:space:]]*$/, "", a)
                k = a; sub(/=.*/, "", k); v = a; sub(/^[^=]*=/, "", v)
                vals[k] = vals[k] " " v
            }
            END {
                for (i = 1; i <= NR; i++) {
                    if (!(i in line)) continue
                    rest = line[i]
                    while ((p = index(rest, "run-record.sh")) > 0) {
                        rest = substr(rest, p + 13)
                        t = rest; sub(/^"/, "", t)
                        if (t !~ /^[[:space:]]/) continue
                        sub(/^[[:space:]]+/, "", t); sub(/[[:space:]].*$/, "", t)
                        verbs = ""
                        if (t ~ /^[a-z][a-z-]*$/) verbs = t
                        else if (t ~ /^"?\$/) {
                            k = t; gsub(/["${}]/, "", k)
                            if (k ~ /^[A-Za-z_][A-Za-z0-9_]*$/) verbs = vals[k]
                        }
                        if (verbs == "") { print f ":" i ": a run-record.sh verb that cannot be resolved: " line[i]; continue }
                        n = split(verbs, vs, " ")
                        for (j = 1; j <= n; j++)
                            if (!owner_ok(vs[j])) print f ":" i ": run-record.sh " vs[j] " called outside its owner: " line[i]
                    }
                }
            }' "$f"
    done <<<"$(skill_files "$1" '*.sh')"
}

FOUND=$(check_grammar "$SKILL_DIR")
if [ -z "$FOUND" ] && grep -q '^CB_RE_ENTRY=' "$CODEC"; then
    pass "no file under skills/execute/ names the index-entry grammar; the codec holds it"
else
    fail "the index-entry grammar is named under skills/execute/: $FOUND"
fi
FOUND=$(check_head "$SKILL_DIR")
if [ -z "$FOUND" ] && grep -q 'head=\\(' "$CODEC"; then
    pass "no non-test file under skills/execute/ holds a pattern on head=; the codec builds the field"
else
    fail "a non-comment line holding \`head=\` outside a printf output line (name the variable oid or sha instead), or the codec no longer builds the field: $FOUND"
fi
FOUND=$(check_run_writes "$SKILL_DIR")
[ -z "$FOUND" ] && pass "no non-test file under skills/execute/ adds or removes a run/ key outside run-record.sh" \
    || fail "a run/ key is written outside run-record.sh: $FOUND"
FOUND=$(check_verbs "$SKILL_DIR")
[ -z "$FOUND" ] && pass "every run-record.sh call under skills/execute/ names a verb its script owns" \
    || fail "a run-record.sh verb is called outside its owner: $FOUND"

# Each check bites: a copy of the skill's scripts and templates with one
# mutation, checked by the same function.
mutated() { # mutated <label> <check> <file under the root> <line to append>
    local root="$T/mut-$2"
    rm -rf "$root"
    mkdir -p "$root"
    cp -R "$SKILL_DIR/scripts" "$SKILL_DIR/koto-templates" "$SKILL_DIR/SKILL.md" "$root/" || { fail "$1: could not copy the tree"; return; }
    printf '%s\n' "$4" >> "$root/$3"
    if [ -n "$("$2" "$root")" ]; then
        pass "$2 fails on a copy with $1"
    else
        fail "$2 passed a copy with $1"
    fi
}
mutated "an index-entry grammar definition in coord-common.sh" check_grammar scripts/coord-common.sh \
    "RE_COORD""_ENTRY='^- x'"
mutated "a head= regex in coord-merge.sh" check_head scripts/coord-merge.sh \
    '[[ $x =~ head=([0-9a-f]+) ]] && echo "${BASH_REMATCH[1]}"'
mutated "a run/ key added by coordinated-next.sh" check_run_writes scripts/coordinated-next.sh \
    'printf x | koto context add "$S" run/node/x'
mutated "a run-record.sh observe call in node-push.sh" check_verbs scripts/node-push.sh \
    '"$BASH" "$COORD_SELF_DIR/run-record.sh" observe --session "$SESSION" --json "$F"'
mutated "a run-record.sh call whose verb is a positional parameter" check_verbs scripts/coord-merge.sh \
    '"$BASH" "$COORD_SELF_DIR/run-record.sh" "$1" --session "$SESSION" --json "$F"'

# check_attempt_grammar <root> -- the merge-attempt grammar is written three
# times: coord-common.sh's RE_COORD_ATTEMPT_ID and RE_COORD_ATTEMPT_VALUE,
# record-coordination-verdict.sh's RE_ATTEMPT_ID and RE_ATTEMPT_VALUE, and the
# <id>:<value> list coordinated-next.sh's --attempts usage error prints. The
# two id regexes and the two value regexes must be byte-equal, the usage
# text's values the value regex's alternatives, and its ids
# node|node/follow-up-n|coordination. Prints one finding per difference.
check_attempt_grammar() {
    local cc="$1/scripts/coord-common.sh" rv="$1/scripts/record-coordination-verdict.sh"
    local cn="$1/scripts/coordinated-next.sh" id_a val_a id_b val_b usage u_ids u_vals
    id_a=$(sed -n "s/^RE_COORD_ATTEMPT_ID='\(.*\)'\$/\1/p" "$cc")
    val_a=$(sed -n "s/^RE_COORD_ATTEMPT_VALUE='\(.*\)'\$/\1/p" "$cc")
    id_b=$(sed -n "s/^RE_ATTEMPT_ID='\(.*\)'\$/\1/p" "$rv")
    val_b=$(sed -n "s/^RE_ATTEMPT_VALUE='\(.*\)'\$/\1/p" "$rv")
    usage=$(sed -n 's/.*--attempts .* is outside <\([^>]*\)>:<\([^>]*\)>.*/\1 \2/p' "$cn")
    u_ids="${usage%% *}"
    u_vals="${usage#* }"
    { [ -n "$id_a" ] && [ "$id_a" = "$id_b" ]; } \
        || echo "$cc: RE_COORD_ATTEMPT_ID [$id_a] is not $rv's RE_ATTEMPT_ID [$id_b]"
    { [ -n "$val_a" ] && [ "$val_a" = "$val_b" ]; } \
        || echo "$cc: RE_COORD_ATTEMPT_VALUE [$val_a] is not $rv's RE_ATTEMPT_VALUE [$val_b]"
    [ "$u_ids" = "node|node/follow-up-n|coordination" ] \
        || echo "$cn: the --attempts usage text's ids [$u_ids] are not node|node/follow-up-n|coordination"
    if [ -z "$usage" ] \
        || [ "$(printf '%s' "$u_vals" | tr '|' '\n' | LC_ALL=C sort)" != "$(printf '%s' "$val_a" | tr -d '()' | tr '|' '\n' | LC_ALL=C sort)" ]; then
        echo "$cn: the --attempts usage text's values [$u_vals] are not RE_COORD_ATTEMPT_VALUE's alternatives [$val_a]"
    fi
}
FOUND=$(check_attempt_grammar "$SKILL_DIR")
[ -z "$FOUND" ] && pass "the merge-attempt grammar's three copies agree (coord-common.sh, record-coordination-verdict.sh, coordinated-next.sh's usage text)" \
    || fail "the merge-attempt grammar's copies differ: $FOUND"
# The mutation removes one value from a copy of record-coordination-verdict.sh.
GRAMMAR_ROOT="$T/mut-check_attempt_grammar"
rm -rf "$GRAMMAR_ROOT"
mkdir -p "$GRAMMAR_ROOT"
if cp -R "$SKILL_DIR/scripts" "$GRAMMAR_ROOT/"; then
    sed 's/^\(RE_ATTEMPT_VALUE=.*\)|body-full)/\1)/' "$SKILL_DIR/scripts/record-coordination-verdict.sh" \
        > "$GRAMMAR_ROOT/scripts/record-coordination-verdict.sh"
    if grep -q '^RE_ATTEMPT_VALUE=.*body-full' "$GRAMMAR_ROOT/scripts/record-coordination-verdict.sh"; then
        fail "check_attempt_grammar: the mutation did not remove body-full"
    elif [ -n "$(check_attempt_grammar "$GRAMMAR_ROOT")" ]; then
        pass "check_attempt_grammar fails on a copy whose RE_ATTEMPT_VALUE lacks one value"
    else
        fail "check_attempt_grammar passed a copy whose RE_ATTEMPT_VALUE lacks one value"
    fi
else
    fail "check_attempt_grammar: could not copy the tree"
fi

# SKILL.md names the run record as a coordinated run's store, and its closed
# write-target set lists every run/ key.
SKILL_MD="$SKILL_DIR/SKILL.md"
if grep -q 'The run record is the run.s store' "$SKILL_MD"; then
    pass "SKILL.md names the run record as the run's store"
else
    fail "SKILL.md does not name the run record as the run's store"
fi
WTS=$(awk '/Closed write-target set/ { f = 1 } f && /^3\. / { exit } f' "$SKILL_MD")
missing=""
for key in 'run/setup' 'run/node/<node>' 'run/follow-up/<node>/<n>' 'run/cascade' 'run/recovered' 'run/adopted' 'run-record.sh' 'coord-render.sh'; do
    grep -qF -- "\`$key\`" <<<"$WTS" || missing="$missing $key"
done
if [ -n "$WTS" ] && [ -z "$missing" ]; then
    pass "SKILL.md's closed write-target set lists every run/ key, each written through run-record.sh, and coord-render.sh"
else
    fail "SKILL.md's closed write-target set lacks:$missing"
fi

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the template was not compiled, so its graph was not checked"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ] || exit 1
    exit 0
fi

WORK="$T/compile"
export HOME="$WORK/home"
mkdir -p "$HOME"

compile() { koto template compile "$@" 2>/dev/null | tail -1; }
holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

CHECKS=(
"the states are exactly the envelope's nine|.states | keys == [\"coord_loop\",\"coord_merge_confirm\",\"coord_setup\",\"coord_verdict\",\"done_blocked\",\"done_error\",\"merged\",\"paused_awaiting_merges\",\"ready_awaiting_merge\"]"
"coord_setup is the initial state|.initial_state == \"coord_setup\""
"no done_refused state is declared|.states | has(\"done_refused\") | not"
"merged, ready_awaiting_merge, and paused_awaiting_merges are non-failure terminals|[.states.merged, .states.ready_awaiting_merge, .states.paused_awaiting_merges] | all(. != null and .terminal == true and ((.failure // false) == false))"
"done_blocked and done_error are failure terminals|.states.done_blocked.terminal == true and .states.done_blocked.failure == true and .states.done_error.terminal == true and .states.done_error.failure == true"
"coord_setup is agent-run|.states.coord_setup.default_action == null"
"coord_loop is agent-run with no gates|.states.coord_loop.default_action == null and ((.states.coord_loop.gates // {}) | length == 0)"
"coord_loop's edges key only on loop_exit|[.states.coord_loop.transitions[] | .when | keys == [\"loop_exit\"]] | length == 3 and all"
"coord_verdict takes no agent evidence|(.states.coord_verdict.accepts // {}) | length == 0"
"coord_verdict's default action runs record-coordination-verdict.sh|(.states.coord_verdict.default_action.command // \"\") | test(\"record-coordination-verdict\\\\.sh \")"
"every edge into merged comes from coord_merge_confirm|[.states | to_entries[] | .key as \$s | (.value.transitions // [])[] | select(.target == \"merged\") | \$s] | . == [\"coord_merge_confirm\"]"
"coord_merge_confirm declares no command gate|[.states.coord_merge_confirm.gates[] | select(.type == \"command\")] | length == 0"
"every coord_merge_confirm gate is a non-overridable context-matches gate|[.states.coord_merge_confirm.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"every coord_verdict gate is a non-overridable context-matches gate|[.states.coord_verdict.gates[] | (.type == \"context-matches\" and .overridable == false)] | length > 0 and all"
"coord_merge_confirm runs record-merge-verdict.sh --confirm on home_repo and coord_branch|(.states.coord_merge_confirm.default_action.command // \"\") | (test(\"record-merge-verdict\\\\.sh --confirm \") and test(\"--repo \\\"\\\\\$\\\\(koto context get execute-\\\\{\\\\{PLAN_SLUG\\\\}\\\\} home_repo\\\\)\\\"\") and test(\"--head-branch \\\"\\\\\$\\\\(koto context get execute-\\\\{\\\\{PLAN_SLUG\\\\}\\\\} coord_branch\\\\)\\\"\") and (test(\" repos\\\\)\") | not))"
"no edge out of coord_verdict assigns reason|[.states.coord_verdict.transitions[] | (.context_assignments // {}) | has(\"reason\")] | any | not"
"only coord_verdict's absent-or-unmatched edge assigns step, the literal execute:status-read|[.states.coord_verdict.transitions[] | select((.context_assignments // {}) | has(\"step\"))] | length == 1 and .[0].context_assignments.step == \"execute:status-read\" and ([.[0].when | to_entries[] | select(.key | startswith(\"gates.\")) | .value] | all(. == false))"
"coord_merge_confirm's not-merged edge assigns reason merge-not-observed|[.states.coord_merge_confirm.transitions[] | select(.target == \"ready_awaiting_merge\") | .context_assignments.reason] == [\"merge-not-observed\"]"
"every edge into a terminal assigns a literal outcome|[.states as \$all | .states[] | (.transitions // [])[] | select(\$all[.target].terminal == true) | ((.context_assignments.outcome // \"\") | (length > 0 and (contains(\"\${\") | not) and (contains(\"{{\") | not)))] | length > 0 and all"
"step and reason are assigned only as literals|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | to_entries[] | select(.key == \"step\" or .key == \"reason\") | .value | (contains(\"\${\") or contains(\"{{\"))] | any | not"
"no assignment reads \${context. or \${gates.|[.states[] | (.transitions // [])[] | (.context_assignments // {}) | .[] | (contains(\"\${context.\") or contains(\"\${gates.\"))] | any | not"
"every terminal declares the full result map|[.states[] | select(.terminal == true) | (.result // {}) | keys == [\"body\",\"outcome\",\"pr\",\"reason\",\"recovered\",\"repos\",\"resume\",\"step\",\"waiting\"]] | length == 5 and all"
"every terminal reads step and reason from context|[.states[] | select(.terminal == true) | .result.step == \"\${context.step}\" and .result.reason == \"\${context.reason}\"] | all"
"every terminal reads body from context|[.states[] | select(.terminal == true) | .result.body == \"\${context.body}\"] | all"
"every terminal reads recovered from context|[.states[] | select(.terminal == true) | .result.recovered == \"\${context.recovered}\"] | length == 5 and all"
"no default_action command holds \${context.|[.states[] | (.default_action.command // \"\") | contains(\"\${context.\")] | any | not"
"MERGE is values [true, false], default false, rebind|.variables.MERGE | (.values == [\"true\",\"false\"] and .default == \"false\" and .rebind == true)"
"REVIEW_FLOOR and REVIEW_CEILING are optional, the level pattern, rebind|[.variables.REVIEW_FLOOR, .variables.REVIEW_CEILING] | all((.required // false) == false and .pattern == \"^(light|standard|full)?\$\" and .rebind == true)"
"the dispatch step passes the review-level bound to every child when not empty|[.states[] | (.directive // \"\") + (.details // \"\")] | any(contains(\"floor \`{{REVIEW_FLOOR}}\` and ceiling \`{{REVIEW_CEILING}}\`\") and contains(\"give every child \`REVIEW_FLOOR\`\") and contains(\"leaving out whichever is empty\"))"
"VERIFICATION is values [local, hosted-ci], default local, optional, not rebind, as in execute.md|.variables.VERIFICATION | (.values == [\"local\",\"hosted-ci\"] and .default == \"local\" and (.required // false) == false and (.rebind // false) == false)"
"VERIFICATION_DEFERRAL_REASON is optional, starts with a letter or digit, not rebind|.variables.VERIFICATION_DEFERRAL_REASON | (. != null and (.required // false) == false and .pattern == \"^([a-zA-Z0-9].*)?\$\" and (.rebind // false) == false)"
"the dispatch step gives every child the deferral when VERIFICATION is hosted-ci|(.states.coord_loop.directive // \"\") | (contains(\"verification is \`{{VERIFICATION}}\`, with reason \`{{VERIFICATION_DEFERRAL_REASON}}\`\") and contains(\"give every child \`VERIFICATION=hosted-ci\` and \`VERIFICATION_DEFERRAL_REASON\`\"))"
"node-push.sh node runs in the coordination checkout with --worktree, never in the node worktree|(.states.coord_loop.directive // \"\") | (contains(\"node-push.sh node --session {{SESSION_NAME}} --worktree <the node's worktree> \") and contains(\"run here in this coordination checkout\") and (contains(\"run in the node worktree\") | not))"
"node-push.sh node gets the run's deferral and its exit 80 is error:execute:deferral-record|(.states.coord_loop.directive // \"\") | (contains(\"--verification \\\"{{VERIFICATION}}\\\" --reason \\\"{{VERIFICATION_DEFERRAL_REASON}}\\\"\") and contains(\"An exit 80\") and contains(\"loop_line: error:execute:deferral-record\"))"
"PAUSE_BEFORE_FINALIZE is values [true, false], default false, rebind|.variables.PAUSE_BEFORE_FINALIZE | (.values == [\"true\",\"false\"] and .default == \"false\" and .rebind == true)"
"PLAN_DOC and PLAN_SLUG are not rebindable|(.variables.PLAN_DOC.rebind // false) == false and (.variables.PLAN_SLUG.rebind // false) == false"
"PLAN_SLUG carries ^[a-z0-9-]+\$|.variables.PLAN_SLUG.pattern == \"^[a-z0-9-]+\$\""
"PLUGIN_ROOT is rebindable|.variables.PLUGIN_ROOT.rebind == true"
"STORE, COORDINATION_PR, FOLLOW_UP, FOLLOW_UP_REMOVE, ADOPT_RUN are optional and rebind|[.variables.STORE, .variables.COORDINATION_PR, .variables.FOLLOW_UP, .variables.FOLLOW_UP_REMOVE, .variables.ADOPT_RUN] | all(. != null and (.required // false) == false and .rebind == true)"
"the five coordinated variables carry their patterns, each admitting empty|.variables.STORE.pattern == \"^(github|session)?\$\" and .variables.COORDINATION_PR.pattern == \"^(https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?\$\" and .variables.FOLLOW_UP.pattern == \"^([a-z][a-z0-9-]* https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*)?\$\" and .variables.FOLLOW_UP_REMOVE.pattern == \"^(true)?\$\" and .variables.ADOPT_RUN.pattern == \"^([0-9a-f]{32})?\$\""
"coord_setup's typed stops each assign their own code as a literal reason|[.states.coord_setup.transitions[] | select((.when.setup_status // \"blocked\") != \"blocked\") | .target == \"done_error\" and .context_assignments.reason == .when.setup_status and .context_assignments.step == \"execute:coord_setup\"] | length == 17 and all"
"coord_setup accepts blocked and the seventeen typed stops|.states.coord_setup.accepts.setup_status.values == [\"blocked\",\"store-mismatch\",\"coordination-pr-missing\",\"coordination-pr-ambiguous\",\"coordination-pr-mismatch\",\"coordination-pr-closed\",\"session-absent\",\"recovery-unproven\",\"recovery-plan-gone\",\"coordination-index-missing\",\"coordination-body-full\",\"adopt-run-refused\",\"follow-up-node\",\"follow-up-repo\",\"follow-up-base\",\"follow-up-author\",\"follow-up-closed\",\"worktree-isolated\"]"
"coord_setup's directive passes all five variables to record-coord-setup.sh|(.states.coord_setup.directive // \"\") | (contains(\"record-coord-setup.sh --session {{SESSION_NAME}} --plan {{PLAN_DOC}}\") and contains(\"--store \\\"{{STORE}}\\\" --coordination-pr \\\"{{COORDINATION_PR}}\\\" --follow-up \\\"{{FOLLOW_UP}}\\\"\") and contains(\"--follow-up-remove \\\"{{FOLLOW_UP_REMOVE}}\\\" --adopt-run \\\"{{ADOPT_RUN}}\\\"\"))"
"every coordinated-next.sh and node-push.sh call in coord_loop passes --session|(.states.coord_loop.directive // \"\") | ([scan(\"scripts/(coordinated-next|node-push)\\\\.sh [a-z]* *--session \\\\{\\\\{SESSION_NAME\\\\}\\\\}\")] | length) == ([scan(\"scripts/(coordinated-next|node-push)\\\\.sh \")] | length)"
)

run_checks() { # run_checks <compiled json> -> prints the labels that fail
    local json="$1" entry label filter
    for entry in "${CHECKS[@]}"; do
        label="${entry%%|*}"
        filter="${entry#*|}"
        holds "$json" "$filter" || printf '%s\n' "$label"
    done
    if [ "$(jq -r '.variables.PLUGIN_ROOT.pattern // ""' "$json")" != "$SINGLE_PLUGIN_PATTERN" ]; then
        printf '%s\n' "PLUGIN_ROOT carries execute.md's absolute-path pattern"
    fi
}

SINGLE_JSON=$(compile "$SINGLE")
SINGLE_PLUGIN_PATTERN=$(jq -r '.variables.PLUGIN_ROOT.pattern // ""' "$SINGLE_JSON" 2>/dev/null)
SHIPPED=$(compile "$TEMPLATE")
if [ -z "$SHIPPED" ] || [ ! -f "$SHIPPED" ]; then
    fail "execute-coordinated.md does not compile"
    koto template compile "$TEMPLATE" 2>&1 | tail -3
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi
pass "execute-coordinated.md compiles"

# PLAN_DOC's declared pattern narrows koto's own value check, so it has to admit
# every path shirabe hands it -- including an absolute one under a directory
# with a `+`, which koto's own value check admits from 0.14.1
# (tsukumogami/koto#266) -- while still refusing
# a `..` segment and shell-active characters. Read from the compiled template
# and run as an ERE, which its plain classes are.
PLAN_DOC_PATTERN=$(jq -r '.variables.PLAN_DOC.pattern // ""' "$SHIPPED")
plan_doc_ok() { grep -Eq -- "$PLAN_DOC_PATTERN" <<<"$1"; }
for good in 'docs/plans/PLAN-x.md' '/home/u/ws/tsuku+shirabe_1/public/shirabe/docs/plans/PLAN-x.md' 'docs/plans/PLAN-a+b.md'; do
    if plan_doc_ok "$good"; then
        pass "PLAN_DOC's pattern admits $good"
    else
        fail "PLAN_DOC's pattern refuses $good"
    fi
done
for bad in 'docs/../PLAN-x.md' 'docs/plans/PLAN x.md' 'docs/plans/PLAN-$(x).md' 'docs/plans/PLAN-x.txt'; do
    if plan_doc_ok "$bad"; then
        fail "PLAN_DOC's pattern admits $bad"
    else
        pass "PLAN_DOC's pattern refuses $bad"
    fi
done
FAILED=$(run_checks "$SHIPPED")
for entry in "${CHECKS[@]}" "PLUGIN_ROOT carries execute.md's absolute-path pattern|"; do
    label="${entry%%|*}"
    if grep -qxF "$label" <<<"$FAILED"; then fail "$label"; else pass "$label"; fi
done

# --- each check bites -------------------------------------------------------------

MUT="$WORK/mut.md"
mutate() { # mutate <label> <expected failing check> <perl substitution>
    local label="$1" want="$2" sub="$3" json failed
    perl -0pe "$sub" "$TEMPLATE" > "$MUT"
    if cmp -s "$TEMPLATE" "$MUT"; then
        fail "mutation [$label] did not change the template; the substitution no longer matches"
        return
    fi
    json=$(compile --allow-legacy-gates "$MUT")
    if [ -z "$json" ] || [ ! -f "$json" ]; then
        fail "mutation [$label] does not compile, so it proves nothing"
        koto template compile --allow-legacy-gates "$MUT" 2>&1 | tail -2
        return
    fi
    failed=$(run_checks "$json")
    if grep -qxF "$want" <<<"$failed"; then
        pass "the check fails on a copy with $label"
    else
        fail "a copy with $label passed [$want]"
    fi
}

mutate "a second edge into merged (from coord_verdict)" \
    "every edge into merged comes from coord_merge_confirm" \
    's/(      - target: )coord_merge_confirm(\n        when:\n          gates.verdict_merged.matches: true)/${1}merged$2/'
mutate "a command gate on coord_merge_confirm" \
    "coord_merge_confirm declares no command gate" \
    's/(    gates:\n      confirmed_merged:\n)/$1        type: context-matches\n        key: confirm_verdict\n        pattern: x\n        overridable: false\n      confirm_exit:\n        type: command\n        command: "true"\n        overridable: false\n      confirmed_merged_2:\n/'
mutate "an overridable coord_verdict gate" \
    "every coord_verdict gate is a non-overridable context-matches gate" \
    's/(pattern: .\^ready\$.\n        overridable: )false/${1}true/'
mutate "a reason assigned out of coord_verdict" \
    "no edge out of coord_verdict assigns reason" \
    's/(        context_assignments:\n          outcome: paused-awaiting-merges\n)/$1          reason: predecessor-unmerged\n/'
mutate "a done_refused state" \
    "no done_refused state is declared" \
    's/(\n  done_error:\n)/\n  done_refused:\n    terminal: true\n    failure: true\n$1/; s/\z/\n## done_refused\n\nRefused.\n/'

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

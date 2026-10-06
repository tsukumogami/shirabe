#!/usr/bin/env bash
# review-level_test.sh -- the review level: choose, raise, lower, the facts
# floor, the level check, the decider slice and the ledger reader
# Part of the work-on skill
#
# review-level.sh is the one way a /work-on run's review level changes. This
# suite pins it in two halves.
#
#   script cases -- review-level.sh against git fixtures, through a koto
#     stand-in on PATH that stores each context key as a file, records the
#     REVIEW_LEVEL a re-attach rebinds, and can be told to fail a rebind or a
#     ledger write. They need git and jq and no engine, so they also run on
#     the macOS bash 3.2 floor leg.
#
#   engine cases -- real koto sessions of a scratch template named work-on
#     that declares REVIEW_LEVEL the way the design does (rebind, optional,
#     pattern ^(light|standard|full)?$), with a choice state that runs `init`
#     and holds until the level is set, and a check state that runs `facts`
#     as its action and `check` as its gate. They assert the rebind lands on
#     the live session, that the variable and the ledger agree after every
#     `set`, that the floor holds a light run until it is raised, that a hand
#     rebind holds the check, that the unset route records `unset`, and what
#     `report` prints for them. Skipped with a note when koto is absent.
#
# Every run isolates HOME and builds its own git fixtures under a temp
# directory.
#
# Usage: review-level_test.sh
#
# Exit codes:
#   0 -- all cases pass (engine cases may have been skipped without koto)
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/review-level.sh"
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
RULES="$SKILL_DIR/references/review-level-rules.tsv"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing or not executable" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main

# --- the koto stand-in ---------------------------------------------------------
#
#   context add|get|exists|remove <s> <key>   $SHIM_STORE/<s>/<key>; get and
#                                             exists exit 1 for an absent key.
#                                             SHIM_FAIL_ADD=<key> fails that
#                                             key's add, SHIM_FAIL_GET=<key>
#                                             its get. Every add is logged.
#   init <s> ... --attach-live --var REVIEW_LEVEL=<v>
#                                             records <v> in
#                                             $SHIM_STORE/<s>/.var and replies
#                                             the way koto does. SHIM_FAIL_INIT=1
#                                             fails it. Every call is logged.
#   workflows                                 every session directory
#   status <s>                                template_path: <s>/.tpl.json
#   overrides list <s>                        <s>/.overrides, or none

SHIM_BIN="$WORKDIR/shim-bin"
SHIM_STORE="$WORKDIR/shim-store"
mkdir -p "$SHIM_BIN" "$SHIM_STORE"
cat > "$SHIM_BIN/koto" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
    context)
        f="$SHIM_STORE/$3/$4"
        case "$2" in
            add)
                if [ -n "${SHIM_FAIL_ADD:-}" ] && [ "$4" = "$SHIM_FAIL_ADD" ]; then
                    echo "koto shim: refusing $4" >&2; exit 9
                fi
                mkdir -p "$SHIM_STORE/$3"
                cat > "$f"
                echo "$4" >> "$SHIM_STORE/$3/.addlog"
                ;;
            get)
                if [ -n "${SHIM_FAIL_GET:-}" ] && [ "$4" = "$SHIM_FAIL_GET" ]; then
                    echo "koto shim: cannot read $4" >&2; exit 9
                fi
                [ -f "$f" ] || { echo "koto shim: no key $4" >&2; exit 1; }; cat "$f" ;;
            exists) [ -f "$f" ] ;;
            remove) rm -f "$f" ;;
            *) echo "koto shim: unsupported: $*" >&2; exit 2 ;;
        esac
        ;;
    init)
        s="$2"; v=""; attach=0
        for a in "$@"; do
            case "$a" in
                --attach-live) attach=1 ;;
                REVIEW_LEVEL=*) v="${a#REVIEW_LEVEL=}" ;;
            esac
        done
        mkdir -p "$SHIM_STORE/$s"
        echo "$v" >> "$SHIM_STORE/$s/.initlog"
        [ "$attach" -eq 1 ] || { echo "koto shim: init without --attach-live" >&2; exit 2; }
        if [ -n "${SHIM_FAIL_INIT:-}" ]; then
            echo '{"code":"template_mismatch","error":"refused"}'; exit 2
        fi
        old=$(cat "$SHIM_STORE/$s/.var" 2>/dev/null)
        printf '%s' "$v" > "$SHIM_STORE/$s/.var"
        if [ "$old" = "$v" ]; then
            printf '{"name":"%s","outcome":"attached","rebound":{},"state":"x"}\n' "$s"
        else
            printf '{"name":"%s","outcome":"attached","rebound":{"REVIEW_LEVEL":"%s"},"state":"x"}\n' "$s" "$v"
        fi
        ;;
    workflows)
        ls "$SHIM_STORE" | jq -R '{name: .}' | jq -s .
        ;;
    status)
        printf '{"template_path":"%s"}\n' "$SHIM_STORE/$2/.tpl.json"
        ;;
    overrides)
        if [ -f "$SHIM_STORE/$3/.overrides" ]; then cat "$SHIM_STORE/$3/.overrides"
        else echo '{"overrides":{"count":0,"items":[]}}'; fi
        ;;
    *) echo "koto shim: unsupported: $*" >&2; exit 2 ;;
esac
SHIM
chmod +x "$SHIM_BIN/koto"
export SHIM_STORE

# --- helpers ------------------------------------------------------------------

RC=0
OUT=""
ERR=""
# run <args...>: the script in $FX/repo through the stand-in.
run() {
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" "$SCRIPT" "$@" 2>"$WORKDIR/stderr")
    RC=$?
    ERR=$(cat "$WORKDIR/stderr")
}

expect_rc() {
    # $1 label, $2 expected
    if [ "$RC" -eq "$2" ]; then pass "$1: exit $2"; else fail "$1: exit $RC, expected $2 (out: $OUT; err: $ERR)"; fi
}

expect_out() {
    # $1 label, $2 substring of stdout
    case "$OUT" in *"$2"*) pass "$1" ;; *) fail "$1: stdout [$OUT] lacks [$2]" ;; esac
}

store() { printf '%s' "$SHIM_STORE/$SESSION/$1"; }
ledger() { cat "$(store review_level.jsonl)" 2>/dev/null; }
var() { cat "$(store .var)" 2>/dev/null; }
# events: the ledger's events, space-separated.
events() { ledger | jq -r '.event' | tr '\n' ' ' | sed 's/ $//'; }
last_level() {
    ledger | jq -r 'select(.event == "choose" or .event == "raise" or .event == "lower"
                           or .event == "floor_raise" or .event == "veto") | .to' | tail -n 1
}

# agree <label>: the variable and the ledger's last level are the same.
agree() {
    local v l
    v=$(var); l=$(last_level)
    [ "$v" = "$l" ] && pass "$1: variable and ledger agree at [${v:-unset}]" \
        || fail "$1: variable is [$v], ledger's last level is [$l]"
}

FX=""
SESSION=""
BASE=""
# fixture <name>: a repository with a base commit (docs/readme.md of 60 lines,
# scripts/old.sh, docs/other.md) and impl_base recorded at it. The session is
# the fixture's name; context.md holds an acceptance-criteria section.
fixture() {
    FX="$WORKDIR/fx-$1"
    SESSION="$1"
    mkdir -p "$FX/repo"
    (
        cd "$FX/repo" || exit 1
        git init -q -b main .
        mkdir -p docs scripts
        seq 1 60 > docs/readme.md
        seq 1 10 > scripts/old.sh
        seq 1 10 > docs/other.md
        git add -A && git commit -q -m init
    ) >/dev/null 2>&1
    BASE=$(cd "$FX/repo" && git rev-parse HEAD)
    mkdir -p "$SHIM_STORE/$SESSION"
    printf '%s\n' "$BASE" > "$(store impl_base)"
    printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] it works\n\n## Notes\n\nfree text\n' > "$(store context.md)"
    printf '{"name":"work-on"}\n' > "$(store .tpl.json)"
}

# commit <message> <command>: runs the command in the fixture and commits.
commit() {
    (cd "$FX/repo" && eval "$2" && git add -A && git commit -q -m "$1") >/dev/null 2>&1 \
        || fail "setup: commit [$1] failed"
}

# setfacts <floor>: a recorded facts key at HEAD with the given floor.
setfacts() {
    local head
    head=$(cd "$FX/repo" && git rev-parse HEAD)
    jq -nc --arg f "$1" --arg h "$head" '{lines:1, files:1, classes:[], tests_changed:false,
        criteria_changed:false, floor:$f, rule:"lines>40", rules_fired:[], head:$h}' > "$(store review_facts.json)"
}

fact() { jq -c "$1" "$(store review_facts.json)" 2>/dev/null; }

# ==============================================================================
echo "--- script: the rules file"

fixture rules
run init "$SESSION" "" ""
expect_rc "the shipped rules file loads" 0
cmp -s "$(store review_level_rules.tsv)" "$RULES" && pass "init stores a copy of the shipped rules" \
    || fail "review_level_rules.tsv is not the shipped file"
grep -q "^class	security	skills/work-on/references/review-level-rules.tsv$" "$RULES" \
    && pass "the rules file is in the security class" || fail "the rules file is not in the security class"

badrules() {
    # $1 label, $2 line appended to the shipped rules
    local f="$WORKDIR/bad-rules.tsv"
    cp "$RULES" "$f"
    printf '%s\n' "$2" >> "$f"
    fixture "bad-$3"
    OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" REVIEW_LEVEL_RULES="$f" "$SCRIPT" init "$SESSION" "" "" 2>"$WORKDIR/stderr")
    RC=$?; ERR=$(cat "$WORKDIR/stderr")
    expect_rc "$1" 64
    [ ! -f "$(store review_level.jsonl)" ] && pass "$1: no bound line written" || fail "$1: a ledger was written"
}
badrules "an unknown record type" "$(printf 'path\tci\tx/**')" type
badrules "an unknown level" "$(printf 'rule\theavy\tlines>1')" level
badrules "an unknown fact" "$(printf 'rule\tfull\tauthors>3')" fact
badrules "a rule naming an undefined class" "$(printf 'rule\tfull\tclass:docs')" class
badrules "a non-numeric threshold" "$(printf 'rule\tfull\tlines>many')" threshold

# ==============================================================================
echo "--- script: init"

fixture init
run init "$SESSION" standard full
expect_rc "init" 0
[ "$(events)" = bound ] && pass "init appends one bound line" || fail "ledger events are [$(events)]"
GOT=$(ledger | jq -c '{floor, ceiling}')
[ "$GOT" = '{"floor":"standard","ceiling":"full"}' ] && pass "the bound line carries the bound" || fail "bound line is $GOT"
GOT=$(jq -c . "$(store review_level_bound.json)")
[ "$GOT" = '{"floor":"standard","ceiling":"full"}' ] && pass "review_level_bound.json holds the bound" || fail "bound key is $GOT"
GOT=$(cat "$(store review_level_criteria.txt)")
case "$GOT" in
    *"it works"*) case "$GOT" in *"free text"*) fail "criteria copy runs past its section: [$GOT]" ;;
                    *) pass "review_level_criteria.txt holds the acceptance-criteria section" ;; esac ;;
    *) fail "criteria copy is [$GOT]" ;;
esac
ADDS=$(wc -l < "$(store .addlog)")
LEDGER_BEFORE=$(ledger)
run init "$SESSION" light light
expect_rc "a second init" 0
[ "$(wc -l < "$(store .addlog)")" -eq "$ADDS" ] && pass "a second init writes nothing" \
    || fail "a second init wrote $(( $(wc -l < "$(store .addlog)") - ADDS )) keys"
[ "$(ledger)" = "$LEDGER_BEFORE" ] && pass "a second init leaves the ledger as it was" || fail "a second init changed the ledger"

fixture init-empty
run init "$SESSION" "" ""
GOT=$(ledger | jq -c '{floor, ceiling}')
[ "$GOT" = '{"floor":null,"ceiling":null}' ] && pass "an empty bound is recorded as none" || fail "empty bound line is $GOT"
run init "$SESSION" heavy ""
expect_rc "init with a floor that isn't a level" 64

# ==============================================================================
echo "--- script: set"

fixture set-early
run set "$SESSION" light --reason x
expect_rc "set before init" 1
expect_out "set before init names the rule" "refused: no bound recorded yet"
[ -z "$(var)" ] && pass "set before init rebinds nothing" || fail "set before init rebound to [$(var)]"

fixture choose
run init "$SESSION" "" standard
run set "$SESSION" light --reason "one-line fix"
expect_rc "choose" 0
[ "$(events)" = "bound choose" ] && pass "choose appends a choose line" || fail "events are [$(events)]"
[ "$(var)" = light ] && pass "choose rebinds REVIEW_LEVEL" || fail "variable is [$(var)]"
GOT=$(ledger | tail -n 1 | jq -c '{to, reason}')
[ "$GOT" = '{"to":"light","reason":"one-line fix"}' ] && pass "the choose line carries the level and reason" || fail "choose line is $GOT"
agree "after choose"

run set "$SESSION" standard
expect_rc "a raise inside the bound with no reason" 0
[ "$(ledger | tail -n 1 | jq -c '[.event, .from, .to]')" = '["raise","light","standard"]' ] \
    && pass "the raise line names from and to" || fail "last line is $(ledger | tail -n 1)"
agree "after raise"

LB=$(ledger)
run set "$SESSION" full
expect_rc "a raise above the ceiling with no reason" 1
expect_out "the refusal names the ceiling" "refused: full is above the ceiling standard"
[ "$(ledger)" = "$LB" ] && [ "$(var)" = standard ] && pass "a refused raise changes nothing" || fail "a refused raise changed something"

run set "$SESSION" full --reason "touches the gate logic"
expect_rc "a raise above the ceiling with a reason" 0
[ "$(events)" = "bound choose raise raise breach" ] && pass "it adds raise and breach" || fail "events are [$(events)]"
agree "after a breach"

fixture floor-raise
run init "$SESSION" "" light
run set "$SESSION" light
setfacts full
run set "$SESSION" full
expect_rc "a raise to exactly the facts floor above the ceiling, no reason" 0
[ "$(events)" = "bound choose floor_raise breach" ] && pass "it adds floor_raise and breach" || fail "events are [$(events)]"
[ "$(ledger | jq -r 'select(.event == "floor_raise") | .rule')" = "lines>40" ] \
    && pass "the floor_raise line names the rule" || fail "floor_raise line is $(ledger | jq -c 'select(.event == "floor_raise")')"
agree "after a floor raise"

fixture veto
run init "$SESSION" "" ""
run set "$SESSION" light
run set "$SESSION" standard --cause veto:level_fits_facts
expect_rc "a veto raise" 0
GOT=$(ledger | tail -n 1 | jq -c '[.event, .to, .rule]')
[ "$GOT" = '["veto","standard","level_fits_facts"]' ] && pass "--cause veto writes a veto line naming the criterion" || fail "veto line is $GOT"
run set "$SESSION" full --cause blame:x
expect_rc "a --cause that isn't veto:" 64

echo "--- script: lowering"

fixture lower
run init "$SESSION" light ""
run set "$SESSION" full
LB=$(ledger)
run set "$SESSION" standard
expect_rc "a lower with no reason" 1
expect_out "the refusal says a reason is needed" "refused: lowering full to standard needs --reason"
[ "$(ledger)" = "$LB" ] && [ "$(var)" = full ] && pass "a refused lower changes nothing" || fail "a refused lower changed something"
run set "$SESSION" standard --reason "   "
expect_rc "a lower with a blank reason" 1
run set "$SESSION" standard --reason "scope is one file"
expect_rc "a lower with a reason" 0
GOT=$(ledger | tail -n 1 | jq -c '[.event, .from, .to, .reason]')
[ "$GOT" = '["lower","full","standard","scope is one file"]' ] && pass "the lower line keeps the reason" || fail "lower line is $GOT"
agree "after lower"
setfacts standard
LB=$(ledger)
run set "$SESSION" light --reason "small"
expect_rc "a lower below the facts floor, with a reason" 1
expect_out "it names the facts floor" "below the facts floor standard"
[ "$(ledger)" = "$LB" ] && [ "$(var)" = standard ] && pass "the refused lower changes nothing" || fail "the refused lower changed something"

fixture lower-bound
run init "$SESSION" standard ""
run set "$SESSION" full
run set "$SESSION" light --reason "small"
expect_rc "a lower below the bound floor, with a reason" 1
expect_out "it names the bound floor" "below the bound's floor standard"

echo "--- script: the bound at the first choice"

fixture out-of-bound
run init "$SESSION" standard full
run set "$SESSION" light --reason x
expect_rc "a first choice below the bound" 1
expect_out "it names the level and the bound" "refused: light is below the bound's floor standard"
fixture out-of-bound-high
run init "$SESSION" "" standard
run set "$SESSION" full --reason x
expect_rc "a first choice above the bound" 1
expect_out "it names the level and the ceiling" "refused: full is above the bound's ceiling standard"
fixture inverted
run init "$SESSION" full light
for l in light standard full; do
    run set "$SESSION" "$l" --reason x
    expect_rc "choice $l under a floor-full ceiling-light bound" 1
    expect_out "the refusal names both values ($l)" "refused: the bound's floor full is above its ceiling light"
done
[ "$(events)" = bound ] && pass "an inverted bound records no choice" || fail "events are [$(events)]"

echo "--- script: koto failures"

fixture rebind-fails
run init "$SESSION" "" ""
run set "$SESSION" light
LB=$(ledger)
OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" SHIM_FAIL_INIT=1 "$SCRIPT" set "$SESSION" standard 2>"$WORKDIR/stderr"); RC=$?; ERR=$(cat "$WORKDIR/stderr")
expect_rc "a failed rebind" 66
[ "$(ledger)" = "$LB" ] && pass "a failed rebind writes no ledger line" || fail "a failed rebind changed the ledger"
agree "after a failed rebind"

fixture ledger-fails
run init "$SESSION" "" ""
run set "$SESSION" light
LB=$(ledger)
OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" SHIM_FAIL_ADD=review_level.jsonl "$SCRIPT" set "$SESSION" standard 2>"$WORKDIR/stderr"); RC=$?; ERR=$(cat "$WORKDIR/stderr")
expect_rc "a failed ledger write after a rebind" 66
[ "$(ledger)" = "$LB" ] && pass "the ledger is unchanged" || fail "the ledger changed"
[ "$(tail -n 2 "$(store .initlog)" | tr '\n' ' ')" = "standard light " ] \
    && pass "the variable was rebound to standard, then back to light" \
    || fail "rebinds were [$(tr '\n' ' ' < "$(store .initlog)")]"
agree "after a failed ledger write"

echo "--- script: the reason is cleaned"

fixture reason
run init "$SESSION" "" ""
run set "$SESSION" light --reason "$(printf 'a\tb\nc\001d\177e')"
GOT=$(ledger | tail -n 1 | jq -r .reason)
[ "$GOT" = "a b c d e" ] && pass "control characters become spaces" || fail "stored reason is [$GOT]"
LONG=$(printf '%0300d' 0)
run set "$SESSION" standard --reason "$LONG"
GOT=$(ledger | tail -n 1 | jq -r '.reason | length')
[ "$GOT" = 200 ] && pass "a reason is cut to 200 characters" || fail "stored reason has $GOT characters"

echo "--- script: an equal set rebinds a drifted variable"

fixture equal
run init "$SESSION" "" ""
run set "$SESSION" standard
printf 'full' > "$(store .var)"
LB=$(ledger)
run set "$SESSION" standard
expect_rc "a set to the ledger's level" 0
[ "$(ledger)" = "$LB" ] && pass "it appends nothing" || fail "it appended [$(ledger | tail -n 1)]"
agree "after a set to the ledger's level"

# ==============================================================================
echo "--- script: facts on fixture commits"

# facts_case <name> <setup command> <expected jq projection>
facts_case() {
    fixture "facts-$1"
    run init "$SESSION" "" ""
    commit "$1" "$2"
    run facts "$SESSION" light
    if [ "$RC" -ne 0 ]; then fail "facts $1: exit $RC ($ERR)"; return; fi
    local got
    got=$(fact '{lines, files, classes, tests_changed, criteria_changed, floor}')
    [ "$got" = "$3" ] && pass "facts $1: $got" || fail "facts $1: got $got, expected $3"
}

facts_case docs 'printf "x\n" >> docs/readme.md' \
    '{"lines":1,"files":1,"classes":[],"tests_changed":false,"criteria_changed":false,"floor":"light"}'
facts_case ci 'mkdir -p .github/workflows && printf "on: push\n" > .github/workflows/ci.yml' \
    '{"lines":1,"files":1,"classes":["ci"],"tests_changed":false,"criteria_changed":false,"floor":"full"}'
facts_case ci-action 'mkdir -p .github/actions/a && printf "x\n" > .github/actions/a/action.yml' \
    '{"lines":1,"files":1,"classes":["ci"],"tests_changed":false,"criteria_changed":false,"floor":"full"}'
facts_case security-hooks 'mkdir -p plug/hooks && printf "x\n" > plug/hooks/pre.sh' \
    '{"lines":1,"files":1,"classes":["security"],"tests_changed":false,"criteria_changed":false,"floor":"full"}'
facts_case security-settings 'printf "{}\n" > settings.local.json' \
    '{"lines":1,"files":1,"classes":["security"],"tests_changed":false,"criteria_changed":false,"floor":"full"}'
facts_case security-token 'printf "x\n" > docs/token-notes.md' \
    '{"lines":1,"files":1,"classes":["security"],"tests_changed":false,"criteria_changed":false,"floor":"full"}'
facts_case security-rules 'mkdir -p skills/work-on/references && printf "x\n" > skills/work-on/references/review-level-rules.tsv' \
    '{"lines":1,"files":1,"classes":["security"],"tests_changed":false,"criteria_changed":false,"floor":"full"}'
facts_case template 'mkdir -p skills/a/koto-templates && printf "x\n" > skills/a/koto-templates/a.md' \
    '{"lines":1,"files":1,"classes":["template"],"tests_changed":false,"criteria_changed":false,"floor":"standard"}'
facts_case executable 'printf "y\n" >> scripts/old.sh' \
    '{"lines":1,"files":1,"classes":["executable"],"tests_changed":false,"criteria_changed":false,"floor":"standard"}'
facts_case test 'mkdir -p lib && printf "x\n" > lib/a_test.go' \
    '{"lines":1,"files":1,"classes":["test"],"tests_changed":true,"criteria_changed":false,"floor":"standard"}'
facts_case criteria-plan 'mkdir -p docs/plans && printf "x\n" > docs/plans/PLAN-x.md' \
    '{"lines":1,"files":1,"classes":[],"tests_changed":false,"criteria_changed":true,"floor":"standard"}'
# Both sides of a rename are classified: scripts/old.sh moved under docs/ is
# still an executable change. A rename is one file plus its changed lines.
facts_case rename 'git mv scripts/old.sh docs/old.txt' \
    '{"lines":0,"files":1,"classes":["executable"],"tests_changed":false,"criteria_changed":false,"floor":"standard"}'
facts_case rename-edit 'git mv docs/readme.md docs/guide.md && printf "x\n" >> docs/guide.md' \
    '{"lines":1,"files":1,"classes":[],"tests_changed":false,"criteria_changed":false,"floor":"light"}'
facts_case deletion 'git rm -q docs/other.md' \
    '{"lines":10,"files":1,"classes":[],"tests_changed":false,"criteria_changed":false,"floor":"light"}'

fixture facts-criteria-text
run init "$SESSION" "" ""
commit docs 'printf "x\n" >> docs/readme.md'
printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] it works\n- [ ] and more\n' > "$(store context.md)"
run facts "$SESSION" light
[ "$(fact .criteria_changed)" = true ] && [ "$(fact .floor)" = '"standard"' ] \
    && pass "acceptance criteria that differ from the stored copy are a change" \
    || fail "criteria_changed is $(fact .criteria_changed), floor $(fact .floor)"

fixture facts-notes
run init "$SESSION" "" ""
commit docs 'printf "x\n" >> docs/readme.md'
printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] it works\n\n## Notes\n\nother text\n' > "$(store context.md)"
run facts "$SESSION" light
[ "$(fact .criteria_changed)" = false ] && pass "text outside the criteria section is not a criteria change" \
    || fail "criteria_changed is $(fact .criteria_changed)"

fixture facts-stored-rules
run init "$SESSION" "" ""
commit docs 'printf "x\n" >> docs/readme.md'
sed 's/^rule	standard	lines>40$/rule	standard	lines>0/' "$RULES" > "$WORKDIR/edited-rules.tsv"
OUT=$(cd "$FX/repo" && PATH="$SHIM_BIN:$PATH" REVIEW_LEVEL_RULES="$WORKDIR/edited-rules.tsv" "$SCRIPT" facts "$SESSION" light 2>&1); RC=$?
[ "$(fact .floor)" = '"light"' ] && pass "facts classifies with the stored rules copy, not the current file" \
    || fail "floor is $(fact .floor) with the rules file edited after init"

echo "--- script: thresholds"

# threshold_case <label> <command> <expected floor>
threshold_case() {
    fixture "th-$1"
    run init "$SESSION" "" ""
    commit "$1" "$2"
    run facts "$SESSION" light
    local got
    got=$(jq -r .floor "$(store review_facts.json)" 2>/dev/null)
    [ "$got" = "$3" ] && pass "threshold $1: floor $got" || fail "threshold $1: floor [$got], expected $3 ($(fact '{lines, files}'))"
}
threshold_case lines-40 'seq 1 40 > docs/new.md' light
threshold_case lines-41 'seq 1 41 > docs/new.md' standard
threshold_case lines-400 'seq 1 400 > docs/new.md' standard
threshold_case lines-401 'seq 1 401 > docs/new.md' full
threshold_case files-12 'for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo x > docs/f$i.md; done' light
threshold_case files-13 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do echo x > docs/f$i.md; done' full
threshold_case standard-and-full 'mkdir -p .github/workflows a/koto-templates && echo x > .github/workflows/w.yml && echo x > a/koto-templates/t.md' full

fixture th-edited-copy
run init "$SESSION" "" ""
commit twenty 'seq 1 20 > docs/new.md'
run facts "$SESSION" light
BEFORE=$(fact 'del(.floor, .rule, .rules_fired)')
FLOOR_BEFORE=$(jq -r .floor "$(store review_facts.json)")
sed 's/^rule	standard	lines>40$/rule	standard	lines>10/' "$(store review_level_rules.tsv)" > "$WORKDIR/copy.tsv"
cp "$WORKDIR/copy.tsv" "$(store review_level_rules.tsv)"
run facts "$SESSION" light
AFTER=$(fact 'del(.floor, .rule, .rules_fired)')
FLOOR_AFTER=$(jq -r .floor "$(store review_facts.json)")
[ "$FLOOR_BEFORE" = light ] && [ "$FLOOR_AFTER" = standard ] \
    && pass "editing one threshold in the rules copy changes the floor (light -> standard)" \
    || fail "floor went $FLOOR_BEFORE -> $FLOOR_AFTER"
[ "$BEFORE" = "$AFTER" ] && pass "and no other fact changes" || fail "facts changed: $BEFORE -> $AFTER"

echo "--- script: facts ledger lines"

fixture facts-lines
run init "$SESSION" "" ""
run set "$SESSION" light
commit docs 'printf "x\n" >> docs/readme.md'
run facts "$SESSION" light
run facts "$SESSION" light
[ "$(events)" = "bound choose check" ] && pass "two ticks at one head, level and floor write one check line" || fail "events are [$(events)]"
GOT=$(ledger | tail -n 1 | jq -c '{level, floor}')
[ "$GOT" = '{"level":"light","floor":"light"}' ] && pass "the check line carries level and floor" || fail "check line is $GOT"
run facts "$SESSION" standard
[ "$(events)" = "bound choose check check" ] && pass "a new level writes a check line" || fail "events are [$(events)]"
commit more 'seq 1 50 >> docs/readme.md'
run facts "$SESSION" standard
[ "$(events)" = "bound choose check check check" ] && pass "a new head writes a check line" || fail "events are [$(events)]"
run facts "$SESSION" ""
[ "$(events)" = "bound choose check check check unset" ] && pass "an empty level writes an unset line" || fail "events are [$(events)]"
run facts "$SESSION" bogus
expect_rc "facts with a level that isn't one" 64

# ==============================================================================
echo "--- script: check"

fixture check
run init "$SESSION" "" standard
run set "$SESSION" light
commit exe 'printf "y\n" >> scripts/old.sh'
run facts "$SESSION" light
run check "$SESSION" light
expect_rc "check below the floor" 1
expect_out "the hold names the rule" "hold: level light is below the facts floor standard (rule class:executable)"
run set "$SESSION" standard
run facts "$SESSION" standard
run check "$SESSION" standard
expect_rc "check at the floor" 0
[ "$(ledger | jq -r 'select(.event == "floor_raise") | [.from, .to, .rule] | join(" ")')" = "light standard class:executable" ] \
    && pass "the raise to the floor is a floor_raise naming the rule" || fail "ledger: $(events)"
run check "$SESSION" full
expect_rc "check when the level differs from the ledger" 1
expect_out "the hold names both levels" "REVIEW_LEVEL is full but the ledger's last level is standard"
run check "$SESSION" ""
expect_rc "check with an empty level over a ledger that has one" 1
expect_out "the hold names the ledger's level" "REVIEW_LEVEL is empty but the ledger's last level is standard"
cp "$(store review_level.jsonl)" "$WORKDIR/ledger.keep"
grep '"event":"bound"' "$WORKDIR/ledger.keep" > "$(store review_level.jsonl)"
run check "$SESSION" ""
expect_rc "check with an empty level and no level in the ledger" 3
[ -z "$OUT" ] && pass "the unset exit prints nothing" || fail "the unset exit printed [$OUT]"
cp "$WORKDIR/ledger.keep" "$(store review_level.jsonl)"
commit later 'printf "z\n" >> docs/readme.md'
run check "$SESSION" standard
expect_rc "check when the facts were gathered at another head" 1
expect_out "the hold names the head" "not HEAD"

fixture check-above
run init "$SESSION" "" light
run set "$SESSION" light
commit docs 'printf "x\n" >> docs/readme.md'
# A ledger edited by hand past the ceiling, with no breach line.
printf '{"ts":"2026-01-01T00:00:00Z","event":"raise","from":"light","to":"standard"}\n' >> "$(store review_level.jsonl)"
run facts "$SESSION" standard
run check "$SESSION" standard
expect_rc "check above the ceiling with no breach" 1
expect_out "the hold names the ceiling" "above the bound's ceiling light with no breach recorded"

fixture check-crossed
run init "$SESSION" full light
run set "$SESSION" light
expect_rc "set under a floor-above-ceiling bound" 1
# A level that got past set some other way: the check holds rather than judge
# it against a contradictory bound.
printf '{"ts":"2026-01-01T00:00:00Z","event":"choose","to":"full"}\n' >> "$(store review_level.jsonl)"
commit docs 'printf "x\n" >> docs/readme.md'
run facts "$SESSION" full
run check "$SESSION" full
expect_rc "check under a bound whose floor is above its ceiling" 1
expect_out "the hold names both bound values" "hold: the bound's floor full is above its ceiling light"

fixture check-above-breach
run init "$SESSION" "" light
run set "$SESSION" light
run set "$SESSION" standard --reason "riskier than it looked"
commit docs 'printf "x\n" >> docs/readme.md'
run facts "$SESSION" standard
run check "$SESSION" standard
expect_rc "check above the ceiling with a breach recorded" 0

# ==============================================================================
echo "--- script: slice"

fixture slice
run init "$SESSION" "" ""
printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] zzcriteriazz\n' > "$(store context.md)"
run set "$SESSION" light --reason zzreasonzz
commit zz 'mkdir -p zzpathzz && seq 1 5 > zzpathzz/zzfilezz.sh'
run facts "$SESSION" light
run slice "$SESSION" light
expect_rc "slice" 0
for leak in zzpathzz zzfilezz zzreasonzz zzcriteriazz "$BASE"; do
    case "$OUT" in *"$leak"*) fail "slice prints [$leak]" ;; *) pass "slice doesn't print [$leak]" ;; esac
done
[ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "level: light" ] && pass "slice ends with the level line" || fail "slice is [$OUT]"
GOT=$(printf '%s\n' "$OUT" | sed -n 1p | jq -c 'keys')
[ "$GOT" = '["classes","criteria_changed","files","floor","lines","tests_changed"]' ] \
    && pass "slice's first line is the fixed projection" || fail "slice keys are $GOT"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2 ] && pass "slice prints two lines" || fail "slice printed [$OUT]"

# ==============================================================================
echo "--- script: report"

REPORT_HEADER="$(printf 'session\tchosen\tfinal\tfloor\tceiling\traises\tlowers\tfloor_raises\tvetoes\tbreaches\toverrides\tseats')"
ts='"ts":"2026-01-01T00:00:00Z"'
fixture rep-full
cat > "$(store review_level.jsonl)" <<EOF
{$ts,"event":"bound","floor":"light","ceiling":"standard"}
{$ts,"event":"choose","to":"light"}
{$ts,"event":"check","level":"light","floor":"standard","head":"a"}
{$ts,"event":"floor_raise","from":"light","to":"standard","rule":"lines>40"}
{$ts,"event":"check","level":"standard","floor":"standard","head":"a"}
{$ts,"event":"raise","from":"standard","to":"full"}
{$ts,"event":"breach","from":"standard","to":"full","ceiling":"standard","reason":"x"}
{$ts,"event":"lower","from":"full","to":"standard","reason":"y"}
{$ts,"event":"veto","from":"standard","to":"full","rule":"level_fits_facts"}
{$ts,"event":"check","level":"light","floor":"full","head":"b"}
EOF
printf '{"history":[{"panel":"scrutiny","round":1,"spawned":3},{"panel":"review","round":1,"spawned":3},{"panel":"scrutiny","round":2,"spawned":1}]}\n' \
    > "$(store verdict_ledger.json)"
printf '{"overrides":{"count":3,"items":[{"gate":"level_floor"},{"gate":"level_fits_facts"},{"gate":"has_commits"}]},"state":"x"}\n' \
    > "$(store .overrides)"
fixture rep-none
fixture rep-corrupt
printf '{%s,"event":"choose","to":"light"}\nnot json\n' "$ts" > "$(store review_level.jsonl)"
fixture rep-docs
printf '{%s,"event":"bound","floor":null,"ceiling":null}\n{%s,"event":"choose","to":"light"}\n' "$ts" "$ts" > "$(store review_level.jsonl)"
fixture rep-escape
printf '{%s,"event":"bound","floor":"a\\tb\\nc\\u0001d\\\\e","ceiling":null}\n{%s,"event":"choose","to":"x\\ty"}\n' "$ts" "$ts" \
    > "$(store review_level.jsonl)"
fixture rep-other
printf '{"name":"execute"}\n' > "$(store .tpl.json)"

FX="$WORKDIR/fx-rep-full"
run report rep-full
expect_rc "report of a named session" 0
[ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "$REPORT_HEADER" ] && pass "report prints the header" || fail "header is [$(printf '%s\n' "$OUT" | sed -n 1p)]"
GOT=$(printf '%s\n' "$OUT" | sed -n 2p)
EXP="$(printf 'rep-full\tlight\tstandard\tlight\tstandard\t1\t1\t1\t1\t1\t2\t7')"
[ "$GOT" = "$EXP" ] && pass "a full ledger's row: chosen, final at the last passing check, bound, counts, overrides, seats" \
    || fail "row is [$GOT], expected [$EXP]"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2 ] && pass "a named session prints one row" || fail "report printed [$OUT]"

run report rep-none rep-docs
GOT=$(printf '%s\n' "$OUT" | sed -n 2p | cut -f1-5)
[ "$GOT" = "$(printf 'rep-none\tnone\t-\t-\t-')" ] && pass "a session with no ledger reads none" || fail "row is [$GOT]"
GOT=$(printf '%s\n' "$OUT" | sed -n 3p | cut -f1-5)
[ "$GOT" = "$(printf 'rep-docs\tlight\t-\t-\t-')" ] && pass "a run with no passing check reports final as -" || fail "row is [$GOT]"

OUT=$(cd "$FX/repo" && SHIM_FAIL_GET=review_level.jsonl PATH="$SHIM_BIN:$PATH" "$SCRIPT" report rep-docs rep-full 2>/dev/null)
RC=$?
expect_rc "report with a ledger it can't read" 2
[ "$(printf '%s\n' "$OUT" | sed -n 2p | cut -f1-2)" = "$(printf 'rep-docs\tunreadable')" ] \
    && pass "an unreadable ledger reads unreadable, not none" || fail "row is [$(printf '%s\n' "$OUT" | sed -n 2p)]"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 3 ] && pass "the rows after an unreadable one still print" \
    || fail "report printed [$OUT]"

run report rep-corrupt rep-full
expect_rc "report with a corrupt ledger" 2
[ "$(printf '%s\n' "$OUT" | sed -n 2p | cut -f1-2)" = "$(printf 'rep-corrupt\tcorrupt')" ] \
    && pass "a corrupt line reads corrupt" || fail "row is [$(printf '%s\n' "$OUT" | sed -n 2p)]"
[ "$(printf '%s\n' "$OUT" | sed -n 3p | cut -f1)" = rep-full ] && pass "the rows after a corrupt one still print" \
    || fail "report printed [$OUT]"

run report rep-escape
GOT=$(printf '%s\n' "$OUT" | sed -n 2p)
EXP='rep-escape	x\ty	-	a\tb\nc\x01d\\e	-	0	0	0	0	0	0	0'
[ "$GOT" = "$EXP" ] && pass "tabs, newlines, backslashes and control characters are escaped" || fail "row is [$GOT], expected [$EXP]"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2 ] && pass "an escaped row is one line" || fail "report printed [$OUT]"

run report
case "$OUT" in *rep-other*) fail "report lists a session whose template isn't work-on" ;; *) pass "report skips other templates" ;; esac
case "$OUT" in *"rep-full	light	standard"*) pass "report with no session lists work-on sessions" ;; *) fail "report printed [$OUT]" ;; esac
expect_rc "report of every session, one corrupt" 2

# ==============================================================================
echo "--- script: usage"

run bogus;                 expect_rc "an unknown subcommand" 64
run set "bad name" light;  expect_rc "a session name koto wouldn't take" 64
run set "$SESSION" heavy;  expect_rc "set to a level that isn't one" 64
run set "$SESSION" light --frobnicate; expect_rc "an unknown set flag" 64

# ==============================================================================
echo "--- script: every ledger line is well-formed"

BAD=0
LINES=0
for f in "$SHIM_STORE"/*/review_level.jsonl; do
    case "$f" in */rep-*) continue ;; esac
    while IFS= read -r l; do
        LINES=$((LINES + 1))
        printf '%s\n' "$l" | jq -e '
            type == "object"
            and (.ts | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
            and (.event | IN("bound","choose","raise","lower","floor_raise","veto","breach","check","unset"))
        ' >/dev/null 2>&1 || { BAD=$((BAD + 1)); echo "  bad line in $f: $l"; }
    done < "$f"
done
[ "$BAD" -eq 0 ] && [ "$LINES" -gt 0 ] && pass "all $LINES ledger lines the script wrote parse, with a UTC ts and a known event" \
    || fail "$BAD of $LINES ledger lines are malformed"

# ==============================================================================
# --- engine cases -------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- engine cases did not run"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

# A scratch template named work-on, standing in for the real one until the
# level states land in it. REVIEW_LEVEL is declared the way the design says.
# koto runs each command through sh -c, so the script path is quoted in it.
RL="$SCRIPT"
TPL="$WORKDIR/scratch-work-on.md"
cat > "$TPL" <<EOF
---
name: work-on
version: "1.0"
description: scratch stand-in for the review level states
initial_state: start
variables:
  REVIEW_LEVEL:
    description: the run's review level
    required: false
    rebind: true
    pattern: "^(light|standard|full)?\$"
  REVIEW_FLOOR:
    description: bound floor
    required: false
    pattern: "^(light|standard|full)?\$"
  REVIEW_CEILING:
    description: bound ceiling
    required: false
    pattern: "^(light|standard|full)?\$"
states:
  start:
    accepts:
      entry:
        type: enum
        values: [choose, skip]
    transitions:
      - target: review_level_choice
        when:
          entry: choose
      - target: review_level_check
        when:
          entry: skip
  review_level_choice:
    default_action:
      command: '"$RL" init "{{SESSION_NAME}}" "{{REVIEW_FLOOR}}" "{{REVIEW_CEILING}}"'
    accepts:
      level_status:
        type: enum
        values: [blocked]
    transitions:
      - target: review_level_check
        when:
          vars.REVIEW_LEVEL: {is_set: true}
      - target: blocked
        when:
          vars.REVIEW_LEVEL: {is_set: false}
          level_status: blocked
  review_level_check:
    default_action:
      command: '"$RL" facts "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"'
    gates:
      level_floor:
        type: command
        command: '"$RL" check "{{SESSION_NAME}}" "{{REVIEW_LEVEL}}"'
    accepts:
      level_status:
        type: enum
        values: [blocked]
    transitions:
      - target: light_panel
        when:
          gates.level_floor.exit_code: 0
          vars.REVIEW_LEVEL: light
      - target: standard_panels
        when:
          gates.level_floor.exit_code: 0
          vars.REVIEW_LEVEL: standard
      - target: full_panels
        when:
          gates.level_floor.exit_code: 0
          vars.REVIEW_LEVEL: full
      - target: unset_panels
        when:
          gates.level_floor.exit_code: 3
          vars.REVIEW_LEVEL: {is_set: false}
      - target: blocked
        when:
          gates.level_floor.exit_code: 1
          level_status: blocked
  light_panel:
    terminal: true
  standard_panels:
    terminal: true
  full_panels:
    terminal: true
  unset_panels:
    terminal: true
  blocked:
    terminal: true
    failure: true
---

## start

Start.

## review_level_choice

Choose a level.

## review_level_check

Check the level.

## light_panel

Light.

## standard_panels

Standard.

## full_panels

Full.

## unset_panels

Unset.

## blocked

Blocked.
EOF

if ! koto template compile "$TPL" >/dev/null 2>"$WORKDIR/compile.err"; then
    fail "the scratch template does not compile: $(cat "$WORKDIR/compile.err")"
fi

STATE=""
NEXT_OUT=""
tick() {
    # $1 session, $2 optional evidence
    if [ -n "${2:-}" ]; then
        NEXT_OUT=$(koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        NEXT_OUT=$(koto next "$1" --no-cleanup 2>/dev/null)
    fi
    STATE=$(koto status "$1" 2>/dev/null | jq -r '.current_state // empty')
}

# kvar <session>: REVIEW_LEVEL as koto last bound it, from the session's log.
kvar() {
    jq -rs '[.[] | select(.type == "variables_rebound") | .payload.variables.REVIEW_LEVEL // empty] | last // ""' \
        "$HOME/.koto/sessions/$1/koto-$1.state.jsonl" 2>/dev/null
}
kledger() { koto context get "$1" review_level.jsonl 2>/dev/null; }
klevel() {
    kledger "$1" | jq -r 'select(.event == "choose" or .event == "raise" or .event == "lower"
                                 or .event == "floor_raise" or .event == "veto") | .to' | tail -n 1
}
kevents() { kledger "$1" | jq -r .event | tr '\n' ' ' | sed 's/ $//'; }
kagree() {
    local v l
    v=$(kvar "$1"); l=$(klevel "$1")
    [ "$v" = "$l" ] && pass "$2: koto's REVIEW_LEVEL and the ledger agree at [${v:-unset}]" \
        || fail "$2: koto's REVIEW_LEVEL is [$v], the ledger's last level is [$l]"
}
kset() {
    OUT=$(REVIEW_LEVEL_TEMPLATE="$TPL" "$RL" set "$@" 2>"$WORKDIR/stderr")
    RC=$?
    ERR=$(cat "$WORKDIR/stderr")
}

# engine_repo <name>: a fresh repository with impl_base at its first commit.
engine_repo() {
    mkdir -p "$WORKDIR/eng-$1"
    cd "$WORKDIR/eng-$1" || return 1
    git init -q -b main .
    mkdir -p docs scripts
    seq 1 10 > docs/readme.md
    seq 1 10 > scripts/run.sh
    git add -A && git commit -q -m init
}

echo "--- engine: choose, rebind, and the light route"

S=rl-light
engine_repo "$S"
koto init "$S" --template "$TPL" >/dev/null 2>&1 || fail "$S: koto init failed"
kset "$S" light --reason x
expect_rc "set before the choice state's init ran" 1
expect_out "it says no bound is recorded" "refused: no bound recorded yet"
tick "$S" '{"entry":"choose"}'
[ "$STATE" = review_level_choice ] && pass "with no level the run holds at the choice" || fail "the run is at [$STATE]"
[ "$(kevents "$S")" = bound ] && pass "the choice state's action recorded the bound" || fail "events are [$(kevents "$S")]"
git rev-parse HEAD | koto context add "$S" impl_base >/dev/null 2>&1
printf 'x\n' >> docs/readme.md && git commit -q -am "docs: one line"
kset "$S" light --reason "one-line docs fix"
expect_rc "set light on a live session" 0
[ "$(kvar "$S")" = light ] && pass "koto reports REVIEW_LEVEL rebound to light" || fail "koto's REVIEW_LEVEL is [$(kvar "$S")]"
kagree "$S" "after choose"
# A hand rebind past the ledger holds the check, naming both levels.
koto init "$S" --template "$TPL" --attach-live --var REVIEW_LEVEL=full >/dev/null 2>&1
tick "$S"
[ "$STATE" = review_level_check ] && pass "a hand rebind holds the level check" || fail "the run is at [$STATE]"
case "$NEXT_OUT" in
    *"REVIEW_LEVEL is full but the ledger's last level is light"*) pass "the hold names both levels" ;;
    *) fail "the hold doesn't name both levels: $NEXT_OUT" ;;
esac
kset "$S" light
expect_rc "set back to the ledger's level" 0
kagree "$S" "after clearing the hand rebind"
tick "$S"
[ "$STATE" = light_panel ] && pass "a light run under every threshold takes the light route" || fail "the run is at [$STATE]"

echo "--- engine: the floor holds a light run until it is raised"

S=rl-floor
engine_repo "$S"
koto init "$S" --template "$TPL" --var REVIEW_CEILING=light >/dev/null 2>&1 || fail "$S: koto init failed"
tick "$S" '{"entry":"choose"}'
git rev-parse HEAD | koto context add "$S" impl_base >/dev/null 2>&1
printf 'echo hi\n' >> scripts/run.sh && git commit -q -am "fix: script"
kset "$S" light
kagree "$S" "after choose under a light ceiling"
tick "$S"
[ "$STATE" = review_level_check ] && pass "a light run with a standard floor holds at the check" || fail "the run is at [$STATE]"
case "$NEXT_OUT" in
    *"below the facts floor standard (rule class:executable)"*) pass "the hold names the rule and the floor" ;;
    *) fail "the hold doesn't name the rule: $NEXT_OUT" ;;
esac
tick "$S"
[ "$(kevents "$S")" = "bound choose check" ] && pass "holding ticks at one head add no check lines" || fail "events are [$(kevents "$S")]"
kset "$S" standard
expect_rc "the raise to the floor above a light ceiling, no reason" 0
kagree "$S" "after the floor raise"
tick "$S"
[ "$STATE" = standard_panels ] && pass "after the raise the next tick takes the standard route" || fail "the run is at [$STATE]"
[ "$(kevents "$S")" = "bound choose check floor_raise breach check" ] \
    && pass "the ledger holds floor_raise, breach, then a check at standard" || fail "events are [$(kevents "$S")]"
[ "$(kledger "$S" | tail -n 1 | jq -c '[.level, .floor]')" = '["standard","standard"]' ] \
    && pass "the last check is at standard" || fail "last line: $(kledger "$S" | tail -n 1)"
kset "$S" light --reason "too much"
expect_rc "lowering below the facts floor on a live session" 1
kagree "$S" "after a refused lower"

echo "--- engine: full, and the unset route"

S=rl-full
engine_repo "$S"
koto init "$S" --template "$TPL" >/dev/null 2>&1
tick "$S" '{"entry":"choose"}'
git rev-parse HEAD | koto context add "$S" impl_base >/dev/null 2>&1
printf 'x\n' >> docs/readme.md && git commit -q -am "docs: x"
kset "$S" full
tick "$S"
[ "$STATE" = full_panels ] && pass "full takes the full route" || fail "the run is at [$STATE]"

S=rl-unset
engine_repo "$S"
koto init "$S" --template "$TPL" >/dev/null 2>&1
git rev-parse HEAD | koto context add "$S" impl_base >/dev/null 2>&1
printf 'x\n' >> docs/readme.md && git commit -q -am "docs: x"
tick "$S" '{"entry":"skip"}'
[ "$STATE" = unset_panels ] && pass "an unset level takes the unset route" || fail "the run is at [$STATE]"
[ "$(kevents "$S")" = unset ] && pass "the ledger records unset" || fail "events are [$(kevents "$S")]"

echo "--- engine: report"

cd "$WORKDIR/eng-rl-light" || exit 1
OUT=$("$RL" report rl-light rl-floor rl-unset 2>"$WORKDIR/stderr"); RC=$?
expect_rc "report on real sessions" 0
[ "$(printf '%s\n' "$OUT" | sed -n 2p | cut -f1-5)" = "$(printf 'rl-light\tlight\tlight\t-\t-')" ] \
    && pass "the light run reports chosen and final light" || fail "row is [$(printf '%s\n' "$OUT" | sed -n 2p)]"
[ "$(printf '%s\n' "$OUT" | sed -n 3p | cut -f1-10)" = "$(printf 'rl-floor\tlight\tstandard\t-\tlight\t0\t0\t1\t0\t1')" ] \
    && pass "the floor run reports final standard, the ceiling, one floor raise and one breach" \
    || fail "row is [$(printf '%s\n' "$OUT" | sed -n 3p)]"
[ "$(printf '%s\n' "$OUT" | sed -n 4p | cut -f1-3)" = "$(printf 'rl-unset\t-\t-')" ] \
    && pass "the unset run has a ledger but no choice and no final level" || fail "row is [$(printf '%s\n' "$OUT" | sed -n 4p)]"
OUT=$("$RL" report 2>/dev/null)
N=$(printf '%s\n' "$OUT" | grep -c '^rl-')
[ "$N" = 4 ] && pass "report with no session lists every work-on session koto reports" || fail "report listed $N sessions: $OUT"

echo "--- engine: every ledger line is well-formed"

BAD=0
for s in rl-light rl-floor rl-full rl-unset; do
    while IFS= read -r l; do
        printf '%s\n' "$l" | jq -e '
            (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
            and (.event | IN("bound","choose","raise","lower","floor_raise","veto","breach","check","unset"))
        ' >/dev/null 2>&1 || BAD=$((BAD + 1))
    done <<EOF
$(kledger "$s")
EOF
done
[ "$BAD" -eq 0 ] && pass "every engine ledger line parses with a UTC ts and a known event" || fail "$BAD engine ledger lines are malformed"

cd "$WORKDIR" || exit 1
echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

#!/usr/bin/env bash
# doc-criteria-wiring_test.sh -- do the five document juries call the
# criteria step where they should, and does a run that follows their phase
# files record the same thing with the step as without it?
#
# Two parts:
#
#   call sites  every doc-criteria.sh call in a skill's phase files, read from
#               the files, against the table below: ten calls, `grade` after
#               the pre-jury document check and before round-started,
#               `agreement` on the line right after the round's verdicts.
#   sessions    the commands themselves, taken line for line from the phase
#               files, run in the order a run takes them through two jury
#               rounds with a fix between, on a real koto in a scratch store,
#               with a stub validator, stub seats (the review-events
#               fixtures) and a loopback stub decider. Each skill runs with the
#               step and with its lines left out, standalone and under its
#               chain parent, and the runs are compared: the run session's
#               states, the document check's exit codes, and the jury rounds
#               and verdict records koto journals. With the step, the criteria
#               children are graded before each round and the agreement
#               recorded after each round's verdicts, on the parent run when
#               there is one.
#
# The criteria-agreement record isn't in an installed koto yet: a koto wrapper
# logs that call and passes every other call to the real koto, logging the
# order of the review records and the children's ticks.
#
# Usage: doc-criteria-wiring_test.sh
# Exit codes: 0 all pass (the sessions part skips without koto or python3),
# 1 any failed, 2 the harness could not run.

set -u
. "$(dirname "$0")/../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
PHASES="$ROOT_DIR/references/doc-check-phases.json"
FIX="$SCRIPT_DIR/fixtures/review-events"
STUB="$SCRIPT_DIR/fixtures/doc-criteria/stub-decider.py"
P=skills

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required to run this suite" >&2; exit 2; }
done

# ================================================================== call sites

arg() { printf '%s\n' "$1" | awk -v f="$2" '{ for (i = 1; i < NF; i++) if ($i == f) { print $(i + 1); exit } }'; }

# file|subcommand|format|skill|doc: every doc-criteria.sh call site.
EXPECTED="brief/references/phases/phase-4-validate.md|grade|brief|brief|docs/briefs/BRIEF-<topic>.md
brief/references/phases/phase-4-validate.md|agreement|brief|brief|
prd/references/phases/phase-4-validate.md|grade|prd|prd|docs/prds/PRD-<topic>.md
prd/references/phases/phase-4-validate.md|agreement|prd|prd|
design/references/phases/phase-6-final-review.md|grade|design|design|docs/designs/DESIGN-<topic>.md
design/references/phases/phase-6-final-review.md|agreement|design|design|
strategy/references/phases/phase-4-validate.md|grade|strategy|strategy|docs/strategies/STRATEGY-<topic>.md
strategy/references/phases/phase-4-validate.md|agreement|strategy|strategy|
roadmap/references/phases/phase-4-validate.md|grade|roadmap|roadmap|docs/roadmaps/ROADMAP-<topic>.md
roadmap/references/phases/phase-4-validate.md|agreement|roadmap|roadmap|"

found=$(cd "$ROOT_DIR/$P" && grep -rn --include='*.md' 'scripts/doc-criteria.sh" ' . | sed 's|^\./||' | while IFS= read -r hit; do
    file=${hit%%:*}
    line=${hit#*:}
    line=${line#*:}
    sub=$(printf '%s\n' "$line" | sed -n 's/.*doc-criteria\.sh" \([a-z]*\) .*/\1/p')
    printf '%s|%s|%s|%s|%s\n' "$file" "$sub" "$(arg "$line" --format)" "$(arg "$line" --skill)" "$(arg "$line" --doc)"
done | sort)
if [ "$found" = "$(printf '%s\n' "$EXPECTED" | sort)" ]; then
    pass "ten doc-criteria.sh call sites, each with its fixed subcommand, format, skill and canonical document, and no others"
else
    fail "call sites differ: $(diff <(printf '%s\n' "$EXPECTED" | sort) <(printf '%s\n' "$found") | grep '^[<>]' | tr '\n' ' ')"
fi
n=$(cd "$ROOT_DIR/$P" && grep -rn --include='*.md' 'scripts/doc-criteria.sh" ' . | grep -c -- '--round')
[ "$n" -eq 0 ] && pass "no call site fixes a round: agreement takes the round round-started opened" || fail "$n call sites pass --round"

line_of() { awk -v t="$2" -v a="${3:-0}" 'NR >= a && index($0, t) { print NR; exit }' "$ROOT_DIR/$P/$1"; }
for s in brief prd design strategy roadmap; do
    case "$s" in design) f=design/references/phases/phase-6-final-review.md ;; *) f=$s/references/phases/phase-4-validate.md ;; esac
    pre=$(line_of "$f" "--moment pre_jury")
    g=$(line_of "$f" 'doc-criteria.sh" grade ')
    r=$(line_of "$f" "review-events.sh\" round-started --skill $s ")
    v=$(line_of "$f" "review-events.sh\" verdicts --skill $s ")
    a=$(line_of "$f" 'doc-criteria.sh" agreement ')
    if [ -n "$pre" ] && [ -n "$g" ] && [ -n "$r" ] && [ "$pre" -lt "$g" ] && [ "$g" -lt "$r" ]; then
        pass "/$s: grade comes after the pre-jury check and before round-started"
    else
        fail "/$s: grade order [pre=$pre grade=$g round=$r]"
    fi
    if [ -n "$v" ] && [ -n "$a" ] && [ "$a" -eq $((v + 1)) ]; then
        pass "/$s: agreement is the line right after the round's verdicts"
    else
        fail "/$s: agreement order [verdicts=$v agreement=$a]"
    fi
done

# ================================================================== sessions

for tool in koto python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: sessions: $tool is not on PATH"
        echo
        echo "doc-criteria-wiring_test: $PASS_COUNT passed, $FAIL_COUNT failed"
        [ "$FAIL_COUNT" -eq 0 ]
        exit
    fi
done

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/doc-criteria-wiring-test.XXXXXX") || exit 2
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 2
STUB_PID=""
cleanup() {
    [ -z "$STUB_PID" ] || kill "$STUB_PID" 2>/dev/null
    case "${WORKDIR:-}" in */doc-criteria-wiring-test.*) rm -rf "$WORKDIR" ;; esac
    return 0
}
ktg_on_exit cleanup

# shellcheck source=lib/doc-check-testlib.sh
. "$SCRIPT_DIR/lib/doc-check-testlib.sh"
dct_setup "$WORKDIR"
export KOTO_SESSIONS_BASE="$HOME/.koto/sessions"
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT DOC_CRITERIA_DEADLINE
case "$(koto session dir 2>/dev/null)" in
    "$WORKDIR"/*) ;;
    *) echo "FAIL: koto session dir is not under the scratch directory; no session case ran"; exit 1 ;;
esac

mkdir -p "$WORKDIR/sd"
python3 -I "$STUB" "$WORKDIR/sd" &
STUB_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s "$WORKDIR/sd/port" ] && break
    sleep 0.25
done
[ -s "$WORKDIR/sd/port" ] || { echo "the stub decider did not start" >&2; exit 2; }
echo pass > "$WORKDIR/sd/mode"
export KOTO_DECIDER=shadow KOTO_DECIDER_API_KEY=doc-criteria-wiring-placeholder \
    KOTO_DECIDER_ENDPOINT="http://127.0.0.1:$(cat "$WORKDIR/sd/port")/v1/systemone"

REAL_KOTO=$(command -v koto)
ORDER="$WORKDIR/order.log"
cat > "$WORKDIR/koto-wrap" <<STUBEOF
#!/usr/bin/env bash
real='$REAL_KOTO'
order='$ORDER'
if [ "\${1-}" = review ] && [ "\${2-}" = record ]; then
    if [ "\${3-}" = --help ]; then
        "\$real" review record --help
        echo "  criteria-agreement  How each document criterion agreed with the round's jury"
        exit 0
    fi
    printf 'record %s %s\n' "\${3-}" "\${4-}" >> "\$order"
    if [ "\${4-}" = criteria-agreement ]; then
        prev=""
        for a in "\$@"; do
            if [ "\$prev" = --file ]; then { printf 'file:'; tr -d '\n' < "\$a"; echo; } >> "\$order"; fi
            prev=\$a
        done
        exit 0
    fi
fi
if [ "\${1-}" = next ]; then printf 'next %s\n' "\${2-}" >> "\$order"; fi
exec "\$real" "\$@"
STUBEOF
chmod +x "$WORKDIR/koto-wrap"
export KOTO_BIN="$WORKDIR/koto-wrap"
# Fixed commit dates, so the same document has the same commit in every run.
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

VD="$WORKDIR/verdicts"
OUTS="$WORKDIR/step-output"
: > "$OUTS"
# cmd <file> <fixed text>: the command line of a phase file holding the text,
# with its placeholders filled for topic $TOPIC.
cmd() {
    local l
    l=$(grep -F -- "$2" "$ROOT_DIR/$P/$1" | grep '^ *"\${CLAUDE_PLUGIN_ROOT}/scripts/' | sed -n 1p)
    [ -n "$l" ] || { echo "no command [$2] in $1" >&2; return 1; }
    printf '%s\n' "$l" | sed -e 's/^ *//' -e "s/<topic>/$TOPIC/g" -e "s|<verdicts-dir>|$VD|g" -e "s|<reviews-dir>|$VD|g" \
        -e 's/<decision>/fix_and_proceed/g'
}
# step <file> <fixed text>: run that command from the repository, as the skill
# would; exit status in RC, output appended to OUTS.
RC=0
step() {
    local c
    c=$(cmd "$@") || { RC=99; return; }
    (cd "$REPO" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" eval "$c") >> "$OUTS" 2>&1
    RC=$?
}
seats() { # <format>: the fixture seats' files in the verdicts directory and as ingested keys
    local f
    rm -rf "$VD"; mkdir -p "$VD"; chmod 700 "$VD"
    cp "$FIX/$1"/*.md "$VD/"
    for f in "$FIX/$1"/*.md; do koto context add "$1-$TOPIC" "research/${f##*/}" --from-file "$f" >/dev/null 2>&1; done
}
doc_of() { jq -r --arg f "$1" --arg t "$TOPIC" '.formats[$f].paths[0] | sub("\\{topic\\}"; $t)' "$PHASES"; }
# write_doc <format>: every required section, as list items; the first two
# share a backticked term, so each format has units to grade.
write_doc() {
    local d n=0
    d=$(doc_of "$1")
    mkdir -p "$REPO/$(dirname "$d")"
    {
        printf -- '---\nschema: %s/v1\nstatus: Draft\n---\n\n# Doc\n' "$1"
        jq -r --arg f "$1" '.formats[$f].required_sections[]' "$PHASES" | while IFS= read -r s; do
            n=$((n + 1))
            case "$n" in
                1|2) printf '\n## %s\n\n- Uses `alpha` here.\n' "$s" ;;
                *) case "$s" in Milestones|Features) ;; *) false ;; esac && { printf '\n## %s\n\n### First\n\n**Evidence:**\n- The evidence holds.\n' "$s"; continue; }
                   printf '\n## %s\n\n- Covers the work.\n- Leaves out the rest.\n' "$s" ;;
            esac
        done
    } > "$REPO/$d"
}

# run_jury <format> <jury file> <with step: yes|no> [<parent>]: a draft, two
# jury rounds with a fix between, through the phase file's commands. Prints
# the document check's exit codes.
run_jury() {
    local f=$1 jury=$2 with=$3 par=${4:-} rcs=""
    dct_repo "$f-$TOPIC"
    (cd "$REPO" && KOTO_BIN="$KOTO_BIN" "$ROOT_DIR/scripts/skill-session.sh" open "$f" "$TOPIC") >/dev/null 2>&1
    if [ -n "$par" ]; then
        (cd "$REPO" && KOTO_BIN="$KOTO_BIN" "$ROOT_DIR/scripts/skill-session.sh" open "$par" "$TOPIC") >/dev/null 2>&1
        (cd "$REPO" && KOTO_BIN="$KOTO_BIN" "$ROOT_DIR/scripts/skill-session.sh" dispatch write "$par" "$TOPIC" "$f" fresh-chain) >/dev/null 2>&1
    fi
    dct_envelope 0
    write_doc "$f"
    dct_commit "docs: draft the $f"
    for round in 1 2; do
        step "$jury" "--moment pre_jury"
        rcs="$rcs $RC"
        [ "$with" = no ] || { step "$jury" 'doc-criteria.sh" grade '; rcs="$rcs g$RC"; }
        step "$jury" "round-started --skill $f "
        seats "$f"
        step "$jury" "verdicts --skill $f "
        [ "$with" = no ] || { step "$jury" 'doc-criteria.sh" agreement '; rcs="$rcs a$RC"; }
        step "$jury" "decision --skill $f "
        if [ "$round" = 1 ]; then
            printf '\nA fix.\n' >> "$REPO/$(doc_of "$f")"
            dct_commit "docs: fix the $f"
            step "$jury" "--answers jury_fail"
            step "$jury" 'doc-events.sh" sections '
            step "$jury" "--moment post_fix"
            rcs="$rcs $RC"
        fi
    done
    printf '%s\n' "$rcs"
}

# session_id <name>; states <name>: the session's id; its transitions in order
# and its current state.
session_id() { koto session list 2>/dev/null | jq -r --arg n "$1" '.[] | select(.id == $n) | .session_id // .uuid // empty'; }
slog() { printf '%s/%s/koto-%s.state.jsonl' "$KOTO_SESSIONS_BASE" "$1" "$1"; }
states() {
    printf '%s|%s' "$(jq -r 'select(.type == "transitioned") | .payload.to // .payload.target // ""' "$(slog "$1")" 2>/dev/null | tr '\n' ' ')" \
        "$(koto status "$1" 2>/dev/null | jq -r '.current_state')"
}
# reviews <session>: the review records koto journalled on the session, each
# as its kind and its koto.review.* and koto.doc.* attributes.
reviews() {
    jq -c --arg s "$1" 'select(.session == $s and (.kind | test("^(review|doc|rule)")))
        | [.kind, (to_entries | map(select(.key | test("^koto\\.(review|doc|rule)\\."))) | sort_by(.key) | from_entries)]' \
        "$KOTO_SESSIONS_BASE/_run_journal.jsonl" 2>/dev/null
}

for spec in "brief brief/references/phases/phase-4-validate.md scope" \
    "prd prd/references/phases/phase-4-validate.md scope" \
    "design design/references/phases/phase-6-final-review.md scope" \
    "strategy strategy/references/phases/phase-4-validate.md charter" \
    "roadmap roadmap/references/phases/phase-4-validate.md charter"; do
    set -- $spec
    f=$1 jury=$2 par=$3
    for chain in alone "$par"; do
        p=""
        [ "$chain" = alone ] || p=$par
        run=$f
        [ -z "$p" ] || run=$p

        TOPIC="off-$chain"
        rcs_off=$(run_jury "$f" "$jury" no "$p")
        states_off=$(states "$f-$TOPIC")
        reviews_off=$(reviews "$run-$TOPIC" | sed "s/$TOPIC/T/g")

        TOPIC="on-$chain"
        : > "$ORDER"
        : > "$WORKDIR/sd/requests.jsonl"
        rcs_on=$(run_jury "$f" "$jury" yes "$p")
        states_on=$(states "$f-$TOPIC")
        reviews_on=$(reviews "$run-$TOPIC" | sed "s/$TOPIC/T/g")
        label="/$f $( [ -z "$p" ] && echo standalone || echo "under /$p")"

        [ "$states_on" = "$states_off" ] && pass "$label: the run's session goes through the same states with the step and without" \
            || fail "$label: states on [$states_on] off [$states_off]"
        checks_on=$(printf '%s\n' $rcs_on | grep -v '^[ga]' | tr '\n' ' ')
        checks_off=$(printf '%s\n' $rcs_off | tr '\n' ' ')
        [ "$checks_on" = "$checks_off" ] && pass "$label: the document check exits the same with the step and without [$checks_on]" \
            || fail "$label: check exits on [$checks_on] off [$checks_off]"
        steps=$(printf '%s\n' $rcs_on | grep '^[ga]' | sort -u | tr '\n' ' ')
        [ "$steps" = "a0 g0 " ] && pass "$label: grade and agreement exit 0 every time" || fail "$label: step exits [$rcs_on]"
        n_on=$(printf '%s\n' "$reviews_on" | grep -c '"review_round')
        [ -n "$reviews_on" ] && [ "$reviews_on" = "$reviews_off" ] && [ "$n_on" -ge 2 ] \
            && pass "$label: the same jury rounds and verdict records with the step and without" \
            || fail "$label: review records differ ($(diff <(printf '%s\n' "$reviews_off") <(printf '%s\n' "$reviews_on") | awk 'NR <= 4' | tr '\n' ' '))"

        # With the step: per round, the children ticked before round-started and
        # the agreement right after the verdicts (one record per seat, read as
        # one), both on the run session.
        seq=$(awk -v r="$run-$TOPIC" -v crit="$f-$TOPIC-crit-" '
            $1 == "next" && index($2, crit) == 1 { if (last != "grade") print "grade"; last = "grade"; next }
            $1 == "record" && $2 == r { if ($3 != last) print $3; last = $3 }' "$ORDER" | grep -v -e '^rule-checks$' -e '^fix$' -e '^section-written$' | tr '\n' ' ')
        [ "$seq" = "grade round-started verdicts criteria-agreement decision grade round-started verdicts criteria-agreement decision " ] \
            && pass "$label: per round, the criteria are graded before the round starts and agreement is recorded after its verdicts" \
            || fail "$label: order [$seq]"
        kids=$(koto session list 2>/dev/null | jq -r --arg p "$run-$TOPIC" '[.[] | select(.parent_workflow == $p) | .id] | length')
        rid=$(jq -r --arg s "$run-$TOPIC" 'select(.session == $s) | .["koto.run.id"]' "$KOTO_SESSIONS_BASE/_run_journal.jsonl" | head -n 1)
        drun=$(jq -r --arg c "$f-$TOPIC-crit-" 'select(.kind == "decider_checked" and (.session | startswith($c))) | .["koto.run.id"]' \
            "$KOTO_SESSIONS_BASE/_run_journal.jsonl" | sort -u | tr '\n' ' ')
        [ "$kids" -gt 0 ] && [ -n "$rid" ] && [ "$drun" = "$rid " ] && [ "$(wc -l < "$WORKDIR/sd/requests.jsonl" | tr -d ' ')" -gt 0 ] \
            && pass "$label: the children are the run session's, and their decider records carry its run id" \
            || fail "$label: children=$kids run id [$rid] decider run ids [$drun]"
        entries=$(grep '^file:' "$ORDER" | sed 's/^file://' | jq -c '[.[].criteria_session | select(. != "none")] | length' | tr '\n' ' ')
        want=$(jq -r --arg f "$f" '.formats[$f] | length' "$ROOT_DIR/references/doc-criteria.json")
        [ "$entries" = "$want $want " ] && pass "$label: each round's agreement names a child for every criterion of the format" \
            || fail "$label: agreement entries [$entries] want $want per round"
    done
done

if grep -q -e 'koto decider answer' -e 'Does this' -e 'rule_ref' -e 'blocking_conditions' "$OUTS"; then
    fail "a criterion's text, a finding or an answer command reached the skill's output"
else
    pass "no criterion text, finding or answer command reached the skill's output in any run"
fi

echo
echo "doc-criteria-wiring_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

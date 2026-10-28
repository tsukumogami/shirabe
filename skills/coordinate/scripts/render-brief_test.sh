#!/usr/bin/env bash
# render-brief_test.sh -- a worker's brief rendered from structured input.
#
# Covered: a complete input renders every section of the brief template in
# order, each holding the values given for it (not only its heading), both
# report channels with the dispatcher as the only source of direction, one
# line per discipline coordinator, the conventions pointer, the keep-alive
# note and each standing rule verbatim; the brief lands at
# <root>/.niwa/dispatch-briefs/<topic>.md through the guarded root lookup;
# and every refusal (each missing required field, an approval-worded
# checkpoint, a pointer that isn't one, a flag outside the entry point's set,
# an unknown entry point, a bad topic, a UUID-shaped value) exits 1 and
# writes nothing. A review_level renders its Acceptance criteria line and
# its flags before --koto-leg; without it the brief matches the goldens in
# testdata/brief-golden/ byte for byte; a bad level, a floor above the
# ceiling, an unknown key, an entry point that doesn't take the flags, or
# the flags given in entry_args or run_mode is refused. On the message path the
# Goal names dispatcher_session and shows the command that records it with
# --dispatched-by filled in, per entry point (skill-session.sh open for
# /explore, /decision and /release, coordinate-open.sh for /coordinate,
# link-dispatcher.sh for /deliver and a /work-on PLAN), and Reporting names
# render-result.sh; a leg brief carries none of it; a dispatcher_session
# that isn't a koto session name is refused.
#
# Usage: bash skills/coordinate/scripts/render-brief_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/render-brief.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/render-brief-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */render-brief-test.*) rm -rf "$T" ;; esac'

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { if grep -Fq -- "$3" <<<"$2"; then ok "$1"; else bad "$1" "missing [$3]"; fi; }
lacks() { if grep -Fq -- "$3" <<<"$2"; then bad "$1" "unexpected [$3]"; else ok "$1"; fi; }

W="$T/ws"
mkdir -p "$W/.niwa" "$W/inst/.niwa" "$W/inst/public/config/.niwa"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"
: >"$W/inst/.niwa/instance.json"
: >"$W/inst/public/config/.niwa/workspace.toml"
BRIEFS="$W/.niwa/dispatch-briefs"

BASE="$T/base.json"
cat >"$BASE" <<'EOF'
{
  "topic": "plugin-api",
  "repo": "acme/widgets",
  "unit": "Feature 2: the plugin API",
  "entry_point": "deliver",
  "entry_args": ["plugin-api", "--no-merge"],
  "run_mode": "--auto",
  "phase": "executing",
  "authority": "You are working for the owner on acme/widgets to build feature 2.",
  "goal": "The plugin API ships with its loader.",
  "checkpoints": ["The scoping PR is open.", "The PR is ready with every CI job green."],
  "acceptance": ["The loader loads a plugin.", "CI is green per job."],
  "dispatcher_session": "coordinate-roadmap-plugin-system-20261006T153752Z",
  "reports_to": "coord-alpha",
  "decisions": [{"decision": "Plugins load eagerly.", "by": "the owner"}],
  "read_first": ["docs/prds/PRD-plugin-api.md", "#12", "acme/widgets#7", "https://example.com/spec"],
  "out_of_scope": ["The CLI's help text."],
  "surfaces": [{"surface": "ci-health", "coordinator": "ci-coord"}, {"surface": "releases", "coordinator": "rel-coord"}],
  "standing_rules": ["Enter a worktree before the first koto init of any run.", "Keep test runs targeted."]
}
EOF

# variant <name> <jq filter> -- write a copy of the base input with a change
variant() { jq "$2" "$BASE" >"$T/$1.json"; printf '%s' "$T/$1.json"; }

# --- a complete input ---------------------------------------------------------------

OUT=$(cd "$W/inst/public/config" && bash "$S" --input "$BASE")
eq  "written: the path under the real root, not the clone's" "$BRIEFS/plugin-api.md" "$OUT"
[ -f "$W/inst/public/config/.niwa/dispatch-briefs/plugin-api.md" ] && bad "written: nothing in the clone" || ok "written: nothing in the clone"
B=$(cat "$BRIEFS/plugin-api.md")

order=$(printf '%s\n' "$B" | grep '^## ' | tr '\n' '|')
eq  "sections: in the template's order" "## Goal|## Checkpoints|## Decisions already made|## Read first|## Acceptance criteria|## Out of scope|## Reporting|## Workspace rules|## Keep-alive|" "$order"

has "goal: authority"            "$B" "You are working for the owner on acme/widgets to build feature 2."
has "goal: the goal"             "$B" "The plugin API ships with its loader."
has "goal: invocation with mode" "$B" 'Run `/shirabe:deliver plugin-api --auto --no-merge` in acme/widgets.'
has "goal: run mode"             "$B" 'Run mode: `--auto`.'
has "goal: phase"                "$B" "You are executing"
has "checkpoints: numbered"      "$B" "2. The PR is ready with every CI job green."
has "decisions: with who"        "$B" "- Plugins load eagerly. (the owner)"
has "read first: path"           "$B" "- docs/prds/PRD-plugin-api.md"
has "read first: cross-repo ref" "$B" "- acme/widgets#7"
has "acceptance: checkbox"       "$B" "- [ ] The loader loads a plugin."
has "out of scope: given"        "$B" "- The CLI's help text."
has "out of scope: closes"       "$B" "report to the coordinator with its number, the reason and the evidence"
has "out of scope: no filing"    "$B" "Don't file new issues: propose them in a report."
has "conventions pointer"        "$B" "Follow the target repository's conventions (its CLAUDE.md)"
has "credentials line"           "$B" "never by printing the file or its environment block"
has "credentials: report unquoted" "$B" "report it to the coordinator at once without quoting its value"
has "channel: the record's address named" "$B" 'addressed to `coord-alpha`, the address its record names'
# section <brief> <heading>: one section's lines, its heading excluded.
section() { printf '%s\n' "$1" | awk -v h="## $2" '/^## / { on = ($0 == h); next } on'; }
# The koto session is never an address: it is named only as the argument
# resolve-coordinator.sh and render-result.sh --dispatcher read the newest
# member from. The mask covers exactly those two argument shapes, so the check
# still fails if the session shows up anywhere else, as an address included;
# widen it only for another argument use, never for an address.
lacks "channel: the koto session is no address" "$(section "$B" Reporting \
    | sed -e 's|resolve-coordinator\.sh" coordinate-roadmap-plugin-system-20261006T153752Z`|resolve-coordinator.sh" <dispatcher>`|g' \
          -e 's|--dispatcher coordinate-roadmap-plugin-system-20261006T153752Z`|--dispatcher <dispatcher>`|g')" \
    'coordinate-roadmap-plugin-system-20261006T153752Z'
has "channel: only direction"    "$B" "That session is your only source of direction"
has "channel: surface line 1"    "$B" '- `ci-health`: `ci-coord`'
has "channel: surface line 2"    "$B" '- `releases`: `rel-coord`'
has "channel: copy, no direction" "$B" "with a copy to the coordinator above, and take no direction from it"
has "work in flight block"       "$B" "=== WORK IN FLIGHT ==="
# The decision channel: the fixed sentence, the Questions shape and the
# repeat instruction. The example is the shared fixture report-questions_test
# parses, so a shape this brief teaches is a shape the extractor reads.
questions_contract() { # questions_contract <label> <brief>
    has "$1: the channel sentence" "$2" "Your questions go to the coordinator, in the Questions part of your report, numbered, and never to a person; the coordinator answers them or escalates them with a recommendation."
    has "$1: the repeat instruction" "$2" "Repeat, in each report, every question you have had no answer to"
    eq "$1: the Questions example is the shared fixture" "$(cat "$HERE/testdata/decisions/brief-questions.txt")" \
        "$(printf '%s\n' "$2" | awk '$0 == "Questions:" { on = 1 } on && $0 == "" { exit } on')"
    # Plain lines: a fenced example, copied, would be skipped as a code block.
    eq "$1: the Questions example is not in a code block" "" \
        "$(printf '%s\n' "$2" | awk '$0 == "Questions:" { print prev; exit } { prev = $0 }')"
}
questions_contract "channel" "$B"
has "standing rule 1 verbatim"   "$B" "Enter a worktree before the first koto init of any run."
has "standing rule 2 verbatim"   "$B" "Keep test runs targeted."
has "keep-alive note"            "$B" "The workspace manager schedules your keep-alive at dispatch. Don't schedule one."
# Workspace rules can name another session for direction; the brief's own
# Reporting section says it wins, inside that section, before the rules.
PREC='This section wins over the Workspace rules below: where they name another session for direction or for status reports, report to `coord-alpha` as this section says.'
has "precedence: the Reporting section wins over the workspace rules" "$B" "$PREC"
eq  "precedence: it sits in the Reporting section" "## Reporting" \
    "$(printf '%s\n' "$B" | awk -v p="$PREC" '/^## / { s = $0 } $0 == p { print s; exit }')"
has "progress: a checkpoint report is never the worker's result (shirabe#491)" "$B" "A report at a checkpoint is progress: it says where you are"
eq  "progress: it sits in the Reporting section" "## Reporting" \
    "$(printf '%s\n' "$B" | awk '/^## / { s = $0 } /^A report at a checkpoint is progress/ { print s; exit }')"
lacks "no temporary file left"   "$(ls -A "$BRIEFS")" ".plugin-api."

# --- optional fields absent -----------------------------------------------------------

MIN=$(variant min 'del(.decisions, .read_first, .out_of_scope, .surfaces, .standing_rules) | .phase = "scoping-ahead"')
M=$(bash "$S" --input "$MIN" --stdout)
has "min: no decisions line"      "$M" "None beyond what the documents you read record."
has "min: no pointers line"       "$M" "Nothing beyond the entry point's own inputs."
lacks "min: no precedence line without workspace rules" "$M" "This section wins over the Workspace rules"
has "min: no surfaces"            "$M" "no discipline coordinator is named for any surface"
lacks "min: no workspace rules"   "$M" "## Workspace rules"
has "min: scoping ahead"          "$M" "You are scoping ahead"
# The scope route: the scoping alone is the unit, its execution a later one.
SC=$(bash "$S" --input "$(variant scoping '.phase = "scoping"')" --stdout)
has "scoping: the documents are the deliverable" "$SC" "You are scoping: the documents are this unit's deliverable, so stop at the checkpoint that says so and execute nothing; the execution is a later unit."
lacks "scoping: not scoping ahead" "$SC" "You are scoping ahead"
questions_contract "min" "$M"
L=$(bash "$S" --input "$BASE" --return-path req_1:deliver --stdout)
questions_contract "leg" "$L"
# The check fails on a brief without them.
questions_contract "a brief without the channel (expected to fail)" "$(printf '%s\n' "$M" | grep -v 'Your questions go to\|Repeat, in each report')" > "$T/neg.out"
grep -q '^FAIL' "$T/neg.out" && ok "the channel check fails on a brief without it" || bad "the channel check fails on a brief without it" "$(cat "$T/neg.out")"
FAIL=$((FAIL - $(grep -c '^FAIL' "$T/neg.out"))); PASS=$((PASS - $(grep -c '^ok' "$T/neg.out")))

L=$(bash "$S" --input "$BASE" --return-path req_1:deliver --stdout)
has "return path: the brief's invocation carries the leg" "$L" 'Run `/shirabe:deliver plugin-api --auto --no-merge --koto-leg=req_1:deliver` in acme/widgets.'

# The template's own headings, read from references/brief-template.md's fenced
# brief, are the rendered brief's first seven, in order: the renderer and the
# prose template can't drift apart unnoticed.
TPL="$HERE/../references/brief-template.md"
WANT=$(awk '/^```markdown/{f=1;next} /^```/{f=0} f && /^## /' "$TPL" | tr '\n' '|')
GOT=$(grep '^## ' <<<"$B" | head -7 | tr '\n' '|')
eq  "template: the rendered headings are the template's" "$WANT" "$GOT"

# An --interactive run mode is allowed (the human's decisions may ask for it,
# per the template), and the caution still reaches the worker.
I=$(bash "$S" --input "$(variant interactive '.run_mode = "--interactive"')" --stdout)
has "interactive: the caution is there too" "$I" 'Run mode: `--interactive`. A background worker can'"'"'t answer the confirmation `--interactive` waits for.'
has "checkpoints: never wait for approval" "$B" "don't wait for approval to go past it"

# --- a review-level bound -----------------------------------------------------------
#
# Without review_level the brief is byte for byte the one rendered before the
# field existed: testdata/brief-golden/ holds those renders of this file's
# base, min and leg inputs. A deliberate change to the brief's wording updates
# them with the same three renders.
GOLD="$HERE/testdata/brief-golden"
golden() { # golden <label> <golden file> <render-brief args...>
    local label=$1 want=$2
    shift 2
    if bash "$S" "$@" --stdout | cmp -s - "$want"; then ok "$label"; else bad "$label" "differs from $want"; fi
}
golden "review level: absent, the base brief is unchanged" "$GOLD/base.txt" --input "$BASE"
golden "review level: absent, the min brief is unchanged"  "$GOLD/min.txt"  --input "$MIN"
golden "review level: absent, the leg brief is unchanged"  "$GOLD/leg.txt"  --input "$BASE" --return-path req_1:deliver
# No brief tells the worker to put its review round in the pull request body.
for args in "--input $BASE" "--input $MIN" "--input $BASE --return-path req_1:deliver"; do
    # shellcheck disable=SC2086
    OUT=$(bash "$S" $args --stdout)
    case "$OUT" in
        *'## Review panel'*|*'PR Workflow Content'*) bad "no Review panel table in the body ($args)" "$(printf '%s\n' "$OUT" | grep -n 'Review panel\|PR Workflow Content')" ;;
        *"It never reads a round from the pull request body"*) ok "the brief says the body carries no round ($args)" ;;
        *) bad "the brief says the body carries no round ($args)" ;;
    esac
done

# --- the worker's grant -------------------------------------------------------------
#
# Absent, the brief is the golden one; present, the Goal gains one line after
# the authority sentence, naming exactly the grant or saying it holds none.
NAMED_REST="A merge, close or release that needs an authority you don't hold isn't yours to take: hand it back to the coordinator in a report, and don't reach the same result another way."
G1=$(bash "$S" --input "$(variant grant-merge '.grant = ["merge-pr"]')" --stdout)
has "grant: names merge-pr and nothing else" "$G1" "Named authority: you hold merge-pr and nothing else. $NAMED_REST"
eq  "grant: the line follows the authority sentence" "You are working for the owner on acme/widgets to build feature 2." \
    "$(printf '%s\n' "$G1" | awk '/^Named authority:/ { print p2; exit } { p2 = p1; p1 = $0 }')"
eq  "grant: nothing else changes" "$(cat "$GOLD/base.txt")" "$(printf '%s\n' "$G1" | awk '/^Named authority:/ { skip = 2 } skip > 0 { skip--; next } { print }')"
G2=$(bash "$S" --input "$(variant grant-two '.grant = ["merge-pr", "close-issue"]')" --stdout)
has "grant: two authorities, both named" "$G2" "Named authority: you hold merge-pr, close-issue and nothing else."
G0=$(bash "$S" --input "$(variant grant-none '.grant = []')" --stdout)
has "grant: none says it holds none" "$G0" "Named authority: you hold no named authority. A merge, close or release isn't yours to take"
lacks "grant: none names no authority" "$(printf '%s\n' "$G0" | grep '^Named authority:')" "merge-pr"
for g in '["merge"]' '"merge-pr"' '["merge-pr","merge-pr"]' '"own"' '[1]'; do
    bash "$S" --input "$(variant grant-bad ".grant = $g")" --stdout >/dev/null 2>"$T/err"
    eq  "grant: $g is refused" "1" "$?"
    has "grant: $g's refusal names the field" "$(cat "$T/err")" "grant: must be an array of distinct authorities"
done

# --- the dispatcher, on the message path ---------------------------------------------
#
# A worker with no request leg records the coordinator run that dispatched it
# itself: its brief's Goal names the run as dispatcher_session and shows the
# exact command that records it, --dispatched-by filled in, and its Reporting
# names render-result.sh as the report step. A leg brief has none of it.
D=coordinate-roadmap-plugin-system-20261006T153752Z
G=$(section "$B" Goal)
has "dispatcher: the Goal names dispatcher_session" "$G" "dispatcher_session: $D"
has "dispatcher: /deliver records it with link-dispatcher.sh" "$G" \
    "\`\"\${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/link-dispatcher.sh\" <session> --dispatched-by $D\`"
has "dispatcher: run once the entry point opened its session" "$G" "once your entry point has opened its session, run this"
has "dispatcher: a failed link is no stop" "$G" 'If it prints `warning=link-failed`, go on'
for ep in explore decision release; do
    E=$(bash "$S" --input "$(variant "ep-$ep" ".entry_point = \"$ep\" | .entry_args = [\"plugin-api\"] | .run_mode = (if \"$ep\" == \"release\" then \"\" else \"--auto\" end)")" --stdout)
    has "dispatcher: /$ep opens with skill-session.sh open --dispatched-by" "$(section "$E" Goal)" \
        "\`\"\${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh\" open $ep <topic> --dispatched-by $D\`"
    has "dispatcher: /$ep's command replaces its skill's open" "$(section "$E" Goal)" "in place of the open your entry point's skill shows"
    has "dispatcher: /$ep, re-briefed with its session open, runs it anyway" "$(section "$E" Goal)" "If your session is already open (this brief re-briefs you), run it anyway"
done
lacks "dispatcher: the link command needs no already-open note" "$G" "this brief re-briefs you"
E=$(bash "$S" --input "$(variant ep-coordinate '.entry_point = "coordinate" | .entry_args = ["docs/roadmaps/ROADMAP-sub.md"] | .run_mode = ""')" --stdout)
has "dispatcher: /coordinate opens with coordinate-open.sh --dispatched-by" "$(section "$E" Goal)" \
    "\`\"\${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/coordinate-open.sh\" --plugin-root \"\${CLAUDE_PLUGIN_ROOT}\" --dispatched-by $D \"\$ARGS_DIR/args.json\"\`"
has "dispatcher: /coordinate's args file is its first step's" "$(section "$E" Goal)" '`$ARGS_DIR/args.json` the args file its first step writes'
E=$(bash "$S" --input "$(variant ep-workon '.entry_point = "work-on" | .entry_args = ["docs/plans/PLAN-x.md"]')" --stdout)
has "dispatcher: /work-on given a PLAN records it with link-dispatcher.sh" "$(section "$E" Goal)" \
    "link-dispatcher.sh\" <session> --dispatched-by $D"
has "dispatcher: the template's Reporting names render-result.sh too" \
    "$(awk '/^```markdown$/ { on = 1; next } on && /^```$/ { exit } on' "$HERE/../references/brief-template.md" | awk '/^## / { on = ($0 == "## Reporting"); next } on')" \
    'scripts/render-result.sh --session <your session>'
R=$(section "$B" Reporting)
has "dispatcher: Reporting names render-result.sh as the report step" "$R" \
    "Your report step: when your entry point finishes, run \`\"\${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/render-result.sh\" --session <your session> --dispatcher $D\`"
has "dispatcher: the final report goes to the resolved coordinator" "$R" \
    'just before the `=== WORK IN FLIGHT ===` block, sent to the session its `coordinator=` line names.'
has "dispatcher: Reporting resolves the newest member before each report" "$R" \
    "Before each report, run \`\"\${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/resolve-coordinator.sh\" $D\` and send the report to the session its \`coordinator=\` line names"
has "dispatcher: ... falling back to the record's address" "$R" \
    'When it prints no `coordinator=` line, report to `coord-alpha`.'
L=$(bash "$S" --input "$BASE" --return-path req_1:deliver --stdout)
lacks "dispatcher: a leg brief names no dispatcher_session" "$L" "dispatcher_session:"
lacks "dispatcher: a leg brief shows no link command" "$L" "--dispatched-by"
lacks "dispatcher: a leg brief has no render-result step" "$L" "render-result.sh"
for bad in "coord alpha" "../coord" "-coord"; do
    rm -rf "$BRIEFS"
    (cd "$W" && bash "$S" --input "$(variant bad-disp ".dispatcher_session = \"$bad\"")") >/dev/null 2>"$T/err"
    rc=$?
    if [ "$rc" -eq 1 ] && grep -q 'dispatcher_session: must be a koto session name' "$T/err" && [ ! -e "$BRIEFS" ]; then
        ok "dispatcher: [$bad] is refused, nothing written"
    else
        bad "dispatcher: [$bad] is refused, nothing written" "rc=$rc $(cat "$T/err")"
    fi
done

RL=$(bash "$S" --input "$(variant rl-ceiling '.review_level = {"ceiling": "standard"}')" --stdout)
has "review level: a ceiling's line in Acceptance criteria" "$RL" "- [ ] Review level: ceiling standard; /work-on's choice must fall inside it."
eq  "review level: the line is in Acceptance criteria, after the given ones" "## Acceptance criteria" \
    "$(printf '%s\n' "$RL" | awk '/^## / { s = $0 } /^- \[ \] Review level:/ { print s; exit }')"
eq  "review level: after the given criteria" "- [ ] CI is green per job." \
    "$(printf '%s\n' "$RL" | awk '/^- \[ \] Review level:/ { print prev; exit } { prev = $0 }')"
has "review level: a ceiling's flag on the invocation" "$RL" 'Run `/shirabe:deliver plugin-api --auto --no-merge --review-ceiling=standard` in acme/widgets.'
lacks "review level: a ceiling alone adds no floor" "$RL" "--review-floor"
# Only the line and the flag differ from the brief without the field.
eq  "review level: nothing else changes" "$(cat "$GOLD/base.txt")" \
    "$(printf '%s\n' "$RL" | grep -v '^- \[ \] Review level:' | sed 's/ --review-ceiling=standard//')"
RL=$(bash "$S" --input "$(variant rl-floor '.review_level = {"floor": "full"}')" --stdout)
has "review level: a floor's line" "$RL" "- [ ] Review level: floor full; /work-on's choice must fall inside it."
has "review level: a floor's flag" "$RL" "--no-merge --review-floor=full\`"
RL=$(bash "$S" --input "$(variant rl-both '.review_level = {"ceiling": "full", "floor": "light"}')" --return-path req_1:deliver --stdout)
has "review level: both, in one line" "$RL" "- [ ] Review level: floor light, ceiling full; /work-on's choice must fall inside it."
has "review level: both flags, before the leg" "$RL" '--no-merge --review-floor=light --review-ceiling=full --koto-leg=req_1:deliver`'
RL=$(bash "$S" --input "$(variant rl-equal '.review_level = {"floor": "standard", "ceiling": "standard"}')" --stdout); RC=$?
eq  "review level: a floor equal to the ceiling is taken" 0 "$RC"
for ep in work-on execute; do
    bash "$S" --input "$(variant "rl-$ep" '.entry_point = "'"$ep"'" | .entry_args = ["#12"] | .review_level = {"ceiling": "light"}')" --stdout >/dev/null 2>&1
    eq "review level: /shirabe:$ep takes it" 0 "$?"
done

# --- refusals write nothing ---------------------------------------------------------

rm -rf "$BRIEFS"
refused() {
    local name="$1" file="$2" want="$3" err rc
    err=$(cd "$W/inst" && bash "$S" --input "$file" 2>&1 >/dev/null)
    rc=$?
    eq "$name: exit 1" 1 "$rc"
    has "$name: names the problem" "$err" "$want"
    if [ -e "$BRIEFS" ]; then bad "$name: nothing written" "$(ls -A "$BRIEFS")"; else ok "$name: nothing written"; fi
}

for k in topic repo unit entry_point run_mode phase authority goal dispatcher_session reports_to; do
    refused "missing $k" "$(variant "no-$k" "del(.$k)")" "$k: required"
done
refused "empty goal"            "$(variant empty-goal '.goal = "  "')"                     "goal: required"
refused "empty run mode"        "$(variant empty-mode '.run_mode = ""')"                   "run_mode: required for deliver, which takes --auto or --interactive"
refused "address with a slash"  "$(variant bad-addr '.reports_to = "a/b"')"                "reports_to: must be a session name"
US=$(bash "$S" --input "$(variant us-addr '.reports_to = "lane_owner"')" --stdout 2>"$T/us.err")
eq "address: an underscored session name renders" 0 "$?"
has "address: and is the one named" "$US" 'addressed to `lane_owner`, the address its record names'
# A release (shirabe#627): its version is the positional, --dry-run its one
# flag, and it takes no run mode.
REL=$(variant release '.entry_point = "release" | .entry_args = ["v0.25.0", "--dry-run"] | .run_mode = "" | .unit = "release acme/widgets v0.25.0"')
R=$(bash "$S" --input "$REL" --stdout 2>"$T/rel.err"); eq "release: renders with no run mode" 0 "$?"
has "release: the invocation" "$R" 'Run `/shirabe:release v0.25.0 --dry-run` in acme/widgets.'
has "release: says it takes no run mode" "$R" 'Run mode: none; `/shirabe:release` takes no execution mode.'
refused "release with --auto"   "$(variant rel-auto '.entry_point = "release" | .entry_args = ["v0.25.0"] | .run_mode = "--auto"')" "run_mode: release doesn't allow --auto"
# A charter (shirabe#1290): no leg, its SKILL.md's flags, and on the message
# path the dispatcher is recorded with link-dispatcher.sh once its session is open.
CH=$(variant charter '.entry_point = "charter" | .entry_args = ["plugin-api"] | .run_mode = "--auto"')
C=$(bash "$S" --input "$CH" --stdout 2>"$T/ch.err"); eq "charter: renders with --auto" 0 "$?"
has "charter: the invocation" "$C" 'Run `/shirabe:charter plugin-api --auto` in acme/widgets.'
has "charter: the run mode" "$C" 'Run mode: `--auto`.'
has "charter: records its dispatcher with link-dispatcher.sh" "$(section "$C" Goal)" \
    "link-dispatcher.sh\" <session> --dispatched-by coordinate-roadmap-plugin-system-20261006T153752Z"
C=$(bash "$S" --input "$(variant charter-rounds '.entry_point = "charter" | .entry_args = ["plugin-api", "--max-rounds=2"] | .run_mode = "--interactive"')" --stdout 2>"$T/ch.err")
eq  "charter: takes --interactive and --max-rounds=N" 0 "$?"
has "charter: --max-rounds=N on the invocation" "$C" 'Run `/shirabe:charter plugin-api --interactive --max-rounds=2` in acme/widgets.'
refused "charter with --upstream" "$(variant ch-up '.entry_point = "charter" | .entry_args = ["plugin-api", "--upstream"] | .run_mode = "--auto"')" "entry_args: charter doesn't allow --upstream"
refused "charter with --merge"    "$(variant ch-merge '.entry_point = "charter" | .entry_args = ["plugin-api"] | .run_mode = "--auto --merge"')" "run_mode: charter doesn't allow --merge"
refused "charter with no run mode" "$(variant ch-none '.entry_point = "charter" | .entry_args = ["plugin-api"] | .run_mode = ""')" "run_mode: required for charter, which takes --auto or --interactive"
# The other planning skills take their own SKILL.md's flags; /brief documents
# no execution mode, so it renders with none and refuses --auto (/comp, which
# takes only private targets, is under the target requirement below).
for ep in prd design plan roadmap strategy vision; do
    bash "$S" --input "$(variant "ep-$ep" ".entry_point = \"$ep\" | .entry_args = [\"plugin-api\"] | .run_mode = \"--auto\"")" --stdout >/dev/null 2>"$T/ep.err"
    eq "$ep: renders with --auto" 0 "$?"
done
P=$(bash "$S" --input "$(variant plan-flags '.entry_point = "plan" | .entry_args = ["docs/designs/DESIGN-x.md", "--intent=stop", "--plan-version=v2", "--tactical"] | .run_mode = "--auto"')" --stdout 2>"$T/ep.err")
eq  "plan: takes its intent, plan version and scope flags" 0 "$?"
has "plan: the invocation" "$P" 'Run `/shirabe:plan docs/designs/DESIGN-x.md --auto --intent=stop --plan-version=v2 --tactical` in acme/widgets.'
refused "plan with --plan-version=v3" "$(variant plan-v3 '.entry_point = "plan" | .entry_args = ["x", "--plan-version=v3"] | .run_mode = "--auto"')" "entry_args: plan doesn't allow --plan-version=v3"
refused "roadmap with --issues"       "$(variant rm-issues '.entry_point = "roadmap" | .entry_args = ["x", "--issues"] | .run_mode = "--auto"')" "entry_args: roadmap doesn't allow --issues"
refused "strategy with --max-rounds"  "$(variant st-rounds '.entry_point = "strategy" | .entry_args = ["x", "--max-rounds=2"] | .run_mode = "--auto"')" "entry_args: strategy doesn't allow --max-rounds=2"
E=$(bash "$S" --input "$(variant ep-brief '.entry_point = "brief" | .entry_args = ["plugin-api"] | .run_mode = ""')" --stdout 2>"$T/ep.err")
eq  "brief: renders with no run mode" 0 "$?"
has "brief: says it takes no run mode" "$E" 'Run mode: none; `/shirabe:brief` takes no execution mode.'
refused "brief with --auto" "$(variant brief-auto '.entry_point = "brief" | .entry_args = ["plugin-api"] | .run_mode = "--auto"')" "run_mode: brief doesn't allow --auto"
refused "no entry_args"         "$(variant no-args 'del(.entry_args)')"                    "entry_args: required"
refused "flag first"            "$(variant flag-first '.entry_args = ["--auto"]')"         "the first token must be the positional argument"
refused "no checkpoints"        "$(variant no-cp '.checkpoints = []')"                     "checkpoints: required"
refused "no acceptance"         "$(variant no-ac 'del(.acceptance)')"                      "acceptance: required"
refused "approval checkpoint"   "$(variant approve '.checkpoints += ["Wait for approval before merging."]')" "may not wait for approval"
refused "approve checkpoint"    "$(variant approve2 '.checkpoints = ["The owner approves the plan."]')"      "may not wait for approval"
refused "wait-for checkpoint"   "$(variant waitfor '.checkpoints = ["Wait for the go."]')"                   "may not wait for approval"
refused "absolute pointer"      "$(variant abs '.read_first = ["/etc/passwd"]')"            "read_first: not a repository path"
refused "traversal pointer"     "$(variant dotdot '.read_first = ["docs/../../x"]')"        "read_first: not a repository path"
refused "http pointer"          "$(variant http '.read_first = ["http://example.com"]')"    "read_first: not a repository path"
refused "prose pointer"         "$(variant prose '.read_first = ["see the PRD"]')"          "read_first: not a repository path"
refused "flag not allowed"      "$(variant badflag '.entry_args += ["--merge"]')"           "entry_args: deliver doesn't allow --merge"
refused "koto-leg not allowed"  "$(variant kl '.entry_args += ["--koto-leg=r:deliver"]')"   "doesn't allow --koto-leg"
refused "run_mode not allowed"  "$(variant rm '.run_mode = "--auto --yolo"')"               "run_mode: deliver doesn't allow --yolo"
refused "unknown entry point"   "$(variant ep '.entry_point = "nope"')"                     "entry_point: not in references/entry-points.tsv"
refused "bad topic"             "$(variant bt '.topic = "Plugin_API"')"                     "topic: must match"
refused "traversal topic"       "$(variant tt '.topic = "../x"')"                           "topic: must match"
refused "bad repo"              "$(variant br '.repo = "widgets"')"                         "repo: must be owner/repo"
refused "bad phase"             "$(variant bp '.phase = "done"')"                           "phase: must be scoping, scoping-ahead or executing"
refused "multi-line session"    "$(variant ms '.dispatcher_session = "a\nb"')"              "dispatcher_session: must be one line"
refused "bad surface"           "$(variant bs '.surfaces = [{"surface": "ci"}]')"           "surfaces: must be"
refused "bad decision"          "$(variant bd '.decisions = [{"decision": "x"}]')"          "decisions: must be"
refused "flag given twice"      "$(variant dup '.entry_args += ["--auto"]')"                "--auto is given twice"
refused "both modes"            "$(variant both '.run_mode = "--auto --interactive"')"      "--auto and --interactive together"
refused "quote in positional"   "$(variant q '.entry_args = ["a\"b"]')"                     "may not contain a quote"
refused "dollar in positional"  "$(variant d '.entry_args = ["$(x)"]')"                     "may not contain a quote"
refused "review level: floor above ceiling" "$(variant rl-inv '.review_level = {"floor": "full", "ceiling": "light"}')" "review_level: the floor (full) is above the ceiling (light)"
refused "review level: not a level"   "$(variant rl-bad '.review_level = {"ceiling": "heavy"}')"     "review_level: ceiling must be light, standard or full"
refused "review level: not a string"  "$(variant rl-num '.review_level = {"floor": 1}')"             "review_level: floor must be light, standard or full"
refused "review level: unknown key"   "$(variant rl-key '.review_level = {"ceiling": "full", "level": "light"}')" "review_level: unknown key level"
refused "review level: empty object"  "$(variant rl-empty '.review_level = {}')"                     "review_level: must be an object with floor, ceiling or both"
refused "review level: not an object" "$(variant rl-str '.review_level = "standard"')"               "review_level: must be an object"
refused "review level: an entry point without the flags" "$(variant rl-scope '.entry_point = "scope" | .entry_args = ["plugin-api"] | .review_level = {"ceiling": "standard"}')" "review_level: /shirabe:scope doesn't take --review-ceiling"
refused "review level: a flag in entry_args" "$(variant rl-arg '.entry_args += ["--review-ceiling=heavy"]')" "entry_args: --review-ceiling goes in review_level"
refused "review level: a flag in run_mode"   "$(variant rl-mode '.run_mode = "--auto --review-floor=full"')" "run_mode: --review-floor goes in review_level"
refused "session id"            "$(variant uuid '.goal = "Resume 3f2b8c1e-9a4d-4c2e-8f1a-2b3c4d5e6f70."')" "UUID-shaped token"

ERR=$(cd "$W/inst" && bash "$S" --input "$BASE" --return-path 'nope; rm' 2>&1 >/dev/null); RC=$?
eq  "bad return path: exit 1" 1 "$RC"
has "bad return path: names it" "$ERR" "--return-path: not message"
if [ -e "$BRIEFS" ]; then bad "bad return path: nothing written" ""; else ok "bad return path: nothing written"; fi

# --- the entry point's target requirement ----------------------------------------------
#
# The shipped table restricts no entry point, so these run on a stand-in where
# /deliver and /execute take only public repositories; /deliver's refusal
# names /work-on instead, and /execute's names no entry point. gh is a stand-in that answers `api repos/<r>` and logs.
RT="$T/restricted.tsv"
awk -F'\t' 'BEGIN { OFS = "\t" } /^#/ { next } NF < 5 { next }
    $1 == "deliver" { $6 = "public"; $7 = "work-on" }
    $1 == "execute" { $6 = "public"; $7 = "-" }
    { print }' "$HERE/../references/entry-points.tsv" >"$RT"
GHB="$T/ghbin"
mkdir -p "$GHB"
cat >"$GHB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "${@: -1}" in
    repos/acme/widgets | repos/acme/tools) printf '{"visibility":"public"}\n' ;;
    repos/acme/vault) printf '{"visibility":"private"}\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$GHB/gh"
export GH_LOG="$T/gh.log"
restricted() { # restricted <input> -- render with the stand-in table and gh
    ERR=$(DC_ENTRY_POINTS="$RT" PATH="$GHB:$PATH" bash "$S" --input "$1" --stdout 2>&1 >/dev/null)
    RC=$?
}
rm -rf "$BRIEFS"
: >"$GH_LOG"

restricted "$BASE"
eq  "target: a public repository passes a public-only entry point" 0 "$RC"
has "target: its visibility was read live" "$(cat "$GH_LOG")" "api --method GET repos/acme/widgets"

restricted "$(variant priv-repo '.repo = "acme/vault"')"
eq  "target: a private repository is refused (exit 1)" 1 "$RC"
has "target: the refusal names the requirement and the field" "$ERR" "entry_point: /shirabe:deliver takes only public repositories, and repo is private"
has "target: the refusal names the alternative" "$ERR" "dispatch it to /shirabe:work-on instead"
lacks "target: the refusal never names the private repository" "$ERR" "acme/vault"

restricted "$(variant priv-target '.targets = ["acme/tools", "acme/vault"]')"
eq  "target: a private repository among targets is refused" 1 "$RC"
has "target: the refusal names targets[2]" "$ERR" "targets[2] is private"

restricted "$(variant exec-no-targets '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"]')"
eq  "target: a PLAN-driven entry point with a requirement needs targets" 1 "$RC"
has "target: it says to list the PLAN's repositories" "$ERR" "targets: required for execute"

restricted "$(variant exec-empty-targets '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"] | .targets = []')"
eq  "target: an empty targets list doesn't satisfy a PLAN-driven entry point" 1 "$RC"

restricted "$(variant exec-priv '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"] | .targets = ["acme/vault"]')"
eq  "target: a PLAN's private issue repository is refused" 1 "$RC"
has "target: with no alternative, the unit goes back to pick" "$ERR" "no entry point takes it; the unit goes back to pick"

restricted "$(variant unread '.repo = "acme/unknown"')"
eq  "target: a visibility that can't be read is exit 2, never a pass" 2 "$RC"

: >"$GH_LOG"
ERR=$(DC_ENTRY_POINTS="$RT" PATH="$GHB:$PATH" bash "$S" --input "$T/priv-repo.json" --stdout --targets-checked 2>&1 >/dev/null)
eq  "target: --targets-checked skips the requirement" 0 "$?"
eq  "target: and reads no visibility" "" "$(cat "$GH_LOG")"

# The shipped table does restrict one entry point since shirabe#1290: /comp
# takes only private repositories and names no alternative. It documents no
# execution mode, so it renders with none.
: >"$GH_LOG"
ERR=$(PATH="$GHB:$PATH" bash "$S" --input "$(variant comp-public '.entry_point = "comp" | .entry_args = ["plugin-api"] | .run_mode = ""')" --stdout 2>&1 >/dev/null)
eq  "comp: a public repository is refused (exit 1)" 1 "$?"
has "comp: its visibility was read live" "$(cat "$GH_LOG")" "api --method GET repos/acme/widgets"
has "comp: the refusal names the requirement" "$ERR" "entry_point: /shirabe:comp takes only private repositories, and repo is public"
has "comp: with no alternative, the unit goes back to pick" "$ERR" "no entry point takes it; the unit goes back to pick"
E=$(PATH="$GHB:$PATH" bash "$S" --input "$(variant comp-private '.entry_point = "comp" | .entry_args = ["plugin-api"] | .run_mode = "" | .repo = "acme/vault"')" --stdout 2>"$T/comp.err")
eq  "comp: a private repository renders" 0 "$?"
has "comp: says it takes no run mode" "$E" 'Run mode: none; `/shirabe:comp` takes no execution mode.'
ERR=$(PATH="$GHB:$PATH" bash "$S" --input "$(variant comp-auto '.entry_point = "comp" | .entry_args = ["plugin-api"] | .run_mode = "--auto" | .repo = "acme/vault"')" --stdout 2>&1 >/dev/null)
eq  "comp: --auto is refused (exit 1)" 1 "$?"
has "comp: the refusal names the flag" "$ERR" "run_mode: comp doesn't allow --auto"

# Written, not printed: a refusal still leaves nothing in the brief directory.
ERR=$(DC_ENTRY_POINTS="$RT" PATH="$GHB:$PATH" bash "$S" --input "$T/priv-repo.json" --workspace-root "$W" 2>&1 >/dev/null)
eq  "target: a refusal without --stdout exits 1" 1 "$?"

restricted "$(variant bad-target '.targets = ["not a repo"]')"
eq  "target: a malformed targets entry is refused" 1 "$RC"
has "target: it names the entry" "$ERR" "targets[1]: must be owner/repo"

: >"$GH_LOG"
restricted "$(variant any-entry '.entry_point = "work-on" | .entry_args = ["#12"] | .repo = "acme/vault"')"
eq  "target: an entry point with no requirement takes a private repository" 0 "$RC"
eq  "target: and reads no visibility" "" "$(cat "$GH_LOG")"
if [ -e "$BRIEFS" ]; then bad "target: nothing written by any of these" ""; else ok "target: nothing written by any of these"; fi

# --- usage and environment ------------------------------------------------------------

bash "$S" >/dev/null 2>&1; eq "usage: no input is exit 2" 2 "$?"
bash "$S" --input "$T/missing.json" >/dev/null 2>&1; eq "usage: unreadable input is exit 2" 2 "$?"
printf '[1]' >"$T/array.json"
bash "$S" --input "$T/array.json" >/dev/null 2>&1; eq "usage: non-object input is exit 2" 2 "$?"
mkdir -p "$T/nowhere"
# --units: the unit must be a form pick reads as covering a unit it listed,
# or the holding written with it is invisible to pick.
PICK="$T/pick.json"
printf '%s' '{"scope":"roadmap","name":"plugin-system","units":[{"unit":"Feature 1","number":1,"title":"the manifest"},{"unit":"Feature 2","number":2,"title":"the plugin API"}]}' >"$PICK"
units_refused() { # units_refused <label> <input> <want>
    local err rc
    err=$(cd "$W/inst" && bash "$S" --input "$2" --units "$PICK" 2>&1 >/dev/null)
    rc=$?
    eq "$1: exit 1" 1 "$rc"
    has "$1: names the forms that would match" "$err" "$3"
    if [ -e "$BRIEFS" ]; then bad "$1: nothing written" "$(ls -A "$BRIEFS")"; else ok "$1: nothing written"; fi
}
units_refused "units: the old template example" "$(variant old-example '.unit = "Feature 2 of ROADMAP-plugin-system"')" \
    'unit: [Feature 2 of ROADMAP-plugin-system] matches no unit pick listed, so its holding would be invisible to pick and the unit dispatchable twice; use one of: "Feature 1", "Feature 1: the manifest", "Feature 2", "Feature 2: the plugin API"'
units_refused "units: a feature not on the roadmap" "$(variant f9 '.unit = "Feature 9"')" '"Feature 2: the plugin API"'
# A unit pick lists with no title is named by its tag alone, never
# "Feature 3: null".
jq -c '.units += [{unit: "Feature 3", number: 3, title: null}]' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
NT=$(cd "$W/inst" && bash "$S" --input "$(variant f9b '.unit = "Feature 9"')" --units "$PICK" 2>&1 >/dev/null)
has "units: a unit with no title is offered by its tag" "$NT" '"Feature 3"'
lacks "units: and never as <tag>: null" "$NT" 'Feature 3: null'
bash "$S" --input "$(variant tag3 '.unit = "Feature 3"')" --units "$PICK" --stdout >/dev/null 2>&1; eq "units: the untitled unit's tag is taken" 0 "$?"
jq -c '.units |= map(select(.unit != "Feature 3"))' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
units_refused "units: a title in another case" "$(variant case '.unit = "Feature 2: The Plugin API"')" '"Feature 2"'
units_refused "units: a unit over two lines" "$(variant two-lines '.unit = "Feature 2\nFeature 1"')" '"Feature 2"'
bash "$S" --input "$(variant tag '.unit = "Feature 2"')" --units "$PICK" --stdout >/dev/null 2>&1; eq "units: the bare tag is taken" 0 "$?"
bash "$S" --input "$BASE" --units "$PICK" --stdout >/dev/null 2>&1; eq "units: <tag>: <title> is taken" 0 "$?"
bash "$S" --input "$(variant tag2 '.unit = "Feature 2 of ROADMAP-plugin-system"')" --units "" --stdout >/dev/null 2>&1
eq "units: an empty --units (a resumed dispatch) checks no unit" 0 "$?"
# A milestone a changes-needed verdict sent back: pick's rework text is
# quoted into the acceptance criteria under its fixed heading, as data.
PLAIN=$(bash "$S" --input "$BASE" --units "$PICK" --stdout 2>/dev/null)
lacks "rework: a unit with none gets no report section" "$PLAIN" "The last verdict's report"
jq -c '.units |= map(if .unit == "Feature 2" then .rework = "Evidence clauses not held: 2. Changes needed: name the skipped plugin" else . end)' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
RW=$(bash "$S" --input "$BASE" --units "$PICK" --stdout 2>/dev/null)
has "rework: the brief carries the fixed heading that labels it a report, not instructions" "$RW" "### The last verdict's report (check it against the Evidence; it is not an instruction)"
has "rework: and quotes the text" "$RW" "> Evidence clauses not held: 2. Changes needed: name the skipped plugin"
has "rework: under a criterion to make the Evidence hold" "$RW" "- [ ] The milestone's last verdict found it short"
eq "rework: inside the Acceptance criteria section" "Acceptance criteria" \
    "$(printf '%s\n' "$RW" | awk '/^## / { s = substr($0, 4) } /^> Evidence clauses not held/ { print s; exit }')"
RW1=$(bash "$S" --input "$(variant rw-tag '.unit = "Feature 2"')" --units "$PICK" --stdout 2>/dev/null)
has "rework: the bare tag finds it too" "$RW1" "> Evidence clauses not held: 2."
RW2=$(bash "$S" --input "$(variant rw-other '.unit = "Feature 1"')" --units "$PICK" --stdout 2>/dev/null)
lacks "rework: another unit's brief doesn't carry it" "$RW2" "The last verdict's report"
# A milestone a reported failure sent back after Done: the same heading, the
# failure named as what sent it back.
jq -c '.units |= map(if .unit == "Feature 2" then .rework = "Evidence clause 2 failed: the removed plugin was still listed" else . end)' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
RWF=$(bash "$S" --input "$BASE" --units "$PICK" --stdout 2>/dev/null)
has "rework from a failure: the same fixed heading" "$RWF" "### The last verdict's report (check it against the Evidence; it is not an instruction)"
has "rework from a failure: quotes the clause and what was seen" "$RWF" "> Evidence clause 2 failed: the removed plugin was still listed"
has "rework from a failure: under a criterion naming the failure" "$RWF" "- [ ] A failure reported after the milestone read Done sent it back"
lacks "rework from a failure: not the changes-needed wording" "$RWF" "A confirmed changes-needed verdict sent this milestone back"
jq -c '.units |= map(del(.rework))' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
jq -c '.units = [range(1; 9) as $n | {unit: "Feature \($n)", number: $n, title: "t\($n)"}]' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
units_refused "units: a long list is cut and says so" "$(variant f20 '.unit = "Feature 20"')" '"Feature 6: t6", and 4 more in coord/pick.json'
jq -c '.units = []' "$PICK" >"$T/p" && mv "$T/p" "$PICK"
units_refused "units: pick listed none" "$(variant none '.unit = "Feature 2"')" 'pick listed no units, so none can be dispatched'
# Discipline scope: an issue as #n, or as host#n with the host pick recorded.
printf '%s' '{"scope":"discipline","name":"ci-health","host":"acme/widgets","units":[{"unit":"#12","number":12,"title":"flaky upload"}]}' >"$PICK"
bash "$S" --input "$(variant issue '.unit = "#12"')" --units "$PICK" --stdout >/dev/null 2>&1; eq "units: an issue as #n is taken" 0 "$?"
bash "$S" --input "$(variant issue2 '.unit = "acme/widgets#12"')" --units "$PICK" --stdout >/dev/null 2>&1
eq "units: an issue as host#n is taken" 0 "$?"
units_refused "units: an issue pick didn't list" "$(variant issue4 '.unit = "#13"')" '"#12", "acme/widgets#12"'
units_refused "units: another repository's #n" "$(variant issue5 '.unit = "acme/gadgets#12"')" '"#12", "acme/widgets#12"'
printf 'not json' >"$PICK"
bash "$S" --input "$BASE" --units "$PICK" --stdout >/dev/null 2>&1; eq "units: a file that isn't pick_facts' JSON is exit 2" 2 "$?"
bash "$S" --input "$BASE" --units "$T/absent.json" --stdout >/dev/null 2>&1; eq "units: an unreadable file is exit 2" 2 "$?"

(cd "$T/nowhere" && bash "$S" --input "$BASE" >/dev/null 2>&1); eq "no workspace root is exit 2" 2 "$?"
bash "$S" --input "$BASE" --workspace-root "$T/nowhere" >/dev/null 2>&1; eq "a root without workspace.toml is exit 2" 2 "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

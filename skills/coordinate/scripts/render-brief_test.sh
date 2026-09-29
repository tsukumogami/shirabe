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
# writes nothing.
#
# Usage: bash skills/coordinate/scripts/render-brief_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/render-brief.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/render-brief-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { if printf '%s' "$2" | grep -Fq -- "$3"; then ok "$1"; else bad "$1" "missing [$3]"; fi; }
lacks() { if printf '%s' "$2" | grep -Fq -- "$3"; then bad "$1" "unexpected [$3]"; else ok "$1"; fi; }

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
  "dispatcher_session": "coord-alpha",
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
has "channel: dispatcher named"  "$B" 'addressed to its session name `coord-alpha`'
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
lacks "no temporary file left"   "$(ls -A "$BRIEFS")" ".plugin-api."

# --- optional fields absent -----------------------------------------------------------

MIN=$(variant min 'del(.decisions, .read_first, .out_of_scope, .surfaces, .standing_rules) | .phase = "scoping-ahead"')
M=$(bash "$S" --input "$MIN" --stdout)
has "min: no decisions line"      "$M" "None beyond what the documents you read record."
has "min: no pointers line"       "$M" "Nothing beyond the entry point's own inputs."
has "min: no surfaces"            "$M" "no discipline coordinator is named for any surface"
lacks "min: no workspace rules"   "$M" "## Workspace rules"
has "min: scoping ahead"          "$M" "You are scoping ahead"
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
GOT=$(printf '%s\n' "$B" | grep '^## ' | head -7 | tr '\n' '|')
eq  "template: the rendered headings are the template's" "$WANT" "$GOT"

# An --interactive run mode is allowed (the human's decisions may ask for it,
# per the template), and the caution still reaches the worker.
I=$(bash "$S" --input "$(variant interactive '.run_mode = "--interactive"')" --stdout)
has "interactive: the caution is there too" "$I" 'Run mode: `--interactive`. A background worker can'"'"'t answer the confirmation `--interactive` waits for.'
has "checkpoints: never wait for approval" "$B" "don't wait for approval to go past it"

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

for k in topic repo unit entry_point run_mode phase authority goal dispatcher_session; do
    refused "missing $k" "$(variant "no-$k" "del(.$k)")" "$k: required"
done
refused "empty goal"            "$(variant empty-goal '.goal = "  "')"                     "goal: required"
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
refused "bad phase"             "$(variant bp '.phase = "done"')"                           "phase: must be scoping-ahead or executing"
refused "multi-line session"    "$(variant ms '.dispatcher_session = "a\nb"')"              "dispatcher_session: must be one line"
refused "bad surface"           "$(variant bs '.surfaces = [{"surface": "ci"}]')"           "surfaces: must be"
refused "bad decision"          "$(variant bd '.decisions = [{"decision": "x"}]')"          "decisions: must be"
refused "flag given twice"      "$(variant dup '.entry_args += ["--auto"]')"                "--auto is given twice"
refused "both modes"            "$(variant both '.run_mode = "--auto --interactive"')"      "--auto and --interactive together"
refused "quote in positional"   "$(variant q '.entry_args = ["a\"b"]')"                     "may not contain a quote"
refused "dollar in positional"  "$(variant d '.entry_args = ["$(x)"]')"                     "may not contain a quote"
refused "session id"            "$(variant uuid '.goal = "Resume 3f2b8c1e-9a4d-4c2e-8f1a-2b3c4d5e6f70."')" "UUID-shaped token"

ERR=$(cd "$W/inst" && bash "$S" --input "$BASE" --return-path 'nope; rm' 2>&1 >/dev/null); RC=$?
eq  "bad return path: exit 1" 1 "$RC"
has "bad return path: names it" "$ERR" "--return-path: not message"
if [ -e "$BRIEFS" ]; then bad "bad return path: nothing written" ""; else ok "bad return path: nothing written"; fi

# --- the entry point's target requirement ----------------------------------------------
#
# The shipped table restricts no entry point, so these run on a stand-in where
# /deliver and /execute take only public repositories and name /work-on and
# nothing instead. gh is a stand-in that answers `api repos/<r>` and logs.
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

restricted "$(variant exec-priv '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"] | .targets = ["acme/vault"]')"
eq  "target: a PLAN's private issue repository is refused" 1 "$RC"
has "target: with no alternative, the unit goes back to pick" "$ERR" "no entry point takes it; the unit goes back to pick"

restricted "$(variant unread '.repo = "acme/unknown"')"
eq  "target: a visibility that can't be read is exit 2, never a pass" 2 "$RC"

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
(cd "$T/nowhere" && bash "$S" --input "$BASE" >/dev/null 2>&1); eq "no workspace root is exit 2" 2 "$?"
bash "$S" --input "$BASE" --workspace-root "$T/nowhere" >/dev/null 2>&1; eq "a root without workspace.toml is exit 2" 2 "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# rule-grants_engine_test.sh -- state-stored-set.sh --rules' grants and
# allows on a real koto session of the shipped coordinate.md
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md): the floor and
# the repository anchor settle rows with no read, at most one
# `niwa authority check` read answers every other row, a row's words never
# widen the answer's grant, and every answer but a bound one fails closed.
#
# The run's Standing is testdata/standing-rules/grant-rows.json, added with
# `koto context add`: six rows the floor or the anchor settles (s1 a pause,
# s2 an inferred brief rule, s3 a pinned rule, s4 a decision rule, unreadable
# until its provenance is read, s5 a skill rule citing a repository other
# than the plugin manifest's, s6 a doc rule citing a repository other than
# the record's host), and five that pass both (s7 and s8 relayed go-aheads,
# s8's What reading `Cut the release v2.0.0 and close #12.`, s9 a relayed
# approval, s10 a skill rule citing the manifest's repository, s11 a doc rule
# citing the host, acme/widgets). Prints one line per criterion:
#   1. on the six floor and anchor rows alone, --rules prints grants false
#      and allows [] on each, and niwa is never run;
#   3. on all eleven, under a bound answer granting merge-pr at supervised,
#      one read: the five passing rows grant ["merge-pr"], the six don't;
#   4. that read is exactly `authority check -C <the instance root, canonical>
#      --session <CLAUDE_CODE_SESSION_ID> --json`, with no --point;
#   5. --rules --id naming only floor and anchor rows makes no read, one
#      naming a passing row and a floor row makes one, and state-handover.sh
#      makes none;
#   6. the go-ahead naming a release and an issue allows merge-pr alone, and
#      a bound answer with an empty grant grants with nothing allowed;
#   7. every answer but a bound one (exit 1, not-dispatched, record-unusable,
#      another schema, a grant or level outside niwa's vocabularies, nothing,
#      text that isn't JSON, a read past its bound) gives grants false and
#      allows [] on every row, --rules exiting 0 and every other field as
#      under the bound answer;
#   8. no niwa, no session id, no instance root, or a record/meta naming
#      another driver makes no read; NIWA_BIN names niwa off PATH;
#   9. run from a copy of the plugin whose manifest names no repository, the
#      skill row citing the original's repository doesn't grant, and on a
#      record where it is the only row that would pass, no read is made;
#  11. check-template-compat.sh holds for the shipped template with the
#      gate_scripts digest recorded, and no gate or action of the compiled
#      template names grants or --rules.
# Criterion 2, rule_grants over rows and hand-written facts, is
# state-schema_test.sh's; criterion 10, step 1's record read through --rules,
# is standing-rules_engine_test.sh's.
#
# niwa is never the real one: a fake in the scratch directory, first on
# PATH, appends its arguments to a call log and answers from an answer file,
# or as a mode file says (exit 1 still printing the answer, print nothing,
# sleep). The no-niwa case runs under a PATH in which every directory holding
# a niwa is replaced by a copy without it. Reads are counted by the call
# log's lines.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there for the
# session before the first koto command, or the suite stops.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/rule-grants_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
ORIG_PATH=$PATH
# test-lib.sh makes the scratch directory T, the gh DB helpers, state_json and
# the ok/bad/eq counters. It puts testdata/ (the koto stand-in) first on PATH;
# this suite needs the real koto, so PATH is rebuilt below.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH NIWA_BIN CLAUDE_CODE_SESSION_ID NIWA_LOOKUP_SECONDS
export HOME="$T/home" KOTO_HOME="$T/home/.koto" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/bin" "$T/fake"

# The fake niwa: it logs its arguments and answers from $T/niwa.answer, or as
# $T/niwa.mode says: exit 1 (still printing the answer), print nothing, sleep.
cat > "$T/fake/niwa" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/niwa.calls"
case "\$(cat "$T/niwa.mode" 2>/dev/null)" in
    exit1) cat "$T/niwa.answer"; exit 1 ;;
    empty) exit 0 ;;
    sleep) sleep 30 ;;
esac
cat "$T/niwa.answer"
EOF
chmod +x "$T/fake/niwa"
BASE_PATH="$T/bin:$ORIG_PATH"
PATH="$T/fake:$BASE_PATH"
export PATH

# The session, named here and nowhere else.
G=coordinate-roadmap-grants-20261020T090000Z
d=$(koto session dir "$G" 2>&1) || { echo "FAIL: koto session dir $G failed: [$d]; no case ran"; exit 1; }
case "$d" in
    "$T"/*) ;;
    *) echo "FAIL: koto's session directory for $G is not under $T: [$d]; no case ran"; exit 1 ;;
esac
# NOPATH: BASE_PATH with every directory holding a niwa replaced by a copy
# without it.
NOPATH= i=0
IFS=: read -r -a PATH_DIRS <<< "$BASE_PATH"
for d in "${PATH_DIRS[@]}"; do
    [ -n "$d" ] || continue
    if [ -e "$d/niwa" ]; then
        i=$((i + 1)); mkdir -p "$T/nopath$i"
        for f in "$d"/*; do [ "${f##*/}" = niwa ] || ln -s "$f" "$T/nopath$i/"; done
        d="$T/nopath$i"
    fi
    NOPATH="$NOPATH${NOPATH:+:}$d"
done
PATH="$NOPATH" command -v niwa >/dev/null 2>&1 && { echo "FAIL: a niwa is still on the no-niwa PATH; no case ran"; exit 1; }

# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
# session_seed and koto_store_ready.
. "$HERE/testdata/engine-session.sh"
export COORD_TESTDATA="$HERE/testdata"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
. "$COORD_TESTDATA/gh" "$@"
EOF
chmod +x "$T/bin/gh"

# koto refuses a --var value outside its allowlist (a `+` in a checkout's
# path, for one), so PLUGIN_ROOT is a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
ROWS="$HERE/testdata/standing-rules/grant-rows.json"
# The instance, and the repository the coordinator runs in. VIA reaches the
# instance through a symlink, so the read must name the canonical root.
INST="$HOME/ws/inst"
WD="$INST/repo"
mkdir -p "$INST/.niwa" "$WD" "$T/elsewhere"
echo '{}' > "$INST/.niwa/instance.json"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
ln -s "$INST" "$T/via"
INST_P=$(cd "$INST" && pwd -P)
SID=4f1c2b9e-7d3a-4e6b-9a8c-0d1e2f3a4b5c
OTHER=9e8d7c6b-5a49-4382-a1b0-c9d8e7f6a5b4
MANIFEST_REPO=$(jq -r '.repository // ""' "$REPO_ROOT/.claude-plugin/plugin.json")

# One line per criterion: need records what failed, crit prints the line.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { if [ -z "$WHY" ]; then ok "$1"; else bad "$1" "${WHY#; }"; fi; WHY=; }
stop() { bad "$1" "${2-}"; done_tests rule-grants-engine; exit 1; }

[ "$MANIFEST_REPO" = https://github.com/tsukumogami/shirabe ] \
    || stop "the plugin manifest names the repository s10 cites" "it names [$MANIFEST_REPO]"

# ---- helpers ---------------------------------------------------------------
at() { (cd "$WD" && koto next "$1" "${@:2}" --no-cleanup 2>"$T/tick.err") | jq -r '.state // empty'; }
ctx() { (cd "$WD" && koto context get "$1" "$2" 2>/dev/null); }
put() { (cd "$WD" && koto context add "$1" "$2" --from-file "$3"); }
# standing <ids...>: put those rows of grant-rows.json in the run's Standing.
standing() {
    jq -c --arg ids "$*" '($ids | split(" ")) as $k | map(select(.standing as $s | $k | index($s)))' "$ROWS" > "$T/standing.json" \
        && put "$G" record/standing "$T/standing.json"
}
# answer <json>: the fake's answer; mode <mode>: how it answers. Each clears
# the call log, so a count after them is the next command's alone.
answer() { printf '%s\n' "$1" > "$T/niwa.answer"; mode answer; }
mode() { printf '%s' "$1" > "$T/niwa.mode"; rm -f "$T/niwa.calls"; }
calls() { if [ -e "$T/niwa.calls" ]; then wc -l < "$T/niwa.calls" | tr -d ' '; else echo 0; fi; }
# rules [args...]: --rules on the run, from the repository, as this session.
rules() { (cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID bash "$PS/state-stored-set.sh" --session "$G" --rules "$@"); }
# verdicts <file>: each object's `<id>:<grants>:<allows>`, space-separated.
verdicts() { jq -r '"\(.standing):\(.grants):\(.allows | tojson)"' "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
# bound <authorities, comma-separated> <level>: a bound answer.
bound() {
    jq -nc --arg g "$1" --arg l "$2" '{schema: "niwa.authority.check/v1", state: "bound", binding: "mapping",
        dispatch_id: "dispatch-under-test", grant: [$g | split(",")[] | select(. != "") | {authority: ., sources: ["dispatch"]}],
        level: $l, level_source: "workspace", grant_ceiling_source: "workspace"}'
}
FLOOR_NONE='s1:false:[] s2:false:[] s3:false:[] s4:false:[] s5:false:[] s6:false:[]'
PASS_MERGE='s7:true:["merge-pr"] s8:true:["merge-pr"] s9:true:["merge-pr"] s10:true:["merge-pr"] s11:true:["merge-pr"]'
PASS_NONE='s7:false:[] s8:false:[] s9:false:[] s10:false:[] s11:false:[]'
ALL_NONE="$FLOOR_NONE $PASS_NONE"

# ---- the run ----------------------------------------------------------------
db_init
db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-grants.md"] = $t' \
    --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 3: third\n**Dependencies:** None\n**Status:** Not started\n')"
koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"
jq -nc --arg p "$PR" '[["SCOPE", "roadmap"], ["ROADMAP", "docs/roadmaps/ROADMAP-grants.md"], ["HOST_REPO", "acme/widgets"],
    ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"
(cd "$WD" && bash "$PR/scripts/koto-open.sh" "$G" "$TPL" "$T/vars.json") > "$T/open.out" 2> "$T/open.err" \
    || stop "the run opens" "$(cat "$T/open.out" "$T/open.err")"
(cd "$WD" && session_seed "$G" "$(record_json roadmap grants)" 2026-10-20T08:00:00Z) || stop "the run's record is seeded" ""
[ "$(at "$G")" = reconcile ] || stop "the run finds its record" "$(cat "$T/tick.err")"
ctx "$G" record/meta > "$T/meta.json"
jq -e 'type == "object" and ((.driver // "") == "")' "$T/meta.json" > /dev/null || stop "the run's record/meta names no driver" "$(cat "$T/meta.json")"
BOUND_MERGE=$(bound merge-pr supervised)

# ---- 1 ------------------------------------------------------------------------
standing s1 s2 s3 s4 s5 s6 || stop "the floor and anchor rows are added" ""
answer "$BOUND_MERGE"
rules > "$T/floor.out" 2> "$T/floor.err"
need "--rules exits 0" 0 "$?$(cat "$T/floor.err")"
need "  ... each row grants false with nothing allowed" "$FLOOR_NONE" "$(verdicts "$T/floor.out")"
need "  ... and niwa is never run" 0 "$(calls)"
crit "1. on a pause, an inferred brief row, a pinned row, a decision row and a skill and a doc row citing other repositories, every object prints grants false and allows [], with no read"

# ---- 3 and 4 ------------------------------------------------------------------
standing s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 || stop "the eleven rows are added" ""
answer "$BOUND_MERGE"
# From the instance reached through a symlink: the read names it canonical.
(cd "$T/via/repo" && CLAUDE_CODE_SESSION_ID=$SID bash "$PS/state-stored-set.sh" --session "$G" --rules) > "$T/bound.out" 2> "$T/bound.err"
need "--rules exits 0" 0 "$?$(cat "$T/bound.err")"
need "  ... one object per row, in record order" "s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11" "$(jq -r .standing "$T/bound.out" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
need "  ... the five passing rows grant merge-pr, the six don't" "$FLOOR_NONE $PASS_MERGE" "$(verdicts "$T/bound.out")"
need "  ... from exactly one read" 1 "$(calls)"
crit "3. under a bound answer granting merge-pr, one read: the two go-aheads, the approval and the anchored skill and doc rows print grants true and allows [\"merge-pr\"], the six floor and anchor rows false and []"
printf 'authority check -C %s --session %s --json\n' "$INST_P" "$SID" > "$T/call.want"
cmp -s "$T/call.want" "$T/niwa.calls" || needf "the read is [$(cat "$T/niwa.calls" 2>/dev/null)], not [$(cat "$T/call.want")]"
grep -q -- '--point' "$T/niwa.calls" 2>/dev/null && needf "the read passes --point"
case "$INST_P" in "$T/via"*) needf "the instance root isn't canonical: $INST_P" ;; esac
crit "4. the one read is exactly \`authority check -C <the instance root, canonical> --session <CLAUDE_CODE_SESSION_ID> --json\`, with no --point"
# Every other field, under the bound answer, for criterion 7.
jq -c 'del(.grants, .allows)' "$T/bound.out" > "$T/bound.rest"

# ---- 5 ------------------------------------------------------------------------
answer "$BOUND_MERGE"
rules --id s1 --id s2 --id s3 --id s4 --id s5 --id s6 > "$T/ids.out" 2> "$T/ids.err"
need "--rules --id naming the six floor and anchor rows exits 0 with no read" "0 0" "$? $(calls)"
need "  ... printing them false" "$FLOOR_NONE" "$(verdicts "$T/ids.out")"
answer "$BOUND_MERGE"
rules --id s9 --id s3 > "$T/ids2.out" 2> "$T/ids2.err"
need "--rules --id naming a passing row and a floor row makes one read" "0 1" "$? $(calls)"
need "  ... the passing row granting, the floor row not" 's3:false:[] s9:true:["merge-pr"]' "$(verdicts "$T/ids2.out")"
answer "$BOUND_MERGE"
(cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID bash "$PS/state-handover.sh" --session "$G") > "$T/handover.out" 2> "$T/handover.err"
need "state-handover.sh reads the record with no read of niwa" "0 0" "$? $(calls)"
crit "5. --rules --id naming only floor or anchor rows makes no read, naming a passing row and a floor row makes one, and state-handover.sh makes none"

# ---- 6 ------------------------------------------------------------------------
need "the go-ahead reading \`Cut the release v2.0.0 and close #12.\` allows merge-pr alone" \
    'Cut the release v2.0.0 and close #12.|true|["merge-pr"]' \
    "$(jq -r 'select(.standing == "s8") | "\(.what)|\(.grants)|\(.allows | tojson)"' "$T/bound.out" 2>/dev/null)"
answer "$(bound "" strict)"
rules > "$T/empty-grant.out" 2> "$T/empty-grant.err"
need "under a bound answer with an empty grant, --rules exits 0 after one read" "0 1" "$? $(calls)"
need "  ... every passing row grants with nothing allowed" "$FLOOR_NONE s7:true:[] s8:true:[] s9:true:[] s10:true:[] s11:true:[]" "$(verdicts "$T/empty-grant.out")"
crit "6. the go-ahead naming a release and an issue allows [\"merge-pr\"] alone, and under a bound answer with an empty grant every passing row grants with allows []"

# ---- 7 ------------------------------------------------------------------------
# closed <label>: --rules under the fake as set gives every row false and [],
# exits 0, made one read, and every other field is as under the bound answer.
closed() {
    rules > "$T/closed.out" 2> "$T/closed.err"
    need "$1: --rules exits 0 after one read" "0 1" "$? $(calls)"
    need "$1: every row grants false with nothing allowed" "$ALL_NONE" "$(verdicts "$T/closed.out")"
    jq -c 'del(.grants, .allows)' "$T/closed.out" > "$T/closed.rest" 2>/dev/null
    cmp -s "$T/bound.rest" "$T/closed.rest" || needf "$1: another field differs from the bound answer's output"
}
answer "$BOUND_MERGE"; mode exit1; closed "exit 1 with a bound document"
answer '{"schema":"niwa.authority.check/v1","state":"not-dispatched","reason":"no-mapping","grant":[]}'; closed "not-dispatched"
answer '{"schema":"niwa.authority.check/v1","state":"record-unusable","reason":"record-missing","dispatch_id":"dispatch-under-test","grant":[]}'; closed "record-unusable"
answer "$(jq -c '.schema = "niwa.authority.check/v2"' <<< "$BOUND_MERGE")"; closed "another schema"
answer "$(jq -c '.grant = "merge-pr"' <<< "$BOUND_MERGE")"; closed "a grant that isn't an array"
answer "$(jq -c '.grant[0].authority = "push-tag"' <<< "$BOUND_MERGE")"; closed "a grant naming another authority"
answer "$(jq -c '.level = "relaxed"' <<< "$BOUND_MERGE")"; closed "a level outside the three"
answer "$BOUND_MERGE"; mode empty; closed "empty stdout"
answer 'merge-pr: granted'; closed "text that isn't JSON"
answer "$BOUND_MERGE"; mode sleep
start=$(date +%s)
export NIWA_LOOKUP_SECONDS=1
closed "a read that sleeps 30 seconds under NIWA_LOOKUP_SECONDS=1"
unset NIWA_LOOKUP_SECONDS
took=$(( $(date +%s) - start ))
[ "$took" -lt 10 ] || needf "the sleeping read held --rules ${took}s, not under 10"
mode answer
crit "7. exit 1, not-dispatched, record-unusable, another schema, a bad grant or level, empty stdout, text that isn't JSON and a read past its bound each give grants false and allows [] on every row, exit 0, every other field unchanged"

# ---- 8 ------------------------------------------------------------------------
answer "$BOUND_MERGE"
(cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID PATH="$NOPATH" bash "$PS/state-stored-set.sh" --session "$G" --rules) > "$T/n.out" 2> "$T/n.err"
need "with no niwa on PATH and no NIWA_BIN, no read" "0 0" "$? $(calls)"
need "  ... and every row false" "$ALL_NONE" "$(verdicts "$T/n.out")"
answer "$BOUND_MERGE"
(cd "$WD" && bash "$PS/state-stored-set.sh" --session "$G" --rules) > "$T/n.out" 2> "$T/n.err"
need "with CLAUDE_CODE_SESSION_ID unset, no read" "0 0" "$? $(calls)"
need "  ... and every row false" "$ALL_NONE" "$(verdicts "$T/n.out")"
answer "$BOUND_MERGE"
(cd "$T/elsewhere" && CLAUDE_CODE_SESSION_ID=$SID bash "$PS/state-stored-set.sh" --session "$G" --rules) > "$T/n.out" 2> "$T/n.err"
need "from a directory with no .niwa/instance.json at or above it, no read" "0 0" "$? $(calls)"
need "  ... and every row false" "$ALL_NONE" "$(verdicts "$T/n.out")"
answer "$BOUND_MERGE"
(cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID NIWA_BIN="$T/fake/niwa" PATH="$NOPATH" bash "$PS/state-stored-set.sh" --session "$G" --rules) > "$T/n.out" 2> "$T/n.err"
need "with niwa off PATH and NIWA_BIN naming the fake, one read" "0 1" "$? $(calls)"
need "  ... answering as on PATH" "$FLOOR_NONE $PASS_MERGE" "$(verdicts "$T/n.out")"
# A takeover writes record/meta's driver: a record driven by another session
# makes no read, and one driven by this session reads as before.
jq -c --arg d "$OTHER" '.driver = $d' "$T/meta.json" > "$T/meta-other.json"
put "$G" record/meta "$T/meta-other.json" || needf "the other driver's record/meta isn't added"
answer "$BOUND_MERGE"
rules > "$T/n.out" 2> "$T/n.err"
need "on a record whose record/meta names another driver, no read" "0 0" "$? $(calls)"
need "  ... and every row false" "$ALL_NONE" "$(verdicts "$T/n.out")"
jq -c --arg d "$SID" '.driver = $d' "$T/meta.json" > "$T/meta-mine.json"
put "$G" record/meta "$T/meta-mine.json" || needf "this session's record/meta isn't added"
answer "$BOUND_MERGE"
rules > "$T/n.out" 2> "$T/n.err"
need "on a record this session drives, one read" "0 1" "$? $(calls)"
need "  ... answering as with no driver" "$FLOOR_NONE $PASS_MERGE" "$(verdicts "$T/n.out")"
put "$G" record/meta "$T/meta.json" || needf "the run's record/meta isn't put back"
crit "8. no niwa, no session id, no instance root, or record/meta naming another driver: no read and every row false; NIWA_BIN names niwa off PATH"

# ---- 9 ------------------------------------------------------------------------
# A copy of the plugin whose manifest has no repository field.
mkdir -p "$T/bare/skills" "$T/bare/.claude-plugin"
cp -R "$REPO_ROOT/skills/coordinate" "$T/bare/skills/" || stop "the plugin is copied" ""
jq 'del(.repository)' "$REPO_ROOT/.claude-plugin/plugin.json" > "$T/bare/.claude-plugin/plugin.json"
answer "$BOUND_MERGE"
(cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID bash "$T/bare/skills/coordinate/scripts/state-stored-set.sh" --session "$G" --rules) > "$T/bare.out" 2> "$T/bare.err"
need "from the copy, --rules exits 0 after one read" "0 1" "$? $(calls)"
need "  ... and the skill row citing the original's repository doesn't grant" \
    "$FLOOR_NONE s7:true:[\"merge-pr\"] s8:true:[\"merge-pr\"] s9:true:[\"merge-pr\"] s10:false:[] s11:true:[\"merge-pr\"]" "$(verdicts "$T/bare.out")"
standing s1 s2 s3 s4 s5 s6 s10 || stop "the floor rows and the anchored skill row are added" ""
answer "$BOUND_MERGE"
(cd "$WD" && CLAUDE_CODE_SESSION_ID=$SID bash "$T/bare/skills/coordinate/scripts/state-stored-set.sh" --session "$G" --rules) > "$T/bare.out" 2> "$T/bare.err"
need "where it is the only row that would pass, the copy makes no read" "0 0" "$? $(calls)"
need "  ... and every row is false" "$FLOOR_NONE s10:false:[]" "$(verdicts "$T/bare.out")"
answer "$BOUND_MERGE"
rules > "$T/bare.out" 2> "$T/bare.err"
need "  ... while the installed plugin, naming it, reads once and grants it" "0 1 s10:true:[\"merge-pr\"]" \
    "$? $(calls) $(jq -c 'select(.standing == "s10")' "$T/bare.out" | verdicts /dev/stdin)"
crit "9. run from a copy whose manifest names no repository, the skill row citing the original's repository prints grants false, and where it is the only row that would pass, no read"

# ---- 11 -----------------------------------------------------------------------
(cd "$WD" && bash "$REPO_ROOT/scripts/check-template-compat.sh" --template "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.md") > "$T/compat.out" 2>&1
RC_COMPAT=$?
[ "$RC_COMPAT" = 0 ] || needf "check-template-compat.sh exits $RC_COMPAT, not 0: $(cat "$T/compat.out")"
COMPILED=$(cd "$WD" && koto template compile "$TPL" < /dev/null 2> "$T/compile.err")
# The structure a run executes (template-fingerprint.jq: every gate, action
# and transition, with the prose left out) names neither.
need "  ... no gate or action of the compiled template names grants or --rules" 0 \
    "$(jq -c -f "$HERE/template-fingerprint.jq" "$COMPILED" 2>&1 | jq '[.. | strings | select(test("grants|--rules"))] | length' 2>&1)"
crit "11. the compat table holds for the shipped template with the gate_scripts digest recorded, and no gate reads grants"

done_tests rule-grants-engine

#!/usr/bin/env bash
# driver-check_engine_test.sh -- the record writers' driver check on real koto
# sessions of the shipped coordinate.md, against the testdata/gh stand-in
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md, the
# acceptance terms for the driver check, D1 to D19; D6 is
# scripts/check-template-compat_test.sh's and the CI compat-table check's).
#
# A driven record is one whose record/meta holds a `driver` id, seeded with
# `koto context add`. D_ID is that id and X_ID another of the same shape; the
# caller's id is CLAUDE_CODE_SESSION_ID, unset here and set per command, and
# its name the job state file under DC_CLAUDE_HOME naming it. "Nothing
# written" means every record/ key, entries included, byte-identical and no
# key added. Prints one line per criterion, named by its D number.
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME, every
# KOTO_SESSION_* name and KOTO_SESSIONS_BASE unset, and the store asserted
# under the scratch directory (D19 sets two bases of its own there).
#
# Needs koto, jq and git; SKIPs (exit 0) without one, which run-tests.sh
# --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/driver-check_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
ORIG_PATH=$PATH
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH NIWA_BIN CLAUDE_CODE_SESSION_ID DC_CLAUDE_HOME KOTO_BIN
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/bin" "$T/claude/jobs"
export DC_CLAUDE_HOME="$T/claude"
ln -sf "$HERE/testdata/gh" "$T/bin/gh"
PATH="$T/bin:$ORIG_PATH"
export PATH
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
. "$HERE/testdata/engine-session.sh"

ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
WD="$T/work"
mkdir -p "$WD"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
case "$(cd "$WD" && koto session dir probe)" in
    "$KOTO_TEST_GUARD_DIR"/*|"$T"/*) ;;
    *) echo "FAIL: the koto store is outside the scratch directory; no case ran"; exit 1 ;;
esac

D_ID=$(printf '%s-0000-4000-8000-%012d' dddddddd 1)
X_ID=$(printf '%s-0000-4000-8000-%012d' eeeeeeee 2)
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 3)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 4)
TODAY=$(date -u +%Y-%m-%d)
day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }

# One line per criterion: need records what failed, crit prints the line.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { if [ -z "$WHY" ]; then ok "$1"; else bad "$1" "${WHY#; }"; fi; WHY=; }
stop() { bad "$1" "${2-}"; done_tests driver-check-engine; exit 1; }

# ---- helpers ---------------------------------------------------------------
# as <id|-> <command...>: the command from the workspace, run by the Claude
# session <id>, or by none (-).
as() {
    local id=$1; shift
    if [ "$id" = - ]; then (cd "$WD" && env -u CLAUDE_CODE_SESSION_ID "$@")
    else (cd "$WD" && env CLAUDE_CODE_SESSION_ID="$id" "$@"); fi
}
ctx() { (cd "$WD" && koto context get "$1" "$2" 2>/dev/null); }
put() { (cd "$WD" && koto context add "$1" "$2" --from-file "$3") > /dev/null; }
putj() { printf '%s' "$3" > "$T/put.json"; put "$1" "$2" "$T/put.json"; }
at() { (cd "$WD" && koto next "$1" "${@:2}" --no-cleanup 2>"$T/tick.err") | jq -r '.state // empty'; }
# job <id> <name>: a Claude job naming the session <id> with <name>; nojobs: none.
job() { mkdir -p "$DC_CLAUDE_HOME/jobs/job-$2"; jq -n --arg s "$1" --arg n "$2" '{sessionId: $s, name: $n, state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-$2/state.json"; }
nojobs() { rm -rf "$DC_CLAUDE_HOME/jobs"; mkdir -p "$DC_CLAUDE_HOME/jobs"; }
# driver <session> <json value|absent>: record/meta's driver, set by hand.
driver() {
    if [ "$2" = absent ]; then ctx "$1" record/meta | jq -c 'del(.driver)' > "$T/meta.json"
    else ctx "$1" record/meta | jq -c --argjson d "$2" '.driver = $d' > "$T/meta.json"; fi
    put "$1" record/meta "$T/meta.json"
}
# snap <session>: every record/ key, its value as hex bytes.
snap() {
    local k
    (cd "$WD" && koto context list "$1" --prefix record/) > "$T/snap.keys" 2>/dev/null || { echo unreadable; return; }
    jq -c 'sort' "$T/snap.keys"
    for k in $(jq -r 'sort | .[]' "$T/snap.keys"); do
        printf '%s %s\n' "$k" "$(ctx "$1" "$k" | od -An -tx1 | tr -d ' \n')"
    done
}
entries_n() { (cd "$WD" && koto context list "$1" --prefix record/entries/) | jq length; }
last_entry() { local k; k=$( (cd "$WD" && koto context list "$1" --prefix record/entries/) | jq -r 'sort | .[-1]'); ctx "$1" "$k"; }
run_rows() { ctx "$1" record/run; }
coord_row() { run_rows "$1" | jq -c '[.[] | select(.key == "coordinator")][0] // empty'; }

# A roadmap run opened with koto-open.sh holding a seeded record, found.
roadmap_file() {
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-" + $n + ".md"] = $r' --arg n "$1" \
        --arg r "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n')"
}
# open_seeded <session> <name> <record-json>: the run opened, its record seeded,
# and its first tick at reconcile.
open_seeded() {
    roadmap_file "$2"
    jq -nc --arg p "$PR" --arg n "$2" '[["SCOPE", "roadmap"], ["ROADMAP", "docs/roadmaps/ROADMAP-" + $n + ".md"], ["HOST_REPO", "acme/widgets"],
        ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"
    (cd "$WD" && bash "$PR/scripts/koto-open.sh" "$1" "$TPL" "$T/vars.json") > "$T/open.out" 2> "$T/open.err" || return 1
    (cd "$WD" && session_seed "$1" "$3" 2026-10-20T08:00:00Z) || return 1
    [ "$(at "$1")" = reconcile ]
}
row() { jq -nc --arg k "$1" --arg v "$2" --arg b "${3:-the human}" '{key: $k, value: $v, set_by: $b, set: "2026-10-20T08:00Z"}'; }
# discipline_run <name> [<id>]: a discipline's first rotation opened through the
# opener and opened by state-open.sh, as <id> (default none), at reconcile; S
# names it. OPEN_OUT and $T/seed.out keep the opener's and the seed's output.
discipline_run() {
    local id=${2:--}
    jq -nc --arg d "$1" '["--discipline", $d, "--host", "acme/widgets", "--role", "manager"]' > "$T/args.json"
    OPEN_OUT=$(as "$id" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ] && [ "$(at "$S")" = record_open ] || return 1
    as "$id" bash "$PS/state-open.sh" --session "$S" --role manager --start "$TODAY" --end "$(day 6)" > "$T/seed.out" 2> "$T/seed.err" || return 1
    [ "$(at "$S" --with-data '{"opened":"opened"}')" = reconcile ]
}

# ---- the D1 calls ----------------------------------------------------------
# Each call is prepared (prep, which may write as no Claude session) and then
# made (cmd) on $G (a roadmap record) or $SD (a discipline record); K is a
# counter so a call that writes writes something new each time.
K=0
ROADMAP_CALLS="cap host rule_files told pending standing end work done write_state pushed_head decision hold rstatus entry"
DISC_CALLS="rotation reasoning seed"
D1_CALLS="$ROADMAP_CALLS $DISC_CALLS"
# The calls whose writer reads the record before its guard (rs_record).
RS_FIRST="cap rule_files told pending standing end work done decision hold rstatus"
# Today's exit for each call made by the driver (D2): the decision write is
# bound to decision_raise (65 at reconcile), and the discipline seed finds a
# record already (10).
today_rc() { case "$1" in decision) echo 65 ;; seed) echo 10 ;; *) echo 0 ;; esac; }
prog_of() {
    case "$1" in
        write_state|pushed_head) echo state-write ;; decision) echo state-decision ;; hold) echo state-hold ;;
        rstatus) echo roadmap-status ;; entry) echo state-entry ;; seed) echo state-open ;; *) echo state-stored-set ;;
    esac
}
target_of() { case " $DISC_CALLS " in *" $1 "*) echo "$SD" ;; *) echo "$G" ;; esac; }
prep() {
    local s
    s=$(target_of "$1")
    K=$((K + 1))
    case "$1" in
        rule_files)
            jq -nc --arg p "/srv/rules/SKILL-$K.md" --arg d "$(printf '%064d' "$K")" '{label: "skill-drv", path: $p, digest: $d}' > "$T/rf.json" ;;
        end)
            ctx "$s" record/standing | jq -e 'length > 0' > /dev/null 2>&1 \
                || as - bash "$PS/state-stored-set.sh" --session "$s" --standing go-ahead --what "ship step $K" --owner "the human" > /dev/null 2>&1
            END_ID=$(ctx "$s" record/standing | jq -r '.[-1].standing // "s1"') ;;
        done)
            ctx "$s" record/work | jq -e 'any(.[]; .kind == "local-agent")' > /dev/null 2>&1 \
                || as - bash "$PS/state-stored-set.sh" --session "$s" --work "task-$K" --kind local-agent --who "the human" --next "step $K" > /dev/null 2>&1
            DONE_ITEM=$(ctx "$s" record/work | jq -r '[.[] | select(.kind == "local-agent") | .item][0] // "task-0"') ;;
        write_state)
            (cd "$WD" && session_record "$s") > "$T/state.json" ;;
        hold)
            jq -n --arg h "hold-$K" '{hold: $h, on: "acme/widgets#12", until: "lifted", set_by: "the human", set: "2026-10-01T10:00Z", lifted: ""}' > "$T/hold.json" ;;
        rstatus)
            ctx "$s" record/side-effects | jq -e 'any(.[]; .target | startswith("Feature 1 "))' > /dev/null 2>&1 \
                || putj "$s" record/side-effects '[{"action":"roadmap-status","target":"Feature 1 [#5](https://github.com/acme/widgets/pull/5)","verified_head":"","attempted":"2026-10-20T07:00Z","how_to_confirm":"the roadmap on main reads Feature 1 Done"}]' ;;
        entry) printf 'note %s\n' "$K" > "$T/entry.txt" ;;
        rotation)
            ctx "$s" record/rotation | jq -c --arg e "$(day $((6 + K)))" '.end = $e' > "$T/rot.json" ;;
        reasoning) printf 'reasoning for the next rotation, %s\n' "$K" > "$T/reasoning.txt" ;;
    esac
}
cmd() {
    local s
    s=$(target_of "$1")
    case "$1" in
        cap) bash "$PS/state-stored-set.sh" --session "$s" --run cap 3 --by "the human" ;;
        host) bash "$PS/state-stored-set.sh" --session "$s" --host source_workspace "/srv/work-$K" ;;
        rule_files) bash "$PS/state-stored-set.sh" --session "$s" --rule-files "$T/rf.json" --by "the human" ;;
        told) bash "$PS/state-stored-set.sh" --session "$s" --told "worker-$K" --by "the human" ;;
        pending) bash "$PS/state-stored-set.sh" --session "$s" --pending "pend-$K" --by "the human" ;;
        standing) bash "$PS/state-stored-set.sh" --session "$s" --standing go-ahead --what "ship step $K" --owner "the human" ;;
        end) bash "$PS/state-stored-set.sh" --session "$s" --end "$END_ID" --by "the human" ;;
        work) bash "$PS/state-stored-set.sh" --session "$s" --work "task-$K" --kind local-agent --who "the human" --next "step $K" ;;
        done) bash "$PS/state-stored-set.sh" --session "$s" --done "$DONE_ITEM" --kind local-agent ;;
        write_state) bash "$PS/state-write.sh" --session "$s" --state-file "$T/state.json" ;;
        pushed_head) bash "$PS/state-write.sh" --session "$s" --pushed-head feature-1 "$(printf '%040d' "$K")" ;;
        decision) bash "$PS/state-decision.sh" --session "$s" --open --question "Ship step $K?" --option yes --option no ;;
        hold) bash "$PS/state-hold.sh" --session "$s" --add --row-file "$T/hold.json" ;;
        rstatus) bash "$PS/roadmap-status.sh" --session "$s" --drop "Feature 1" --reason "the pull request was closed ($K)" ;;
        entry) bash "$PS/state-entry.sh" --session "$s" --kind entry --text-file "$T/entry.txt" ;;
        rotation) bash "$PS/state-stored-set.sh" --session "$s" --rotation "$T/rot.json" ;;
        reasoning) bash "$PS/state-stored-set.sh" --session "$s" --reasoning-file "$T/reasoning.txt" ;;
        seed) bash "$PS/state-open.sh" --session "$s" --role manager --start "$TODAY" --end "$(day 6)" ;;
    esac
}
# try <call> <id|-> [env assignments...]: prep, then the call as <id>, its exit
# in RC, stdout in $T/out, stderr in $T/err; NOTHING is yes when its target's
# record/ keys are byte-identical afterwards.
try() {
    local c=$1 id=$2 s before
    shift 2
    s=$(target_of "$c")
    prep "$c"
    before=$(snap "$s")
    ( cd "$WD" || exit 99
      if [ "$id" = - ]; then unset CLAUDE_CODE_SESSION_ID; else export CLAUDE_CODE_SESSION_ID="$id"; fi
      for a in "$@"; do export "${a?}"; done
      cmd "$c" ) > "$T/out" 2> "$T/err"
    RC=$?
    if [ "$before" = "$(snap "$s")" ]; then NOTHING=yes; else NOTHING=no; fi
}
END_ID=s1 DONE_ITEM=task-0
# refused_as <label> <call> <message tail>: the last try exited 10, printed
# nothing, wrote one stderr line `<prog>: refused: driver: <tail>`, and wrote
# nothing.
refused_as() {
    need "$1 $2: exit" 10 "$RC"
    need "$1 $2: stdout" "" "$(cat "$T/out")"
    need "$1 $2: stderr" "$(prog_of "$2"): refused: driver: $3" "$(cat "$T/err")"
    need "$1 $2: nothing written" yes "$NOTHING"
}
# all_refused <label> <id> <tail-for-G> <tail-for-SD> [env...]: every D1 call
# as <id> is refused with the tail for its record.
all_refused() {
    local label=$1 id=$2 tg=$3 tsd=$4 c
    shift 4
    for c in $D1_CALLS; do
        try "$c" "$id" "$@"
        case " $DISC_CALLS " in *" $c "*) refused_as "$label" "$c" "$tsd" ;; *) refused_as "$label" "$c" "$tg" ;; esac
    done
}
# all_today <label> <id> [env...]: every D1 call as <id> exits as it does today.
all_today() {
    local label=$1 id=$2 c
    shift 2
    for c in $D1_CALLS; do
        try "$c" "$id" "$@"
        need "$label $c: exit" "$(today_rc "$c")" "$RC"
        case "$RC" in 0) need "$label $c: no driver refusal" "" "$(grep 'refused: driver' "$T/err")" ;; esac
        # A state file written back unchanged may write nothing.
        [ "$(today_rc "$c")" != 0 ] || [ "$c" = write_state ] || need "$label $c: written" no "$NOTHING"
    done
}
driven_msg() { echo "$1 is driven by Claude session $2, not this one ($3); nothing was written"; }
unread_msg() { echo "$1's driver couldn't be read ($2); nothing was written"; }

# ---- the koto wrapper for D4 ---------------------------------------------------
# It logs nothing and runs the real koto, except that it counts each
# `context get $FAIL_S $FAIL_K` in $FAIL_CNT and fails the FAIL_N-th (or
# every one with FAIL_N=all).
REAL_KOTO=$(command -v koto)
mkdir -p "$T/kw"
cat > "$T/kw/koto" <<EOF
#!/bin/sh
if [ "\$1 \$2" = "context get" ] && [ -n "\${FAIL_S:-}" ] && [ "\$3" = "\$FAIL_S" ] && [ "\$4" = "\$FAIL_K" ]; then
    c=\$(( \$(cat "\$FAIL_CNT" 2>/dev/null || echo 0) + 1 ))
    echo "\$c" > "\$FAIL_CNT"
    if [ "\${FAIL_N:-0}" = all ] || [ "\${FAIL_N:-0}" = "\$c" ]; then echo "koto: the store could not be read" >&2; exit 1; fi
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/kw/koto"
# fail_check_read <label> <call> <id> <key>: count the call's gets of <key> as
# the check refuses it (so the check's get is the last), then make the call
# again failing only that get.
fail_check_read() {
    local n s
    s=$(target_of "$2")
    : > "$T/cnt"
    try "$2" "$3" KOTO_BIN="$T/kw/koto" FAIL_S="$s" FAIL_K="$4" FAIL_N=0 FAIL_CNT="$T/cnt"
    n=$(cat "$T/cnt" 2>/dev/null || echo 0)
    need "$1 $2: the logging call is refused" 10 "$RC"
    : > "$T/cnt"
    try "$2" "$5" KOTO_BIN="$T/kw/koto" FAIL_S="$s" FAIL_K="$4" FAIL_N="$n" FAIL_CNT="$T/cnt"
}

# ---- the records ---------------------------------------------------------------
db_init
koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"
G=coordinate-roadmap-drv-20261020T090000Z
HOLDING=$(holding feature-1 '{"unit": "Feature 1"}')
REC=$(record_json roadmap drv | jq -c --argjson h "$HOLDING" --argjson r "[$(row coordinator coord-d coord-d)]" \
    '.holdings = [$h] | .run = $r')
open_seeded "$G" drv "$REC" || stop "the roadmap run opens at reconcile" "$(cat "$T/open.out" "$T/open.err" "$T/tick.err")"
SD_NAME=drvd
discipline_run "$SD_NAME" || stop "the discipline run opens at reconcile" "$OPEN_OUT $(cat "$T/open.err" "$T/seed.err" "$T/tick.err")"
SD=$S
as - bash "$PS/state-stored-set.sh" --session "$SD" --run coordinator coord-d --by coord-d > /dev/null 2> "$T/w.err" \
    || stop "the discipline run writes its address" "$(cat "$T/w.err")"
drive() { driver "$G" "\"$1\""; driver "$SD" "\"$1\""; }
undrive() { driver "$G" absent; driver "$SD" absent; }
drive "$D_ID"
TG_D=$(driven_msg "$G" "$D_ID" "$X_ID")
TSD_D=$(driven_msg "$SD" "$D_ID" "$X_ID")

# ---- D1 ------------------------------------------------------------------------
all_refused D1 "$X_ID" "$TG_D" "$TSD_D"
crit "D1. on a driven record every write mode of state-stored-set.sh, state-write.sh, state-decision.sh, state-hold.sh, roadmap-status.sh's write, state-open.sh's discipline seed and a state-entry.sh post, run as X_ID, exits 10, prints nothing, names D_ID and X_ID, and writes nothing"

# ---- D2 ------------------------------------------------------------------------
all_today D2 "$D_ID"
crit "D2. the same calls run as D_ID exit as they do today"

# ---- D3 ------------------------------------------------------------------------
job "$X_ID" coord-d
all_refused D3 "$X_ID" "$TG_D" "$TSD_D"
nojobs
try cap "$D_ID"; need "D3: D_ID with no job file" 0 "$RC"
crit "D3. a job file naming X_ID with the coordinator row's name doesn't help X_ID, and D_ID with no job file passes"

# ---- D4 ------------------------------------------------------------------------
for v in 7 '{}'; do
    driver "$G" "$v"; driver "$SD" "$v"
    all_refused "D4 driver $v:" "$D_ID" "$(unread_msg "$G" "its record/meta driver isn't a Claude session id")" \
        "$(unread_msg "$SD" "its record/meta driver isn't a Claude session id")"
done
drive "$D_ID"
for c in $D1_CALLS; do
    s=$(target_of "$c")
    fail_check_read "D4 meta read:" "$c" "$X_ID" record/meta "$D_ID"
    refused_as "D4 meta read:" "$c" "$(unread_msg "$s" "its record/meta couldn't be read: koto: the store could not be read")"
done
undrive
job "$X_ID" coord-x
for c in $D1_CALLS; do
    s=$(target_of "$c")
    fail_check_read "D4 run read:" "$c" "$X_ID" record/run "$X_ID"
    refused_as "D4 run read:" "$c" "$(unread_msg "$s" "its coordinator row couldn't be read: koto: the store could not be read")"
done
nojobs
drive "$D_ID"
for c in $RS_FIRST; do
    s=$(target_of "$c")
    : > "$T/cnt"
    try "$c" "$D_ID" KOTO_BIN="$T/kw/koto" FAIL_S="$s" FAIL_K=record/meta FAIL_N=all FAIL_CNT="$T/cnt"
    need "D4 every meta read: $c: exit" 2 "$RC"
    need "D4 every meta read: $c: nothing written" yes "$NOTHING"
done
crit "D4. a driver of 7 or {}, the check's own record/meta read failing, and on a run with no driver its record/run read failing, each exit 10 with the second message for every D1 call; a writer reading the record first exits 2 when every record/meta read fails"

# ---- D5 ------------------------------------------------------------------------
OVR=(--scope roadmap --name drv --repo acme/widgets)
as "$X_ID" env RS_SESSION="$G" bash "$PS/state-stored-set.sh" "${OVR[@]}" --skip-session-checks --run cap 4 --by x > "$T/out" 2> "$T/err"
need "D5: with the override flags" 0 "$?"
as "$X_ID" bash "$PS/state-stored-set.sh" --session "$G" --skip-session-checks --run cap 4 --by x > "$T/out" 2> "$T/err"
need "D5: without them" 64 "$?"
crit "D5. --skip-session-checks with the override flags writes as today as X_ID on a driven record; without them it exits 64"

# ---- D7 ------------------------------------------------------------------------
for q in "$G --list" "$G --rules" "$G --rules --counts" "$SD --reasoning-check"; do
    set -- $q
    s=$1; shift
    as "$X_ID" bash "$PS/state-stored-set.sh" --session "$s" "$@" > "$T/rx" 2>/dev/null; rx=$?
    as "$D_ID" bash "$PS/state-stored-set.sh" --session "$s" "$@" > "$T/rd" 2>/dev/null; rd=$?
    need "D7 $*: exit" "$rd" "$rx"
    cmp -s "$T/rd" "$T/rx" || needf "D7 $*: output differs"
done
crit "D7. on a driven record --list, --rules, --rules --counts and --reasoning-check as X_ID give D_ID's output and exit"

# ---- D8 ------------------------------------------------------------------------
before=$(snap "$G")
as "$X_ID" bash "$PS/state-holding.sh" --session "$G" --topic feature-1 --strand > "$T/out" 2> "$T/err"; rc=$?
need "D8: state-holding.sh exit" 10 "$rc"
need "D8: its message" "state-write: refused: driver: $TG_D" "$(cat "$T/err")"
need "D8: state-holding.sh writes nothing" "$before" "$(snap "$G")"
as "$X_ID" bash "$PS/handover-classify.sh" --session "$G" > "$T/out" 2> "$T/err"
need "D8: handover-classify.sh writes nothing" "$before" "$(snap "$G")"
crit "D8. state-holding.sh as X_ID exits 10 with D1's message, and handover-classify.sh as X_ID writes nothing"

# ---- D9 ------------------------------------------------------------------------
grep -q 'pass_env' "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.md" && needf "D9: coordinate.md holds a pass_env"
PRINTED=$(bash "$REPO_ROOT/scripts/check-template-compat.sh" --template "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.md" --print 2>/dev/null)
FP=$(printf '%s' "$PRINTED" | jq -r '.fingerprint // empty')
need "D9: the template's structure is one the compat table lists at 2" 2 \
    "$(jq -r --arg f "$FP" '.fingerprints[$f] // "unlisted"' "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json")"
crit "D9. coordinate.md holds no pass_env, and its structure (its gates among it) is unchanged"

# ---- D10 -----------------------------------------------------------------------
job "$X_ID" coord-x
roadmap_file fresh
jq -nc '["docs/roadmaps/ROADMAP-fresh.md", "--role", "manager"]' > "$T/args.json"
OUT=$(as "$X_ID" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
F=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
need "D10 roadmap: the find reads no record" record_open "$( [ -n "$F" ] && at "$F")"
as "$X_ID" bash "$PS/state-open.sh" --session "$F" --role manager > "$T/out" 2> "$T/err"
need "D10 roadmap: exit" 0 "$?$(cat "$T/err")"
need "D10 roadmap: no warning" "" "$(grep warning=rules-unrecorded "$T/out")"
need "D10 roadmap: role and rules rows" "true true" "$(run_rows "$F" | jq -r '"\(any(.[]; .key == "role")) \(any(.[]; .key == "rules"))"')"
discipline_run freshd "$X_ID"; rc=$?
need "D10 discipline: the seed exits 0 and reaches reconcile" 0 "$rc$(cat "$T/seed.err")"
need "D10 discipline: no warning" "" "$(grep warning=rules-unrecorded "$T/seed.out")"
need "D10 discipline: role and rules rows" "true true" "$(run_rows "$S" | jq -r '"\(any(.[]; .key == "role")) \(any(.[]; .key == "rules"))"')"
need "D10 discipline: its rotation" "$TODAY" "$(ctx "$S" record/rotation | jq -r .start)"
nojobs
crit "D10 (a). on a scope with no record, state-open.sh's roadmap and discipline seeds as X_ID with a job file exit 0 with no rules-unrecorded warning, holding the role and rules rows and the rotation"

# ---- D11 -----------------------------------------------------------------------
drive "$D_ID"
all_today "D11 unset:" -
all_today "D11 not an id:" not-a-session-id
crit "D11 (c). on a driven record the D1 calls with CLAUDE_CODE_SESSION_ID unset, or not of an id's shape, exit as they do today"

# ---- D12 -----------------------------------------------------------------------
job "$D_ID" coord-z
try cap "$D_ID"; need "D12: exit" 0 "$RC$(cat "$T/err")"
need "D12: the row names another session" coord-d "$(coord_row "$G" | jq -r .value)"
nojobs
crit "D12 (d). on a driven record whose coordinator row names another session, --run cap as D_ID exits 0"

# ---- D14 -----------------------------------------------------------------------
for v in "[\"$D_ID\"]" "{\"id\": \"$D_ID\"}" '""'; do
    driver "$G" "$v"; driver "$SD" "$v"
    all_refused "D14 driver $v:" "$D_ID" "$(unread_msg "$G" "its record/meta driver isn't a Claude session id")" \
        "$(unread_msg "$SD" "its record/meta driver isn't a Claude session id")"
done
crit "D14 (b). a driver of [\"D_ID\"], {\"id\": \"D_ID\"} or \"\", run as D_ID, exits 10 with the second message for every D1 call, writing nothing"

# ---- D15 to D17: a run with no driver -------------------------------------------
undrive
ROWS=$(run_rows "$G")
putj "$G" record/run "$(printf '%s' "$ROWS" | jq -c 'map(select(.key != "coordinator"))')"
job "$X_ID" coord-x
try cap "$X_ID"; need "D15: exit" 0 "$RC$(cat "$T/err")"
crit "D15 (e). on a record with no driver and no coordinator row, --run cap as X_ID with a job file exits 0"
putj "$G" record/run "$(run_rows "$G" | jq -c --argjson r "$(row coordinator coord-a coord-a)" '. + [$r]')"
nojobs
try cap "$X_ID"; need "D16: exit" 0 "$RC$(cat "$T/err")"
crit "D16 (e). on a record with no driver whose row is coord-a, a write as X_ID with no job file exits 0"
job "$X_ID" coord-x
try cap "$X_ID"
refused_as D17 cap "$G has no driver and its coordinator row names coord-a, not this Claude session (coord-x, $X_ID); nothing was written"
job "$A_ID" coord-a
try cap "$A_ID"; need "D17: as A_ID" 0 "$RC$(cat "$T/err")"
nojobs
crit "D17 (e). on a record with no driver whose row is coord-a, X_ID named coord-x is refused naming coord-a, coord-x and X_ID, writing nothing, and A_ID named coord-a passes"

# ---- D13 -----------------------------------------------------------------------
# takeover <session> <name> <base or ->: run A opened with a go-ahead and
# coordinator row coord-a, then taken over by B_ID (named coord-b); B names
# the new run.
takeover_fixture() {
    local a=$1 n=$2
    open_seeded "$a" "$n" "$(record_json roadmap "$n" | jq -c --argjson r "[$(row coordinator coord-a coord-a)]" \
        '.run = $r | .standing = [{standing: "s1", kind: "go-ahead", on: "", until: "", what: "ship it", owner: "the human", relayed_by: "", set: "2026-10-20T08:00Z", source: ""}]')" || return 1
}
take_over() {
    jq -nc --arg n "$1" '["docs/roadmaps/ROADMAP-" + $n + ".md", "--role", "manager"]' > "$T/args.json"
    OUT=$(as "$B_ID" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/take.err")
    B=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
    grep -qx 'outcome=continued' <<< "$OUT" && [ "$(at "$B")" = reconcile ]
}
job "$A_ID" coord-a; job "$B_ID" coord-b
A=coordinate-roadmap-take-20261020T090000Z
takeover_fixture "$A" take || stop "D13: run A opens" "$(cat "$T/open.err" "$T/tick.err")"
take_over take || stop "D13: B_ID takes A over" "$OUT $(cat "$T/take.err")"
need "D13: B's driver" "$B_ID" "$(ctx "$B" record/meta | jq -r .driver)"
before=$(snap "$B"); n0=$(entries_n "$B")
TB=$(driven_msg "$B" "$B_ID" "$A_ID")
as "$A_ID" bash "$PS/state-stored-set.sh" --session "$B" --standing go-ahead --what "reversed" --owner "the human" > "$T/out" 2> "$T/err"
need "D13 --standing: exit" 10 "$?"
need "D13 --standing: stdout" "" "$(cat "$T/out")"
need "D13 --standing: message" "state-stored-set: refused: driver: $TB" "$(cat "$T/err")"
as "$A_ID" bash "$PS/state-stored-set.sh" --session "$B" --end s1 --by "the human" > "$T/out" 2> "$T/err"
need "D13 --end: exit" 10 "$?"
need "D13 --end: stdout" "" "$(cat "$T/out")"
need "D13 --end: message" "state-stored-set: refused: driver: $TB" "$(cat "$T/err")"
need "D13: every record/ key unchanged" "$before" "$(snap "$B")"
need "D13: the entry count unchanged" "$n0" "$(entries_n "$B")"
nojobs
crit "D13 (d). after B_ID takes run A over into B, a --standing write and an --end as A_ID on B exit 10 naming B_ID and A_ID, writing nothing"

# ---- D18: the opener's carry ------------------------------------------------------
# carry_fixture <name>: a run of the scope holding a coordinator row coord-a,
# a told and a pending row and an entry, with the plugin's rules rows written,
# then cancelled, so the next start carries it; P names it.
carry_fixture() {
    P=coordinate-roadmap-$1-20261020T090000Z
    open_seeded "$P" "$1" "$(record_json roadmap "$1" | jq -c --argjson r "[$(row role manager), $(row coordinator coord-a coord-a), $(row told w-one coord-a), $(row pending w-two coord-a)]" '.run = $r')" \
        || return 1
    printf '{"n":1,"stamp":"2026-10-20T08:00:00Z","kind":"entry","text":"note 1"}' > "$T/e.json"; put "$P" record/entries/000001 "$T/e.json"
    # Listed from the workspace, as the opener lists them, so the carry's own
    # rules write finds them unchanged.
    (cd "$WD" && bash "$PS/rule-files.sh" --plugin-root "$PR") > "$T/rf.list" 2>/dev/null
    as - bash "$PS/state-stored-set.sh" --session "$P" --rule-files "$T/rf.list" --by "$P" > /dev/null 2>&1 || return 1
    (cd "$WD" && koto cancel "$P") > /dev/null 2>&1
}
# carry_start <name> <id>: the start that carries it, as <id>; N names the new run.
carry_start() {
    jq -nc --arg n "$1" '["docs/roadmaps/ROADMAP-" + $n + ".md", "--role", "manager"]' > "$T/args.json"
    OUT=$(as "$2" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/carry.err")
    N=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
    grep -qx "carried=$P" <<< "$OUT" && [ "$(at "$N")" = reconcile ]
}
ADDR_X="The coordinator's address is now coord-x, set by coord-x. Nobody has been told it yet."
job "$X_ID" coord-x
carry_fixture carry || stop "D18: the predecessor opens" "$(cat "$T/open.err" "$T/tick.err")"
PRUN=$(run_rows "$P"); PN=$(entries_n "$P")
carry_start carry "$X_ID" || stop "D18: the opener carries it" "$OUT $(cat "$T/carry.err" "$T/tick.err")"
need "D18 opener: the row names the carrier" "coord-x coord-x" "$(coord_row "$N" | jq -r '"\(.value) \(.set_by)"')"
need "D18 opener: no told or pending row" 0 "$(run_rows "$N" | jq '[.[] | select(.key == "told" or .key == "pending")] | length')"
need "D18 opener: every other Run row as the predecessor's" \
    "$(printf '%s' "$PRUN" | jq -c 'map(select(.key != "coordinator" and .key != "told" and .key != "pending"))')" \
    "$(run_rows "$N" | jq -c 'map(select(.key != "coordinator"))')"
need "D18 opener: the first entry after the copy" "run|$ADDR_X" \
    "$(ctx "$N" "record/entries/$(printf '%06d' $((PN + 1)))" | jq -r '"\(.kind)|\(.text)"')"
for k in $( (cd "$WD" && koto context list "$P" --prefix record/) | jq -r '.[]'); do
    case "$k" in record/meta|record/run) continue ;; esac
    [ "$(ctx "$P" "$k" | od -An -tx1)" = "$(ctx "$N" "$k" | od -An -tx1)" ] || needf "D18 opener: $k differs from the predecessor's"
done
try_n() { as "$1" bash "$PS/state-stored-set.sh" --session "$2" --run cap 5 --by "the human" > "$T/out" 2> "$T/err"; }
try_n "$X_ID" "$N"; need "D18 opener: --run cap as X_ID" 0 "$?$(cat "$T/err")"
nojobs
carry_fixture carry2 || stop "D18: the second predecessor opens" "$(cat "$T/open.err" "$T/tick.err")"
PRUN=$(run_rows "$P"); PN=$(entries_n "$P")
carry_start carry2 "$X_ID" || stop "D18: the opener carries it with no job file" "$OUT $(cat "$T/carry.err" "$T/tick.err")"
need "D18 opener, no job file: the Run rows as the predecessor's" "$(printf '%s' "$PRUN" | jq -c .)" "$(run_rows "$N" | jq -c .)"
grep -q "The coordinator's address is now" <<<"$( (cd "$WD" && koto context list "$N" --prefix record/entries/) | jq -r '.[]' | while read -r k; do ctx "$N" "$k"; done)" \
    && needf "D18 opener, no job file: an address entry was posted"
try_n "$X_ID" "$N"; need "D18 opener, no job file: --run cap as X_ID" 0 "$?$(cat "$T/err")"

# ---- D18: the rotation's carry ----------------------------------------------------
# rotation_fixture <name>: a discipline's first rotation with coordinator row
# coord-a and a told and a pending row, its window ended yesterday; R1 names it.
rotation_fixture() {
    discipline_run "$1" || return 1
    R1=$S
    as - bash "$PS/state-stored-set.sh" --session "$R1" --run coordinator coord-a --by coord-a > /dev/null 2>&1 \
        && as - bash "$PS/state-stored-set.sh" --session "$R1" --told w-one --by coord-a > /dev/null 2>&1 \
        && as - bash "$PS/state-stored-set.sh" --session "$R1" --pending w-two --by coord-a > /dev/null 2>&1 || return 1
    ctx "$R1" record/rotation | jq -c --arg e "$(day -1)" '.end = $e | .start = $e' > "$T/rot.json"
    as - bash "$PS/state-stored-set.sh" --session "$R1" --rotation "$T/rot.json" > /dev/null 2>&1
}
# rotation_carry <name> <id>: the next rotation, carried as <id>; R2 names it,
# CARRY_RC and $T/carry.out keep state-open.sh --carry's exit and output.
rotation_carry() {
    jq -nc --arg d "$1" '["--discipline", $d, "--host", "acme/widgets", "--role", "manager"]' > "$T/args.json"
    OUT=$(as "$2" bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    R2=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
    [ -n "$R2" ] && [ "$R2" != "$R1" ] && [ "$(at "$R2")" = predecessor_carry ] || return 1
    as "$2" bash "$PS/state-open.sh" --session "$R2" --carry --role manager > "$T/carry.out" 2> "$T/carry.err"
    CARRY_RC=$?
    [ "$(at "$R2" --with-data '{"carry":"carried"}')" = reconcile ]
}
job "$X_ID" coord-x
rotation_fixture rot || stop "D18: the first rotation opens" "$(cat "$T/open.err" "$T/seed.err" "$T/tick.err")"
PRUN=$(run_rows "$R1")
rotation_carry rot "$X_ID" || stop "D18: the next rotation carries it" "$OUT $(cat "$T/open.err" "$T/carry.err" "$T/tick.err")"
need "D18 rotation: state-open.sh --carry exits 0" "0 carried=$R1" "$CARRY_RC $(grep '^carried=' "$T/carry.out")"
need "D18 rotation: its window written" "$R1" "$(ctx "$R2" record/rotation | jq -r .predecessor)"
need "D18 rotation: the row names the carrier" "coord-x coord-x" "$(coord_row "$R2" | jq -r '"\(.value) \(.set_by)"')"
need "D18 rotation: no told or pending row" 0 "$(run_rows "$R2" | jq '[.[] | select(.key == "told" or .key == "pending")] | length')"
need "D18 rotation: every other Run row as the predecessor's" \
    "$(printf '%s' "$PRUN" | jq -c 'map(select(.key != "coordinator" and .key != "told" and .key != "pending"))')" \
    "$(run_rows "$R2" | jq -c 'map(select(.key != "coordinator"))')"
need "D18 rotation: its first entry is the address entry" "run|$ADDR_X" \
    "$(ctx "$R2" record/entries/000001 | jq -r '"\(.kind)|\(.text)"')"
try_n "$X_ID" "$R2"; need "D18 rotation: --run cap as X_ID" 0 "$?$(cat "$T/err")"
nojobs
rotation_fixture rot2 || stop "D18: the second first rotation opens" "$(cat "$T/open.err" "$T/seed.err" "$T/tick.err")"
PRUN=$(run_rows "$R1")
rotation_carry rot2 "$X_ID" || stop "D18: the next rotation carries it with no job file" "$OUT $(cat "$T/open.err" "$T/carry.err" "$T/tick.err")"
need "D18 rotation, no job file: state-open.sh --carry exits 0" 0 "$CARRY_RC"
need "D18 rotation, no job file: the Run rows as the predecessor's" "$(printf '%s' "$PRUN" | jq -c .)" "$(run_rows "$R2" | jq -c .)"
need "D18 rotation, no job file: no entry" 0 "$(entries_n "$R2")"
try_n "$X_ID" "$R2"; need "D18 rotation, no job file: --run cap as X_ID" 0 "$?$(cat "$T/err")"
crit "D18. both carries put the carrier's coordinator row into the copy, dropping told and pending, and post the address entry first, so the carrier's writes pass; with no job file the rows stay and the write passes by (e)"

# ---- D19 -----------------------------------------------------------------------
job "$A_ID" coord-a; job "$B_ID" coord-b
BASE1="$T/base1" BASE2="$T/base2"
mkdir -p "$BASE1" "$BASE2"
A2=coordinate-roadmap-split-20261020T090000Z
export KOTO_SESSIONS_BASE="$BASE1"
case "$(cd "$WD" && koto session dir "$A2")" in "$BASE1"/*) ;; *) stop "D19: the first base holds the sessions" "$(cd "$WD" && koto session dir "$A2")" ;; esac
takeover_fixture "$A2" split || stop "D19: run A opens under the first base" "$(cat "$T/open.err" "$T/tick.err")"
cp -R "$(cd "$WD" && koto session dir "$A2")" "$BASE2/" || stop "D19: run A is copied to the second base" ""
take_over split || stop "D19: B_ID takes A over under the first base" "$OUT $(cat "$T/take.err")"
before=$(snap "$B")
as "$A_ID" bash "$PS/state-stored-set.sh" --session "$B" --standing go-ahead --what "reversed" --owner "the human" > "$T/out" 2> "$T/err"
need "D19 first base: exit" 10 "$?"
need "D19 first base: message" "state-stored-set: refused: driver: $(driven_msg "$B" "$B_ID" "$A_ID")" "$(cat "$T/err")"
need "D19 first base: nothing written" "$before" "$(snap "$B")"
export KOTO_SESSIONS_BASE="$BASE2"
as "$A_ID" bash "$PS/state-stored-set.sh" --session "$A2" --run cap 6 --by "the human" > "$T/out" 2> "$T/err"
need "D19 second base: exit" 0 "$?$(cat "$T/err")"
need "D19 second base: it lands" 6 "$(run_rows "$A2" | jq -r '[.[] | select(.key == "cap") | .value][0]')"
unset KOTO_SESSIONS_BASE
nojobs
crit "D19. a predecessor's write to its successor's record is refused under the store that holds the driver, and its write to its own run under a store without the fence lands"

done_tests driver-check-engine

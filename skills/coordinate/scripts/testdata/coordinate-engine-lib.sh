# coordinate-engine-lib.sh -- the shared setup of the coordinate engine suites
# (coordinate_1_engine_test.sh to coordinate_4_engine_test.sh, and the suites
# that drive a whole run the same way): the harness, the gh and date
# stand-ins, the working directories, and every helper the cases use.
#
# Sourced at a suite's top level, after `set -uo pipefail` and after it sets HERE
# to its own directory (skills/coordinate/scripts). Exits 0 with SKIP when koto,
# jq or git is missing, as each suite did on its own; that exit ends the suite
# only because the source is not inside a function or subshell. Not shipped
# behaviour.
#
# The record lives in the run's koto session, its only store. A case that
# needs a run to find a record seeds it with seed_record, and open_run writes
# it into the new session's keys before the run's first find
# (testdata/engine-session.sh); nothing seeds a coordinator record on GitHub.
# On a koto without the session store's features a start is refused, so the
# lib checks that refusal once and ends the suite there.
#
# Each suite gets its own $T (the scratch tree, removed on exit), with HOME, the
# gh DB and the koto store under it, so the suites can run side by side. It
# counts through test-lib.sh's ok/bad/eq into PASS and FAIL, and ends by
# printing its own PASS/FAIL line and running `[ "$FAIL" -eq 0 ]`.

REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
ORIG_PATH=$PATH

# test-lib.sh gives the GitHub DB helpers, the state_json helper and the
# ok/bad/eq counters. It also puts testdata/ (the koto stand-in included)
# first on PATH; these suites need the real koto, so PATH is rebuilt with only
# the gh stand-in in front, and the stand-in koto's variables are dropped.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH
# session_seed, session_record and koto_store_ready.
. "$HERE/testdata/engine-session.sh"
# The board fixtures (bt_board, H, MOVED) for the land case.
. "$HERE/testdata/board/helpers.sh"
mkdir -p "$T/bin"
export GH_BOARD_DIR="$T/ghb" COORD_TESTDATA="$HERE/testdata"
mkdir -p "$GH_BOARD_DIR"

# `gh` is testdata/gh (the DB stand-in) for everything but the board reads
# verify_board and land make, which go to testdata/gh-board when its case
# directory holds a response for them: the board's GraphQL snapshot (any
# GraphQL query but the author/editor one) and the REST reads only the board
# makes (runs, jobs, rules, branch, the ref, files, checks), and the merge
# confirmation's reads (the pull request's record, the repository, and the
# comparison of the default branch with the merge commit) when the case
# directory holds them. The DB stand-in is sourced rather than started, and
# the case directory is read with a glob rather than ls, so a call costs one
# shell.
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
has() { local f; for f in "$1"*; do [ -e "$f" ] && return 0; done; return 1; } # has <prefix>: a file starts with it
key=
case "${1-} ${2-}" in
    "api graphql") case "$*" in *"editor {"*) ;; *) key=snapshot ;; esac ;;
    "api --method")
        p=${4-}; p=${p%%\?*}
        case "$p" in
            repos/*/*/actions/runs) key=runs ;;
            repos/*/*/actions/runs/*/jobs) i=${p%/jobs}; key="jobs-${i##*/}" ;;
            repos/*/*/rules/branches/*) key=rules ;;
            repos/*/*/branches/*) key=branch ;;
            repos/*/*/git/ref/heads/*) key=ref ;;
            repos/*/*/pulls/*/files) key=files ;;
            repos/*/*/commits/*/check-runs) key=checkruns ;;
            repos/*/*/commits/*/status) key=statuses ;;
            repos/*/*/contents/*) has "$GH_BOARD_DIR/contents-" && exec "$COORD_TESTDATA/gh-board" "$@" ;;
            repos/*/*/compare/*) key="compare-${p##*/compare/}" ;;
            repos/*/*/*) ;;
            repos/*/*) key=repo ;;
        esac ;;
    "pr view") key="prview-${3-}" ;;
esac
if [ -n "$key" ] && has "$GH_BOARD_DIR/$key."; then exec "$COORD_TESTDATA/gh-board" "$@"; fi
# The stand-in runs in this shell, so it starts with none of this wrapper's
# names set, as it did when it was started on its own.
unset -f has; unset key p i
. "$COORD_TESTDATA/gh" "$@"
EOF
chmod +x "$T/bin/gh"
# The land check runs the repository's PR-body rule through the shirabe
# binary; the stand-in answers clean, so the run never needs a real one.
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"

# A clock the quiet case can move forward: set_clock <seconds> and clear_clock
# (testdata/date-stand-in.sh).
. "$HERE/testdata/date-stand-in.sh"
PATH="$T/bin:$ORIG_PATH"
export PATH
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"

# koto refuses a --var value outside its allowlist (a `+` in this checkout's
# path, for one), so PLUGIN_ROOT is a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"

# Two working directories, each a clone-shaped repo whose origin is the host.
# work/ sits in a niwa instance whose settings permit every finishing step, so
# the posture reads `readable`; bare/ has no instance root, so it reads
# `unread`.
for d in work bare; do
    mkdir -p "$T/$d"
    (cd "$T/$d" && git init -q && git remote add origin https://github.com/acme/widgets.git)
done
mkdir -p "$T/work/.niwa" "$T/work/.claude"
echo '{}' > "$T/work/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$T/work/.claude/settings.json"

db_init

# ---- helpers the cases define -----------------------------------------------

roadmap_text() { # roadmap_text <status>
    printf -- '---\nstatus: %s\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Planned\n\n### Feature 2: second\n\n**Dependencies:** Feature 1\n**Status:** Planned\n' "$1"
}

seed_roadmap() { # seed_roadmap <name> [status]; ROADMAP_TEXT, when set, is the roadmap instead
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-\($n).md"] = $t' --arg n "$1" --arg t "${ROADMAP_TEXT:-$(roadmap_text "${2:-Active}")}"
}

# stored <record-json>: the record with a complete stored set, so the
# reconcile's handover gate passes: the run's arguments and cap, this
# coordinator's address, who it reports to, and for every live holding a next step and its
# worker told. The handover cases build theirs by hand.
stored() {
    printf '%s' "$1" | jq -c '
        ([.holdings[] | select(.dispatch_status == "dispatched")
          | select(((.verified_head // "") != "" and (.pull_request // "") == "") | not)]) as $live
        | .run = ((.run // []) + [{key: "arguments", value: "--roadmap docs/roadmaps/ROADMAP-test.md", set_by: "the human", set: "2026-09-26T08:00Z"},
                                  {key: "cap", value: "5", set_by: "the human", set: "2026-09-26T08:00Z"},
                                  {key: "coordinator", value: "coord-test", set_by: "coord-test", set: "2026-09-26T08:00Z"},
                                  {key: "reports-to", value: "the human", set_by: "the human", set: "2026-09-26T08:00Z"}]
                 + [$live[] | {key: "told", value: .worker, set_by: "coord-test", set: "2026-09-26T08:00Z"}])
        | .work = ((.work // []) + [$live[] | {item: .unit, kind: "holding", who: .worker, next: "waiting on the worker", updated: "2026-09-26T08:00Z"}])
        | if (.work | length) == 0 then del(.work) else . end'
}

# seed_record <name> [record-json]: the scope's record, its stored set
# complete unless RAW_RECORD=1, for the next open_run of <name> to write into
# its new session before the run's first find, as a session-store
# coordinator's keys hold it.
seed_record() {
    local j=${2-}
    [ -n "$j" ] || j=$(record_json roadmap "$1")
    [ "${RAW_RECORD-}" = 1 ] || j=$(stored "$j")
    printf '%s' "$j" > "$T/seed-$1.json"
}

# open_run <name> [workdir]: a start from coordinate-open.sh, with no store to
# choose; sets S, WD and OPEN_OUT (the opener's output). A fresh start opens a
# new session (named to the second, so two opens of one scope wait), into
# which the record seed_record left for <name>, if any, is written; a start
# while the scope's run is live and resumable resumes that run.
open_run() {
    WD=${2:-$T/work}
    printf '["docs/roadmaps/ROADMAP-%s.md"]' "$1" > "$T/args.json"
    OPEN_OUT=$(cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err")
    S=$(printf '%s\n' "$OPEN_OUT" | sed -n 's/^session=//p')
    [ -n "$S" ] || return 1
    if [ -f "$T/seed-$1.json" ]; then
        (cd "$WD" && session_seed "$S" "$(cat "$T/seed-$1.json")") \
            || { echo "the record seeded for $1 wasn't written into $S" >> "$T/open.err"; return 1; }
        rm -f "$T/seed-$1.json"
    fi
}

tick() { # tick [koto next args...]: one advance of $S from $WD; stdout is koto's JSON
    (cd "$WD" && koto next "$S" "$@" --no-cleanup 2>"$T/tick.err")
}

at() { tick "$@" | jq -r '.state // empty'; }            # the state an advance lands on
now_at() { koto status "$S" 2>/dev/null | jq -r '.current_state // .state // empty'; }
logf() { printf '%s/koto-%s.state.jsonl' "$(koto session dir "$S")" "$S"; }
entered() { # entered <state>: how many times the run entered it
    jq -s --arg s "$1" '[.[] | select((.type == "transitioned" or .type == "directed_transition") and .payload.to == $s)] | length' "$(logf)"
}

from_to() { # from_to <from> <to>: the run has an edge from -> to
    jq -s -e --arg f "$1" --arg t "$2" 'any(.[]; (.type == "transitioned" or .type == "directed_transition") and .payload.from == $f and .payload.to == $t)' "$(logf)" >/dev/null
}

write_as_agent() { # write_as_agent <script> <args...>: a write script, run from $WD as the agent runs it
    local s=$1; shift
    (cd "$WD" && bash "$PS/$s" --session "$S" "$@" >"$T/w.out" 2>"$T/w.err")
}

live_body() { # live_body: the run's record as its session holds it, its written time included
    (cd "$WD" && session_record "$S")
}

# to_pick <name> <record-json>: seed the roadmap and the run's record, open a
# run and drive it to pick. Returns non-zero if it doesn't get there. With
# SAVE_RECONCILE set, the run is saved under that label at reconcile.
to_pick() {
    seed_roadmap "$1"
    seed_record "$1" "$2"
    open_run "$1" || return 1
    [ "$(at)" = reconcile ] || return 1
    [ -z "${SAVE_RECONCILE-}" ] || snap_save "$SAVE_RECONCILE"
    [ "$(at --with-data '{"reconciled":"reported"}')" = pick ]
}

# Captures in koto's charset: no `=` or `,` in a template value either.
unit_row() { holding "$1" "$(jq -nc --arg u "${2:-Feature 1}" '{unit: $u, pull_request: "", branch: ""}')"; }

# dispatched_row <topic>: the row dispatch-worker.sh leaves once the worker is
# confirmed launched.
dispatched_row() { holding "$1" "$(jq -nc '{unit: "Feature 1", pull_request: "", branch: "", dispatch_status: "dispatched", return_path: "message"}')"; }

# land_run <name>: a run whose holding links acme/widgets#12, driven
# wait -> report -> classify_report (done) -> verify, then on through
# verify_board (the complete-board fixture) to verified_confirm.
land_row() { # land_row [verified-head]; LAND_PHASE sets the Phase (executing), LAND_UNIT the unit (Feature 1)
    holding feat-1 "$(jq -nc --arg h "${1-}" --arg p "${LAND_PHASE:-executing}" --arg u "${LAND_UNIT:-Feature 1}" '{unit: $u, branch: "feat/x", verified_head: $h,
        phase: $p, pull_request: "[#12](https://github.com/acme/widgets/pull/12)"}')"
}

land_run() {
    # The body carries the worker's Review panel at the head, which land reads.
    db '.prs = [{repo: "acme/widgets", number: 12, title: "feat: the loader", body: $b, state: "OPEN", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice",
        mergeStateStatus: "CLEAN"}]' --arg h "$H" --arg b "$(bt_body)"
    bt_board complete-board
    to_pick "$1" "$(record_json roadmap "$1" | jq -c --argjson h "$(land_row)" '.holdings = [$h]')" || return 1
    [ "$(at --with-data '{"choice":"hold"}')" = wait ] || return 1
    [ "$(at --with-data '{"event":"report","unit":"feat-1","report":"PR #12 is ready; CI is green."}')" = classify_report ] || return 1
    [ "$(at --with-data '{"classification":"done"}')" = verify ] || return 1
    [ "$(at --with-data '{"predicted":"recorded","prediction":"every job green"}')" = verified_confirm ]
}

record_verified() { # the agent writes the verified head into the unit's row
    land_row "$H" > "$T/row.json"
    write_as_agent record-holding.sh --topic feat-1 --row-file "$T/row.json"
}

assigned_brief() { # assigned_brief <topic> <unit> <entry point> <positional> <run mode>
    jq -nc --arg t "$1" --arg u "$2" --arg e "$3" --arg a "$4" --arg m "$5" '{topic: $t, repo: "acme/widgets", unit: $u, entry_point: $e,
        entry_args: [$a], run_mode: $m, phase: "executing", authority: "You are working for the owner on acme/widgets.",
        goal: "\($u) lands.", checkpoints: ["The work is done and reported."], acceptance: ["It is done."], dispatcher_session: "x"}' \
        | jq -c --arg s "$S" '.dispatcher_session = $s'
}

dispatch22() { # dispatch22 <brief-json>: dispatch-worker.sh at dispatch, as the agent runs it; D22 its exit
    printf '%s' "$1" > "$T/brief22.json"
    (cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/brief22.json" >/dev/null)
    : > "$T/work/.niwa/workspace.toml"
    (cd "$WD" && NIWA="$T/niwa22/niwa" bash "$PS/dispatch-worker.sh" --session "$S" >"$T/d22.out" 2>"$T/d22.err"); D22=$?
    rm -f "$T/work/.niwa/workspace.toml"
}

send_exec_to_dispatch() { # send_exec_to_dispatch <name>: a run at dispatch on send_execution
    to_pick "$1" "$(record_json roadmap "$1" | jq -c --argjson h "$SCOPING_ROW" '.holdings = [$h]')" || return 1
    [ "$(at --with-data '{"choice":"send_execution","unit":"feat-1"}')" = dispatch ]
}

# empty_row [return path]: feat-1's holding with Branch and Pull request empty,
# as dispatch-worker.sh writes it.
empty_row() {
    holding feat-1 "$(jq -nc --arg r "${1:-message}" '{unit: "Feature 1", branch: "", verified_head: "", pull_request: "", return_path: $r}')"
}

# empty_run <name> [return path]: a run at wait whose one holding has no pull
# request yet; acme/widgets#12 is open on feat/w-head, board complete.
empty_run() {
    db '.prs = [{repo: "acme/widgets", number: 12, title: "feat", body: "", state: "OPEN", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "feat/w-head", headRefOid: $h, author: "alice",
        mergeStateStatus: "CLEAN"}]' --arg h "$H"
    bt_board complete-board
    to_pick "$1" "$(record_json roadmap "$1" | jq -c --argjson h "$(empty_row "${2-}")" '.holdings = [$h]')" || return 1
    [ "$(at --with-data '{"choice":"hold"}')" = wait ]
}

linked_row() { live_body | jq -c '.holdings[] | select(.worker == "feat-1") | {branch, pull_request}'; }

# link_through <label>: at report_link, the agent runs holding-link.sh
# and submits written; the run reads the holding again and reaches
# classify_report, then verify_board reads #12's board.
link_through() {
    write_as_agent holding-link.sh
    eq "16 $1: holding-link.sh (agent-run) writes the pull request" 0 $?
    eq "16 $1: Branch is the headRefName GitHub reports, Pull request the link" "$LINKED" "$(linked_row)"
    eq "16 $1: written reads the holding again and reaches classify_report" classify_report "$(at --with-data '{"linked":"written"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name REPORT)" in
        "holding 12 feat-1 "*) ok "16 $1: report_facts now reads the holding's own pull request" ;;
        *) bad "16 $1: report_facts now reads the holding's own pull request" ;;
    esac
    eq "16 $1: done reaches verify" verify "$(at --with-data '{"classification":"done"}')"
    eq "16 $1: verify_board reads #12 with no hand write" verified_confirm "$(at --with-data '{"predicted":"recorded","prediction":"every job green"}')"
    case "$(bash "$PS/coord-log.sh" capture --session "$S" --name VERIFIED)" in
        "verified 12 $H "*) ok "16 $1: VERIFIED is #12's head" ;; *) bad "16 $1: VERIFIED is #12's head" ;;
    esac
}

# dent <n> <state> [jq object to merge]: one Decisions entry. The escalation
# fields go through --arg: bash 3.2 misreads escaped quotes nested in "$(...)".
dent() {
    local extra=${3-}
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg n "$1" --arg s "$2" --argjson x "$extra" '{decision: $n, round: "0", question: "Ship the loader first?",
        options: "ship -- the loader is ready\nwait -- the registry needs it", state: $s,
        source: "self [20260925T080000Z raise \($n)]", updated: "2026-09-26T07:00Z"} + $x'
}

with_decisions() { # with_decisions <name> <entries-json>
    record_json roadmap "$1" | jq -c --argjson e "$2" '.decisions = {next: 20, entries: $e}'
}

# to_reconciled <name> <record-json>: open a run and tick past reconcile; sets
# S and REACHED, the state it lands on. Never called in $(...), which would
# keep S from the caller.
to_reconciled() {
    REACHED=
    seed_roadmap "$1"; seed_record "$1" "$2"
    open_run "$1" || return 1
    [ "$(at)" = reconcile ] || return 1
    REACHED=$(at --with-data '{"reconciled":"reported"}')
}

entry_of() { live_body | jq -c --arg d "$1" '.decisions.entries[] | select(.decision == $d)'; } # entry_of <decision>

brief() { # brief <topic> <unit> <entry point> <arg> <phase>: a brief input
    jq -nc --arg t "$1" --arg u "$2" --arg e "$3" --arg a "$4" --arg p "$5" '{topic: $t, repo: "acme/widgets", unit: $u, entry_point: $e,
        entry_args: ([$a] + (if $e == "scope" then ["--intent=continue"] else [] end)), run_mode: "--auto", phase: $p,
        authority: "You are working for the owner on acme/widgets.", goal: "\($u) lands.",
        checkpoints: ["The PR is ready with every CI job green."], acceptance: ["CI is green per job."], dispatcher_session: "coord-test"}'
}

dispatch_as_agent() { # dispatch_as_agent <brief-json>: dispatch-worker.sh at dispatch, as the agent runs it; DW_RC its exit
    printf '%s' "$1" > "$T/brief.json"
    (cd "$WD" && koto context add "$S" brief_input.json --from-file "$T/brief.json" >/dev/null)
    : > "$T/work/.niwa/workspace.toml"
    (cd "$WD" && NIWA="$T/niwa-bin/niwa" bash "$PS/dispatch-worker.sh" --session "$S" >"$T/dw.out" 2>"$T/dw.err"); DW_RC=$?
    rm -f "$T/work/.niwa/workspace.toml"
}

three_features() { # three_features <name>: three independent features
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-\($n).md"] = $t' --arg n "$1" \
        --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Not started\n\n### Feature 2: second\n\n**Dependencies:** None\n**Status:** Not started\n\n### Feature 3: third\n\n**Dependencies:** None\n**Status:** Not started\n')"
}

pickf() { (cd "$WD" && koto context get "$S" coord/pick.json 2>/dev/null); }

# ---- saved runs ----------------------------------------------------------------
# Opening a run and driving it to pick costs some 800 process starts, nearly
# all in the shipped actions and gates. A case whose run starts from a state
# an earlier case already drove there, and asserted on the way, can load that
# run instead of driving its own: snap_save keeps the koto store, the gh DB
# with its call log and the board directory as they stand, with S and WD, and
# snap_load puts them back byte for byte, so the loaded run is the one the
# earlier case drove. Everything a case did since is discarded with it. The
# work/ and bare/ trees, the clock and the files a case writes under $T are
# not saved, so a case that loads a run must not depend on them having been
# left as the saving case left them.
#
# A saved run is only as good as the build that drove it. Saved runs live in
# $T, so they never outlive the suite, but the tree can still change under a
# running suite (a branch switch, a plugin rewritten in place). So both record
# a fingerprint of the template, the shipped scripts, the gh stand-ins and the
# koto binary (its size and time, not its bytes), and a load under a different
# one fails as a check of its own rather than loading.
snap_build() {
    { cat "$TPL" "$PS"/*.sh "$PS"/*.jq "$PR"/skills/coordinate/legacy-import/*.sh "$REPO_ROOT"/scripts/lib/*.sh "$HERE/testdata/gh" "$HERE/testdata/gh-board"
      ls -lL "$(command -v koto)"; } | $SHA256
}

snap_save() { # snap_save <label>
    local d="$T/snap/$1"
    rm -rf "$d" && mkdir -p "$d" \
        && cp -Rp "$HOME/.koto" "$d/koto" && cp -p "$GH_DB" "$GH_DB.calls" "$d/" && cp -Rp "$GH_BOARD_DIR" "$d/ghb" \
        && printf '%s\n%s\n%s\n' "$S" "$WD" "$(snap_build)" > "$d/meta"
}

snap_load() { # snap_load <label>: sets S and WD; a failed load is a FAIL
    local d="$T/snap/$1" s w b
    [ -f "$d/meta" ] && { read -r s && read -r w && read -r b; } < "$d/meta" \
        || { bad "load the run saved as $1" "nothing was saved as $1"; return 1; }
    [ "$b" = "$(snap_build)" ] \
        || { bad "load the run saved as $1" "it was saved from another template, script or koto build"; return 1; }
    rm -rf "$HOME/.koto" "$GH_BOARD_DIR" \
        && cp -Rp "$d/koto" "$HOME/.koto" && cp -Rp "$d/ghb" "$GH_BOARD_DIR" \
        && cp -p "$d/${GH_DB##*/}" "$GH_DB" && cp -p "$d/${GH_DB##*/}.calls" "$GH_DB.calls" \
        || { bad "load the run saved as $1" "the copy failed"; return 1; }
    S=$s WD=$w
}

work_rows() { live_body | jq -r '[(.work // [])[] | "\(.item):\(.kind):\(.who)"] | join(" ")'; }

# ---- a koto without the session store's features --------------------------------
# The session is the only store, and a start on a koto without `context list
# --prefix` and `session import` is refused before it opens anything. Every
# case needs a run, so on such a koto the suite proves that refusal and ends.
if ! koto_store_ready; then
    seed_roadmap nostore
    if open_run nostore; then
        bad "a koto without the session store's features refuses the start" "it opened $S"
    else
        case "$OPEN_OUT $(cat "$T/open.err")" in
            *store-unsupported*) ok "a koto without the session store's features refuses the start as store-unsupported" ;;
            *) bad "a koto without the session store's features refuses the start as store-unsupported" "$OPEN_OUT $(cat "$T/open.err")" ;;
        esac
    fi
    echo "koto lacks the session store's features; the cases need a newer koto"
    echo; echo "${0##*/}: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]; exit $?
fi

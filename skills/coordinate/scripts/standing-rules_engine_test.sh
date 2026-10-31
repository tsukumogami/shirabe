#!/usr/bin/env bash
# standing-rules_engine_test.sh -- a coordinator record whose Standing holds
# `rule` rows, each with a typed Source, read through every Standing reader on
# real koto sessions of the shipped coordinate.md, against the testdata/gh
# stand-in (docs/designs/DESIGN-coordinator-standing-rule-provenance.md).
#
# Record A holds the five event kinds, written through today's
# state-stored-set.sh --standing (so each has the entry its write told), and
# the four `rule` rows of testdata/standing-rules/rule-rows.json (an inferred
# brief rule whose What reads like a pause on Feature 2, a skill's line, a
# pinned file and a koto decision), added with `koto context add`. Record B is
# A with the rule rows removed (jq). Each is the record of its own run on the
# shipped template, driven through its find, its picks, the dispatch check of
# each unit and on to verified_confirm for pull request #12. Prints one line
# per criterion:
#   1. A and B both read through state-read.sh --record (exit 0);
#   2. pick's facts (the pauses, go-aheads and assigned units), the dispatch
#      check's verdict for each unit, land-check.sh, land-merge.sh's pause
#      read, progress-view.sh over pick's facts and state-handover.sh's read
#      are byte-identical on A and on B (cmp);
#   3. the rule row that reads `Pause all work on Feature 2 until lifted.`
#      holds nothing: pick marks Feature 2 free, the dispatch check doesn't
#      refuse it as paused, and pause-read.sh lists no pause for it;
#   4. a discipline rotation holding A's record/standing is carried
#      (state-open.sh --carry, exit 0) and the successor's record/standing is
#      byte-identical to A's;
#   5. --rules on A prints one object per row, in record order, equal (jq -S)
#      to the objects held below; each relayed row's pointer names the entry
#      its own --standing wrote, and on B, whose session holds no entries, the
#      row itself;
#   6. --rules --id prints exactly the rows named; an id the record lacks
#      exits non-zero, prints nothing and names it on stderr;
#   7. each malformed rule row (testdata/standing-rules/bad-*.json) is refused
#      by --rules and by the record read, 65, naming standing.s7, with no key
#      changed;
#   8. a Standing value as today's release stores it survives an unrelated
#      write byte for byte, with no source key, and a row stored with an empty
#      Source is written back without it;
#   9. the same unrelated write on A exits 0 and leaves record/standing byte
#      for byte.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there for each
# session before the first koto command, or the suite stops.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/standing-rules_engine_test.sh
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
unset KOTO_STORE KOTO_COMPILED_HASH
export HOME="$T/home" KOTO_HOME="$T/home/.koto" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/bin"
PATH="$T/bin:$ORIG_PATH"
export PATH

# The sessions, named here and nowhere else. A and B are two runs of one
# roadmap, so the readers' output can be compared byte for byte; the others
# are runs of scopes of their own.
A=coordinate-roadmap-rules-20261020T090000Z
B=coordinate-roadmap-rules-20261020T090100Z
BAD=coordinate-roadmap-rules-bad-20261020T090000Z
NOW_S=coordinate-roadmap-rules-today-20261020T090000Z
for s in "$A" "$B" "$BAD" "$NOW_S" coordinate-discipline-rules-20261020T090000Z; do
    d=$(koto session dir "$s" 2>&1) || { echo "FAIL: koto session dir $s failed: [$d]; no case ran"; exit 1; }
    case "$d" in
        "$T"/*) ;;
        *) echo "FAIL: koto's session directory for $s is not under $T: [$d]; no case ran"; exit 1 ;;
    esac
done

# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
# session_seed, session_record and koto_store_ready.
. "$HERE/testdata/engine-session.sh"
# The board fixtures (bt_board, bt_body, bt_result, bt_round, H) for the land
# path. helpers.sh starts its own counters; nothing has counted yet.
. "$HERE/testdata/board/helpers.sh"
export GH_BOARD_DIR="$T/ghb" COORD_TESTDATA="$HERE/testdata"
mkdir -p "$GH_BOARD_DIR"
# `gh` is testdata/gh (the DB stand-in) for everything but the board reads
# verify_board and land make, which go to testdata/gh-board when its case
# directory holds a response for them, as in testdata/coordinate-engine-lib.sh.
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
has() { local f; for f in "$1"*; do [ -e "$f" ] && return 0; done; return 1; }
key=
case "${1-} ${2-}" in
    "api graphql") case "$*" in *"editor {"*|*"query pickAssigned("*) ;; *) key=snapshot ;; esac ;;
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
unset -f has; unset key p i
. "$COORD_TESTDATA/gh" "$@"
EOF
chmod +x "$T/bin/gh"
ln -sf "$HERE/testdata/board/stand-in-shirabe" "$T/bin/shirabe"

# koto refuses a --var value outside its allowlist (a `+` in a checkout's
# path, for one), so PLUGIN_ROOT is a symlink to the repository.
ln -s "$REPO_ROOT" "$T/plugin"
PR="$T/plugin"
PS="$PR/skills/coordinate/scripts"
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
SR_TD="$HERE/testdata/standing-rules"
WD="$T/work"
mkdir -p "$WD/.niwa" "$WD/.claude"
(cd "$WD" && git init -q && git remote add origin https://github.com/acme/widgets.git)
echo '{}' > "$WD/.niwa/instance.json"
jq -n '{permissions: {defaultMode: "bypassPermissions"}}' > "$WD/.claude/settings.json"

# One line per criterion: need records what failed, crit prints the line.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { if [ -z "$WHY" ]; then ok "$1"; else bad "$1" "${WHY#; }"; fi; WHY=; }
stop() { bad "$1" "${2-}"; done_tests standing-rules-engine; exit 1; }

# ---- helpers ---------------------------------------------------------------
tick() { local s=$1; shift; (cd "$WD" && koto next "$s" "$@" --no-cleanup 2>"$T/tick.err"); }
at() { tick "$@" | jq -r '.state // empty'; }
ctx() { (cd "$WD" && koto context get "$1" "$2" 2>/dev/null); }
put() { (cd "$WD" && koto context add "$1" "$2" --from-file "$3"); }
agent() { local s=$1 x=$2; shift 2; (cd "$WD" && bash "$PS/$x" --session "$s" "$@"); }
# open_roadmap <session> <name>: a run of ROADMAP-<name>.md on the shipped
# template, opened the way coordinate-open.sh opens a fresh one.
open_roadmap() {
    jq -nc --arg r "docs/roadmaps/ROADMAP-$2.md" --arg p "$PR" \
        '[["SCOPE", "roadmap"], ["ROADMAP", $r], ["HOST_REPO", "acme/widgets"], ["ROADMAP_FORM", "feature"], ["PLUGIN_ROOT", $p]]' > "$T/vars.json"
    (cd "$WD" && bash "$PR/scripts/koto-open.sh" "$1" "$TPL" "$T/vars.json") > "$T/open.out" 2> "$T/open.err"
}
# snapshot <session>: every record/ key and its bytes, as hex, one per line.
snapshot() {
    local k
    (cd "$WD" && koto context list "$1" --prefix record/) | jq -r '.[]' | LC_ALL=C sort | while read -r k; do
        printf '%s %s\n' "$k" "$(cd "$WD" && koto context get "$1" "$k" | od -An -tx1 | tr -d ' \n')"
    done
}
# merge_pause_read <session>: land-merge.sh's pause read, the two calls it
# makes before a merge (rs_record_api, then bl_pauses_on for #12).
merge_pause_read() {
    ( cd "$WD" || exit 2
      HERE=$PS
      . "$PS/board-lib.sh" || exit 2
      d=$(mktemp -d "$T/merge-pauses.XXXXXX") || exit 2
      rs_record_api "$d/rec" "$1" || exit 2
      bl_pauses_on "$d/rec" acme/widgets 12 )
}

# ---- the host ---------------------------------------------------------------
db_init
for n in rules rules-bad rules-today; do
    db '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-\($n).md"] = $t' --arg n "$n" \
        --arg t "$(printf -- '---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 2: second\n**Dependencies:** None\n**Status:** In progress\n\n### Feature 3: third\n**Dependencies:** None\n**Status:** Not started\n')"
done
# Pull request #12 is Feature 2's, open on a complete board; issue #7 is the
# unit a person assigns outside the scope.
db '.prs = [{repo: "acme/widgets", number: 12, title: "feat: the loader", body: $b, state: "OPEN", isDraft: false,
        isCrossRepository: false, baseRefName: "main", headRefName: "feat/x", headRefOid: $h, author: "alice", mergeStateStatus: "CLEAN"}]
    | .issues += [{repo: "acme/widgets", number: 7, title: "the retry fix", body: "", state: "open", author: "alice", editor: null}]' \
    --arg h "$H" --arg b "$(bt_body)"
bt_board complete-board

# ---- the record --------------------------------------------------------------
# Feature 1's worker is scoping ahead; Feature 2's is executing on #12. The
# cap of 2 is reached, so a dispatch nothing pauses is refused as at-cap and
# the run goes back to wait.
LANE_A=$(holding lane-a '{"unit": "Feature 1", "phase": "scoping-ahead", "branch": "feat/first", "pull_request": ""}')
FEAT_2=$(holding feat-2 '{"unit": "Feature 2"}')
run_row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "the human", set: "2026-10-20T08:00Z"}'; }
stored_record() { # stored_record <name> <holdings-json>: a record whose stored set is complete
    record_json roadmap "$1" | jq -c --argjson h "$2" \
        --argjson r "[$(run_row arguments "--roadmap docs/roadmaps/ROADMAP-$1.md"),$(run_row cap 2),$(run_row coordinator rules-coord),$(run_row reports-to "the human")]" '
        .holdings = $h
        | .run = ($r + [$h[] | {key: "told", value: .worker, set_by: "rules-coord", set: "2026-10-20T08:00Z"}])
        | .work = [$h[] | {item: .unit, kind: "holding", who: .worker, next: "waiting on the worker", updated: "2026-10-20T08:00Z"}]
        | if (.work | length) == 0 then del(.work) else . end'
}
RECORD=$(stored_record rules "[$LANE_A,$FEAT_2]")

koto_store_ready || stop "this koto has the session store's features" "koto lacks context list --prefix or session import"

# ---- record A ----------------------------------------------------------------
open_roadmap "$A" rules || stop "run A opens" "$(cat "$T/open.out" "$T/open.err")"
(cd "$WD" && session_seed "$A" "$RECORD" 2026-10-20T08:00:00Z) || stop "record A's first state is seeded" ""
[ "$(at "$A")" = reconcile ] || stop "run A finds its record" "$(cat "$T/tick.err")"
[ "$(at "$A" --with-data '{"reconciled":"reported"}')" = pick ] || stop "run A reaches pick" "$(cat "$T/tick.err")"
[ "$(at "$A" --with-data '{"choice":"hold"}')" = wait ] || stop "run A holds to wait" "$(cat "$T/tick.err")"
# The five event rows, through today's writer: s1 to s5.
agent "$A" state-stored-set.sh --standing pause --on "Feature 1" --until lifted --what "hold the first lane" \
    --owner "the human" --relayed-by "the process owner" > /dev/null 2> "$T/w.err" || stop "A's pause is written" "$(cat "$T/w.err")"
agent "$A" state-stored-set.sh --standing go-ahead --on "Feature 3" --what "one dispatch of the third lane" \
    --owner "the human" > /dev/null 2> "$T/w.err" || stop "A's go-ahead is written" "$(cat "$T/w.err")"
agent "$A" state-stored-set.sh --standing approval --what "the release notes as drafted" \
    --owner "the human" > /dev/null 2> "$T/w.err" || stop "A's approval is written" "$(cat "$T/w.err")"
agent "$A" state-stored-set.sh --standing answer --what "panels at the head are the cost to cut" \
    --owner "the human" --relayed-by "the process owner" > /dev/null 2> "$T/w.err" || stop "A's answer is written" "$(cat "$T/w.err")"
agent "$A" state-stored-set.sh --standing assignment --on "#7" --what "fix the loader's retry" \
    --owner "the human" > /dev/null 2> "$T/w.err" || stop "A's assignment is written" "$(cat "$T/w.err")"
# The four rule rows, s6 to s9, from the testdata file.
ctx "$A" record/standing > "$T/a-events.json"
[ "$(jq -r '[.[].standing] | join(" ")' "$T/a-events.json")" = "s1 s2 s3 s4 s5" ] || stop "A holds s1 to s5" "$(cat "$T/a-events.json")"
jq -c --slurpfile r "$SR_TD/rule-rows.json" '. + $r[0]' "$T/a-events.json" > "$T/a-standing.json"
put "$A" record/standing "$T/a-standing.json" || stop "A's rule rows are added with koto context add" ""

# 9. The unrelated write on A leaves record/standing byte for byte.
ctx "$A" record/standing > "$T/a-st.before"
agent "$A" state-stored-set.sh --run friction rules-friction --by "the human" > /dev/null 2> "$T/w.err"
need "the friction write on A exits 0" 0 "$?$(cat "$T/w.err")"
ctx "$A" record/standing > "$T/a-st.after"
cmp -s "$T/a-st.before" "$T/a-st.after" || needf "A's record/standing changed: $(cat "$T/a-st.after")"
need "  ... the friction row is in A's Run" rules-friction "$(agent "$A" state-stored-set.sh --list 2>/dev/null | jq -r '.run[] | select(.key == "friction") | .value')"
CRIT9=$WHY; WHY=

# 1, A's half: the record read.
agent "$A" state-read.sh --record > "$T/A.record" 2> "$T/A.record.err"
RC_A=$?

# 5 and 6, A's half: --rules.
agent "$A" state-stored-set.sh --rules > "$T/A.rules" 2> "$T/A.rules.err"; RC_RULES=$?
agent "$A" state-stored-set.sh --rules --id s2 --id s7 > "$T/A.two" 2> "$T/A.two.err"; RC_TWO=$?
agent "$A" state-stored-set.sh --rules --id s99 > "$T/A.none" 2> "$T/A.none.err"; RC_NONE=$?
(cd "$WD" && koto context list "$A" --prefix record/entries/) > "$T/A.entries" 2>/dev/null

# readers <session> <label>: the run, at wait after its first pick, through a
# second pick, the dispatch check of each lane, and on to verified_confirm for
# #12; each reader's output in $T/<label>.*.
readers() {
    local s=$1 l=$2
    [ "$(at "$s" --with-data '{"event":"resume"}')" = pick ] || { needf "$l: a resume brings pick: $(cat "$T/tick.err")"; return 1; }
    ctx "$s" coord/pick.json > "$T/$l.pick"
    [ "$(at "$s" --with-data '{"choice":"send_execution","unit":"lane-a","rationale":"its blocker landed"}')" = wait ] \
        || { needf "$l: lane-a's dispatch goes back to wait: $(cat "$T/tick.err")"; return 1; }
    ctx "$s" coord/dispatch_check.json > "$T/$l.dc-lane-a"
    [ "$(at "$s" --with-data '{"event":"resume"}')" = pick ] || { needf "$l: a resume brings pick again"; return 1; }
    [ "$(at "$s" --with-data '{"choice":"send_execution","unit":"feat-2","rationale":"its blocker landed"}')" = wait ] \
        || { needf "$l: feat-2's dispatch goes back to wait: $(cat "$T/tick.err")"; return 1; }
    ctx "$s" coord/dispatch_check.json > "$T/$l.dc-feat-2"
    [ "$(at "$s" --with-data '{"event":"resume"}')" = pick ] && [ "$(at "$s" --with-data '{"choice":"hold"}')" = wait ] \
        || { needf "$l: the run holds to wait"; return 1; }
    [ "$(at "$s" --with-data "$(jq -nc --arg r "PR #12 is ready; CI is green.
$(bt_result "$(bt_round)")" '{event: "report", unit: "feat-2", report: $r}')")" = classify_report ] \
        || { needf "$l: feat-2's report reaches classify_report: $(cat "$T/tick.err")"; return 1; }
    [ "$(at "$s" --with-data '{"classification":"done"}')" = verify ] || { needf "$l: done reaches verify"; return 1; }
    [ "$(at "$s" --with-data '{"predicted":"recorded","prediction":"every job green"}')" = verified_confirm ] \
        || { needf "$l: verify_board reaches verified_confirm: $(cat "$T/tick.err")"; return 1; }
    (cd "$WD" && bash "$PS/land-check.sh" --session "$s" --pr 12 --no-seal) > "$T/$l.land" 2>&1
    echo "exit $?" >> "$T/$l.land"
    merge_pause_read "$s" > "$T/$l.merge" 2>&1
    echo "exit $?" >> "$T/$l.merge"
    (cd "$WD" && bash "$PS/progress-view.sh") < "$T/$l.pick" > "$T/$l.progress" 2>&1
    echo "exit $?" >> "$T/$l.progress"
    agent "$s" state-handover.sh > "$T/$l.handover" 2>&1
    echo "exit $?" >> "$T/$l.handover"
}
readers "$A" A
READ_A=$WHY; WHY=
# pause-read.sh over A's Standing, for every unit pick lists.
jq '{standing}' "$T/A.record" > "$T/A.standing-file" 2>/dev/null
printf '["Feature 1", "Feature 2", "Feature 3"]' > "$T/units.json"
bash "$PS/pause-read.sh" --standing "$T/A.standing-file" --units "$T/units.json" > "$T/A.pauses" 2> "$T/A.pauses.err"
RC_PAUSES=$?
ctx "$A" record/standing > "$T/A.standing"
# A's run ends here, as a run whose start has moved on does, so B is the
# roadmap's one live run while it is driven.
(cd "$WD" && koto cancel "$A" > /dev/null 2>&1)

# ---- record B: A with the rule rows removed -----------------------------------
jq -c '.standing |= map(select(.kind != "rule"))' "$T/A.record" > "$T/B.seed" 2>/dev/null
open_roadmap "$B" rules || stop "run B opens" "$(cat "$T/open.out" "$T/open.err")"
(cd "$WD" && session_seed "$B" "$(cat "$T/B.seed")" 2026-10-20T08:00:00Z) || stop "record B is seeded" ""
[ "$(at "$B")" = reconcile ] || stop "run B finds its record" "$(cat "$T/tick.err")"
[ "$(at "$B" --with-data '{"reconciled":"reported"}')" = pick ] || stop "run B reaches pick" "$(cat "$T/tick.err")"
[ "$(at "$B" --with-data '{"choice":"hold"}')" = wait ] || stop "run B holds to wait" "$(cat "$T/tick.err")"
agent "$B" state-read.sh --record > "$T/B.record" 2> "$T/B.record.err"
RC_B=$?
agent "$B" state-stored-set.sh --rules > "$T/B.rules" 2> "$T/B.rules.err"; RC_BRULES=$?
readers "$B" B
READ_B=$WHY; WHY=

# ---- 1 ----------------------------------------------------------------------
need "A's record read exits 0" "0" "$RC_A$(cat "$T/A.record.err")"
need "B's record read exits 0" "0" "$RC_B$(cat "$T/B.record.err")"
need "  ... A holds the five event kinds and the four rule rows" "pause go-ahead approval answer assignment rule rule rule rule" \
    "$(jq -r '[.standing[].kind] | join(" ")' "$T/A.record" 2>/dev/null)"
need "  ... none of A's event rows has a Source" "0" "$(jq '[.standing[] | select(.kind != "rule" and has("source"))] | length' "$T/A.record" 2>/dev/null)"
need "  ... B is A without its rule rows" "$(jq -cS 'del(.written) | .standing |= map(select(.kind != "rule"))' "$T/A.record" 2>/dev/null)" \
    "$(jq -cS 'del(.written)' "$T/B.record" 2>/dev/null)"
crit "1. records A and B, A with rule rows and B without, both read through state-read.sh --record (exit 0)"

# ---- 2 ----------------------------------------------------------------------
[ -z "$READ_A$READ_B" ] || needf "${READ_A#; }${READ_B}"
for r in pick dc-lane-a dc-feat-2 land merge progress handover; do
    [ -s "$T/A.$r" ] || needf "A's $r output is empty"
    cmp -s "$T/A.$r" "$T/B.$r" || needf "$r differs on A and B: A [$(head -c 400 "$T/A.$r" 2>/dev/null)] B [$(head -c 400 "$T/B.$r" 2>/dev/null)]"
done
need "  ... pick's facts carry the pause, the go-ahead and the assigned unit" "s1|Feature 3|#7" \
    "$(jq -r '"\([.pauses[].standing] | join(","))|\([.go_aheads[].on] | join(","))|\([.units[] | select(.assigned) | .unit] | join(","))"' "$T/A.pick" 2>/dev/null)"
need "  ... the land check passes the pause read" "" "$(grep '^paused' "$T/A.land")"
crit "2. pick's facts, the dispatch check of each unit, land-check.sh, land-merge.sh's pause read, progress-view.sh and the handover read are byte-identical on A and B"

# ---- 3 ----------------------------------------------------------------------
need "pick marks Feature 1 paused by s1, Feature 2 and Feature 3 free" "s1 free free" \
    "$(jq -r '[.units[] | select(.unit == "Feature 1" or .unit == "Feature 2" or .unit == "Feature 3") | .paused // "free"] | join(" ")' "$T/A.pick" 2>/dev/null)"
need "  ... and Feature 2's holding free" "free" "$(jq -r '.holdings[] | select(.worker == "feat-2") | .paused // "free"' "$T/A.pick" 2>/dev/null)"
need "the dispatch check refuses lane-a (Feature 1) as paused by s1" "paused" "$(jq -r .verdict "$T/A.dc-lane-a" 2>/dev/null)"
need "  ... and doesn't refuse feat-2 (Feature 2) as paused" "at-cap feat-2" "$(jq -r '"\(.verdict) \(.topic)"' "$T/A.dc-feat-2" 2>/dev/null)"
need "  ... naming no pause" "" "$(jq -r '.reason' "$T/A.dc-feat-2" 2>/dev/null | grep -i pause)"
need "pause-read.sh lists the event pause alone, none covering Feature 2" "0|s1|null|s1" \
    "$RC_PAUSES|$(jq -r '"\([.pauses[].standing] | join(","))|\(.covers["Feature 2"])|\(.covers["Feature 1"])"' "$T/A.pauses" 2>/dev/null)"
crit "3. the rule row reading \`Pause all work on Feature 2 until lifted.\` holds nothing: pick, the dispatch check and pause-read.sh leave Feature 2 free"

# ---- 4: the carry ----------------------------------------------------------
# The carry is a discipline rotation's: a rotation holding A's record/standing,
# its window ended, and the next rotation's find naming it its predecessor.
day() { jq -rn --argjson n "$1" 'now + ($n * 86400) | strftime("%Y-%m-%d")'; }
open_discipline() { # prints the new run's session; the opener's output in $T/open.out
    printf '["--discipline", "rules", "--host", "acme/widgets"]' > "$T/args.json"
    (cd "$WD" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json") > "$T/open.out" 2> "$T/open.err"
    sed -n 's/^session=//p' "$T/open.out"
}
carry_case() {
    local p q
    p=$(open_discipline)
    [ -n "$p" ] || { needf "the first rotation opens: $(cat "$T/open.err")"; return; }
    [ "$(at "$p")" = record_open ] || { needf "the first rotation's find reads first: $(cat "$T/tick.err")"; return; }
    agent "$p" state-open.sh --start "$(day -7)" --end "$(day 6)" > /dev/null 2> "$T/w.err" || { needf "the first rotation opens its record: $(cat "$T/w.err")"; return; }
    [ "$(at "$p" --with-data '{"opened":"opened"}')" = reconcile ] || { needf "the first rotation reaches reconcile: $(cat "$T/tick.err")"; return; }
    put "$p" record/standing "$T/A.standing" || { needf "A's record/standing goes into the rotation"; return; }
    ctx "$p" record/rotation | jq -c --arg e "$(day -1)" '.end = $e' > "$T/rot.json"
    agent "$p" state-stored-set.sh --rotation "$T/rot.json" > /dev/null 2> "$T/w.err" || { needf "the rotation's window ends yesterday: $(cat "$T/w.err")"; return; }
    q=$(open_discipline)
    [ -n "$q" ] && [ "$q" != "$p" ] || { needf "the next rotation opens: $(cat "$T/open.out" "$T/open.err")"; return; }
    [ "$(at "$q")" = predecessor_carry ] || { needf "the next rotation's find names its predecessor: $(cat "$T/tick.err")"; return; }
    agent "$q" state-open.sh --carry > "$T/carry.out" 2> "$T/carry.err"
    need "state-open.sh --carry exits 0, carried from the first rotation" "0 carried=$p" "$? $(tail -1 "$T/carry.out")"
    ctx "$q" record/standing > "$T/Q.standing"
    cmp -s "$T/A.standing" "$T/Q.standing" || needf "the successor's record/standing differs from A's: $(cat "$T/Q.standing")"
    need "  ... rule rows and Sources included" 4 "$(jq '[.[] | select(.kind == "rule" and (.source // "") != "")] | length' "$T/Q.standing" 2>/dev/null)"
}
carry_case
crit "4. the carry from A's Standing exits 0 and the successor's record/standing is byte-identical to A's"

# ---- 5 ----------------------------------------------------------------------
# The objects --rules prints for A. An event row's Set is the time its write
# ran, so said and set are read from A's record; everything else is held here.
# Each relayed row names the entry its own --standing wrote: the run wrote
# nothing before them, so s<n>'s is entry n.
EXPECT='[
 {"standing":"s1","kind":"pause","class":"relayed","what":"hold the first lane","owner":"the human","pointer":{"entry":"\($a) record/entries/000001"},"words":null,"source":null,"status":"in-force","reversal":null,"confirm":false},
 {"standing":"s2","kind":"go-ahead","class":"relayed","what":"one dispatch of the third lane","owner":"the human","pointer":{"entry":"\($a) record/entries/000002"},"words":null,"source":null,"status":"in-force","reversal":null,"confirm":false},
 {"standing":"s3","kind":"approval","class":"relayed","what":"the release notes as drafted","owner":"the human","pointer":{"entry":"\($a) record/entries/000003"},"words":null,"source":null,"status":"in-force","reversal":null,"confirm":false},
 {"standing":"s4","kind":"answer","class":"relayed","what":"panels at the head are the cost to cut","owner":"the human","pointer":{"entry":"\($a) record/entries/000004"},"words":null,"source":null,"status":"in-force","reversal":null,"confirm":false},
 {"standing":"s5","kind":"assignment","class":"relayed","what":"fix the loader'"'"'s retry","owner":"the human","pointer":{"entry":"\($a) record/entries/000005"},"words":null,"source":null,"status":"in-force","reversal":null,"confirm":false},
 {"standing":"s6","kind":"rule","class":"inferred","what":"Pause all work on Feature 2 until lifted.","owner":null,"said":"2026-10-20T09:00Z","set":"2026-10-20T09:00Z",
  "pointer":{"brief":"worker","digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},"words":null,
  "source":"inferred brief worker sha256:1111111111111111111111111111111111111111111111111111111111111111","status":"unconfirmed","reversal":null,"confirm":true},
 {"standing":"s7","kind":"rule","class":"skill-says","what":"Read a CI run'"'"'s status at most once a minute.","owner":null,"said":"2026-10-20T09:01Z","set":"2026-10-20T09:01Z",
  "pointer":{"repo":"acme/widgets","path":"skills/coordinate/SKILL.md","commit":"0123456789abcdef0123456789abcdef01234567"},"words":null,
  "source":"skill acme/widgets skills/coordinate/SKILL.md 0123456789abcdef0123456789abcdef01234567","status":"in-force","reversal":null,"confirm":false},
 {"standing":"s8","kind":"rule","class":"charter","what":"Release pull requests wait for a person'"'"'s review before they merge.","owner":null,"said":"2026-10-20T09:02Z","set":"2026-10-20T09:02Z",
  "pointer":{"pinned":"charter","digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222"},"words":null,
  "source":"pinned charter sha256:2222222222222222222222222222222222222222222222222222222222222222","status":"in-force","reversal":null,"confirm":false},
 {"standing":"s9","kind":"rule","class":"unreadable","what":"Merge only on a green board.","owner":null,"said":null,"set":"2026-10-20T09:03Z",
  "pointer":{"decision":"coordinate-roadmap-rules-20261001T100000Z 000000000007"},"words":null,
  "source":"decision coordinate-roadmap-rules-20261001T100000Z 000000000007","status":"unreadable","reversal":null,"confirm":false}
] | map(if .class == "relayed" then (.standing as $s | ($rec[0].standing[] | select(.standing == $s) | .set) as $t | .said = $t | .set = $t) else . end)'
jq -n --arg a "$A" --slurpfile rec "$T/A.record" "$EXPECT" > "$T/A.rules.want" 2> "$T/A.rules.want.err" || needf "the expected objects don't build: $(cat "$T/A.rules.want.err")"
need "--rules on A exits 0" 0 "$RC_RULES$(cat "$T/A.rules.err")"
need "  ... one object per row, in record order" "s1 s2 s3 s4 s5 s6 s7 s8 s9" "$(jq -r .standing "$T/A.rules" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
need "  ... each as the test holds it (jq -S)" "$(jq -cS . "$T/A.rules.want" 2>/dev/null)" "$(jq -s -cS . "$T/A.rules" 2>/dev/null)"
need "  ... no object has a grants key" 0 "$(jq -s 'map(select(has("grants"))) | length' "$T/A.rules" 2>/dev/null)"
for n in 1 2 3 4 5; do
    k=$(jq -r --arg s "s$n" 'select(.standing == $s) | .pointer.entry // "" | sub("^[^ ]* "; "")' "$T/A.rules" 2>/dev/null)
    case "$(ctx "$A" "$k" | jq -r '.text // ""')" in
        "s$n ("*) ;;
        *) needf "s$n's pointer, $k, doesn't name the entry its --standing wrote" ;;
    esac
done
NEWEST=$(jq -r '.[]' "$T/A.entries" 2>/dev/null | LC_ALL=C sort | tail -1)
[ -n "$NEWEST" ] && [ "$NEWEST" != record/entries/000001 ] || needf "s1's entry is the newest, $NEWEST, so the pointer proves nothing"
need "--rules on B, whose session holds no entries, points each event row at the row itself" "0 $B record/standing s1|$B record/standing s5" \
    "$RC_BRULES $(jq -r 'select(.standing == "s1" or .standing == "s5") | .pointer.row // "none"' "$T/B.rules" 2>/dev/null | tr '\n' '|' | sed 's/|$//')"
crit "5. --rules on A prints one object per row in record order, each its class, owner, Set, pointer, status and confirm (jq -S), with no grants key"

# ---- 6 ----------------------------------------------------------------------
need "--rules --id s2 --id s7 prints exactly those two" "0 s2 s7" "$RC_TWO $(jq -r .standing "$T/A.two" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
need "  ... as the full --rules prints them" "$(jq -c 'select(.standing == "s2" or .standing == "s7")' "$T/A.rules")" "$(jq -c . "$T/A.two" 2>/dev/null)"
[ "$RC_NONE" != 0 ] || needf "--rules --id s99 exits 0"
need "--rules --id s99 prints nothing on stdout" 0 "$(wc -c < "$T/A.none" | tr -d ' ')"
grep -q 's99' "$T/A.none.err" || needf "--rules --id s99 doesn't name s99 on stderr: $(cat "$T/A.none.err")"
crit "6. --rules --id prints exactly the rows named; --id s99 exits non-zero, prints nothing and names s99 on stderr"

# ---- 7: malformed rule rows ---------------------------------------------------
open_roadmap "$BAD" rules-bad || stop "the malformed rows' run opens" "$(cat "$T/open.out" "$T/open.err")"
(cd "$WD" && session_seed "$BAD" "$(stored_record rules-bad '[]')" 2026-10-20T08:00:00Z) || stop "its record is seeded" ""
[ "$(at "$BAD")" = reconcile ] || stop "the malformed rows' run finds its record" "$(cat "$T/tick.err")"
for f in owner relayed-by no-source empty-source on decision-11-digits decision-dash-session skill-dotdot skill-39-hex; do
    put "$BAD" record/standing "$SR_TD/bad-$f.json" || { needf "$f: the row isn't seeded"; continue; }
    snapshot "$BAD" > "$T/bad.before"
    agent "$BAD" state-stored-set.sh --rules > "$T/bad.out" 2> "$T/bad.err"; rc=$?
    agent "$BAD" state-read.sh --record > "$T/bad2.out" 2> "$T/bad2.err"; rc2=$?
    snapshot "$BAD" > "$T/bad.after"
    need "$f: --rules and the record read exit 65" "65 65" "$rc $rc2"
    grep -q 'standing\.s7: ' "$T/bad.err" || needf "$f: --rules doesn't name standing.s7: $(cat "$T/bad.err")"
    grep -q 'standing\.s7: ' "$T/bad2.err" || needf "$f: the record read doesn't name standing.s7: $(cat "$T/bad2.err")"
    [ ! -s "$T/bad.out" ] && [ ! -s "$T/bad2.out" ] || needf "$f: a refusal printed on stdout"
    [ -s "$T/bad.before" ] && cmp -s "$T/bad.before" "$T/bad.after" || needf "$f: the session's keys changed"
done
crit "7. each malformed rule row is refused by --rules and the record read, 65, naming standing.s7, with no key changed"

# ---- 8: today's Standing -------------------------------------------------------
open_roadmap "$NOW_S" rules-today || stop "today's run opens" "$(cat "$T/open.out" "$T/open.err")"
(cd "$WD" && session_seed "$NOW_S" "$(stored_record rules-today '[]')" 2026-10-20T08:00:00Z) || stop "today's record is seeded" ""
put "$NOW_S" record/standing "$SR_TD/standing-today.json" || stop "today's record/standing is seeded verbatim" ""
[ "$(at "$NOW_S")" = reconcile ] || stop "today's run finds its record" "$(cat "$T/tick.err")"
ctx "$NOW_S" record/standing > "$T/today.before"
cmp -s "$SR_TD/standing-today.json" "$T/today.before" || needf "the seeded record/standing isn't the testdata file: $(cat "$T/today.before")"
agent "$NOW_S" state-stored-set.sh --run friction friction-log --by "the human" > /dev/null 2> "$T/w.err"
need "the unrelated write exits 0" 0 "$?$(cat "$T/w.err")"
ctx "$NOW_S" record/standing > "$T/today.after"
cmp -s "$SR_TD/standing-today.json" "$T/today.after" || needf "record/standing isn't byte-identical to the testdata file after the write: $(cat "$T/today.after")"
need "  ... and holds no source key" 0 "$(grep -c '"source"' "$T/today.after")"
put "$NOW_S" record/standing "$SR_TD/standing-empty-source.json" || needf "the empty-Source row isn't seeded"
agent "$NOW_S" state-stored-set.sh --run friction friction-next --by "the human" > /dev/null 2> "$T/w.err"
need "the same write over a row stored with an empty Source exits 0" 0 "$?$(cat "$T/w.err")"
ctx "$NOW_S" record/standing > "$T/today.empty"
cmp -s "$SR_TD/standing-today.json" "$T/today.empty" || needf "the empty Source wasn't left out: $(cat "$T/today.empty")"
crit "8. today's record/standing survives an unrelated write byte for byte with no source key, and an empty Source is written back without it"

# ---- 9 ----------------------------------------------------------------------
WHY=$CRIT9
crit "9. the same unrelated write on A exits 0 and leaves every byte of record/standing unchanged"

done_tests standing-rules-engine

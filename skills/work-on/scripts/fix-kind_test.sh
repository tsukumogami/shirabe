#!/usr/bin/env bash
# fix-kind_test.sh -- fix-kind.sh against git fixtures, a koto stand-in and a
# gh stand-in.
#
# Covers:
#   resolve    an issue labelled `bug` is a fix with source label:bug, and its
#              body is stored as the report; under `## Fix Labels: regression`
#              a `bug` issue is a change and a `regression` one a fix; no
#              label and no Fixes line is a change; a Fixes line (--fix-report)
#              is a fix with source step and is the report, not the issue
#              body; a free-form task's text comes from the event log; a
#              label removed later leaves a fix a fix; a change later
#              labelled becomes a fix; an empty --current is restored from
#              the ledger, a non-empty one left alone; the rebind carries
#              REVIEW_LEVEL and PLUGIN_ROOT; the declaration is read at
#              impl_base, not the working tree
#   declare    a change declared a fix records source declared; declared
#              again writes no line; refused outside its states
#   withdraw   a fix: exit 1, a refused: line naming the source, a refuse line
#              in the ledger, still a fix; a change: nothing to withdraw
#   agree      passes on a match; holds on a hand rebind naming the source,
#              on an empty variable, and with no determination
#   failures   gh can't read the issue, the rebind fails, the ledger write
#              fails (the variable is put back), a duplicate Fix Labels
#              header, and usage errors
#   refused    a context read koto refuses fails kind and resolve with 66 and
#              holds agree, never reading as an absent key; resolve's report
#              read too
#
# Usage: bash skills/work-on/scripts/fix-kind_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/fix-kind.sh"
command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH"; exit 0; }

PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "[$3] lacks [$2]" ;; esac; }

W=$(mktemp -d) || { echo "FAIL: could not create a temporary directory"; exit 1; }
ktg_on_exit 'rm -rf "$W"'
export HOME="$W/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t

# --- stand-ins -------------------------------------------------------------------
#
# koto:  context add|get|exists|remove <s> <key>  files under $SHIM_STORE/<s>;
#                                                 SHIM_FAIL_ADD=<key> fails an add
#        init <s> --attach-live --var K=V...      records every K=V in <s>/.vars,
#                                                 appends the args to <s>/.initlog;
#                                                 SHIM_FAIL_INIT=1 fails it
#        status <s>                               current_state from <s>/.state
#        SHIM_REFUSE=<s> refuses every context call on <s>, and
#        SHIM_REFUSE_KEY=<key> every `context exists` of <key>, the way koto
#        refuses a session bound to another workspace: the refusal on stdout,
#        exit 2 (or SHIM_REFUSE_RC)
# gh:    issue view ...                           prints $GH_ISSUE; GH_FAIL=1 fails
BIN="$W/bin"
STORE="$W/store"
mkdir -p "$BIN" "$STORE"
cat > "$BIN/koto" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
    context)
        if [ "${SHIM_REFUSE:-}" = "$3" ] || { [ "$2" = exists ] && [ "${SHIM_REFUSE_KEY:-}" = "$4" ]; }; then
            printf '{"error":{"code":"session_bound_elsewhere","message":"session %s is bound to another workspace"}}\n' "$3"
            exit "${SHIM_REFUSE_RC:-2}"
        fi
        f="$SHIM_STORE/$3/$4"
        case "$2" in
            add)
                [ "${SHIM_FAIL_ADD:-}" != "$4" ] || { echo "shim: refusing $4" >&2; exit 9; }
                mkdir -p "$SHIM_STORE/$3"; cat > "$f" ;;
            get) [ -f "$f" ] || exit 1; cat "$f" ;;
            exists) [ -f "$f" ] ;;
            remove) rm -f "$f" ;;
        esac ;;
    init)
        s="$2"; shift 2
        mkdir -p "$SHIM_STORE/$s"
        echo "$*" >> "$SHIM_STORE/$s/.initlog"
        [ -z "${SHIM_FAIL_INIT:-}" ] || { echo '{"error":"refused"}'; exit 2; }
        reb="{}"
        while [ $# -gt 0 ]; do
            if [ "$1" = --var ]; then
                k=${2%%=*}; v=${2#*=}
                grep -v "^$k=" "$SHIM_STORE/$s/.vars" 2>/dev/null > "$SHIM_STORE/$s/.vars.n"
                echo "$k=$v" >> "$SHIM_STORE/$s/.vars.n"
                mv "$SHIM_STORE/$s/.vars.n" "$SHIM_STORE/$s/.vars"
                reb=$(printf '%s' "$reb" | jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}')
                shift 2
            else
                shift
            fi
        done
        printf '{"outcome":"attached","rebound":%s}\n' "$reb" ;;
    status)
        printf '{"current_state":"%s"}\n' "$(cat "$SHIM_STORE/$2/.state" 2>/dev/null)" ;;
    *) echo "shim: unsupported $*" >&2; exit 2 ;;
esac
SHIM
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
[ -z "${GH_FAIL:-}" ] || { echo "gh: HTTP 404" >&2; exit 1; }
echo "$*" >> "$SHIM_STORE/.ghlog"
printf '%s\n' "$GH_ISSUE"
SHIM
chmod +x "$BIN/koto" "$BIN/gh"
export SHIM_STORE="$STORE"

TPL="$W/work-on.md"
printf 'variables:\n  PLUGIN_ROOT:\n  REVIEW_LEVEL:\n  UNIT_KIND:\n' > "$TPL"
export FIX_KIND_TEMPLATE="$TPL"

REPO="$W/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q -b main . && printf '# Repo\n' > CLAUDE.md && git add . && git commit -q -m base) || exit 1
BASE=$(git -C "$REPO" rev-parse HEAD)

OUT="" RC=0
run() {
    OUT=$(cd "$REPO" && PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>"$W/err")
    RC=$?
}
issue() { jq -nc --arg b "$1" --arg l "$2" '{body: $b, labels: ($l | split(",") | map(select(. != "")) | map({name: .}))}'; }

# new_session <s>: a session whose impl_base is the fixture's base, at <state>.
new_session() {
    rm -rf "${STORE:?}/$1"
    mkdir -p "$STORE/$1"
    printf '%s\n' "$BASE" > "$STORE/$1/impl_base"
    printf '%s' "${2:-fix_determination}" > "$STORE/$1/.state"
}
ledger() { cat "$STORE/$1/fix_kind.jsonl" 2>/dev/null; }
var() { grep "^$2=" "$STORE/$1/.vars" 2>/dev/null | tail -n 1 | cut -d= -f2-; }
events() { ledger "$1" | jq -r '.event' | tr '\n' ' ' | sed 's/ $//'; }

# --- resolve ---------------------------------------------------------------------
new_session s1
export GH_ISSUE
GH_ISSUE=$(issue "Running ./greet.sh '' prints Hello, ! instead of error: name required" "bug,ui")
run resolve s1 --current "" --issue 7
eq "a bug label: exit 0" 0 "$RC"
has "a bug label: recorded as a fix from the label" "recorded: fix (source label:bug)" "$OUT"
eq "a bug label: UNIT_KIND is fix" fix "$(var s1 UNIT_KIND)"
eq "a bug label: the ledger line" "determine|fix|label:bug|default" "$(ledger s1 | jq -r '"\(.event)|\(.kind)|\(.source)|\(.labels_from)"')"
eq "a bug label: the issue body is the report" "Running ./greet.sh '' prints Hello, ! instead of error: name required" "$(cat "$STORE/s1/fix_report.txt")"
eq "a bug label: report_source issue" issue "$(ledger s1 | jq -r .report_source)"
has "the rebind carries PLUGIN_ROOT" "PLUGIN_ROOT=" "$(cat "$STORE/s1/.initlog")"
has "the rebind carries REVIEW_LEVEL" "REVIEW_LEVEL=" "$(cat "$STORE/s1/.initlog")"

# The review level survives the rebind.
new_session s1b
printf '{"ts":"t","event":"choose","to":"standard"}\n' > "$STORE/s1b/review_level.jsonl"
run resolve s1b --issue 7
eq "the rebind passes the review ledger's level" standard "$(var s1b REVIEW_LEVEL)"

# The repository's own fix labels, read at the base.
(cd "$REPO" && printf '# Repo\n\n## Fix Labels: regression, flaky test\n' > CLAUDE.md && git commit -q -am labels) || exit 1
LBASE=$(git -C "$REPO" rev-parse HEAD)
new_session s2; printf '%s\n' "$LBASE" > "$STORE/s2/impl_base"
GH_ISSUE=$(issue "body" "bug")
run resolve s2 --issue 8
eq "under Fix Labels: regression, a bug issue is a change" change "$(var s2 UNIT_KIND)"
eq "the declaration is recorded as the labels' source" "CLAUDE.md|regression, flaky test" "$(ledger s2 | jq -r '"\(.labels_from)|\(.fix_labels)"')"
new_session s3; printf '%s\n' "$LBASE" > "$STORE/s3/impl_base"
GH_ISSUE=$(issue "body" "Regression")
run resolve s3 --issue 9
eq "a regression label (any case) is a fix" "fix|label:Regression" "$(var s3 UNIT_KIND)|$(ledger s3 | jq -r .source)"
new_session s3b; printf '%s\n' "$LBASE" > "$STORE/s3b/impl_base"
GH_ISSUE=$(issue "body" "flaky test")
run resolve s3b --issue 9
eq "a label with a space in it matches" "label:flaky test" "$(ledger s3b | jq -r .source)"
# The working tree's CLAUDE.md doesn't count; the base's does.
new_session s3c
(cd "$REPO" && printf '## Fix Labels: ux\n' > CLAUDE.md)
GH_ISSUE=$(issue "body" "ux")
run resolve s3c --issue 9
eq "a working-tree edit to the declaration is not read" change "$(var s3c UNIT_KIND)"
(cd "$REPO" && git checkout -q CLAUDE.md)

new_session s4
GH_ISSUE=$(issue "plain feature" "enhancement")
run resolve s4 --current "" --issue 10
eq "no fix label: recorded as a change" "recorded: change (source none)" "$OUT"
eq "no fix label: UNIT_KIND is change" change "$(var s4 UNIT_KIND)"

new_session s5
GH_ISSUE=$(issue "the issue body" "")
run resolve s5 --fix-report "greet.sh prints Hello, for an empty name instead of error: name required"
eq "a Fixes line: a fix from the step" "fix|step" "$(var s5 UNIT_KIND)|$(ledger s5 | jq -r .source)"
eq "a Fixes line is the report" "greet.sh prints Hello, for an empty name instead of error: name required" "$(cat "$STORE/s5/fix_report.txt")"
new_session s5b
GH_ISSUE=$(issue "the issue body" "")
run resolve s5b --issue 3 --fix-report "the step text says what is wrong here"
eq "a Fixes line wins over the issue body" "the step text says what is wrong here" "$(cat "$STORE/s5b/fix_report.txt")"

# A free-form task: the report is the task text from the entry evidence.
new_session s6
LOG="$W/s6.state.jsonl"
printf '%s\n' '{"type":"workflow_initialized","payload":{}}' \
    '{"type":"evidence_submitted","payload":{"state":"entry","fields":{"mode":"free_form","task_description":"greet.sh accepts an empty name"}}}' > "$LOG"
run resolve s6 --task-log "$LOG"
eq "a free-form task: change, and its text is the report" "change|greet.sh accepts an empty name" "$(var s6 UNIT_KIND)|$(cat "$STORE/s6/fix_report.txt")"
eq "a free-form task: report_source task" task "$(ledger s6 | jq -r .report_source)"

# --- a fix stays a fix -----------------------------------------------------------
GH_ISSUE=$(issue "body" "")
run resolve s1 --current fix --issue 7
eq "a label removed later: exit 0" 0 "$RC"
has "a label removed later: still a fix" "unchanged: fix (source label:bug)" "$OUT"
has "a label removed later: says why" "never withdrawn" "$OUT"
eq "a label removed later: no new ledger line" 1 "$(ledger s1 | grep -c .)"

GH_ISSUE=$(issue "plain feature" "bug")
run resolve s4 --current change --issue 10
eq "a change later labelled becomes a fix" "fix|determine determine" "$(var s4 UNIT_KIND)|$(events s4)"
has "a change later labelled: says so" "over the earlier change" "$OUT"

# A hand rebind: resolve leaves a non-empty variable alone, and agree holds.
printf 'UNIT_KIND=change\n' >> "$STORE/s1/.vars"
N0=$(grep -c . "$STORE/s1/.initlog")
GH_ISSUE=$(issue "body" "bug")
run resolve s1 --current change --issue 7
eq "a hand-rebound variable is not overwritten" "$N0" "$(grep -c . "$STORE/s1/.initlog")"
run agree s1 change
eq "agree on a hand rebind: exit 1" 1 "$RC"
has "agree on a hand rebind names the source" "hold: UNIT_KIND is change but the ledger records a fix (source label:bug)" "$OUT"
# An empty variable is restored.
run resolve s1 --current "" --issue 7
has "an empty variable is restored from the ledger" "restored: UNIT_KIND=fix" "$OUT"
eq "an empty variable is restored: UNIT_KIND fix" fix "$(var s1 UNIT_KIND)"

# --- agree -------------------------------------------------------------------------
run agree s1 fix
eq "agree on a match: exit 0" 0 "$RC"
run agree s1 ""
eq "agree on an empty variable: exit 1" 1 "$RC"
has "agree on an empty variable says to tick again" "tick again" "$OUT"
new_session s7
run agree s7 change
has "agree with no determination holds" "no determination is recorded yet" "$OUT"
run agree s4 change
has "agree: a change ledger and a fix variable name declare" "ledger records a fix" "$OUT"

# --- declare -------------------------------------------------------------------
new_session s8
GH_ISSUE=$(issue "it is broken" "")
run resolve s8 --issue 11
run declare s8 --reason "the report describes existing behaviour as wrong"
eq "declare on a change: exit 0" 0 "$RC"
eq "declare on a change: a fix with source declared" "fix|declare|declared" "$(var s8 UNIT_KIND)|$(ledger s8 | tail -n 1 | jq -r '"\(.event)|\(.source)"')"
run declare s8 --reason again
eq "declare on a fix: no new line" 2 "$(ledger s8 | grep -c .)"
has "declare on a fix: says so" "already a fix (source declared)" "$OUT"
new_session s9 implementation
run declare s9 --reason late
eq "declare from implementation: exit 1" 1 "$RC"
has "declare from implementation: refused naming the state" "refused: a fix is declared at fix_determination" "$OUT"
eq "declare from implementation: no ledger" "" "$(ledger s9)"
new_session s9b analysis
run declare s9b --reason "on a return to analysis"
eq "declare at analysis: recorded" "fix" "$(var s9b UNIT_KIND)"
run declare s9b
eq "declare without --reason: exit 64" 64 "$RC"

# --- withdraw ------------------------------------------------------------------
run withdraw s1 --reason "not a bug after all"
eq "withdraw a fix: exit 1" 1 "$RC"
eq "withdraw a fix: refused naming the source" "refused: the unit is a fix (source label:bug), and a fix determination can't be withdrawn" "$OUT"
eq "withdraw a fix: a refuse line" "refuse|withdraw|label:bug" "$(ledger s1 | tail -n 1 | jq -r '"\(.event)|\(.action)|\(.source)"')"
run kind s1
eq "withdraw a fix: still a fix" fix "$OUT"
new_session s10
GH_ISSUE=$(issue "x" "")
run resolve s10 --issue 12
run withdraw s10
eq "withdraw a change: exit 0" 0 "$RC"
has "withdraw a change: nothing to withdraw" "nothing to withdraw" "$OUT"

# --- failures ------------------------------------------------------------------
new_session f1
GH_FAIL=1 run resolve f1 --issue 13
eq "gh can't read the issue: exit 66" 66 "$RC"
eq "gh can't read the issue: no ledger" "" "$(ledger f1)"
new_session f2
GH_ISSUE=$(issue "x" "bug")
SHIM_FAIL_INIT=1 run resolve f2 --issue 13
eq "the rebind fails: exit 66" 66 "$RC"
eq "the rebind fails: no ledger" "" "$(ledger f2)"
new_session f3
SHIM_FAIL_ADD=fix_kind.jsonl run resolve f3 --issue 13
eq "the ledger write fails: exit 66" 66 "$RC"
eq "the ledger write fails: the variable is put back" "" "$(var f3 UNIT_KIND)"
(cd "$REPO" && printf '## Fix Labels: a\n## Fix Labels: b\n' > CLAUDE.md && git commit -q -am dup) || exit 1
new_session f4; git -C "$REPO" rev-parse HEAD > "$STORE/f4/impl_base"
run resolve f4 --issue 13
eq "a duplicate Fix Labels declaration: exit 64" 64 "$RC"
run resolve "bad name" --issue 1
eq "a bad session name: exit 64" 64 "$RC"
run resolve f4 --issue 1x
eq "a bad issue number: exit 64" 64 "$RC"
run resolve f4 --issue-repo "a/b/c"
eq "a bad issue repo: exit 64" 64 "$RC"
run resolve f4 --current maybe
eq "a bad --current: exit 64" 64 "$RC"
run frobnicate f4
eq "an unknown subcommand: exit 64" 64 "$RC"

# --- a refused read --------------------------------------------------------------
# koto refuses a read of a session bound to another workspace, printing the
# refusal on stdout and exiting 2. That is a failed read, which fails the
# command rather than reading as an absent key.
new_session r1
SHIM_REFUSE=r1 run kind r1
eq "kind on a refused session: exit 66 rather than reading as an absent key" 66 "$RC"
eq "kind on a refused session: nothing on stdout" "" "$OUT"
has "kind on a refused session: koto's refusal on stderr" "session_bound_elsewhere" "$(cat "$W/err")"
SHIM_REFUSE=r1 SHIM_REFUSE_RC=1 run kind r1
eq "kind on a refused session at exit 1 with the refusal: exit 66 rather than reading as an absent key" 66 "$RC"
SHIM_REFUSE=r1 run agree r1 fix
eq "agree on a refused session: holds" 1 "$RC"
has "agree on a refused session names the failed read rather than reading as an absent key" "could not read fix_kind.jsonl" "$OUT"
new_session r2
GH_ISSUE=$(issue "x" "bug")
SHIM_REFUSE_KEY=fix_kind.jsonl run resolve r2 --issue 14
eq "resolve with the ledger read refused: exit 66 rather than reading as an absent key" 66 "$RC"
eq "resolve with the ledger read refused: no ledger" "" "$(ledger r2)"
eq "resolve with the ledger read refused: UNIT_KIND unbound" "" "$(var r2 UNIT_KIND)"
new_session r3
SHIM_REFUSE_KEY=fix_report.txt run resolve r3 --issue 14
eq "resolve with the report read refused: exit 66 rather than reading as an absent key" 66 "$RC"
eq "resolve with the report read refused: no report stored" "" "$(cat "$STORE/r3/fix_report.txt" 2>/dev/null)"
eq "resolve with the report read refused: no ledger" "" "$(ledger r3)"

echo
echo "fix-kind: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

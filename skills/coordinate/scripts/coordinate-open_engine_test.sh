#!/usr/bin/env bash
# coordinate-open_engine_test.sh -- coordinate-open.sh against real koto and
# the shipped coordinate.md.
#
# Proves: a roadmap invocation opens a per-run session with the host taken
# from the repository's origin; text after `--` is decisions and changes no
# setting (`-- --cap 9` leaves the cap as given); the rotation length defaults
# to seven days; a discipline without --host asks and opens nothing; malformed
# values (a path outside docs/roadmaps/, an uppercase discipline, a rotation
# length of 0, a cap of 0, -1 or abc, a parked bound of abc, a host that isn't
# owner/repo, a --reports-to topic that isn't a topic) are refused with no new
# session and the live run left alone, and so is --store, whatever its value,
# as usage naming it (the session is the only store); --reports-to sets
# REPORTS_TO, empty without it; ROADMAP_FORM is feature for a roadmap not in
# the working tree and milestone for a roadmap/v2 or roadmap/v3 one there; a
# second valid invocation cancels the first run without deleting its log.
# --dispatched-by writes a dispatched-by link in the opened run's own session
# with one link call, and none is written without it; a link that fails once is
# retried and recorded with no warning; one that fails twice prints
# warning=link-failed after session=, records it in session/link-warning,
# writes no link and leaves the run live, exit 0; a malformed or repeated
# --dispatched-by is usage with nothing opened. A carried run (the recycled
# coordinator) is linked in its own session to the run it carried, before its
# dispatcher, writing nothing in the earlier run; a failed carry link warns
# after carried= and records only that run; two failed links record both
# dispatchers under one warning line, and a later link to one that works
# takes away only its own line, the key going with the last. Behind a koto
# that refuses reads of a live source as bound to another directory
# (session_bound_elsewhere): a carry refused part way is refused=bound-elsewhere
# naming `koto session rebind <run> --to <this directory>` and the order, and
# one cut short by another failure is failed=carry, each with the source live
# and uncancelled and the new run cancelled holding no record; a start whose
# candidate can't be read is refused with no session= and nothing opened; a
# carry whose source is written while it runs is failed=carry, the source
# live and the new run cancelled with the record/meta it got withdrawn; a
# carry that lands cancels the source after it, the new run holding the
# source's written time; and after that run is cancelled and can't be read,
# the second start is refused, and the next once it reads carries it. On a
# koto without the session store's features the only case is the start's
# refusal, store-unsupported, opening no session.
# The run's role (docs/designs/DESIGN-coordinator-named-roles.md, Decision 1):
# a role other than manager or director is refused=invalid_role (exit 2) with
# its row, the value echoed with backticks and control characters removed and
# cut to 32, and a repeated --role or a malformed change flag is usage (64),
# none of them opening a session; a new run with no --role, a resume and a
# carry of a role-less record are asked (ask=role, exit 10, the whole message
# asserted) with nothing written, and a discipline missing host and role is
# asked the host; a new run prints role= before session=; a resume of a
# role-less record given --role writes the row (set by `start --role`) before
# outcome=resumed, and a write that fails prints no outcome= or session=; a
# role-less carry given --role prints role= and leaves the no-role gap. On a
# resume and a carry: the matching role is accepted, both directions of
# mismatch are refused role-mismatch (whole message) with the record, the
# run's state and the session list unchanged, and a failed role read is
# failed=role_read; a dispatcher change naming a session the record doesn't
# report to, the row's name half, the run, its predecessor (the run its carry
# linked) or its address is refused with its whole message naming the row; a
# person change from a brief, a dispatcher change with no address or no row,
# and two causes at once each get their own row; the flags with the recorded
# role or a role-less record change nothing; an accepted dispatcher change
# and person change are written with their set_by, set and entry, on a carry
# after cancel_others, and a carry whose change write fails stands with
# role=<recorded>, warning=role-change-unwritten and session=, the same start
# later applying it as a resume; a dispatcher naming the resumed run is still
# usage (64), naming the way out.
# On two simulated hosts sharing koto's cloud backend (testdata/cloud-hosts.sh
# over testdata/fake-s3.py): a plain session imported on host B arrives with
# every key, and host A's copy then refuses a write as session_migrated, and
# koto's dashboard detail says it migrated; on koto 0.32.0 and later A's copy
# still answers a read with A's last pushed copy (the import keeps it as a
# read-only predecessor), and before that it refuses the read too. The opener's
# --import, run on host B: a malformed or settings-bearing import is usage
# and a name that isn't a run of the scope refused session-name, neither of
# them calling `session import`; on koto 0.32.0 and later, whose import is a
# takeover recording the Claude session as driver, an import with no
# CLAUDE_CODE_SESSION_ID is refused session-id before koto imports, and B's
# opener otherwise runs as a synthetic Claude session; a discipline one
# reaches the import, which finds no such run; a
# run A opened whose find never ran (no session-store find) is imported, then
# refused session-source; host A, whose koto (0.32.0 and later) still lists that
# run, doesn't count it as a live run of the scope, and its next open opens a
# new run without cancelling it (no failed=cancel); and one A opened from a copy of the plugin at another path
# is imported and refused only as session-source, its find never having run,
# an older koto re-attaching it with this host's plugin root first (rebound=)
# and koto 0.32.0 and later, whose takeover opens the new run from this
# plugin's root, printing no rebound=; a child
# source is refused with koto's import_source_is_child and leaves no session; a
# run from a template B lacks is refused import_template_unavailable, leaving
# no session either, and with --trust-template imported but refused
# template-incompatible (its template isn't in the compat table), staying on
# B; with that run live, another import of the
# scope is refused session-live before koto runs.
#
# Needs koto, jq, git and python3; SKIPs (exit 0) without one, which
# run-tests.sh --engine turns into a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for b in koto jq git python3; do command -v "$b" >/dev/null 2>&1 || { echo "SKIP: $b not on PATH"; exit 0; }; done
T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-open-engine.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */coordinate-open-engine.*) rm -rf "$T" ;; esac'
export HOME="$T/home"; mkdir -p "$HOME"; export GIT_CEILING_DIRECTORIES="$T"
PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
ln -s "$REPO_ROOT" "$T/plugin"
OPEN="$T/plugin/skills/coordinate/scripts/coordinate-open.sh"
# gh is the testdata/gh stand-in over a DB with no issue and no pull request:
# a fresh start's one lookup for a record still on GitHub (the legacy
# importer's) finds none, and nothing reaches the real gh.
export GH_DB="$T/gh.json"
jq -n '{login: "coord", repos: {"acme/widgets": {private: false, default_branch: "main"}}, issues: [], prs: [],
    branches: {}, commits: {}, permissions: {}, files: {}, fail: []}' > "$GH_DB"
: > "$GH_DB.calls"
mkdir -p "$T/bin" && ln -s "$HERE/testdata/gh" "$T/bin/gh"
export PATH="$T/bin:$PATH"
# koto_store_ready, the session store's koto features.
. "$HERE/testdata/engine-session.sh"
mkdir "$T/repo" && cd "$T/repo" && git init -q && git remote add origin https://github.com/acme/widgets.git
# with_role <args json>: the args with --role manager before any `--`, unless
# they name a role already or are an import, so the cases that aren't about
# the role start as a new run must: knowing its role.
with_role() { jq -c 'if index("--role") or index("--import") then . else (index("--") // length) as $c | .[:$c] + ["--role", "manager"] + .[$c:] end' <<<"$1"; }
open_() { with_role "$1" > "$T/args.json"; bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" 2>"$T/err"; }
# open_raw <args json>: the opener with the args exactly as given.
open_raw() { printf '%s' "$1" > "$T/args.json"; bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" 2>"$T/err"; }
sessions() { koto session list 2>/dev/null | jq -r '.[].id' | sort | tr '\n' ' '; }
var() { local d; d=$(koto session dir "$1"); jq -r --arg k "$2" 'select(.type == "workflow_initialized") | .payload.variables[$k]' "$d/koto-$1.state.jsonl"; }

# The session is the record's only store: on a koto without its features
# (`context list --prefix`, `session import`) every start is refused before a
# session opens, so that refusal is all this suite can prove there.
if ! koto_store_ready; then
    open_ '["docs/roadmaps/ROADMAP-plugin-system.md"]' > "$T/out"; rc=$?
    if [ $rc -ne 0 ] && grep -q store-unsupported "$T/out" "$T/err"; then pass "a koto without the session store's features refuses the start as store-unsupported"
    else fail "a koto without the session store's features refuses the start as store-unsupported" "rc=$rc $(cat "$T/out" "$T/err")"; fi
    eq "  ... opening no session" "" "$(sessions)"
    echo "koto lacks the session store's features; the other cases need a newer koto"
    echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit $?
fi

OUT=$(open_ '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","4","--reports-to","ws-lead","--","feature 3 waits","--cap","9"]'); eq "a roadmap invocation opens" 0 $?
S1=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
case "$S1" in coordinate-roadmap-plugin-system-2*Z) pass "the session is per run" ;; *) fail "the session is per run" "$S1" ;; esac
eq "the host is the roadmap's repository" acme/widgets "$(var "$S1" HOST_REPO)"
eq "the cap given before -- is set" 4 "$(var "$S1" CAP)"
eq "the rotation length defaults to seven days" 7 "$(var "$S1" ROTATION_DAYS)"
eq "--reports-to sets the run's escalation target" ws-lead "$(var "$S1" REPORTS_TO)"
eq "a roadmap not in the working tree is read as a feature roadmap" feature "$(var "$S1" ROADMAP_FORM)"

BEFORE=$(sessions)
open_ '["--discipline","ci-health"]' >/dev/null; eq "a discipline without --host asks" 10 $?
eq "asking opens nothing" "$BEFORE" "$(sessions)"
for bad in '["docs/other/ROADMAP-x.md"]' '["--discipline","CI","--host","acme/widgets"]' '["--discipline","ci","--host","acme/widgets","--rotation-days","0"]' \
           '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","0"]' '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","-1"]' \
           '["docs/roadmaps/ROADMAP-plugin-system.md","--cap","abc"]' '["docs/roadmaps/ROADMAP-plugin-system.md","--parked-bound","abc"]' \
           '["--discipline","ci","--host","acme"]' '["docs/roadmaps/ROADMAP-plugin-system.md","--reports-to","-lead"]' \
           '["docs/roadmaps/ROADMAP-plugin-system.md","--reports-to","ws lead"]'; do
    open_ "$bad" >/dev/null; rc=$?
    if [ $rc -ne 0 ] && [ "$(sessions)" = "$BEFORE" ]; then pass "refused, nothing opened: $bad"; else fail "refused, nothing opened: $bad" "rc=$rc"; fi
done
# The session is the only store: --store is no longer a setting, whatever its
# value.
for st in session github; do
    open_ "[\"docs/roadmaps/ROADMAP-plugin-system.md\",\"--store\",\"$st\"]" >/dev/null; rc=$?
    if [ $rc -eq 64 ] && grep -q -- '--store' "$T/err" && [ "$(sessions)" = "$BEFORE" ]; then pass "--store $st is usage naming --store, nothing opened"
    else fail "--store $st is usage naming --store, nothing opened" "rc=$rc $(cat "$T/err")"; fi
done
eq "a refused invocation leaves the live run alone" false "$(koto status "$S1" | jq -r .is_terminal)"
sleep 1
OUT=$(open_ '["docs/roadmaps/ROADMAP-plugin-system.md"]'); eq "a second invocation opens" 0 $?
S2=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
grep -qx "cancelled=$S1" <<<"$OUT" && pass "the earlier run is cancelled" || fail "the earlier run is cancelled" "$OUT"
[ -r "$(koto session dir "$S1")/koto-$S1.state.jsonl" ] && pass "the cancelled run's log is kept" || fail "the cancelled run's log is kept"
eq "the new run keeps the default cap" 5 "$(var "$S2" CAP)"
eq "without --reports-to the target is a person (REPORTS_TO empty)" "" "$(var "$S2" REPORTS_TO)"
# A roadmap/v2 roadmap in the working tree opens a milestone run.
mkdir -p docs/roadmaps
printf -- '---\nschema: roadmap/v2\nstatus: Active\n---\n\n# ROADMAP: milestones\n' > docs/roadmaps/ROADMAP-milestones.md
OUT=$(open_ '["docs/roadmaps/ROADMAP-milestones.md"]'); eq "a milestone roadmap's run opens" 0 $?
S3=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... with ROADMAP_FORM milestone" milestone "$(var "$S3" ROADMAP_FORM)"
# So does a roadmap/v3 one, the milestone roadmap that lists its milestones
# under `## Milestones`.
printf -- '---\nschema: roadmap/v3\nstatus: Active\n---\n\n# ROADMAP: milestones v3\n' > docs/roadmaps/ROADMAP-milestones-v3.md
OUT=$(open_ '["docs/roadmaps/ROADMAP-milestones-v3.md"]'); eq "a roadmap/v3 roadmap's run opens" 0 $?
S4=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... with ROADMAP_FORM milestone" milestone "$(var "$S4" ROADMAP_FORM)"

# --- --dispatched-by: the run records the coordinator that dispatched it -------
# koto runs behind a shim that logs each `session link` and fails the first
# LINK_FAILS of them, so the retry and the warning are seen from outside.
echo "== --dispatched-by =="
REAL_KOTO=$(command -v koto)
cat > "$T/link-shim" <<EOF
#!/bin/sh
if [ "\$1 \$2" = "session link" ]; then
    printf '%s\n' "\$*" >> "$T/links"
    n=\$(wc -l < "$T/links")
    [ "\$n" -le "\${LINK_FAILS:-0}" ] && exit 1
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/link-shim"
open_by() { # open_by <fails> <dispatcher> <args json>: the opener with --dispatched-by behind the shim
    : > "$T/links"
    with_role "$3" > "$T/args.json"
    LINK_FAILS=$1 KOTO_BIN="$T/link-shim" bash "$OPEN" --plugin-root "$T/plugin" --dispatched-by "$2" "$T/args.json" 2>"$T/err"
}
links() { koto context list "$1" --prefix koto/links/dispatched-by/ 2>/dev/null | jq -r '.[]' | tr '\n' ' '; }
RMV2='["docs/roadmaps/ROADMAP-milestones.md"]'
sleep 1
OUT=$(open_by 0 coord-parent "$RMV2"); eq "a run opened with --dispatched-by opens" 0 $?
SL=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... its own session holds the dispatched-by link" "koto/links/dispatched-by/coord-parent " "$(links "$SL")"
eq "  ... written by one link call from the run's session" "session link $SL --dispatched-by coord-parent" "$(cat "$T/links")"
eq "  ... printing no warning" "" "$(printf '%s\n' "$OUT" | grep '^warning=')"
eq "without --dispatched-by no dispatcher link is written" "" "$(links "$S4")"
sleep 1
OUT=$(open_by 1 coord-parent "$RMV2"); eq "a link that fails once opens the run" 0 $?
SL=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... the link is run twice" 2 "$(grep -c "^session link $SL --dispatched-by coord-parent\$" "$T/links")"
eq "  ... and recorded on the retry" "koto/links/dispatched-by/coord-parent " "$(links "$SL")"
eq "  ... with no warning printed" "" "$(printf '%s\n' "$OUT" | grep '^warning=')"
koto context exists "$SL" session/link-warning; eq "  ... and no warning key" 1 $?
sleep 1
OUT=$(open_by 2 coord-parent "$RMV2"); eq "a link that fails twice still opens the run, exit 0" 0 $?
SL=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
[ -n "$SL" ] && pass "  ... printing session=" || fail "  ... printing session=" "$OUT"
eq "  ... the warning follows session=" "session=$SL|warning=link-failed dispatched_by=coord-parent" \
    "$(printf '%s\n' "$OUT" | grep -A1 '^session=' | tr '\n' '|' | sed 's/|$//')"
eq "  ... recorded in the run's own session" "warning=link-failed
dispatched_by=coord-parent" "$(koto context get "$SL" session/link-warning)"
eq "  ... no link written" "" "$(links "$SL")"
eq "  ... and the run is live" false "$(koto status "$SL" | jq -r .is_terminal)"
BEFORE=$(sessions)
for bad in ../x -x "$(head -c 201 /dev/zero | tr '\0' a)"; do
    open_by 0 "$bad" "$RMV2" >/dev/null; rc=$?
    if [ $rc -eq 64 ] && [ "$(sessions)" = "$BEFORE" ] && [ ! -s "$T/links" ]; then pass "--dispatched-by ${bad:0:12} is usage, nothing opened"
    else fail "--dispatched-by ${bad:0:12} is usage, nothing opened" "rc=$rc $(cat "$T/err")"; fi
done
with_role "$RMV2" > "$T/args.json"
bash "$OPEN" --plugin-root "$T/plugin" --dispatched-by a --dispatched-by b "$T/args.json" >/dev/null 2>"$T/err"
eq "--dispatched-by given twice is usage" 64 $?
eq "  ... nothing opened" "$BEFORE" "$(sessions)"

# The recycled coordinator: a run holding the scope's record that a start
# can't resume (its find never recorded the session store) is carried into a
# new run, which is linked to it in its own session, and to the dispatcher
# the start names.
# state_json and session_keys as testdata/test-lib.sh has them (session_seed
# needs both); this suite doesn't source test-lib.sh, which puts the koto
# stand-in first on PATH.
state_json() { printf '%s' "$1" | jq -c -L "$HERE" --arg w "${2:-2026-09-26T09:00:00Z}" 'include "state-schema"; normalize_state([]) | .written = $w'; }
session_keys() {
    local pair field key
    jq -c '{scope, store: "session", written, pending: false}' "$2" | koto context add "$1" record/meta
    for pair in $ES_SECTIONS; do
        field=${pair%%:*} key=${pair#*:}
        jq -e --arg f "$field" 'has($f)' "$2" > /dev/null || continue
        jq -c --arg f "$field" '.[$f]' "$2" | koto context add "$1" "record/$key"
    done
}
RMC='["docs/roadmaps/ROADMAP-carry.md"]'
sleep 1
OUT=$(open_ "$RMC"); eq "a run of another scope opens" 0 $?
SC=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
session_seed "$SC" "$(jq -nc '{scope: {kind: "roadmap", name: "carry"}, holdings: [], deferrals: [], side_effects: [], reversals: []}')"
eq "  ... and holds the scope's record" 0 $?
# Its find recorded the session store, and it ended: a start carries it.
printf '{"source":"session"}' | koto context add "$SC" coord/source.json
koto cancel "$SC" >/dev/null 2>&1
sleep 1
OUT=$(open_by 0 coord-parent "$RMC"); eq "the next start opens a new run" 0 $?
SN=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
grep -qx "carried=$SC" <<<"$OUT" && [ "$SN" != "$SC" ] && pass "  ... carrying the earlier run's record" || fail "  ... carrying the earlier run's record" "$OUT $(cat "$T/err")"
eq "  ... linked in its own session to the run it carried and to its dispatcher" \
    "koto/links/dispatched-by/coord-parent koto/links/dispatched-by/$SC" "$(links "$SN" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
eq "  ... the carry's link written first" "session link $SN --dispatched-by $SC|session link $SN --dispatched-by coord-parent" "$(tr '\n' '|' < "$T/links" | sed 's/|$//')"
koto context exists "$SC" "koto/links/dispatched-by/$SN"; eq "  ... and nothing written in the earlier run" 1 $?
# The carried run ends in turn; the next start carries it with its link to it
# failing twice (the shim fails the first two link calls) and its dispatcher's
# link working: the warning names only the run it carried.
printf '{"source":"session"}' | koto context add "$SN" coord/source.json
koto cancel "$SN" >/dev/null 2>&1
sleep 1
OUT=$(open_by 2 coord-parent "$RMC"); eq "a carry whose links fail still opens the run, exit 0" 0 $?
SN2=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... warning after carried=" "carried=$SN|warning=link-failed dispatched_by=$SN" \
    "$(printf '%s\n' "$OUT" | grep -A1 '^carried=' | tr '\n' '|' | sed 's/|$//')"
eq "  ... recorded in the new run's own session" "warning=link-failed
dispatched_by=$SN" "$(koto context get "$SN2" session/link-warning)"
# Both links failing: one warning line each, and one dispatched_by line each
# under the key's one warning line.
printf '{"source":"session"}' | koto context add "$SN2" coord/source.json
koto cancel "$SN2" >/dev/null 2>&1
sleep 1
OUT=$(open_by 4 coord-parent "$RMC"); eq "a carry whose two links both fail opens the run, exit 0" 0 $?
SN3=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
eq "  ... printing both warnings" "warning=link-failed dispatched_by=$SN2|warning=link-failed dispatched_by=coord-parent" \
    "$(printf '%s\n' "$OUT" | grep '^warning=' | tr '\n' '|' | sed 's/|$//')"
eq "  ... the key names both dispatchers" "warning=link-failed
dispatched_by=$SN2
dispatched_by=coord-parent" "$(koto context get "$SN3" session/link-warning)"
# A later link to one of them that works takes only its own line away.
. "$REPO_ROOT/scripts/lib/dispatch-link.sh"
dl_link koto "$SN3" coord-parent; eq "a later link to one dispatcher works" 0 $?
eq "  ... leaving the other's line" "warning=link-failed
dispatched_by=$SN2" "$(koto context get "$SN3" session/link-warning)"
dl_link koto "$SN3" "$SN2"; eq "a link to the last one works" 0 $?
koto context exists "$SN3" session/link-warning; eq "  ... and the key goes" 1 $?

# --- a carry whose source is bound to another directory (shirabe#1257) ----------
# koto's cloud backend answers a run only in the directory it is bound to and
# refuses a read from any other as session_bound_elsewhere. A stand-in in front
# of the real koto plays that for one run, BE_SRC: with BE_ARM=always every
# read of it (context get, list and exists, and status) is refused from the
# start; with BE_ARM=write the refusals start once the carry has written its
# first key into the new run, a carry cut short part way. BE_KIND=other
# refuses with another failure instead. The source is live, and the starts
# run a copy of the plugin whose template the compat table doesn't list, so
# each carries it.
echo "== a carry whose source is bound elsewhere =="
mkdir -p "$T/beshim" "$T/plugin3"
cat > "$T/beshim/koto" <<EOF
#!/bin/sh
# BE_ARM=touch: once the carry writes the new run's record/meta, the source's
# record/meta is written with a later time, a write that landed mid-carry.
if [ "\$BE_ARM" = touch ] && [ "\$1 \$2" = "context add" ] && [ "\$3" != "\$BE_SRC" ] && [ "\$4" = record/meta ]; then
    "$REAL_KOTO" "\$@" || exit \$?
    "$REAL_KOTO" context get "\$BE_SRC" record/meta | jq -c '.written = "2099-01-01T00:00:00Z"' > "$T/touched-meta" \
        && "$REAL_KOTO" context add "\$BE_SRC" record/meta --from-file "$T/touched-meta" > /dev/null
    exit 0
fi
if [ "\$1 \$2" = "context add" ] && [ "\$3" != "\$BE_SRC" ] && [ "\$BE_ARM" = write ]; then
    case "\$4" in record/*|legs/*) : > "$T/be-armed" ;; esac
fi
if [ "\$BE_ARM" = always ] || [ -e "$T/be-armed" ]; then
    v=
    case "\$1 \$2" in "context get"|"context list"|"context exists") v=1 ;; esac
    [ "\$1" = status ] && v=1
    if [ -n "\$v" ]; then
        for a in "\$@"; do
            [ "\$a" = "\$BE_SRC" ] || continue
            if [ "\$BE_KIND" = other ]; then echo "koto: the bucket read timed out" >&2; exit 1; fi
            printf '{"error":"session_bound_elsewhere: session %s is bound to another directory","code":"session_bound_elsewhere","session":"%s"}\n' "\$a" "\$a"
            exit 2
        done
    fi
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/beshim/koto"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin3/"
printf '\n<!-- a change to the template, for the carry case -->\n' >> "$T/plugin3/skills/coordinate/koto-templates/coordinate.md"
jq '.compat += 1' "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json" > "$T/plugin3/skills/coordinate/koto-templates/coordinate.compat.json"
RMB='["docs/roadmaps/ROADMAP-bound.md"]'
open_be() { # open_be <arm> <kind> <source>: a start from the plugin copy behind the stand-in; output in $T/out
    with_role "$RMB" > "$T/args.json"
    rm -f "$T/be-armed"
    BE_SRC=$3 BE_ARM=$1 BE_KIND=$2 PATH="$T/beshim:$PATH" bash "$T/plugin3/skills/coordinate/scripts/coordinate-open.sh" \
        --plugin-root "$T/plugin3" "$T/args.json" > "$T/out" 2>"$T/err"
}
live_bound() { bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" live-session --scope-slug roadmap-bound --all 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
cancelled() { jq -s '[.[] | select(.type == "workflow_cancelled")] | length' "$(koto session dir "$1")/koto-$1.state.jsonl"; }
opened_by() { jq -nr --arg b "$1" --arg a "$(sessions)" '($a | split(" ")) - ($b | split(" ")) | map(select(. != "")) | join(" ")'; }
sleep 1
OUT=$(open_ "$RMB"); BS=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
session_seed "$BS" "$(jq -nc '{scope: {kind: "roadmap", name: "bound"}, holdings: [], deferrals: [], side_effects: [], reversals: []}')"
printf '{"source":"session"}' | koto context add "$BS" coord/source.json
eq "a live run of the scope holds its record" "$BS" "$(live_bound)"

sleep 1
BEFORE=$(sessions)
open_be write bound "$BS"; rc=$?
NB=$(opened_by "$BEFORE")
eq "a carry whose source read is refused with session_bound_elsewhere is refused=bound-elsewhere, exit 2" "2 refused=bound-elsewhere" "$rc $(grep '^refused=' "$T/out")"
grep -q '^session=' "$T/out" && fail "  ... printing no session=" "$(cat "$T/out")" || pass "  ... printing no session="
grep -qF "koto session rebind $BS --to $(pwd -P)" "$T/err" && pass "  ... naming koto session rebind <run> --to <this directory>" \
    || fail "  ... naming koto session rebind <run> --to <this directory>" "$(cat "$T/err")"
grep -q 'stop the coordinator session.*rebind.*only then reap' "$T/err" && pass "  ... and the order: stop, rebind or carry, only then reap" \
    || fail "  ... and the order: stop, rebind or carry, only then reap" "$(cat "$T/err")"
eq "  ... the source still live and uncancelled" "$BS 0" "$(live_bound) $(cancelled "$BS")"
eq "  ... the new run cancelled" 1 "$( [ -n "$NB" ] && cancelled "$NB")"
koto context exists "$NB" record/meta; eq "  ... holding no record" 1 $?

sleep 1
BEFORE=$(sessions)
open_be write other "$BS"; rc=$?
NB=$(opened_by "$BEFORE")
eq "a carry cut short at a key by another failure is failed=carry, exit 1" "1 failed=carry" "$rc $(grep '^failed=' "$T/out")"
eq "  ... the source still live and uncancelled" "$BS 0" "$(live_bound) $(cancelled "$BS")"
eq "  ... the new run cancelled" 1 "$( [ -n "$NB" ] && cancelled "$NB")"
koto context exists "$NB" record/meta; eq "  ... holding no record" 1 $?

sleep 1
BEFORE=$(sessions)
open_be always bound "$BS"; rc=$?
eq "a start whose candidate holds a record it can't read (session_bound_elsewhere) is refused=bound-elsewhere, exit 2" "2 refused=bound-elsewhere" "$rc $(grep '^refused=' "$T/out")"
grep -q '^session=' "$T/out" && fail "  ... printing no session=" "$(cat "$T/out")" || pass "  ... printing no session="
eq "  ... opening nothing" "$BEFORE" "$(sessions)"
grep -qF "koto session rebind $BS --to $(pwd -P)" "$T/err" && pass "  ... naming the rebind" || fail "  ... naming the rebind" "$(cat "$T/err")"

sleep 1
BEFORE=$(sessions)
open_be touch bound "$BS"; rc=$?
NB=$(opened_by "$BEFORE")
eq "a carry whose source was written while it ran is failed=carry, exit 1" "1 failed=carry" "$rc $(grep '^failed=' "$T/out")"
grep -q 'written during the carry' "$T/err" && pass "  ... saying so" || fail "  ... saying so" "$(cat "$T/err")"
eq "  ... the source still live and uncancelled" "$BS 0" "$(live_bound) $(cancelled "$BS")"
eq "  ... the new run cancelled" 1 "$( [ -n "$NB" ] && cancelled "$NB")"
koto context exists "$NB" record/meta; eq "  ... its record/meta, written by the carry, withdrawn" 1 $?

sleep 1
open_be none bound "$BS"; rc=$?
NB=$(sed -n 's/^session=//p' "$T/out")
eq "a carry that lands opens the new run" "0 carried=$BS" "$rc $(grep '^carried=' "$T/out")"
eq "  ... and cancels the source after it" "carried=$BS|cancelled=$BS" "$(grep -E '^(carried|cancelled)=' "$T/out" | tr '\n' '|' | sed 's/|$//')"
eq "  ... once the new run's record/meta holds the source's written time" "$(koto context get "$BS" record/meta | jq -r .written)" \
    "$(koto context get "$NB" record/meta | jq -r .written)"
eq "  ... leaving the new run the scope's live one" "$NB" "$(live_bound)"

# The issue's second start: the run holding the record was cancelled and can't
# be read from here. The start refuses rather than open an empty run.
printf '{"source":"session"}' | koto context add "$NB" coord/source.json
koto cancel "$NB" > /dev/null 2>&1
sleep 1
BEFORE=$(sessions)
open_be always bound "$NB"; rc=$?
eq "a second start after a cancelled source it can't read (session_bound_elsewhere) is refused, exit 2" "2 refused=bound-elsewhere" "$rc $(grep '^refused=' "$T/out")"
grep -q '^session=' "$T/out" && fail "  ... printing no session=" "$(cat "$T/out")" || pass "  ... printing no session="
eq "  ... opening nothing" "$BEFORE" "$(sessions)"
# Once it reads again (rebound here), the next start carries the cancelled run.
sleep 1
open_be none bound "$NB"
grep -qx "carried=$NB" "$T/out" && pass "once it can be read, the next start carries the cancelled run" \
    || fail "once it can be read, the next start carries the cancelled run" "$(cat "$T/out" "$T/err")"

# --- the run's role -------------------------------------------------------------
# docs/designs/DESIGN-coordinator-named-roles.md, Decision 1; PRD R2, R5, R9.
# A shim in front of the real koto fails, for one run, every read of its
# record/run (FAIL_RUN_READ) or the write of its record/meta (FAIL_META_ADD,
# the first key any record write makes, so a refused write leaves nothing),
# and with FAIL_AFTER_CARRY fails every record/meta write once the start has
# linked a new run to that run, the carry having landed (a same-host carry's
# change write, made after cancel_others).
echo "== the run's role =="
# The role cases tick their runs, whose gates read the gh stand-in.
. "$REPO_ROOT/scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
cat > "$T/rshim" <<EOF
#!/bin/sh
if [ -n "\$FAIL_RUN_READ" ] && [ "\$3" = "\$FAIL_RUN_READ" ]; then
    case "\$1 \$2 \$*" in "context list "*record/run*|"context get "*record/run*) echo "koto: the read of record/run failed" >&2; exit 1 ;; esac
fi
if [ -n "\$FAIL_META_ADD" ] && [ "\$1 \$2 \$3 \$4" = "context add \$FAIL_META_ADD record/meta" ]; then echo "koto: the write failed" >&2; exit 1; fi
if [ -n "\$FAIL_AFTER_CARRY" ]; then
    if [ "\$1 \$2" = "session link" ]; then case "\$*" in *"--dispatched-by \$FAIL_AFTER_CARRY") : > "$T/rshim-armed" ;; esac; fi
    if [ -e "$T/rshim-armed" ] && [ "\$1 \$2" = "context add" ] && [ "\$4" = record/meta ]; then echo "koto: the write failed" >&2; exit 1; fi
fi
exec "$REAL_KOTO" "\$@"
EOF
chmod +x "$T/rshim"
ropen() { # ropen <args json> [opener flags...]: the opener with exactly these args behind the shim; OUT, RC
    printf '%s' "$1" > "$T/args.json"; shift
    rm -f "$T/rshim-armed"
    OUT=$(KOTO_BIN="$T/rshim" bash "$OPEN" --plugin-root "$T/plugin" "$@" "$T/args.json" 2>"$T/err"); RC=$?
}
line() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
msg() { grep '^coordinate-open: ' "$T/err" | tail -1; }
row() { jq -nc --arg k "$1" --arg v "$2" '{key: $k, value: $v, set_by: "the human", set: "2026-09-26T08:00Z"}'; }
# found_run <run>: the run's first tick, its find sealing the record found
# (and recording the session store), as a run a start resumes has done.
found_run() {
    koto next "$1" --no-cleanup > "$T/tick.out" 2>&1
    bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" run-facts --session "$1" > /dev/null 2>&1 \
        || fail "$1's find seals its record found" "$(head -c 600 "$T/tick.out")"
}
# rec_run <scope> <run-rows-json>: a new live run of roadmap <scope> (Active on
# the host's default branch), opened as a manager, holding a record whose Run
# section is <rows>, its find run, so a start resumes it. Sets R.
rec_run() {
    sleep 1
    jq --arg n "$1" '.files["acme/widgets"]["main:docs/roadmaps/ROADMAP-\($n).md"] = "---\nstatus: Active\n---\n\n# Roadmap\n\n## Features\n\n### Feature 1: first\n\n**Dependencies:** None\n**Status:** Planned\n"' \
        "$GH_DB" > "$T/gh.tmp" && mv "$T/gh.tmp" "$GH_DB"
    OUT=$(open_raw "[\"docs/roadmaps/ROADMAP-$1.md\",\"--role\",\"manager\"]"); R=$(printf '%s\n' "$OUT" | sed -n 's/^session=//p')
    session_seed "$R" "$(jq -nc --arg n "$1" --argjson r "$2" '{scope: {kind: "roadmap", name: $n}, holdings: [], deferrals: [], side_effects: [], reversals: []}
        + (if $r == [] then {} else {run: $r} end)')"
    found_run "$R"
}
# snap <run>: the run's record keys and values, its log's length and the
# session list, which a refused or asked start leaves as they were.
snap() {
    local k
    { for k in $(koto context list "$1" --prefix record/ | jq -r '.[]'); do printf '%s %s\n' "$k" "$(koto context get "$1" "$k" | jq -cS .)"; done
      wc -l < "$(koto session dir "$1")/koto-$1.state.jsonl" | tr -d ' '; sessions; } | shasum
}
rrow() { koto context get "$1" record/run | jq -r '[.[] | select(.key == "role")] | if length == 0 then "none" else (.[0] | "\(.value)|\(.set_by)") end'; }
rset() { koto context get "$1" record/run | jq -r '.[] | select(.key == "role") | .set'; }
# rentry <run>: the text of the run's last role entry.
rentry() { bash "$T/plugin/skills/coordinate/scripts/state-entry.sh" --session "$1" --list 2>/dev/null | jq -r '[.[] | select(.text | startswith("Run role"))] | last | .text // empty'; }
# in_window <set> <before> <after>: a Set time between two clock reads.
in_window() { [[ ! $1 < $2 ]] && [[ ! $1 > $3 ]]; }
now_min() { date -u +%Y-%m-%dT%H:%MZ; }

# The flag, checked before any koto call.
BEFORE=$(sessions)
for v in lead Director ''; do
    open_raw "[\"docs/roadmaps/ROADMAP-role-x.md\",\"--role\",\"$v\"]" > "$T/out"; rc=$?
    eq "--role '$v' is refused=invalid_role, exit 2" "2 refused=invalid_role" "$rc $(cat "$T/out")"
    eq "  ... with the invalid_role row" "coordinate-open: The role \`$v\` must be manager or director." "$(grep '^coordinate-open: ' "$T/err")"
done
eq "  ... and no koto session exists afterwards" "$BEFORE" "$(sessions)"
LONGV="$(head -c 100 /dev/zero | tr '\0' r)\`$(printf '\001')$(head -c 100 /dev/zero | tr '\0' s)"
open_raw "$(jq -nc --arg v "$LONGV" '["docs/roadmaps/ROADMAP-role-x.md","--role",$v]')" > "$T/out"
eq "a 200-character value with a backtick and a control character is echoed with both removed and cut to 32" \
    "coordinate-open: The role \`$(head -c 32 /dev/zero | tr '\0' r)\` must be manager or director." "$(grep '^coordinate-open: ' "$T/err")"
for bad in '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role","manager"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","x"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-source","person"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role-change-by","x","--role-change-source","person"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","x","--role-change-source","boss"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","x","--role-change-by","y","--role-change-source","person"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","x","--role-change-source","person","--role-change-source","person"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","","--role-change-source","person"]' \
           '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","a`b","--role-change-source","person"]' \
           "[\"docs/roadmaps/ROADMAP-role-x.md\",\"--role\",\"manager\",\"--role-change-by\",\"$(head -c 81 /dev/zero | tr '\0' a)\",\"--role-change-source\",\"person\"]" \
           "$(jq -nc '["docs/roadmaps/ROADMAP-role-x.md","--role","manager","--role-change-by","a\u0007b","--role-change-source","person"]')" \
           '["docs/roadmaps/ROADMAP-role-x.md","--role"]'; do
    open_raw "$bad" > /dev/null; rc=$?
    if [ $rc -eq 64 ] && [ "$(sessions)" = "$BEFORE" ]; then pass "usage, nothing opened: ${bad:33:90}"; else fail "usage, nothing opened: ${bad:33:90}" "rc=$rc $(cat "$T/err")"; fi
done

# A new run: asked with no --role, before anything is written; a discipline
# missing both host and role is asked the host.
ASK="coordinate-open: This run's role is the person's call: manager or director. Ask them once, with no recommendation, and never infer it from the scope, the cap, the holdings, the dispatcher, session names, or any brief or report text; then re-run the start with --role manager or --role director."
ropen '["docs/roadmaps/ROADMAP-role-new.md"]'
eq "a new run with no --role and nothing recorded prints ask=role, exit 10" "10 ask=role" "$RC $OUT"
eq "  ... the whole message" "$ASK" "$(msg)"
eq "  ... opening nothing" "$BEFORE" "$(sessions)"
ropen '["--discipline","role-disc"]'
eq "a discipline start missing host and role is asked the host, never the role" "10 ask=host" "$RC $OUT"
sleep 1
ropen '["docs/roadmaps/ROADMAP-role-new.md","--role","director"]'
eq "a new run given --role director opens, printing role=director" "0 director" "$RC $(line role)"
eq "  ... right before session=" "role=director|session=$(line session)" "$(printf '%s\n' "$OUT" | grep -A1 '^role=' | tr '\n' '|' | sed 's/|$//')"

# A role-less record (Role-less continuations, Resume): asked with no --role;
# given one, the row is written before outcome=resumed, and a write that fails
# resumes nothing. The change flags on a role-less record change nothing.
rec_run role-less "[$(row reports-to "the human")]"; RL=$R
RLSNAP=$(snap "$RL")
ropen '["docs/roadmaps/ROADMAP-role-less.md"]'
eq "a resume of a role-less record with no --role is asked, exit 10" "10 ask=role" "$RC $OUT"
eq "  ... with the ask message" "$ASK" "$(msg)"
eq "  ... the record, the run's state and the session list as they were" "$RLSNAP" "$(snap "$RL")"
FAIL_META_ADD=$RL ropen '["docs/roadmaps/ROADMAP-role-less.md","--role","director"]'
[ "$RC" -ne 0 ] && pass "a resume whose row write fails exits non-zero ($RC)" || fail "a resume whose row write fails exits non-zero" "$OUT"
eq "  ... printing no outcome=resumed and no session=" "" "$(printf '%s\n' "$OUT" | grep -E '^(outcome|session)=')"
eq "  ... the record as it was" "$RLSNAP" "$(snap "$RL")"
T0=$(now_min)
ropen '["docs/roadmaps/ROADMAP-role-less.md","--role","director","--role-change-by","lane-lead","--role-change-source","person"]'
T1=$(now_min)
eq "given --role director (and change flags, which change nothing here) it resumes" "0 resumed $RL director" "$RC $(line outcome) $(line session) $(line role)"
eq "  ... no role_changed_from" "" "$(line role_changed_from)"
eq "  ... the row written as a first role, by the start's --role" "director|start --role" "$(rrow "$RL")"
in_window "$(rset "$RL")" "$T0" "$T1" && pass "  ... at the write's time" || fail "  ... at the write's time" "$T0 <= $(rset "$RL") <= $T1"

# A run recorded manager whose reports-to row has an address, resumed and
# carried. MGR_ADDR is a realistic dispatcher address, longer than 32
# characters, which every refusal names whole.
MGR_ADDR=coordinate-roadmap-director-plan-20260926T080000Z
MGR_RT="Lane lead at $MGR_ADDR"
rec_run role-m "[$(row role manager),$(row reports-to "$MGR_RT"),$(row coordinator coord-m)]"; M0=$R
M0SNAP=$(snap "$M0")
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","director"]'
eq "a resume naming director for a run recorded manager is refused role-mismatch, exit 2" "2 refused role-mismatch" "$RC $(line outcome) $(line reason)"
eq "  ... the whole role_mismatch message" "coordinate-open: $M0 is recorded as manager; this start names director. A continuation keeps its role unless an intervention from above changes it; nothing was written and $M0 goes on as it was. Start again naming manager, or no role, or start director as a new lineage." "$(msg)"
eq "  ... the record, the run's state and the session list as they were" "$M0SNAP" "$(snap "$M0")"
FAIL_RUN_READ=$M0 ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager"]'
eq "a resume whose role read fails is failed=role_read, exit 1" "1 failed=role_read" "$RC $OUT"
eq "  ... never asked or accepted, nothing written" "$M0SNAP" "$(snap "$M0")"
# The carry: the run ended, so a start carries it.
koto cancel "$M0" > /dev/null 2>&1
M0SNAP=$(snap "$M0")
sleep 1
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","director"]'
eq "a carry naming director for a run recorded manager is refused role-mismatch" "2 refused role-mismatch" "$RC $(line outcome) $(line reason)"
eq "  ... nothing opened, nothing written" "$M0SNAP" "$(snap "$M0")"
FAIL_RUN_READ=$M0 ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager"]'
eq "a carry whose role read fails is failed=role_read, exit 1" "1 failed=role_read" "$RC $OUT"
eq "  ... nothing opened, nothing written" "$M0SNAP" "$(snap "$M0")"
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager"]'
M1=$(line session)
eq "a carry naming the recorded role carries it" "0 $M0 manager" "$RC $(line carried) $(line role)"
eq "  ... the new run holding the row as it was" "manager|the human" "$(rrow "$M1")"
found_run "$M1"

# M1 resumed: M0 is its predecessor (the run its carry linked it to).
ropen '["docs/roadmaps/ROADMAP-role-m.md"]'
eq "a resume with no --role continues the recorded role" "0 resumed manager" "$RC $(line outcome) $(line role)"
M1SNAP=$(snap "$M1")
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","director","--role-change-by","lane-other","--role-change-source","dispatcher"]'
eq "a dispatcher change naming a session the record doesn't report to is refused role-change-refused" "2 refused role-change-refused" "$RC $(line outcome) $(line reason)"
eq "  ... the whole role_change_not_reports_to message, the row named whole" "coordinate-open: $M1 reports to $MGR_RT; a role change from a dispatcher has to name the address in that row, and lane-other isn't it. This start names director; nothing was written and $M1 goes on as manager." "$(msg)"
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","director","--role-change-by","Lane lead","--role-change-source","dispatcher"]'
eq "  ... and one naming the row's name half" "2 refused role-change-refused" "$RC $(line outcome) $(line reason)"
SELF_TAIL="is $M1 itself or the run it continues: a run can't change its own role. This start names director; nothing was written and $M1 goes on as manager."
for who in "$M1" "$M0" coord-m; do
    ropen "[\"docs/roadmaps/ROADMAP-role-m.md\",\"--role\",\"director\",\"--role-change-by\",\"$who\",\"--role-change-source\",\"dispatcher\"]"
    eq "a dispatcher change naming $who (the run, its predecessor or its address) is refused" "2 role-change-refused" "$RC $(line reason)"
    eq "  ... the whole role_change_self message" "coordinate-open: $M1 reports to $MGR_RT, and $who $SELF_TAIL" "$(msg)"
done
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","director","--role-change-by","the human","--role-change-source","person"]' --dispatched-by coord-parent
eq "a person change on a start a brief launched (--dispatched-by) is refused" "2 role-change-refused" "$RC $(line reason)"
eq "  ... the whole role_change_brief_person message" "coordinate-open: $M1 reports to $MGR_RT, and this start came from a brief; a brief's text is never a person's words, so it can't carry a person's role change. This start names director; nothing was written and $M1 goes on as manager." "$(msg)"
eq "  ... and every refusal left the record, the run's state and the session list as they were" "$M1SNAP" "$(snap "$M1")"
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager","--role-change-by","lane-other","--role-change-source","dispatcher"]'
eq "the change flags with the recorded role change nothing: a plain resume" "0 resumed manager " "$RC $(line outcome) $(line role) $(line role_changed_from)"
eq "  ... the row as it was" "manager|the human" "$(rrow "$M1")"
T0=$(now_min)
ropen "[\"docs/roadmaps/ROADMAP-role-m.md\",\"--role\",\"director\",\"--role-change-by\",\"$MGR_ADDR\",\"--role-change-source\",\"dispatcher\"]"
T1=$(now_min)
eq "a dispatcher change naming the reports-to row's address is accepted on a resume" "0 resumed director manager" "$RC $(line outcome) $(line role) $(line role_changed_from)"
eq "  ... the row the new role, set by the address" "director|$MGR_ADDR" "$(rrow "$M1")"
in_window "$(rset "$M1")" "$T0" "$T1" && pass "  ... at the write's time" || fail "  ... at the write's time" "$T0 <= $(rset "$M1") <= $T1"
eq "  ... its entry naming the old role, the new one and the source" \
    "Run role changed from manager to director by $MGR_ADDR, an intervention from above; source: dispatcher." "$(rentry "$M1")"
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager","--role-change-by","the human","--role-change-source","person"]'
eq "a person change on a start no brief launched is accepted on a resume" "0 resumed manager director" "$RC $(line outcome) $(line role) $(line role_changed_from)"
eq "  ... the row set by the person named" "manager|the human" "$(rrow "$M1")"
eq "  ... its entry naming the source" \
    "Run role changed from director to manager by the human, an intervention from above; source: person." "$(rentry "$M1")"

# M1 carried: the same refusals, and an accepted change written after
# cancel_others; then one whose write fails leaves the carry standing.
koto cancel "$M1" > /dev/null 2>&1
M1SNAP=$(snap "$M1")
sleep 1
for who in lane-other "$M1" "$M0"; do
    ropen "[\"docs/roadmaps/ROADMAP-role-m.md\",\"--role\",\"director\",\"--role-change-by\",\"$who\",\"--role-change-source\",\"dispatcher\"]"
    eq "a carry's dispatcher change naming $who is refused" "2 role-change-refused" "$RC $(line reason)"
    case "$(msg)" in "coordinate-open: $M1 reports to $MGR_RT"*"This start names director; nothing was written and $M1 goes on as manager.") pass "  ... naming the reports-to row and both roles" ;;
        *) fail "  ... naming the reports-to row and both roles" "$(msg)" ;; esac
done
eq "  ... nothing opened, nothing written" "$M1SNAP" "$(snap "$M1")"
T0=$(now_min)
ropen "[\"docs/roadmaps/ROADMAP-role-m.md\",\"--role\",\"director\",\"--role-change-by\",\"$MGR_ADDR\",\"--role-change-source\",\"dispatcher\"]"
T1=$(now_min)
M2=$(line session)
eq "an accepted dispatcher change on a carry carries" "0 $M1 director manager" "$RC $(line carried) $(line role) $(line role_changed_from)"
eq "  ... the row the new role, set by the address" "director|$MGR_ADDR" "$(rrow "$M2")"
in_window "$(rset "$M2")" "$T0" "$T1" && pass "  ... at the write's time" || fail "  ... at the write's time" "$T0 <= $(rset "$M2") <= $T1"
eq "  ... and the source run left holding manager" "manager|the human" "$(rrow "$M1")"
found_run "$M2"
eq "  ... with its entry, read once the run's find has run" "Run role changed from manager to director by $MGR_ADDR, an intervention from above; source: dispatcher." "$(rentry "$M2")"
koto cancel "$M2" > /dev/null 2>&1
sleep 1
FAIL_AFTER_CARRY=$M2 ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager","--role-change-by","the human","--role-change-source","person"]'
M3=$(line session)
eq "a carry whose change write fails still stands, exit 0" "0 $M2" "$RC $(line carried)"
eq "  ... printing the recorded role and warning=role-change-unwritten, then session=" "role=director|warning=role-change-unwritten|session=$M3" \
    "$(printf '%s\n' "$OUT" | grep -E '^(role=|warning=role-change|session=)' | tr '\n' '|' | sed 's/|$//')"
eq "  ... the new run holding the recorded role" "director|$MGR_ADDR" "$(rrow "$M3")"
found_run "$M3"
ropen '["docs/roadmaps/ROADMAP-role-m.md","--role","manager","--role-change-by","the human","--role-change-source","person"]'
eq "  ... and the same start, once the run's find has recorded its store, applies it as a resume" "0 resumed manager director" \
    "$RC $(line outcome) $(line role) $(line role_changed_from)"
eq "  ... writing the row" "manager|the human" "$(rrow "$M3")"

# The other direction (recorded director, asked manager), on a record whose
# reports-to row names no address, then none at all.
rec_run role-d "[$(row role director),$(row reports-to "the human")]"; D0=$R
D0SNAP=$(snap "$D0")
ropen '["docs/roadmaps/ROADMAP-role-d.md","--role","manager"]'
eq "a resume naming manager for a run recorded director is refused role-mismatch" "2 refused role-mismatch" "$RC $(line outcome) $(line reason)"
eq "  ... the whole message, ending 'or start manager as a new lineage.'" "coordinate-open: $D0 is recorded as director; this start names manager. A continuation keeps its role unless an intervention from above changes it; nothing was written and $D0 goes on as it was. Start again naming director, or no role, or start manager as a new lineage." "$(msg)"
ropen '["docs/roadmaps/ROADMAP-role-d.md","--role","manager","--role-change-by","lane-lead","--role-change-source","dispatcher"]'
eq "a dispatcher change on a record whose reports-to row has no address is refused" "2 role-change-refused" "$RC $(line reason)"
eq "  ... the whole role_change_no_address message, naming the row" "coordinate-open: $D0 reports to the human, which names no address, so no dispatcher change can be checked. This start names manager; nothing was written and $D0 goes on as director." "$(msg)"
eq "  ... the record as it was" "$D0SNAP" "$(snap "$D0")"
koto cancel "$D0" > /dev/null 2>&1
D0SNAP=$(snap "$D0")
sleep 1
ropen '["docs/roadmaps/ROADMAP-role-d.md","--role","manager"]'
eq "a carry naming manager for a run recorded director is refused role-mismatch" "2 refused role-mismatch" "$RC $(line outcome) $(line reason)"
eq "  ... nothing opened, nothing written" "$D0SNAP" "$(snap "$D0")"
ropen '["docs/roadmaps/ROADMAP-role-d.md","--role","manager","--role-change-by","the human","--role-change-source","person"]'
D1=$(line session)
eq "a person change on a carry is accepted" "0 $D0 manager director" "$RC $(line carried) $(line role) $(line role_changed_from)"
eq "  ... the new run's row" "manager|the human" "$(rrow "$D1")"
rec_run role-n "[$(row role director)]"; N0=$R
ropen '["docs/roadmaps/ROADMAP-role-n.md","--role","manager","--role-change-by","lane-lead","--role-change-source","dispatcher"]'
eq "  ... and on a record with no reports-to row, naming no session on its record" \
    "coordinate-open: $N0 reports to no session on its record, which names no address, so no dispatcher change can be checked. This start names manager; nothing was written and $N0 goes on as director." "$(msg)"
ropen "[\"docs/roadmaps/ROADMAP-role-n.md\",\"--role\",\"manager\",\"--role-change-by\",\"$N0\",\"--role-change-source\",\"dispatcher\"]"
eq "two causes (the run's own name, no reports-to row): role_change_self, the design's order" \
    "coordinate-open: $N0 reports to no session on its record, and $N0 is $N0 itself or the run it continues: a run can't change its own role. This start names manager; nothing was written and $N0 goes on as director." "$(msg)"

# A role-less carry: asked with no --role; given one it prints role= and
# leaves the row to the no-role gap.
rec_run role-lc "[$(row reports-to "the human")]"; LC0=$R
koto cancel "$LC0" > /dev/null 2>&1
LCSNAP=$(snap "$LC0")
sleep 1
ropen '["docs/roadmaps/ROADMAP-role-lc.md"]'
eq "a carry of a role-less record with no --role is asked" "10 ask=role" "$RC $OUT"
eq "  ... before the carry: nothing opened, nothing written" "$LCSNAP" "$(snap "$LC0")"
ropen '["docs/roadmaps/ROADMAP-role-lc.md","--role","manager"]'
LC1=$(line session)
eq "given --role it carries, printing role=manager" "0 $LC0 manager" "$RC $(line carried) $(line role)"
eq "  ... leaving the row to the no-role gap" "none" "$(rrow "$LC1")"
found_run "$LC1"
grep -q '^  no-role: ' <<<"$(bash "$T/plugin/skills/coordinate/scripts/state-handover.sh" --session "$LC1" --check 2>&1)" \
    && pass "  ... which the handover check lists" || fail "  ... which the handover check lists" "$(bash "$T/plugin/skills/coordinate/scripts/state-handover.sh" --session "$LC1" --check 2>&1)"

# An import given --role reads the source's role where it is, before koto
# imports; on the local backend koto refuses that read.
BEFORE=$(sessions)
CLAUDE_CODE_SESSION_ID=$(printf '%s-0000-4000-8000-%012d' dddddddd 4) \
    ropen '["docs/roadmaps/ROADMAP-role-imp.md","--import","coordinate-roadmap-role-imp-20260101T000000Z","--from","/srv/source-ws","--role","manager"]'
eq "an import given --role on the local backend is refused=workspace_needs_cloud, exit 2" "2 refused=workspace_needs_cloud" "$RC $OUT"
eq "  ... landing nothing" "$BEFORE" "$(sessions)"

# A dispatcher naming the run a start resumes is still refused (64).
found_run "$D1"
ropen "[\"docs/roadmaps/ROADMAP-role-d.md\",\"--role\",\"manager\"]" --dispatched-by "$D1"
eq "a resume whose --dispatched-by names the resumed run is usage, exit 64" 64 "$RC"
grep -q 'start again without --dispatched-by' "$T/err" && pass "  ... saying to start again without --dispatched-by" || fail "  ... saying to start again without --dispatched-by" "$(cat "$T/err")"

# --- two hosts on koto's cloud backend -----------------------------------------
# Hosts A and B share a bucket served by testdata/fake-s3.py; each has its own
# HOME, cache and workspace (testdata/cloud-hosts.sh). Everything from here
# needs koto's `session import`, which the start above already required.
echo "== two hosts =="
. "$HERE/testdata/cloud-hosts.sh"
ktg_on_exit 's3_stop; case "$T" in */coordinate-open-engine.*) rm -rf "$T" ;; esac'
s3_start || { fail "the fake S3 server starts" "$(cat "$T/s3/log" 2>&1)"; echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; exit 1; }
host_make a; host_make b
for h in a b; do
    (cd "$T/hosts/$h/work" && git init -q && git remote add origin https://github.com/acme/widgets.git \
        && printf '.koto/\n' >> .git/info/exclude)
    printf -- '---\nname: plain\nversion: "1.0"\ndescription: One state, then done.\ninitial_state: work\nstates:\n  work:\n    accepts:\n      status:\n        type: enum\n        values: [ok]\n        required: true\n    transitions:\n      - target: done\n        when:\n          status: ok\n  done:\n    terminal: true\n---\n\n## work\n\nSubmit `status: ok`.\n\n## done\n\nTerminal.\n' \
        > "$T/hosts/$h/work/plain.md"
done
host_on a koto init plain-run --template plain.md > /dev/null 2>"$T/err"; eq "a plain session opens on host A" 0 $?
printf '{"a":1}' | host_on a koto context add plain-run record/meta > /dev/null 2>"$T/err"
printf '{"b":2}' | host_on a koto context add plain-run legs/r1/deliver > /dev/null 2>"$T/err"
host_on b koto template compile plain.md > /dev/null 2>"$T/err"
OUT=$(host_on b koto session import plain-run --from "$(host_ws a)" 2>"$T/err"); eq "host B imports it" 0 $?
eq "  ... with every key" 2 "$(printf '%s' "$OUT" | jq -r .keys)"
eq "  ... readable on B" '{"b":2}' "$(host_on b koto context get plain-run legs/r1/deliver 2>&1)"
# koto 0.32.0 keeps an import's source as a read-only predecessor
# (koto_keeps_source); an older koto's source refuses its reads too.
KEEPS_SOURCE=0
koto_keeps_source && KEEPS_SOURCE=1
host_on a koto context get plain-run record/meta > "$T/out" 2>"$T/err"; rc=$?
if [ "$KEEPS_SOURCE" = 1 ]; then
    eq "host A's copy still answers a read with its last pushed copy" '0 {"a":1}' "$rc $(cat "$T/out")"
else
    eq "host A's copy then refuses a read" 2 $rc
    grep -q session_migrated "$T/out" && pass "  ... as session_migrated" || fail "  ... as session_migrated" "$(cat "$T/out" "$T/err")"
fi
printf '{"a":2}' | host_on a koto context add plain-run record/meta > "$T/out" 2>"$T/err"; eq "host A's copy refuses a write" 2 $?
grep -q session_migrated "$T/out" && pass "  ... as session_migrated" || fail "  ... as session_migrated" "$(cat "$T/out" "$T/err")"
eq "  ... and koto's dashboard detail says it migrated to B's copy" plain-run \
    "$(host_on a koto dashboard plain-run --detail 2>/dev/null | jq -r '.migrated.target // empty')"

# --- the opener's --import -----------------------------------------------------
# Host B runs the opener with koto behind a shim that logs every call, so a
# refusal made before koto runs is seen to make no `session import`.
echo "== --import =="
REAL_KOTO=$(command -v koto)
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$T/koto-calls" "$REAL_KOTO" > "$T/koto-shim"
chmod +x "$T/koto-shim"
# On koto 0.32.0 and later an import is taken over, which records the Claude
# session running the opener as the new run's driver, so B's opener runs as a
# synthetic Claude session, built here so no id-shaped literal ships.
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
import_b() { # import_b <args json>: the opener on host B; output in $T/out, stderr in $T/err
    : > "$T/koto-calls"
    printf '%s' "$1" > "$T/args.json"
    host_on b env KOTO_BIN="$T/koto-shim" CLAUDE_CODE_SESSION_ID="$B_ID" bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" > "$T/out" 2>"$T/err"
}
# The opener's feature probe runs `session import --help`, which imports nothing.
imported() { grep '^session import' "$T/koto-calls" | grep -vc -- ' --help$'; }
RM='docs/roadmaps/ROADMAP-plugin-system.md'
WS_A=$(host_ws a)

for bad in "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\"]" \
           "[\"$RM\",\"--from\",\"$WS_A\"]" \
           "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\",\"--from\",\"work\"]" \
           "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\",\"--from\",\"$WS_A\",\"--cap\",\"4\"]" \
           "[\"$RM\",\"--import\",\"a\",\"--import\",\"b\",\"--from\",\"$WS_A\"]"; do
    import_b "$bad"; rc=$?
    if [ $rc -eq 64 ] && [ "$(imported)" = 0 ]; then pass "usage, nothing imported: $bad"; else fail "usage, nothing imported: $bad" "rc=$rc $(cat "$T/out" "$T/err")"; fi
done
import_b "[\"--discipline\",\"ci\",\"--host\",\"acme/widgets\",\"--import\",\"coordinate-discipline-ci-20260101T000000Z\",\"--from\",\"$WS_A\"]"
eq "--import at discipline scope reaches koto's import, which finds no such run" "2 refused=import_source_not_found" "$? $(cat "$T/out")"
import_b "[\"$RM\",\"--import\",\"plain-run\",\"--from\",\"$WS_A\"]"
eq "a name that isn't a run of the scope is refused" "2 refused=session-name" "$? $(cat "$T/out")"
eq "  ... before any import" 0 "$(imported)"
# The takeover an import makes on koto 0.32.0 and later needs the Claude
# session's id; without one the import is refused before koto imports.
if [ "$KEEPS_SOURCE" = 1 ]; then
    printf '%s' "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260101T000000Z\",\"--from\",\"$WS_A\"]" > "$T/args.json"
    : > "$T/koto-calls"
    host_on b env KOTO_BIN="$T/koto-shim" bash "$OPEN" --plugin-root "$T/plugin" "$T/args.json" > "$T/out" 2>"$T/err"
    eq "an import with no Claude session id is refused" "2 refused=session-id" "$? $(cat "$T/out")"
    eq "  ... before any import" 0 "$(imported)"
fi

# Refusals after koto's import, each on a real run host A opened. Each leaves
# the run live on B (the source is marked migrated), so it is cancelled there
# before the next case, which needs no live run of the scope on B.
open_a() { # open_a <plugin root>: the opener on host A with the roadmap alone; the run in $OPENED
    printf '["%s","--role","manager"]' "$RM" > "$T/args-a.json"
    OPENED=$(host_on a bash "$1/skills/coordinate/scripts/coordinate-open.sh" --plugin-root "$1" "$T/args-a.json" 2>"$T/open-a.err" | sed -n 's/^session=//p')
}
# A run whose find never ran, so it never recorded the session store
# (coord/source.json): no record, and no run a start would resume.
open_a "$T/plugin"
[ -n "$OPENED" ] && pass "host A opens a plain run of the scope" || fail "host A opens a plain run of the scope" "$(cat "$T/open-a.err")"
import_b "[\"$RM\",\"--import\",\"$OPENED\",\"--from\",\"$WS_A\"]"
eq "a run whose find never recorded the session store is imported, then refused" "2 refused=session-source" "$? $(grep '^refused=' "$T/out")"
host_on b koto cancel "$OPENED" >/dev/null 2>&1
sleep 1
# The host the import left (shirabe#1417). koto 0.32.0 and later still list
# the run there, as its copy's read-only predecessor, and refuse its cancel as
# session_migrated. It isn't a live run of the scope on A, so A's next open
# opens its new run and leaves it as it is, rather than stop at failed=cancel.
SRC=$OPENED
if [ "$KEEPS_SOURCE" = 1 ]; then
    eq "host A still lists the run B imported" "$SRC" "$(host_on a koto session list | jq -r --arg s "$SRC" '.[] | select(.id == $s) | .id')"
fi
eq "  ... which koto says migrated" "$SRC" "$(host_on a koto dashboard "$SRC" --detail 2>/dev/null | jq -r '.migrated.target // empty')"
eq "  ... and isn't a live run of the scope on A" "" \
    "$(host_on a bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" live-session --scope-slug roadmap-plugin-system --all 2>/dev/null)"
printf '["%s","--role","manager"]' "$RM" > "$T/args-a.json"
host_on a bash "$OPEN" --plugin-root "$T/plugin" "$T/args-a.json" > "$T/out" 2>"$T/open-a.err"; rc=$?
NEW=$(sed -n 's/^session=//p' "$T/out")
if [ $rc -eq 0 ] && [ -n "$NEW" ] && [ "$NEW" != "$SRC" ]; then
    pass "host A's next open of the scope opens a new run"
else
    fail "host A's next open of the scope opens a new run" "rc=$rc $(cat "$T/out" "$T/open-a.err")"
fi
grep -q '^failed=' "$T/out" && fail "  ... printing no failed=" "$(cat "$T/out" "$T/open-a.err")" || pass "  ... printing no failed="
grep -qx "cancelled=$SRC" "$T/out" && fail "  ... and cancelling nothing of the migrated run" "$(cat "$T/out")" || pass "  ... and cancelling nothing of the migrated run"
eq "  ... the new run the scope's one live run on A" "$NEW" \
    "$(host_on a bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" live-session --scope-slug roadmap-plugin-system 2>/dev/null)"
sleep 1
# Behind a koto whose dashboard read fails, the migrated run stays listed as
# live (as it would be had it been imported after the listing): the opener's
# cancel of it refuses as session_migrated, which it leaves alone, and it
# cancels the live run it should.
printf '#!/bin/sh\n[ "$1" = dashboard ] && exit 2\nexec "%s" "$@"\n' "$REAL_KOTO" > "$T/koto-nodash"
chmod +x "$T/koto-nodash"
printf '["%s","--role","manager"]' "$RM" > "$T/args-a.json"
host_on a env KOTO_BIN="$T/koto-nodash" bash "$OPEN" --plugin-root "$T/plugin" "$T/args-a.json" > "$T/out" 2>"$T/open-a.err"; rc=$?
NEW2=$(sed -n 's/^session=//p' "$T/out")
if [ $rc -eq 0 ] && [ -n "$NEW2" ] && [ "$NEW2" != "$NEW" ]; then
    pass "behind a koto that can't say the run migrated, A's next open still opens a new run"
else
    fail "behind a koto that can't say the run migrated, A's next open still opens a new run" "rc=$rc $(cat "$T/out" "$T/open-a.err")"
fi
eq "  ... cancelling the live run, and only it" "cancelled=$NEW" "$(grep '^cancelled=' "$T/out")"
sleep 1
# A run opened from the plugin at another path: the same template, so the same
# hash, but the run's PLUGIN_ROOT isn't this host's.
mkdir -p "$T/plugin2"
cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/plugin2/"
open_a "$T/plugin2"
[ -n "$OPENED" ] && pass "host A opens a run from a plugin at another path" || fail "host A opens a run from a plugin at another path" "$(cat "$T/open-a.err")"
import_b "[\"$RM\",\"--import\",\"$OPENED\",\"--from\",\"$WS_A\"]"
# koto 0.32.0 and later take the import over, opening the new run from this
# plugin's root, so the copy isn't rebound; an older koto resumes it, after
# moving its plugin root here.
rc=$?
if [ "$KEEPS_SOURCE" = 1 ]; then
    eq "a run from another plugin path is imported, then refused only for its find" "2 refused=session-source" "$rc $(grep '^refused=' "$T/out")"
    grep -q '^rebound=' "$T/out" && fail "  ... with no rebound=, a takeover never rebinding the copy" "$(cat "$T/out")" \
        || pass "  ... with no rebound=, a takeover never rebinding the copy"
else
    eq "a run from another plugin path is imported, its plugin root moved here, then refused only for its find" "2 refused=session-source" "$rc $(grep '^refused=' "$T/out")"
    grep -q '^rebound=.*PLUGIN_ROOT' "$T/out" && pass "  ... after rebound= naming PLUGIN_ROOT" || fail "  ... after rebound= naming PLUGIN_ROOT" "$(cat "$T/out")"
fi
host_on b koto cancel "$OPENED" >/dev/null 2>&1
eq "  ... and neither refused run is left live on B" "" "$(host_on b bash "$T/plugin/skills/coordinate/scripts/coord-log.sh" live-session --scope-slug roadmap-plugin-system --all 2>/dev/null)"

# A child session on host A: koto refuses to import it alone.
CHILD=coordinate-roadmap-plugin-system-20260101T000000Z
host_on a koto init parent-run --template plain.md > /dev/null 2>"$T/err"
host_on a koto init "$CHILD" --template plain.md --parent parent-run > /dev/null 2>"$T/err"; eq "a child session opens on host A" 0 $?
import_b "[\"$RM\",\"--import\",\"$CHILD\",\"--from\",\"$WS_A\"]"
eq "a child source is refused with koto's code" "2 refused=import_source_is_child" "$? $(head -1 "$T/out")"
eq "  ... no session on B" "" "$(host_on b koto session list 2>/dev/null | jq -r --arg s "$CHILD" '.[] | select(.id == $s) | .id')"

# A run compiled from a template host B doesn't have: koto refuses it without
# --trust-template; with it the run is imported, then refused as another
# template than the shipped one, and stays on B.
OTHER=coordinate-roadmap-plugin-system-20260102T000000Z
sed 's/One state, then done./Another template./' "$T/hosts/a/work/plain.md" > "$T/hosts/a/work/other.md"
host_on a koto init "$OTHER" --template other.md > /dev/null 2>"$T/err"; eq "a run from another template opens on host A" 0 $?
import_b "[\"$RM\",\"--import\",\"$OTHER\",\"--from\",\"$WS_A\"]"
eq "without --trust-template koto refuses the unknown template" "2 refused=import_template_unavailable" "$? $(head -1 "$T/out")"
grep -q -- '--trust-template' "$T/err" && pass "  ... and the refusal names --trust-template" || fail "  ... and the refusal names --trust-template" "$(cat "$T/err")"
eq "  ... leaving no session on B" "" "$(host_on b koto session list 2>/dev/null | jq -r --arg s "$OTHER" '.[] | select(.id == $s) | .id')"
import_b "[\"$RM\",\"--import\",\"$OTHER\",\"--from\",\"$WS_A\",\"--trust-template\"]"
eq "with --trust-template it is imported, then refused as a template this plugin can't drive" "2 refused=template-incompatible" "$? $(cat "$T/out")"
grep -q 'compat' "$T/err" && pass "  ... and the refusal names the compat numbers" || fail "  ... and the refusal names the compat numbers" "$(cat "$T/err")"
grep -q "compiled from coordinate.md at compat [^ ]* (template [0-9a-f]\{64\}); this plugin ships compat [0-9][0-9]* (template [0-9a-f]\{64\})" "$T/err" \
    && pass "  ... the template, both compat numbers and both hashes" || fail "  ... the template, both compat numbers and both hashes" "$(cat "$T/err")"
eq "  ... koto was asked with --trust-template" 1 "$(grep -c -- "^session import $OTHER --from $WS_A --trust-template\$" "$T/koto-calls")"
eq "  ... and the run stays on B" false "$(host_on b koto status "$OTHER" 2>/dev/null | jq -r .is_terminal)"

# That run is live on B now, so importing another run of the scope would make two.
import_b "[\"$RM\",\"--import\",\"coordinate-roadmap-plugin-system-20260103T000000Z\",\"--from\",\"$WS_A\"]"
eq "another live run of the scope refuses the import" "2 refused=session-live" "$? $(cat "$T/out")"
eq "  ... before any import" 0 "$(imported)"
echo; echo "coordinate-open engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]

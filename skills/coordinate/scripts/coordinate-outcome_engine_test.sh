#!/usr/bin/env bash
# coordinate-outcome_engine_test.sh -- coordinate-open.sh's takeover result
# contract, against real koto (0.28.0 or later, with `koto init --supersede`)
# and the shipped coordinate.md: every refusal by reason, the race of two
# successors, and a takeover interrupted at each step and run again
# (docs/designs/DESIGN-coordinate-successor-continues.md, Decision 1's re-run
# table and coordinate-open.sh's result contract).
#
# Proves, on a run A of one roadmap scope opened by one Claude session (a
# synthetic CLAUDE_CODE_SESSION_ID per session) and holding record entries,
# two open legs, taken_legs and leg_children, and on a second run of another
# scope opened from a plugin copy whose template has another structure:
#   1. with a second live run of A's scope beside it, the opener run by
#      another Claude session prints outcome=refused, reason=ambiguous-scope;
#   2. `--continues` naming a run of another scope, and naming A once B has
#      taken it over (a run of this scope that isn't the newest member),
#      prints reason=not-newest-member;
#   3. reason=taken-over (the race is case 6): with CLAUDE_CODE_SESSION_ID
#      unset, against a successor completed by a takeover and against one
#      whose takeover was cut after the fence, and from the rival session
#      while that takeover is cut; with it unset, the untouched A resumes
#      (outcome=resumed);
#   4. with A's append lock held past koto's 10-second fence wait, the
#      takeover prints reason=predecessor-unstoppable, and once the lock is
#      released `koto next A` is accepted;
#   5. against the run from the plugin copy, whose structure the shipped
#      compat table doesn't list, reason=template-incompatible, naming both
#      sides' compat numbers and compiled hashes, the run's as `-` with no
#      compat recorded and as its record/meta's template_compat once it holds
#      one (shirabe#1333); on a koto whose `init
#      --help` lacks --supersede, reason=koto-too-old, naming 0.28.0;
#   6. two successors taking one run over at once, from two Claude sessions
#      and two directories, held at koto's fence until both reach it: exactly
#      one prints outcome=continued, the other reason=taken-over, and exactly
#      one successor session exists;
#   7. a takeover killed at each step and run again from the same Claude
#      session: after the predecessor's state read; before `koto init
#      --supersede` runs; after it, with the successor's session directory
#      then removed (the crash after the fence, before the create); right
#      after it returns (the crash between the fence and the driver write);
#      after the first record/meta write; after the coordinator-row write;
#      after the takeover entry; after the last record/meta write
#      (takeover_done). Each re-run prints outcome=continued (outcome=resumed
#      for the last), opens exactly one successor, whose record/meta names the
#      caller as driver with takeover_done true and which holds exactly one
#      takeover entry naming it and every key the run carried, and `koto next`
#      on the predecessor is refused naming that successor.
# Every refusal also leaves the scope's session list, every session's
# record/, legs/, taken_legs and leg_children keys (each with its value's
# digest), every session's log (byte for byte; on a koto without the fence,
# every line but koto's own context_read events, which that koto writes to the
# log on each read) and its cancellations as they were, and a non-read write
# to the log is shown to fail that check. The interrupted takeovers are
# chained: each case's successor is the predecessor of the next, taken over by
# the other synthetic session.
#
# The koto calls a case interrupts or holds are named by what a takeover
# makes them as (logged once): the predecessor's second `status` (the
# candidate's live-session read is the first), the one `init ... --supersede`,
# the successor's record/meta writes (the driver, the write core's pending
# mark and its last write for the coordinator row, then takeover_done) and
# its record/entries/ writes (the coordinator row's own entry, then the
# takeover entry).
#
# Every koto call runs under koto-test-guard.sh: a scratch HOME, every
# KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME unset, and the store
# asserted under the scratch directory. The Claude job directory is a fixture
# (DC_CLAUDE_HOME). Needs koto, jq, git and perl (or flock); SKIPs (exit 0)
# without one, which run-tests.sh --engine turns into a failure. On a koto
# without --supersede (the floor koto CI's entry-floor job installs) it opens
# A and runs only case 5's koto-too-old refusal, against that koto.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/testdata/coordinate-engine-lib.sh"
# On a koto without the fence (the floor's), only the koto-too-old case can
# run, against that koto itself; run-tests.sh --engine fails a suite that
# SKIPs, so the floor job runs that one case rather than skipping the suite.
. "$HERE/testdata/takeover-flags.sh"
command -v flock >/dev/null 2>&1 || command -v perl >/dev/null 2>&1 \
    || { echo "SKIP: neither flock nor perl is on PATH -- the lock case can't hold koto's append lock; no case ran"; exit 0; }
case "$(koto session dir probe)" in "$T"/*|"$KOTO_TEST_GUARD_DIR"/*) ;; *) echo "FAIL: the koto store is outside the scratch directory"; exit 1 ;; esac
REAL_KOTO=$(command -v koto)
mkdir -p "$T/tmp"
# A background helper (the lock holder, the racing openers) is stopped on
# exit, and the scratch tree removed as test-lib.sh's own trap does, with the
# guard's directory, whose trap this one replaces.
BG=
trap 'for p in $BG; do kill "$p" 2>/dev/null; done; case "$T" in */coordinate-test.*) rm -rf "$T" ;; esac
    case "${KOTO_TEST_GUARD_DIR:-}" in */suite-scratch.*) rm -rf "$KOTO_TEST_GUARD_DIR" ;; esac' EXIT

# Synthetic Claude session ids, built here so no id-shaped literal ships, and
# each one's Claude job (its name is its messaging address) and directory.
A_ID=$(printf '%s-0000-4000-8000-%012d' aaaaaaaa 1)
B_ID=$(printf '%s-0000-4000-8000-%012d' bbbbbbbb 2)
C_ID=$(printf '%s-0000-4000-8000-%012d' cccccccc 3)
D_ID=$(printf '%s-0000-4000-8000-%012d' dddddddd 4)
export DC_CLAUDE_HOME="$T/claude"
for x in "a:$A_ID" "b:$B_ID" "c:$C_ID" "d:$D_ID"; do
    mkdir -p "$DC_CLAUDE_HOME/jobs/job-${x%%:*}"
    jq -n --arg s "${x#*:}" --arg n "coord-${x%%:*}" '{sessionId: $s, name: $n, state: "working"}' > "$DC_CLAUDE_HOME/jobs/job-${x%%:*}/state.json"
done
for d in work2 work3 work4; do
    mkdir -p "$T/$d/.niwa" "$T/$d/.claude"
    (cd "$T/$d" && git init -q && git remote add origin https://github.com/acme/widgets.git)
    cp "$T/work/.niwa/instance.json" "$T/$d/.niwa/"; cp "$T/work/.claude/settings.json" "$T/$d/.claude/"
done
wd_for() { # wd_for <claude-id>: the directory that session runs in; A's for none
    case "$1" in "$B_ID") echo "$T/work2" ;; "$C_ID") echo "$T/work3" ;; "$D_ID") echo "$T/work4" ;; *) echo "$T/work" ;; esac
}

opener() { # opener <name> <workdir> [token...]: coordinate-open.sh as the agent runs it; OUT its stdout, ORC its exit. NOID=1 unsets CLAUDE_CODE_SESSION_ID
    local n=$1 w=$2 a
    shift 2
    # One token a line, read raw: jq would take a token like --continues for
    # its own option.
    for a in "docs/roadmaps/ROADMAP-$n.md" "$@"; do printf '%s\n' "$a"; done | jq -Rsc 'split("\n")[:-1]' > "$T/args.json"
    if [ "${NOID-}" = 1 ]; then
        OUT=$(cd "$w" && env -u CLAUDE_CODE_SESSION_ID bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); ORC=$?
    else
        OUT=$(cd "$w" && bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args.json" 2>"$T/open.err"); ORC=$?
    fi
}
line() { sed -n "s/^$1=//p" <<< "$OUT"; }
put() { printf '%s' "$3" > "$T/v.json"; (cd "$T/work" && koto context add "$1" "$2" --from-file "$T/v.json" >/dev/null); }
kget() { (cd "$T/work" && koto context get "$1" "$2" 2>/dev/null); }
scope_sessions() { # scope_sessions <name>: the scope's sessions, oldest stamp first
    koto session list | jq -r --arg p "coordinate-roadmap-$1-" '.[] | .id | select(startswith($p))' | LC_ALL=C sort
}
newest() { scope_sessions outcome | tail -n 1; }
logf_of() { printf '%s/koto-%s.state.jsonl' "$(koto session dir "$1")" "$1"; }
driver_of() { kget "$1" record/meta | jq -r '.driver // ""'; }
# other_than <driver>: the synthetic session that takes a run over from it; A's
# run has no driver and is A_ID's.
other_than() { if [ "$1" = "$B_ID" ]; then echo "$A_ID"; else echo "$B_ID"; fi; }
keyset() { # keyset <session>: every carried key but record/meta and record/run, and its value's digest
    local p k
    for p in record/ legs/ taken_legs leg_children; do
        (cd "$T/work" && koto context list "$1" --prefix "$p") | jq -r '.[]'
    done | grep -v '^record/meta$' | grep -v '^record/run$' | grep -v '^koto/' | sort -u | while read -r k; do
        printf '%s %s\n' "$k" "$(kget "$1" "$k" | $SHA256 | cut -d' ' -f1)"
    done
}
# log_kept <log>: the log's lines a refusal must leave as they were, raw and in
# order. On a koto with the fence that is every byte of the log: reads never
# reach it there (koto writes its read trail, the context_read events, to a
# file of their own). A koto without the fence (the floor's) appends a
# context_read event to the log itself for every `context get` and `context
# exists`, so any read of the run, this suite's own key reads included, grows
# it; there only the lines whose type is exactly context_read are left out,
# and every other line is still compared verbatim.
log_kept() {
    if [ "$TAKEOVER_FLAGS" = 1 ]; then cat "$1"
    else jq -R -r 'select((try (fromjson | .type) catch null) != "context_read")' "$1"
    fi
}
# snapshot <name>: what a refusal must leave as it found it: each of the
# scope's sessions with its log's kept lines (log_kept: their count and
# digest) and cancellations, and every record/, legs/, taken_legs and
# leg_children key it holds with its value's digest.
snapshot() {
    local s p k log
    for s in $(scope_sessions "$1"); do
        log=$(logf_of "$s")
        printf '%s lines=%s log=%s cancelled=%s\n' "$s" "$(log_kept "$log" | wc -l | tr -d ' ')" \
            "$(log_kept "$log" | $SHA256 | cut -d' ' -f1)" \
            "$(jq -s '[.[] | select(.type == "workflow_cancelled")] | length' "$log")"
        for p in record/ legs/ taken_legs leg_children; do
            (cd "$T/work" && koto context list "$s" --prefix "$p") | jq -r '.[]'
        done | sort -u | while read -r k; do
            printf '  %s %s\n' "$k" "$(kget "$s" "$k" | $SHA256 | cut -d' ' -f1)"
        done
    done
}
# refused <label> <reason> <name> <snapshot before>: the opener refused for
# <reason> with exit 2, opened no session, and the scope is as it was.
refused() {
    local now d
    eq "$1: outcome=refused, reason=$2" "2 refused $2" "$ORC $(line outcome) $(line reason)"
    eq "$1:   ... naming no session" "" "$(line session)"
    now=$(snapshot "$3")
    if [ -z "$4" ]; then bad "$1:   ... and writing nothing" "the snapshot before it is empty, so it can't tell"
    elif [ "$4" = "$now" ]; then ok "$1:   ... and writing nothing: the sessions, their keys, logs and cancellations are as they were"
    else
        d=$(diff <(printf '%s\n' "$4") <(printf '%s\n' "$now"))
        bad "$1:   ... and writing nothing: the sessions, their keys, logs and cancellations are as they were" "$(head -n 20 <<< "$d")"
    fi
}
# append_caught <label> <name> <session>: the snapshot sees a write to the
# session's log that is not a read: a key outside the snapshot's prefixes is
# added and removed, so the log alone changes, and the snapshot must differ.
append_caught() {
    local before now
    before=$(snapshot "$2")
    printf '"probe"' > "$T/probe.json"
    (cd "$T/work" && koto context add "$3" probe/append --from-file "$T/probe.json" > /dev/null && koto context remove "$3" probe/append > /dev/null) \
        || { bad "$1:   ... a non-read write to the log is made" "koto context add or remove failed"; return; }
    now=$(snapshot "$2")
    [ -n "$before" ] && [ "$before" != "$now" ] \
        && ok "$1:   ... and the same check fails on a non-read write to the log" \
        || bad "$1:   ... and the same check fails on a non-read write to the log" "the snapshot didn't change: $now"
}

# ---- wrappers koto runs through (KOTO_BIN) -------------------------------------
mkdir -p "$T/kw" "$T/ko" "$T/kb" "$T/kbar"
# The interrupting koto: the real one, except that the KW_NTH-th call whose
# arguments match KW_PAT (a case pattern) kills the opener, before
# (KW_WHEN=before) or after (after) the real call runs. It walks up from its
# parent to the opener's own bash process (the topmost coordinate-open.sh, a
# command substitution's subshell shows the same arguments), kills every
# process on the way and that one with SIGKILL, the opener first, and exits
# 137. The name an `init` call opens is kept in kw.init. /proc gives a
# process's parent and arguments where it exists (run-tests.sh's PATH has no
# ps), ps otherwise.
cat > "$T/kw/koto" <<EOF
#!/usr/bin/env bash
REAL="$REAL_KOTO" DIR="$T"
EOF
cat >> "$T/kw/koto" <<'EOF'
case "${1-}:${2-}" in init:-*) ;; init:*) printf '%s\n' "$2" > "$DIR/kw.init" ;; esac
ps_bin=$(command -v ps 2>/dev/null) || ps_bin=/bin/ps
ppid_of() { if [ -r "/proc/$1/stat" ]; then sed 's/^.*) [A-Za-z] \([0-9]*\) .*/\1/' "/proc/$1/stat"; else "$ps_bin" -o ppid= -p "$1" | tr -d ' '; fi; }
args_of() { if [ -r "/proc/$1/cmdline" ]; then tr '\0' ' ' < "/proc/$1/cmdline"; else "$ps_bin" -ww -o args= -p "$1"; fi; }
kill_opener() {
    local p=$PPID pp chain= found=
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        chain="$p $chain"
        pp=$(ppid_of "$p")
        case "$(args_of "$p")" in
            *coordinate-open.sh*) case "$(args_of "$pp")" in *coordinate-open.sh*) ;; *) found=1; break ;; esac ;;
        esac
        p=$pp
    done
    printf '%s\n' "$*" > "$DIR/kw.hit"
    [ -n "$found" ] && kill -9 $chain
    exit 137
}
hit=0
if [ -n "${KW_PAT-}" ]; then
    case "$*" in
        $KW_PAT) n=$(( $(cat "$DIR/kw.count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$DIR/kw.count"
                 [ "$n" = "${KW_NTH:-1}" ] && hit=1 ;;
    esac
fi
[ "$hit" = 1 ] && [ "${KW_WHEN-}" = before ] && kill_opener "$@"
"$REAL" "$@"
rc=$?
[ "$hit" = 1 ] && kill_opener "$@"
exit $rc
EOF
# The old koto: the real one, but its `init --help` has no --supersede.
cat > "$T/ko/koto" <<EOF
#!/usr/bin/env bash
if [ "\${1-}" = init ] && [ "\${2-}" = --help ]; then "$REAL_KOTO" init --help | sed 's/--supersede//g'; exit 0; fi
exec "$REAL_KOTO" "\$@"
EOF
# The barrier: an `init ... --supersede` waits, up to 60 seconds, until two
# have reached it, then both run; each leaves the name it opens in kbar/.
cat > "$T/kb/koto" <<EOF
#!/usr/bin/env bash
case " \$* " in
    *" --supersede "*)
        printf '%s\n' "\$2" > "$T/kbar/at.\$\$"
        n=0
        while [ "\$(set -- "$T"/kbar/at.*; [ -e "\$1" ] && echo \$# || echo 0)" -lt 2 ] && [ \$n -lt 1200 ]; do sleep 0.05; n=\$((n + 1)); done ;;
esac
exec "$REAL_KOTO" "\$@"
EOF
arrived() { set -- "$T"/kbar/at.*; if [ -e "$1" ]; then echo $#; else echo 0; fi; } # how many have reached the barrier
chmod +x "$T/kw/koto" "$T/ko/koto" "$T/kb/koto"

# ---- A: a run driven by one Claude session --------------------------------------
export CLAUDE_CODE_SESSION_ID=$A_ID
three_features outcome; seed_record outcome
if open_run outcome && [ "$(at)" = reconcile ]; then
    A=$S
    ok "A: the run opens and reaches reconcile"
    printf 'a first account line\n' > "$T/e1"; printf 'a second account line\n' > "$T/e2"
    write_as_agent state-entry.sh --text-file "$T/e1" && write_as_agent state-entry.sh --text-file "$T/e2"
    eq "A: two record entries are written" 0 $?
    put "$A" legs/req-a1/work-on '{"worker":"feat-1","request":"req-a1"}'
    put "$A" legs/req-a2/work-on '{"worker":"feat-2","request":"req-a2"}'
    put "$A" taken_legs '["req-a1:work-on"]'
    put "$A" leg_children '{"req-a1:work-on":"feat-1-session"}'
    BASE=$(keyset "$A")
    NB=$(grep -c . <<< "$BASE")
    [ "$NB" -ge 6 ] && ok "A: holds record, leg, taken_legs and leg_children keys ($NB)" || bad "A: holds record, leg, taken_legs and leg_children keys" "$BASE"
else
    bad "A: the run opens and reaches reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
    echo; echo "coordinate-outcome engine: $PASS passed, $FAIL failed (no run to take over)"; exit 1
fi

# ---- 5 on a koto without the fence: koto-too-old against that koto -------------------
if [ "$TAKEOVER_FLAGS" = 0 ]; then
    export CLAUDE_CODE_SESSION_ID=$B_ID
    SNAP=$(snapshot outcome)
    opener outcome "$T/work2"
    refused "5: this koto, whose init lacks --supersede" koto-too-old outcome "$SNAP"
    grep -q '0\.28\.0' "$T/open.err" && ok "5:   ... naming koto 0.28.0" || bad "5:   ... naming koto 0.28.0" "$(cat "$T/open.err")"
    append_caught 5 outcome "$A"
fi
needs_takeover "1-7: every case after the floor's koto-too-old refusal" || {
    echo; echo "coordinate-outcome engine: $PASS passed, $FAIL failed (this koto has no init --supersede: only the koto-too-old refusal ran)"
    [ "$FAIL" -eq 0 ]; exit
}

# ---- 3. with no Claude session id, the untouched run resumes ---------------------------
NOID=1 opener outcome "$T/work"
eq "3: with CLAUDE_CODE_SESSION_ID unset, a run no takeover has touched resumes" "0 resumed $A" "$ORC $(line outcome) $(line session)"

# ---- 1. a second live run of the scope: ambiguous-scope -----------------------------------
X=coordinate-roadmap-outcome-20200101T000000Z
(cd "$T/work" && bash "$PS/coord-log.sh" vars --session "$A") | jq -c 'to_entries | map([.key, (.value | tostring)])' > "$T/xvars.json"
if (cd "$T/work" && koto init "$X" --template "$TPL" --vars-file "$T/xvars.json" > "$T/x.out" 2>&1); then
    export CLAUDE_CODE_SESSION_ID=$B_ID
    SNAP=$(snapshot outcome)
    opener outcome "$T/work2"
    refused "1: a second live run of the scope beside A" ambiguous-scope outcome "$SNAP"
    grep -q "$X" "$T/open.err" && grep -q "$A" "$T/open.err" && ok "1:   ... naming both live runs" || bad "1:   ... naming both live runs" "$(cat "$T/open.err")"
    (cd "$T/work" && koto cancel "$X" > /dev/null 2>&1) || bad "1: the second run is cancelled once the case is done" "$X"
else
    bad "1: a second live run of the scope opens beside A" "$(cat "$T/x.out")"
fi

# ---- 5. koto-too-old ---------------------------------------------------------------------
export CLAUDE_CODE_SESSION_ID=$B_ID
SNAP=$(snapshot outcome)
KOTO_BIN=$T/ko/koto opener outcome "$T/work2"
refused "5: a koto whose init lacks --supersede" koto-too-old outcome "$SNAP"
grep -q '0\.28\.0' "$T/open.err" && ok "5:   ... naming koto 0.28.0" || bad "5:   ... naming koto 0.28.0" "$(cat "$T/open.err")"
append_caught 5 outcome "$A"

# ---- 4. A's append lock held past the fence's wait: predecessor-unstoppable -------------------
LOCK="$(koto session dir "$A")/append.lock"
rm -f "$T/locked"
if command -v flock >/dev/null 2>&1; then
    ( exec 9>>"$LOCK"; flock -x 9 && : > "$T/locked" && exec sleep 120 ) &
else
    perl -e 'use Fcntl qw(:flock); open(my $f, ">>", $ARGV[0]) or die; flock($f, LOCK_EX) or die; open(my $r, ">", $ARGV[1]) or die; close $r; sleep 120' "$LOCK" "$T/locked" &
fi
LP=$!; BG="$BG $LP"
n=0; while [ ! -f "$T/locked" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
if [ -f "$T/locked" ]; then
    SNAP=$(snapshot outcome)
    SECONDS=0
    opener outcome "$T/work2"
    WAITED=$SECONDS
    refused "4: A's append lock held past koto's 10-second fence wait" predecessor-unstoppable outcome "$SNAP"
    [ "$WAITED" -ge 10 ] && ok "4:   ... after koto waited for the lock (${WAITED}s)" || bad "4:   ... after koto waited for the lock" "${WAITED}s"
    kill "$LP" 2>/dev/null; wait "$LP" 2>/dev/null
    NA_OUT=$(cd "$T/work" && koto next "$A" --no-cleanup 2>&1); rc=$?
    if [ $rc -eq 0 ]; then ok "4: once the lock is released, koto next A is accepted"
    else bad "4: once the lock is released, koto next A is accepted" "rc=$rc $NA_OUT"; fi
else
    kill "$LP" 2>/dev/null
    bad "4: the test holds A's append lock" "$LOCK"
fi

# ---- 5. a template this plugin can't drive: template-incompatible ------------------------------
# The plugin copy's template gains a variable, so its structure (the compat
# fingerprint) differs, and its own compat table raises compat and lists the
# new structure there. The shipped table lists neither.
export CLAUDE_CODE_SESSION_ID=$A_ID
mkdir -p "$T/pcopy" && cp -R "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$T/pcopy/"
PT=$T/pcopy/skills/coordinate/koto-templates
awk '{ print } /^variables:$/ && !d { print "  COMPAT_PROBE:\n    description: A variable only this copy declares, so its structure differs.\n    default: \"\""; d = 1 }' \
    "$PT/coordinate.md" > "$T/pcopy.md" && mv "$T/pcopy.md" "$PT/coordinate.md"
PFP=$(bash "$T/pcopy/skills/coordinate/scripts/template-fingerprint.sh" "$(koto template compile "$PT/coordinate.md" 2>/dev/null)")
jq --arg f "$PFP" '.compat += 1 | .fingerprints[$f] = .compat' "$PT/coordinate.compat.json" > "$T/pcompat.json" && mv "$T/pcompat.json" "$PT/coordinate.compat.json"
SHIP_COMPAT=$(jq -r .compat "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json")
three_features compat; seed_record compat
if PR=$T/pcopy PS=$T/pcopy/skills/coordinate/scripts open_run compat && [ "$(at)" = reconcile ]; then
    A2=$S
    A2_HASH=$(bash "$PS/coord-log.sh" template-hash --session "$A2")
    SHIPPED=$(basename -- "$(koto template compile "$TPL" 2>/dev/null)" .json)
    export CLAUDE_CODE_SESSION_ID=$B_ID
    SNAP=$(snapshot compat)
    opener compat "$T/work2"
    refused "5: a run compiled from a template the shipped compat table doesn't list" template-incompatible compat "$SNAP"
    case "$(cat "$T/open.err")" in
        *"at compat - (template $A2_HASH)"*"at compat $SHIP_COMPAT (template $SHIPPED)"*)
            ok "5:   ... naming the run's compat number (unlisted) and hash and the shipped compat $SHIP_COMPAT and hash" ;;
        *) bad "5:   ... naming the run's compat number (unlisted) and hash and the shipped compat $SHIP_COMPAT and hash" "$(cat "$T/open.err")" ;;
    esac
    # The same run with its compat recorded, as the plugin copy's write core
    # records it (its own table's answer for the run; shirabe#1333): the
    # shipped table still doesn't list the run, and the refusal names the
    # run's real compat instead of `-`.
    read -r PCOMPAT _ PFP_RUN <<< "$(bash "$T/pcopy/skills/coordinate/scripts/coord-log.sh" compat --session "$A2" 2>/dev/null)"
    eq "5: the plugin copy's table lists the run at its raised compat" "$((SHIP_COMPAT + 1)) $PFP" "$PCOMPAT $PFP_RUN"
    kget "$A2" record/meta | jq -c --argjson c "$PCOMPAT" --arg f "$PFP_RUN" '. + {template_compat: $c, template_fingerprint: $f}' > "$T/a2-meta.json"
    (cd "$T/work" && koto context add "$A2" record/meta --from-file "$T/a2-meta.json" > /dev/null)
    COUT=$(bash "$REPO_ROOT/skills/coordinate/scripts/coord-log.sh" compat --session "$A2" 2>/dev/null); CRC=$?
    eq "5: coord-log.sh compat reports the recorded compat the shipped table doesn't list, still exit 1" "1 $PCOMPAT $SHIP_COMPAT $PFP" "$CRC $COUT"
    SNAP=$(snapshot compat)
    opener compat "$T/work2"
    refused "5: a run whose recorded compat the shipped table doesn't list" template-incompatible compat "$SNAP"
    case "$(cat "$T/open.err")" in
        *"at compat $PCOMPAT (template $A2_HASH)"*"at compat $SHIP_COMPAT (template $SHIPPED)"*)
            ok "5:   ... naming the run's recorded compat $PCOMPAT and hash and the shipped compat $SHIP_COMPAT and hash" ;;
        *) bad "5:   ... naming the run's recorded compat $PCOMPAT and hash and the shipped compat $SHIP_COMPAT and hash" "$(cat "$T/open.err")" ;;
    esac
else
    bad "5: the run from the plugin copy opens and reaches reconcile" "$(cat "$T/open.err" "$T/tick.err" 2>/dev/null)"
fi

# ---- 2. --continues naming a run of another scope ------------------------------------------
export CLAUDE_CODE_SESSION_ID=$B_ID
SNAP=$(snapshot outcome)
opener outcome "$T/work2" --continues "${A2:-coordinate-roadmap-compat-20200101T000000Z}"
refused "2: --continues naming a run of another scope" not-newest-member outcome "$SNAP"

# ---- 7. interrupted takeovers, each run again ---------------------------------------------------
# interrupted <label> <pattern> <n> <before|after> [hook]: the newest member
# taken over by the synthetic session that doesn't drive it, from its own
# directory, killed at the n-th koto call matching <pattern>; <hook> runs
# once the kill is seen (it may remove the successor, or run refusals
# against the cut takeover); then the plain opener again from the same
# session, and its result checked. Sets PRED and SUCC.
interrupted() {
    local l=$1 pat=$2 nth=$3 when=$4 hook=${5-} id wd pwd before want=continued new nx rc missing
    PRED=$(newest); pwd=$(wd_for "$(driver_of "$PRED")")
    id=$(other_than "$(driver_of "$PRED")"); wd=$(wd_for "$id")
    before=$(scope_sessions outcome)
    rm -f "$T/kw.count" "$T/kw.hit" "$T/kw.init"
    export CLAUDE_CODE_SESSION_ID=$id
    KOTO_BIN=$T/kw/koto KW_PAT=$pat KW_NTH=$nth KW_WHEN=$when TMPDIR=$T/tmp opener outcome "$wd"
    if [ -f "$T/kw.hit" ] && [ "$ORC" = 137 ]; then ok "$l: the opener is killed at \`$(cut -c1-60 "$T/kw.hit")\`"
    else bad "$l: the opener is killed at the call" "exit $ORC; out: $OUT; $(cat "$T/open.err")"; return 1; fi
    [ -z "$hook" ] || "$hook" "$l" "$PRED" "$id"
    export CLAUDE_CODE_SESSION_ID=$id
    opener outcome "$wd"
    [ "$l" = "7 takeover_done" ] && want=resumed
    SUCC=$(line session)
    eq "$l: the re-run prints outcome=$want" "0 $want" "$ORC $(line outcome)"
    [ "$want" = resumed ] || eq "$l:   ... predecessor= naming the run it continues" "$PRED" "$(line predecessor)"
    new=$(scope_sessions outcome | grep -vxF -f <(printf '%s\n' "$before"))
    eq "$l: exactly one successor beyond the predecessor, the one it names" "$SUCC" "$new"
    eq "$l:   ... continuing the predecessor" "continues: $PRED" "$( (cd "$wd" && koto session hierarchy "$SUCC") | grep '^continues: ')"
    eq "$l: its record/meta names the caller as driver, takeover_done true" "$id true" "$(kget "$SUCC" record/meta | jq -r '"\(.driver) \(.takeover_done)"')"
    eq "$l: exactly one takeover entry for it" 1 \
        "$( (cd "$wd" && bash "$PS/state-entry.sh" --session "$SUCC" --list 2>/dev/null) | jq --arg p "takeover $SUCC:" '[.[] | select(.kind == "takeover" and (.text | startswith($p)))] | length')"
    missing=$(grep -vxF -f <(keyset "$SUCC") <<< "$BASE")
    eq "$l: every key A's run carried is in it with the same value" "" "$missing"
    nx=$(cd "$pwd" && koto next "$PRED" --no-cleanup 2>&1); rc=$?
    if [ $rc -ne 0 ] && grep -q session_superseded <<< "$nx" && grep -q "$SUCC" <<< "$nx"; then ok "$l: koto next on the predecessor is refused, naming the successor"
    else bad "$l: koto next on the predecessor is refused, naming the successor" "rc=$rc $nx"; fi
}

# The kill after init, the successor's session directory then removed: the
# crash after the fence, before koto created the successor.
remove_succ() {
    local s
    s=$(cat "$T/kw.init" 2>/dev/null)
    case "$s" in coordinate-roadmap-outcome-[0-9]*Z) ;; *) bad "$1: the successor's name is known" "$s"; return ;; esac
    case "$(koto session dir "$s")" in
        "$T"/*/"$s") rm -rf "$(koto session dir "$s")"; ok "$1: the successor's session directory is removed" ;;
        *) bad "$1: the successor's session directory is under the scratch store" "$(koto session dir "$s")" ;;
    esac
    case " $(scope_sessions outcome | tr '\n' ' ') " in *" $s "*) bad "$1:   ... and koto no longer lists it" ;; *) ok "$1:   ... and koto no longer lists it" ;; esac
}
# The crash between the fence and the driver write: no Claude session id, and
# the rival session, are both refused taken-over, writing nothing.
cut_refusals() {
    local snap
    snap=$(snapshot outcome)
    NOID=1 opener outcome "$T/work"
    refused "3: with CLAUDE_CODE_SESSION_ID unset, against a successor cut after the fence" taken-over outcome "$snap"
    CLAUDE_CODE_SESSION_ID=$(other_than "$3"); export CLAUDE_CODE_SESSION_ID
    opener outcome "$(wd_for "$CLAUDE_CODE_SESSION_ID")"
    refused "3: from the rival session while that takeover is cut" taken-over outcome "$snap"
}

# What A holds as the first takeover reaches it (case 4 ticked it since).
BASE=$(keyset "$A")
interrupted "7 (a) after the state read" "status $A" 2 after
# A completed takeover touched the run: with no id it is refused.
SNAP=$(snapshot outcome)
NOID=1 opener outcome "$T/work"
refused "3: with CLAUDE_CODE_SESSION_ID unset, against a completed successor" taken-over outcome "$SNAP"
# A is no longer the newest member of its run.
export CLAUDE_CODE_SESSION_ID=$A_ID
SNAP=$(snapshot outcome)
opener outcome "$T/work" --continues "$A"
refused "2: --continues naming A, superseded" not-newest-member outcome "$SNAP"
grep -q "$(newest)" "$T/open.err" && ok "2:   ... naming the newest member" || bad "2:   ... naming the newest member" "$(cat "$T/open.err")"

interrupted "7 (b) before koto init --supersede" "init * --supersede *" 1 before
interrupted "7 (b) after the fence, before the create" "init * --supersede *" 1 after remove_succ
interrupted "7 (b) after koto init --supersede" "init * --supersede *" 1 after cut_refusals
interrupted "7 (c) after the first record/meta write" "context add * record/meta *" 1 after
interrupted "7 (c) after the coordinator row" "context add * record/meta *" 3 after
interrupted "7 (c) after the takeover entry" "context add * record/entries/*" 2 after
interrupted "7 takeover_done" "context add * record/meta *" 4 after

# ---- 6. two successors at once ------------------------------------------------------------------
PRED=$(newest)
BEFORE_S=$(scope_sessions outcome)
PLOG=$(logf_of "$PRED")
PLINES=$(wc -l < "$PLOG" | tr -d ' ')
race() { # race <id> <workdir> <tag>: the opener through the barrier, its output in race-<tag>.*
    printf '["docs/roadmaps/ROADMAP-outcome.md"]' > "$T/args-$3.json"
    (cd "$2" && CLAUDE_CODE_SESSION_ID=$1 KOTO_BIN=$T/kb/koto bash "$PS/coordinate-open.sh" --plugin-root "$PR" "$T/args-$3.json" \
        > "$T/race-$3.out" 2> "$T/race-$3.err"; echo $? > "$T/race-$3.rc")
}
rm -f "$T"/kbar/* "$T"/race-*
race "$C_ID" "$T/work3" c &
RC1=$!; BG="$BG $RC1"
# The second starts once the first is at the fence, and a second later, so
# the two successors' names (stamped to the second) differ.
n=0; while [ "$(arrived)" -lt 1 ] && [ $n -lt 1200 ]; do sleep 0.05; n=$((n + 1)); done
sleep 1.1
race "$D_ID" "$T/work4" d &
RC2=$!; BG="$BG $RC2"
wait "$RC1"; wait "$RC2"
RES="$(sed -n 's/^outcome=//p' "$T/race-c.out" 2>/dev/null) $(sed -n 's/^outcome=//p' "$T/race-d.out" 2>/dev/null)"
case "$RES" in
    "continued refused") WIN=c LOSE=d ;;
    "refused continued") WIN=d LOSE=c ;;
    *) WIN='' LOSE='' ;;
esac
if [ -n "$WIN" ]; then ok "6: of two successors at once, exactly one continues ($RES)"
else bad "6: of two successors at once, exactly one continues" "$RES; $(cat "$T"/race-*.err 2>/dev/null)"; fi
if [ -n "$LOSE" ]; then
    eq "6:   ... and the other is refused taken-over, exit 2" "2 taken-over" "$(cat "$T/race-$LOSE.rc") $(sed -n 's/^reason=//p' "$T/race-$LOSE.out")"
    WS=$(sed -n 's/^session=//p' "$T/race-$WIN.out")
    LS=$(cat "$T"/kbar/at.* | grep -vxF "$WS")
    eq "6: the two named different successors" 1 "$(grep -c . <<< "$LS")"
    eq "6: exactly one successor session exists, the winner's" "$WS" "$(scope_sessions outcome | grep -vxF -f <(printf '%s\n' "$BEFORE_S"))"
    (cd "$T/work" && koto status "$LS" > /dev/null 2>&1) && bad "6: the loser opened no session" "$LS" || ok "6: the loser opened no session"
    eq "6: the predecessor holds exactly one fence" 1 "$(jq -s '[.[] | select(.type == "session_superseded")] | length' "$PLOG")"
    eq "6:   ... the winner's" "$WS" "$(jq -rs '[.[] | select(.type == "session_superseded")][0].payload.by' "$PLOG")"
    eq "6:   ... and its log gained only that line" "$((PLINES + 1))" "$(wc -l < "$PLOG" | tr -d ' ')"
    if [ "$WIN" = c ]; then WID=$C_ID; else WID=$D_ID; fi
    eq "6: the winner's record/meta names its own session as driver" "$WID true" \
        "$(kget "$WS" record/meta | jq -r '"\(.driver) \(.takeover_done)"')"
fi

echo; echo "coordinate-outcome engine: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]

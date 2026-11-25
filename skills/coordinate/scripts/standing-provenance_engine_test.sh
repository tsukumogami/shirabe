#!/usr/bin/env bash
# standing-provenance_engine_test.sh -- standing-provenance.sh, the read of
# one cited koto decision's facts, on real koto sessions in a scratch store
# and against fake kotos (KOTO_BIN)
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md).
#
# The sessions are made here on a one-state template: p1 holds a person
# judgment and a session judgment; pred is superseded by succ, which reverses
# pred's session decision through the fence; w1, dispatched by dir1, has its
# decision reversed from dir1 with no supersede hop; w2 is dispatched by boss,
# which holds a coordinator record; r1's Run section holds a reports-to row;
# new continues mid, which continues old, the one coordinator record on new's
# chain; cc holds text with control characters. Prints one line per
# criterion:
#   1. a person judgment and a session judgment read as the objects held
#      below, koto's time in each (jq -S);
#   2. pred's session decision, reversed by succ through the fence, reads
#      reversed with hop true and one fence step equal to koto's marker;
#   3. w1's decision, reversed from dir1 by its dispatched-by link, reads hop
#      false and fence [];
#   4. bound is true on w2 (boss) and r1 (reports-to), false on a session
#      with neither and on new, whose only chain record is an earlier member
#      of its run; bound_by names what made it true;
#   5. a reason, subject field, link and handle with control characters and
#      over 200 characters come out under quoted with neither;
#   6. a missing decision, a missing session, five fake kotos (a non-zero
#      exit, text, JSON with no status, status unreadable, a sleep past the
#      deadline, back within 7 s), a bad id and a session name starting
#      with `-` (no koto call) read unreadable with a why and exit 0, none
#      of them changing the store's files, and no read in this suite
#      changing any but koto's own journal of context reads;
#   7. a logging koto shows `decisions show <session> <id>` as separate
#      arguments and no `koto decisions` command but show and chain;
#   8. scripts/check-template-compat.sh passes against the base branch's
#      coordinate.compat.json, compat unchanged: no gate runs the helper.
#
# Every koto call runs on a store under this suite's scratch directory: the
# guard (scripts/lib/koto-test-guard.sh) unsets every KOTO_SESSION_* variable
# and KOTO_SESSIONS_BASE, HOME and KOTO_HOME are set under the scratch
# directory, and `koto session dir` must name a directory there before the
# first koto command, or the suite stops.
#
# A koto without `decisions show`, `decisions chain` and `decisions reverse`,
# or without `init --supersede` (the entry floor among them), runs criteria 6
# and 8 alone and names the others it left out.
#
# Needs koto, jq and git; SKIPs (exit 0) without koto, which
# run-tests.sh --engine turns into a failure.
# Usage: bash skills/coordinate/scripts/standing-provenance_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../../.." && pwd -P)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
REAL_KOTO=$(command -v koto)
ORIG_PATH=$PATH
# test-lib.sh makes the scratch directory T and the ok/bad counters. It puts
# testdata/ (the koto stand-in) first on PATH; this suite needs the real
# koto, so PATH is put back.
. "$HERE/testdata/test-lib.sh"
T=$(cd -P "$T" && pwd -P) || exit 1
unset KOTO_STORE KOTO_COMPILED_HASH KOTO_BIN
export HOME="$T/home" KOTO_HOME="$T/home/.koto" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME" "$T/bin" "$T/out"
PATH=$ORIG_PATH
export PATH
SP="$HERE/standing-provenance.sh"

d=$(koto session dir probe 2>&1) || { echo "FAIL: koto session dir failed: [$d]; no case ran"; exit 1; }
case "$d" in
    "$T"/*) ;;
    *) echo "FAIL: koto's session directory is not under $T: [$d]; no case ran"; exit 1 ;;
esac

# Whether this koto records, shows, chains and reverses decisions and fences
# a predecessor; without them criteria 1-5 and 7 are left out.
DEC=1
case "$(koto decisions --help 2>&1)" in *show*) ;; *) DEC=0 ;; esac
case "$(koto decisions --help 2>&1)" in *chain*) ;; *) DEC=0 ;; esac
case "$(koto decisions --help 2>&1)" in *reverse*) ;; *) DEC=0 ;; esac
case "$(koto init --help 2>&1)" in *--supersede*) ;; *) DEC=0 ;; esac

# One line per criterion: need records what failed, crit keeps the line under
# its number and report prints them, 1 to 8.
WHY=
need() { [ "$2" = "$3" ] || WHY="$WHY; $1: want [$2], got [$3]"; }
needf() { WHY="$WHY; $1"; }
crit() { local n=${1%%.*}; printf -v "CM_$n" '%s' "$1"; printf -v "CW_$n" '%s' "$WHY"; WHY=; }
LEFT=" "
report() {
    local n m w
    for n in 1 2 3 4 5 6 7 8; do
        case "$LEFT" in *" $n "*) echo "left out $n: this koto has no decisions show, chain or reverse, or no init --supersede"; continue ;; esac
        m="CM_$n" w="CW_$n"
        [ -n "${!m-}" ] || { bad "criterion $n" "no case reached it"; continue; }
        if [ -z "${!w}" ]; then ok "${!m}"; else bad "${!m}" "${!w#; }"; fi
    done
}

# ---- helpers ---------------------------------------------------------------
cat > "$T/t.md" <<'EOF'
---
name: provenance-probe
version: "1.0"
initial_state: open
states:
  open:
    transitions:
      - target: done
  done:
    terminal: true
---
## open
Open.
## done
Done.
EOF
new_session() { koto init "$1" --template "$T/t.md" "${@:2}" > /dev/null 2> "$T/init.err" || needf "koto init $1 failed: $(cat "$T/init.err")"; }
# record <session> <args>...: koto decisions record; its output in $T/rec.
record() { local s=$1; shift; koto decisions record "$s" --kind judgment --outcome settled "$@" > "$T/rec" 2> "$T/rec.err" || needf "koto decisions record $s failed: $(cat "$T/rec" "$T/rec.err")"; }
# The store's files; a read that writes shows here or in what's newer than
# the stamp.
snap() { find "$KOTO_HOME" | LC_ALL=C sort; }
# koto keeps its own journal of context reads (context-reads.jsonl) in the
# session it reads, so a read that asks `context exists` adds to that one
# file. Criterion 6's reads hold no file at all still; every other read may
# touch nothing but that journal.
WROTE=
WROTE_ELSE=
# sp <name> <args>...: the helper, its stdout in $T/out/<name>, its exit in
# SPRC; any change it made to the store goes in WROTE, and one to anything
# but koto's read journal in WROTE_ELSE too.
sp() {
    local n=$1 newer
    shift
    snap > "$T/snap.before"
    : > "$T/stamp"
    bash "$SP" "$@" > "$T/out/$n" 2> "$T/out/$n.err"
    SPRC=$?
    snap > "$T/snap.after"
    newer=$(find "$KOTO_HOME" -newer "$T/stamp" -type f)
    cmp -s "$T/snap.before" "$T/snap.after" || WROTE="$WROTE; $n: the store's listing changed"
    [ -z "$newer" ] || WROTE="$WROTE; $n: a file in the store changed"
    diff "$T/snap.before" "$T/snap.after" | grep '^[<>]' | grep -v '/context-reads\.jsonl$' > "$T/snap.diff"
    [ -s "$T/snap.diff" ] && WROTE_ELSE="$WROTE_ELSE; $n: the store's listing changed: $(tr '\n' ' ' < "$T/snap.diff")"
    newer=$(printf '%s\n' "$newer" | grep -v '/context-reads\.jsonl$' | grep .)
    [ -z "$newer" ] || WROTE_ELSE="$WROTE_ELSE; $n: changed $newer"
}
# expect <label> <name> <want-json>: the helper's object is want, by jq -S.
expect() {
    need "$1" "$(printf '%s' "$3" | jq -cS . 2>&1)" "$(jq -cS . "$T/out/$2" 2>&1)"
    need "$1: exits 0, one line" "0 1" "$SPRC $(wc -l < "$T/out/$2" | tr -d ' ')"
}
# fake <name> <body>: a fake koto, logging each call's arguments (<a><b>...)
# one line per call to $FAKE_LOG, then running body.
# shellcheck disable=SC2016 # the body is the fake's own code, expanded when it runs
fake() {
    { printf '#!/usr/bin/env bash\n'
      printf 'printf "<%%s>" "$@" >> "${FAKE_LOG:?}"; echo >> "$FAKE_LOG"\n'
      printf '%s\n' "$2"; } > "$T/bin/$1"
    chmod +x "$T/bin/$1"
}
fake koto-logged "exec \"$REAL_KOTO\" \"\$@\""
URL='https://github.com/acme/widgets/issues/1#issuecomment-1'
NOBIND='"bound": false, "bound_by": {"sessions": [], "reports_to": null}'

if [ "$DEC" = 1 ]; then
# ---- 1 ----------------------------------------------------------------------
new_session p1
record p1 --by person:bob --surface relay --link "$URL" --reason "go ahead" --subject what=go
t1=$(jq -r '.decision.time' "$T/rec")
record p1 --by session --reason "hold the line" --subject what=hold
t2=$(jq -r '.decision.time' "$T/rec")
sp p1-person p1 000000000001
expect "the person judgment" p1-person '{"session": "p1", "id": "000000000001", "status": "in-effect",
    "decider": {"kind": "person", "entering": "p1", "surface": "relay"}, "time": "'"$t1"'", '"$NOBIND"',
    "reversal": null,
    "quoted": {"subject": {"what": "go"}, "reason": "go ahead", "link": "'"$URL"'", "handle": "bob", "reversal_reason": null}}'
sp p1-session p1 000000000002
expect "the session judgment" p1-session '{"session": "p1", "id": "000000000002", "status": "in-effect",
    "decider": {"kind": "session", "session": "p1"}, "time": "'"$t2"'", '"$NOBIND"',
    "reversal": null,
    "quoted": {"subject": {"what": "hold"}, "reason": "hold the line", "link": null, "handle": null, "reversal_reason": null}}'
crit "1. a person judgment reads in-effect, its handle, surface, link, entering session and koto's time; a session judgment reads its session"

# ---- 2 ----------------------------------------------------------------------
new_session pred
record pred --by session --reason "ship it" --subject what=ship
new_session succ --continues pred --supersede
koto decisions chain pred > "$T/marker" 2> "$T/marker.err" || needf "koto decisions chain pred failed: $(cat "$T/marker.err")"
koto decisions reverse pred 000000000001 --in succ --by session --reason "not yet" > "$T/rev" 2> "$T/rev.err" \
    || needf "the reversal through the fence failed: $(cat "$T/rev" "$T/rev.err")"
need "the marker's successor is succ's session id" "$(jq -r '.decision.session.id' "$T/rev")" "$(jq -r '.marker.successor.id' "$T/marker")"
sp pred pred 000000000001
need "pred's decision reads reversed, exit 0" "reversed 0" "$(jq -r .status "$T/out/pred") $SPRC"
need "the reversal" "$(jq -cS --slurpfile r "$T/rev" '.marker as $m | {session: "succ", id: $r[0].id, time: $r[0].decision.time,
        decider: {kind: "session", session: "succ"}, standing: "verified", hop: true,
        fence: [{session: "pred", to: "succ", successor_id: $m.successor.id, actor: $m.actor, time: $m.time}]}' "$T/marker")" \
    "$(jq -cS .reversal "$T/out/pred")"
need "the reversal's reason, quoted" "not yet" "$(jq -r .quoted.reversal_reason "$T/out/pred")"
crit "2. a decision reversed through a supersede fence reads reversed, standing verified, hop true, one fence step equal to koto's marker"

# ---- 3 ----------------------------------------------------------------------
new_session dir1
new_session w1
koto session link w1 --dispatched-by dir1 > /dev/null 2> "$T/link.err" || needf "koto session link w1 failed: $(cat "$T/link.err")"
record w1 --by session --reason "use the cache" --subject what=cache
koto decisions reverse w1 000000000001 --in dir1 --by session --reason "drop the cache" > "$T/rev" 2> "$T/rev.err" \
    || needf "the reversal from above failed: $(cat "$T/rev" "$T/rev.err")"
need "koto's path is the link, no supersede step" '[{"session":"w1","to":"dir1","via":"link"}]' "$(jq -cS .decision.path "$T/rev")"
sp w1 w1 000000000001
need "w1's decision reads reversed by dir1, hop false, fence []" "reversed|dir1|$(jq -r .id "$T/rev")|verified|false|[]" \
    "$(jq -r '"\(.status)|\(.reversal.session)|\(.reversal.id)|\(.reversal.standing)|\(.reversal.hop)|\(.reversal.fence | tojson)"' "$T/out/w1")"
crit "3. a reversal from a dispatching session, with no supersede hop, reads hop false and fence []"

# ---- 4 ----------------------------------------------------------------------
echo '{"scope": "roadmap"}' > "$T/meta.json"
jq -n '[{key: "reports-to", value: "the human", set_by: "the human", set: "2026-10-07T10:00Z"},
        {key: "cap", value: "2", set_by: "the human", set: "2026-10-07T10:00Z"}]' > "$T/run.json"
new_session boss
koto context add boss record/meta --from-file "$T/meta.json" 2> "$T/ctx.err" || needf "seeding boss failed: $(cat "$T/ctx.err")"
new_session w2
koto session link w2 --dispatched-by boss > /dev/null 2> "$T/link.err" || needf "koto session link w2 failed: $(cat "$T/link.err")"
record w2 --by session --reason "split the work" --subject what=split
sp w2 w2 000000000001
need "w2, dispatched by boss, holding record/meta: bound by boss" '{"bound":true,"bound_by":{"reports_to":null,"sessions":["boss"]}}' \
    "$(jq -cS '{bound, bound_by}' "$T/out/w2")"
new_session r1
koto context add r1 record/run --from-file "$T/run.json" 2> "$T/ctx.err" || needf "seeding r1 failed: $(cat "$T/ctx.err")"
record r1 --by person:bob --surface relay --link "$URL" --reason "merge it" --subject what=merge
sp r1 r1 000000000001
need "r1, its Run section holding a reports-to row: bound by it" '{"bound":true,"bound_by":{"reports_to":"the human","sessions":[]}}' \
    "$(jq -cS '{bound, bound_by}' "$T/out/r1")"
new_session alone
record alone --by session --reason "wait" --subject what=wait
sp alone alone 000000000001
need "a session with neither: not bound" '{"bound":false,"bound_by":{"reports_to":null,"sessions":[]}}' "$(jq -cS '{bound, bound_by}' "$T/out/alone")"
# old holds the run's record; mid and then new took it over, and new names
# old on its chain. old is an earlier member of new's run.
new_session old
koto context add old record/meta --from-file "$T/meta.json" 2> "$T/ctx.err" || needf "seeding old failed: $(cat "$T/ctx.err")"
new_session mid --continues old --supersede
new_session new --continues mid --supersede
koto session link new --dispatched-by old > /dev/null 2> "$T/link.err" || needf "koto session link new failed: $(cat "$T/link.err")"
record new --by session --reason "carry on" --subject what=carry
need "new's frozen chain names old" '[{"session":"old","via":"link"}]' "$(jq -c .decision.chain.links "$T/rec")"
sp new new 000000000001
need "new, whose only chain record is old, an earlier member of its run: not bound" '{"bound":false,"bound_by":{"reports_to":null,"sessions":[]}}' \
    "$(jq -cS '{bound, bound_by}' "$T/out/new")"
crit "4. bound is true through a chain session's record or a reports-to row, naming it, and false with neither or through an earlier member of the run"

# ---- 5 ----------------------------------------------------------------------
LONG=$(printf '%0300d' 0 | tr 0 x)
CTRL=$(printf 'a\001b\033[31mc\td\ne\177f\302\205g')
new_session cc
# koto refuses a control character in a handle or a link, so those two are
# long here and get theirs from the fake below.
record cc --by "person:bob${LONG:0:240}" --surface relay --link "$URL${LONG:0:150}" --reason "r${CTRL}$LONG" --subject "what=s${CTRL}$LONG"
sp cc cc 000000000001
koto decisions show cc 000000000001 > "$T/cc.body" 2> /dev/null
jq -c --arg c "$CTRL" --arg l "$LONG" '.decision.decider.handle.value = "bob\($c)\($l)" | .decision.decider.link = "https://x/\($c)\($l)"' \
    "$T/cc.body" > "$T/cc.fake"
fake koto-body "case \"\$1 \$2\" in \"decisions show\") cat \"$T/cc.fake\" ;; \"context list\") echo '[]' ;; *) exit 1 ;; esac"
FAKE_LOG="$T/body.log" KOTO_BIN="$T/bin/koto-body" sp cc-fake cc 000000000001
# clean_ok <name>: every quoted string has no control character and at most
# 200 characters, and the four fields are there.
clean_ok() {
    need "$1: in-effect, exit 0" "in-effect 0" "$(jq -r .status "$T/out/$1") $SPRC"
    need "$1: no quoted string holds a control character or runs past 200" "" \
        "$(jq -r '[.quoted | .. | strings | select(length > 200 or (explode | any(. < 32 or (. >= 127 and . <= 159))))] | .[]' "$T/out/$1")"
    need "$1: reason, subject, link and handle are quoted, cut to 200" "200 200 200 200" \
        "$(jq -r '[.quoted.reason, .quoted.subject.what, .quoted.link, .quoted.handle] | map(length) | join(" ")' "$T/out/$1")"
}
clean_ok cc
need "cc: the reason keeps its text" "rab[31mcdefgxxx" "$(jq -r '.quoted.reason[0:15]' "$T/out/cc")"
clean_ok cc-fake
need "cc-fake: the handle and link keep their text" "bobab[31mcdefgx|https://x/ab[31mcdefgx" \
    "$(jq -r '"\(.quoted.handle[0:15])|\(.quoted.link[0:22])"' "$T/out/cc-fake")"
crit "5. a reason, subject field, link and handle holding control characters and over 200 characters come out under quoted with none and at most 200"
else
    LEFT=" 1 2 3 4 5 7 "
    new_session p1
fi

# ---- 6 ----------------------------------------------------------------------
# unread_ok <name> <session> <id>: unreadable, a why, exit 0, the four keys.
unread_ok() {
    need "$1: unreadable with a why, exit 0" "unreadable true 0" \
        "$(jq -r '"\(.status) \(.why | type == "string" and length > 0)"' "$T/out/$1" 2>&1) $SPRC"
    need "$1: the four keys, its session and id" "$(jq -cn --arg s "$2" --arg i "$3" '{session: $s, id: $i, status: "unreadable"}')" \
        "$(jq -c '{session, id, status}' "$T/out/$1" 2>&1)"
    need "$1: one line and nothing else" "1 id,session,status,why" "$(wc -l < "$T/out/$1" | tr -d ' ') $(jq -r 'keys | join(",")' "$T/out/$1" 2>&1)"
}
WROTE=
sp no-decision p1 000000000099
unread_ok no-decision p1 000000000099
sp no-session ghost 000000000001
unread_ok no-session ghost 000000000001
fake koto-exit 'exit 3'
fake koto-text 'echo "this is not json"'
# shellcheck disable=SC2016
fake koto-nostatus 'printf "%s\n" "{\"v\":1,\"session\":\"$3\",\"id\":\"$4\",\"decision\":{}}"'
# shellcheck disable=SC2016
fake koto-unreadable 'printf "%s\n" "{\"v\":1,\"session\":\"$3\",\"id\":\"$4\",\"status\":\"unreadable\"}"'
fake koto-sleep 'sleep 30'
for f in exit text nostatus unreadable; do
    FAKE_LOG="$T/$f.log" KOTO_BIN="$T/bin/koto-$f" sp "fake-$f" p1 000000000001
    unread_ok "fake-$f" p1 000000000001
    need "fake-$f: koto was asked" "<decisions><show><p1><000000000001>" "$(head -1 "$T/$f.log" 2>&1)"
done
start=$(date +%s)
FAKE_LOG="$T/sleep.log" KOTO_BIN="$T/bin/koto-sleep" sp fake-sleep p1 000000000001
took=$(($(date +%s) - start))
unread_ok fake-sleep p1 000000000001
[ "$took" -le 7 ] || needf "the sleeping koto took the read ${took}s, past 7"
need "fake-sleep: the why names the deadline" "true" "$(jq -r '.why | test("within")' "$T/out/fake-sleep")"
for c in "bad-id p1 12345" "bad-id-letters p1 00000000000a" "bad-session -p1 000000000001"; do
    # shellcheck disable=SC2086 # split on purpose: the case's words
    set -- $c
    : > "$T/none.log"
    FAKE_LOG="$T/none.log" KOTO_BIN="$T/bin/koto-logged" sp "$1" "$2" "$3"
    unread_ok "$1" "$2" "$3"
    need "$1: no koto call" "" "$(cat "$T/none.log")"
done
need "none of these reads changed the store" "" "${WROTE#; }"
need "no read in this suite changed anything in the store but koto's read journal" "" "${WROTE_ELSE#; }"
crit "6. a missing decision or session, a failing, wordy, statusless, unreadable or sleeping koto, a bad id and a '-' session read unreadable with a why, exit 0, nothing written"

# ---- 7 ----------------------------------------------------------------------
if [ "$DEC" = 1 ]; then
    : > "$T/calls.log"
    for c in "new 000000000001" "r1 000000000001" "pred 000000000001" "w2 000000000001"; do
        # shellcheck disable=SC2086 # split on purpose: the case's words
        set -- $c
        FAKE_LOG="$T/calls.log" KOTO_BIN="$T/bin/koto-logged" sp "logged-$1" "$1" "$2"
        need "logged-$1: the logged read matches the plain one" "$(jq -cS . "$T/out/$1")" "$(jq -cS . "$T/out/logged-$1")"
    done
    grep -qx '<decisions><show><new><000000000001>' "$T/calls.log" || needf "no call reads decisions show new 000000000001 as four arguments: $(head -3 "$T/calls.log")"
    grep -q '^<decisions><chain><' "$T/calls.log" || needf "the earlier-member walk made no decisions chain call"
    grep -q '^<context><get><r1><record/run>$' "$T/calls.log" || needf "no context get of r1's Run section"
    need "no koto decisions command but show and chain" "" "$(grep '^<decisions>' "$T/calls.log" | grep -vE '^<decisions><(show|chain)>')"
    need "no koto command but decisions show/chain and context exists/list/get" "" \
        "$(grep -vE '^<(decisions><(show|chain)|context><(exists|list|get))>' "$T/calls.log")"
    crit "7. the call log shows decisions show <session> <id> as separate arguments and no decisions command but show and chain"
fi

# ---- 8 ----------------------------------------------------------------------
# The base branch's table, origin/main's (or main's). A checkout holding
# neither (a shallow clone) still checks that the table records this
# template's structure and gate scripts digest, and says it had no base.
BASE=$(git -C "$REPO_ROOT" rev-parse --verify -q origin/main 2>/dev/null) || BASE=$(git -C "$REPO_ROOT" rev-parse --verify -q main 2>/dev/null) || BASE=
CARGS=(--template skills/coordinate/koto-templates/coordinate.md)
if [ -n "$BASE" ]; then
    git -C "$REPO_ROOT" show "$BASE:skills/coordinate/koto-templates/coordinate.compat.json" > "$T/base.compat.json" 2> "$T/base.err" \
        || needf "the base's coordinate.compat.json can't be read: $(cat "$T/base.err")"
    CARGS+=(--base-table "$T/base.compat.json")
    # compat stays the base's only while the template keeps the structure the
    # base lists at its compat; a structure the base doesn't list there is a
    # change's own raise, and check-template-compat.sh decides whether it holds.
    FP=$(cd "$REPO_ROOT" && bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md --print 2>/dev/null | jq -r '.fingerprint // empty')
    [ -n "$FP" ] || needf "check-template-compat.sh printed no fingerprint"
    if jq -e --arg f "$FP" '.fingerprints[$f] == .compat' "$T/base.compat.json" >/dev/null; then
        need "  ... compat unchanged from the base's over the base's own structure" "$(jq -c .compat "$T/base.compat.json" 2>/dev/null)" \
            "$(jq -c .compat "$REPO_ROOT/skills/coordinate/koto-templates/coordinate.compat.json")"
    fi
else
    echo "     (no origin/main or main in this checkout: the compat check runs without a base table)"
fi
(cd "$REPO_ROOT" && bash scripts/check-template-compat.sh "${CARGS[@]}") > "$T/compat.out" 2>&1
rc=$?
[ "$rc" = 0 ] || needf "scripts/check-template-compat.sh exits $rc: $(cat "$T/compat.out")"
crit "8. scripts/check-template-compat.sh passes against the base branch's coordinate.compat.json, compat the base's over the base's own structure: no gate runs the helper"

report
done_tests standing-provenance-engine

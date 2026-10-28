#!/usr/bin/env bash
# coord-log-chain_engine_test.sh -- coord-log.sh chain-start against real koto:
# the chain is what koto's links give, whatever the runs are named.
#
# Proves, printing each chain start it reads:
#   - a three-member chain of takeovers (koto init --supersede, each writing
#     koto/links/continues/<pred>) whose names share no prefix returns its
#     first member from every member;
#   - cancelled runs named with S's prefix and stamp, which the name walk this
#     replaced would have followed, are not in S's chain, and a run continuing
#     a differently named run reaches that run, not its name neighbours;
#   - a member with no relation follows its dispatched-by link to the run it
#     carried when that run was cancelled and has the same scope and name (a
#     restart), the newest of several, and not to a run that ended at a
#     terminal (a rotation's predecessor) or a cancelled coordinator of
#     another scope (one that dispatched it);
#   - runs written before the relation existed, carried and linked only by
#     dispatched-by under coordinate-<slug>-<stamp> names, return the start
#     the name walk returned for them;
#   - a run that took another over has the predecessor's chain start as its
#     own, so deferral-check.sh still reads a carry made before the takeover
#     but after that chain start as disposed, and one made before the chain
#     start as open.
#
# Every session lives in a scratch HOME and KOTO_HOME (koto-test-guard.sh
# clears every KOTO_SESSION_* name, KOTO_SESSIONS_BASE and KOTO_HOME first).
# Each fixture's created_at values are rewritten to fixed times once koto has
# written everything, so the starts read as distinct minutes.
#
# Needs koto and jq; SKIPs (exit 0) without koto, which CI asserts first.
# On a koto without init --supersede (the entry floor among them) no run can
# take another over: there it runs only the cases with no takeover in them and
# prints a skip line for each case it leaves out.
# Usage: bash skills/coordinate/scripts/coord-log-chain_engine_test.sh
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the chain cases did not run"; exit 0; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/coord-log-chain.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
trap 'case "$T" in */coord-log-chain.*) rm -rf "$T" ;; esac' EXIT
export HOME="$T/home" KOTO_HOME="$T/home/.koto"
mkdir -p "$HOME"
export GIT_CEILING_DIRECTORIES="$T"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }
SKIPPED=0
skip() { SKIPPED=$((SKIPPED + 1)); printf 'skip %s\n     this koto has no init --supersede\n' "$1"; }

CL="$HERE/coord-log.sh"
DC="$HERE/deferral-check.sh"

mkdir -p "$T/work"
cd "$T/work" && git init -q && git commit -q --allow-empty -m init 2>/dev/null
case "$(koto session dir probe)" in "$T"/*) ;; *) echo "FAIL: koto's store is outside the scratch directory; no case ran"; exit 1 ;; esac
# --supersede requires --continues, so a koto that lists it can run takeover below.
case "$(koto init --help 2>/dev/null)" in *--supersede*) TAKEOVER=1 ;; *) TAKEOVER=0 ;; esac

TPL="$T/skeleton.md"
cat > "$TPL" <<'TPLEOF'
---
name: chain-skeleton
version: "1.0"
description: a skeleton for coord-log-chain_engine_test.sh
initial_state: work
variables:
  SCOPE:
    description: scope kind
    default: roadmap
  ROADMAP:
    description: roadmap path
    default: docs/roadmaps/ROADMAP-demo.md
  DISCIPLINE:
    description: discipline
    default: ""
  HOST_REPO:
    description: host
    default: acme/widgets
states:
  work:
    transitions:
      - target: done
  done:
    terminal: true
---

## work

Work.

## done

Done.
TPLEOF

# open <session> [koto init flags...]: a run of the demo roadmap unless the
# flags say otherwise.
open() {
    local s=$1; shift
    koto init "$s" --template "$TPL" "$@" >/dev/null 2>"$T/init.err" || { fail "koto init $s" "$(cat "$T/init.err")"; return 1; }
}
takeover() { local s=$1 p=$2; shift 2; open "$s" --continues "$p" --supersede "$@"; } # takeover <successor> <predecessor> [koto init flags...]
carry() { koto session link "$1" --dispatched-by "$2" >/dev/null 2>&1 || fail "link $1 dispatched-by $2"; } # carry <new run> <run it carried>
cancel() { koto cancel "$1" >/dev/null 2>&1 || fail "koto cancel $1"; }
finish() { koto next "$1" --no-cleanup >/dev/null 2>&1 || fail "koto next $1"; }
# stamp <session> <created_at>: rewrite the header's created_at, once koto is
# done writing the session.
stamp() {
    local f
    f="$(koto session dir "$1")/koto-$1.state.jsonl"
    { head -1 "$f" | jq -c --arg t "$2" '.created_at = $t' && tail -n +2 "$f"; } > "$f.new" && mv "$f.new" "$f" || fail "stamp $1"
}
chain() { bash "$CL" chain-start --session "$1" 2>"$T/chain.err"; }
show() { printf '     chain-start %s -> %s\n' "$1" "$2"; }
check_chain() { # check_chain <label> <want> <session>
    local got
    got=$(chain "$3")
    show "$3" "$got"
    eq "$1" "$2" "$got"
}

echo "== a continues chain whose names share no prefix =="
if [ "$TAKEOVER" = 1 ]; then
    open north-17 && takeover q.relay north-17 && takeover zz-final q.relay
    stamp north-17 2026-05-01T08:00:00.000Z
    stamp q.relay 2026-05-02T08:00:00.000Z
    stamp zz-final 2026-05-03T08:00:00.000Z
    check_chain "the newest member reaches the first" 2026-05-01T08:00:00.000Z zz-final
    check_chain "the middle member reaches the first" 2026-05-01T08:00:00.000Z q.relay
    check_chain "the first member is its own chain start" 2026-05-01T08:00:00.000Z north-17
else
    skip "the newest member reaches the first"
    skip "the middle member reaches the first"
    skip "the first member is its own chain start"
fi

echo "== same-prefix runs outside the chain =="
A=coordinate-demo-20260601T000000Z B=coordinate-demo-20260602T000000Z S=coordinate-demo-20260603T000000Z
open "$A" && open "$B" && open "$S"
cancel "$A"
cancel "$B"
stamp "$A" 2026-06-01T00:00:00.000Z
stamp "$B" 2026-06-02T00:00:00.000Z
stamp "$S" 2026-06-03T00:00:00.000Z
# The name walk read A's start here: S's prefix and stamp, every earlier one cancelled.
check_chain "cancelled runs named like S, unlinked, are not S's chain" 2026-06-03T00:00:00.000Z "$S"
if [ "$TAKEOVER" = 1 ]; then
    open elsewhere-run
    stamp elsewhere-run 2026-05-20T00:00:00.000Z
    S2=coordinate-demo-20260604T000000Z
    takeover "$S2" elsewhere-run
    stamp "$S2" 2026-06-04T00:00:00.000Z
    check_chain "a run continuing another name reaches it, not its name neighbours" 2026-05-20T00:00:00.000Z "$S2"
else
    skip "a run continuing another name reaches it, not its name neighbours"
fi

echo "== a member with only a dispatched-by link =="
open head-run && open mid-run
carry mid-run head-run
cancel head-run
[ "$TAKEOVER" = 1 ] && takeover tail-run mid-run
stamp head-run 2026-07-01T00:00:00.000Z
stamp mid-run 2026-07-02T00:00:00.000Z
if [ "$TAKEOVER" = 1 ]; then
    stamp tail-run 2026-07-03T00:00:00.000Z
    check_chain "the relation, then the carried run's dispatched-by link" 2026-07-01T00:00:00.000Z tail-run
else
    skip "the relation, then the carried run's dispatched-by link"
fi
check_chain "a member with only a dispatched-by link reaches the run it carried" 2026-07-01T00:00:00.000Z mid-run
open rot-old --var SCOPE=discipline --var DISCIPLINE=ci-health
finish rot-old
open rot-new --var SCOPE=discipline --var DISCIPLINE=ci-health
carry rot-new rot-old
stamp rot-old 2026-07-10T00:00:00.000Z
stamp rot-new 2026-07-11T00:00:00.000Z
check_chain "a predecessor that ended at a terminal (a rotation) ends the chain" 2026-07-11T00:00:00.000Z rot-new
open parent-coord --var ROADMAP=docs/roadmaps/ROADMAP-other.md
open child-coord --var SCOPE=discipline --var DISCIPLINE=ci-health
carry child-coord parent-coord
cancel parent-coord
stamp parent-coord 2026-07-20T00:00:00.000Z
stamp child-coord 2026-07-21T00:00:00.000Z
check_chain "a cancelled dispatcher of another scope is not in the chain" 2026-07-21T00:00:00.000Z child-coord
open older-carry && open newer-carry && open both-links
carry both-links parent-coord
carry both-links older-carry
carry both-links newer-carry
cancel older-carry
cancel newer-carry
stamp older-carry 2026-07-22T00:00:00.000Z
stamp newer-carry 2026-07-23T00:00:00.000Z
stamp both-links 2026-07-24T00:00:00.000Z
check_chain "of several carried runs, the newest" 2026-07-23T00:00:00.000Z both-links

echo "== runs written before the relation, linked only by dispatched-by =="
L1=coordinate-legacy-20260801T000000Z L2=coordinate-legacy-20260802T000000Z L3=coordinate-legacy-20260803T000000Z
open "$L1" --var ROADMAP=docs/roadmaps/ROADMAP-legacy.md
open "$L2" --var ROADMAP=docs/roadmaps/ROADMAP-legacy.md
carry "$L2" "$L1"
cancel "$L1"
open "$L3" --var ROADMAP=docs/roadmaps/ROADMAP-legacy.md
carry "$L3" "$L2"
cancel "$L2"
stamp "$L1" 2026-08-01T00:00:00.000Z
stamp "$L2" 2026-08-02T00:00:00.000Z
stamp "$L3" 2026-08-03T00:00:00.000Z
# The name walk read the same starts: each earlier run of the prefix cancelled.
check_chain "a carried restart reaches the run it carried, as the name walk did" 2026-08-01T00:00:00.000Z "$L2"
check_chain "two restarts back, as the name walk did" 2026-08-01T00:00:00.000Z "$L3"

echo "== a takeover keeps the predecessor's chain start =="
open tk-a --var ROADMAP=docs/roadmaps/ROADMAP-tk.md
open tk-b --var ROADMAP=docs/roadmaps/ROADMAP-tk.md
carry tk-b tk-a
cancel tk-a
[ "$TAKEOVER" = 1 ] && takeover tk-new tk-b --var ROADMAP=docs/roadmaps/ROADMAP-tk.md
stamp tk-a 2026-09-01T00:00:00.000Z
stamp tk-b 2026-09-02T00:00:00.000Z
check_chain "the predecessor's chain start" 2026-09-01T00:00:00.000Z tk-b
if [ "$TAKEOVER" = 1 ]; then
    stamp tk-new 2026-09-03T00:00:00.000Z
    CS=$(chain tk-new)
    show tk-new "$CS"
    eq "a takeover's chain start is its predecessor's" 2026-09-01T00:00:00.000Z "$CS"
    RS=$(bash "$CL" run-start --session tk-new)
    eq "the takeover's own run start is later" 2026-09-03T00:00:00.000Z "$RS"
    row() { jq -nc --arg d "$1" '{deferral: "x", reason: "r", raised: "2026-08-31T10:00Z", disposition: $d}' > "$T/row.json"; bash "$DC" --row-file "$T/row.json" --run-start "$RS" --chain-start "$CS"; }
    OUT=$(row 'carried 2026-09-01T12:00Z: tk-a carried it'); RC=$?
    printf '     deferral carried 2026-09-01T12:00Z -> %s\n' "$OUT"
    eq "a carry made in the chain before the takeover stays disposed" "0 disposed carried 2026-09-01T12:00Z" "$RC $OUT"
    OUT=$(row 'carried 2026-08-31T12:00Z: before the chain'); RC=$?
    printf '     deferral carried 2026-08-31T12:00Z -> %s\n' "$OUT"
    eq "a carry made before the chain start is open" "1 undisposed carried-before-chain-start" "$RC $OUT"
else
    skip "a takeover's chain start is its predecessor's"
    skip "the takeover's own run start is later"
    skip "a carry made in the chain before the takeover stays disposed"
    skip "a carry made before the chain start is open"
fi

echo "== reads that fail =="
bash "$CL" chain-start --session no-such-run >/dev/null 2>&1; eq "an unreadable S exits 2" 2 $?

echo
if [ "$SKIPPED" -gt 0 ]; then
    echo "coord-log chain: $PASS passed, $FAIL failed, $SKIPPED skipped (this koto has no init --supersede: no takeover ran)"
else
    echo "coord-log chain: $PASS passed, $FAIL failed"
fi
[ "$FAIL" -eq 0 ]

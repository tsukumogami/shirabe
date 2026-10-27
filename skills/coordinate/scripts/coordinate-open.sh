#!/usr/bin/env bash
# coordinate-open.sh -- /coordinate's entry: the invocation's tokens to the
# session's variables, and a fresh per-run session.
#
# The record lives in a run's koto session on this host
# (docs/designs/current/DESIGN-coordinator-record-teardown.md; PRD R12). The
# session store needs koto's `context list --prefix` and `session import`; a
# koto without either is refused before anything else (`refused=store-unsupported`,
# exit 2), naming what it lacks. A start then asks state-read.sh --candidate
# about this host's runs of the scope that hold a record, against the shipped
# template's hash. At discipline scope the candidate is only a rotation still
# open by the window rule (today on or before its end date, no reasoning
# written); after it ends the start opens a new run, which carries the rotation
# as its predecessor. The newest, live, the scope's only live run, compiled
# from that hash, passing provenance, whose find recorded the session
# (coord/source.json) and with no directed transition, is resumed: no session
# opens and none is cancelled, the run keeps its stamp, and the output is
# `resumed=1` then `session=<it>` (settings given with the invocation aren't
# applied to it). One that fails any of those is carried: a new run opens,
# any other live run of the scope is cancelled (never cleaned up, so its log
# stays readable), and then every record/ and legs/ key of the old run is
# copied into the new one through the write core (core_carry), printing
# `carried=<old>`. A carry cut short exits 1 (`failed=carry`) with the new run
# holding no record, and the next start carries again.
#
# A resumable run another Claude session drives is taken over instead
# (docs/designs/DESIGN-coordinate-successor-continues.md, Decision 1): its
# record/meta names another driver, or no driver and another coordinator
# address than this session's name (CLAUDE_CODE_SESSION_ID, and the name its
# Claude job state file gives it). A new run continues it through koto's fence,
# `koto init <new> --continues <run> --supersede --expect-state <its state>`
# carrying record/, legs/, taken_legs and leg_children; from then on koto
# refuses every write to the old run with session_superseded, naming the new
# one, and coord-log.sh live-session no longer lists it. The new run's
# record/meta takes this session as its driver, its coordinator row this
# session's name (which clears the told set), one takeover entry is
# appended, and record/meta's takeover_done is written last. Nothing is
# cancelled, rebound or copied key by key. It prints `outcome=continued`,
# `predecessor=<run>`, `session=<new>` and `predecessor_stopped=yes|no`: yes
# when the old run was live by the liveness probe (dispatch-common.sh
# dc_session_live) just before the fence. The same opener run again from
# this session finds the new run its own and resumes it, printing
# `outcome=resumed` and writing nothing. One cut short after any step
# converges on the same command run again: before the fence nothing was
# written and it takes over afresh; after it, this session knows the run as
# its own by the fence's actor (its Claude session) and finishes what is
# missing, running koto init again under the fence's name when the successor
# is absent or its carry unfinished, and prints `outcome=continued`. Of two
# sessions taking one run over at once, koto's fence lets exactly one through.
# `--continues <run>` names the predecessor; without it, it is the newest
# member of the scope's one unfinished run. A refused takeover writes nothing,
# leaves the predecessor driving, and prints `outcome=refused` and `reason=`,
# exit 2:
#   ambiguous-scope          more than one run of the scope is unfinished
#   not-newest-member        --continues names a run that isn't the newest
#                            member of the scope's unfinished run
#   taken-over               another Claude session fenced the run (it lost
#                            the race, or its rival's takeover is under way),
#                            or this session has no Claude session id and the
#                            run is one a takeover has touched
#   predecessor-unstoppable  the fence couldn't be taken (fence_unavailable),
#                            or the run moved state twice before it
#   template-incompatible    the run's compat number isn't the shipped one, or
#                            its state isn't in the shipped template; names
#                            both compat numbers and compiled hashes
#   koto-too-old             this koto lacks init --supersede and its flags
# (or koto's own code for any other refusal).
#
# A fresh start (no session here holds the scope's record) opens
# `coordinate-<scope-slug>-<UTC stamp>`, cancels any other live run of the
# scope, and then calls the legacy importer (../legacy-import/import.sh) once:
# `--lookup` for an open coordinator record still on GitHub, and, when it
# answers `record <n>`, the import of that record into the new run, printing
# `record-imported=<n>`. A discipline's next rotation is not a fresh start: the
# ended rotation's session is here, and the new run's find carries it. What
# the lookup says on stderr (a candidate it skipped) is passed on. The import's refusal (`record-unreadable`, a body it
# can't read, or `several`, more than one open record) stops the start for the
# person: the new run is cancelled and the output is `refused=<code>` (exit
# 2). An import that fails part way cancels the new run too (`failed=import`,
# exit 1), and the next start imports again. A resume, a carry and an
# `--import` never call it.
#
# An import (PRD R14) moves a run another host started here: `--import
# <session> --from <workspace path>` with the roadmap path, or a discipline's
# --discipline and --host, and no other setting. Before koto runs, the opener
# refuses, in this order: a name that isn't a
# run of this scope (`refused=session-name`) and another live run of the scope
# here (`refused=session-live`; the import's own target may be live, after
# koto's import_unmarked, since the same import run again only marks the
# source). koto's `session import` then brings the
# run from the bucket, taking the template from the bucket only under
# `--trust-template`, and marks the source migrated; its refusals print
# `refused=<koto code>`. The imported run must pass what a resume needs, or it
# stays here refused: a template this plugin can drive, the shipped one or one
# the compat table beside it lists at the shipped compat number
# (`refused=template-incompatible`, naming both compat numbers and hashes),
# provenance (`refused=session-provenance`; a run from another plugin root
# whose template lets koto rebind it is re-attached with this root first, and
# refused only when that attach is), a find that recorded the session
# (`refused=session-source`) and no directed transition
# (`refused=session-directed`). A plain start then carries it, except after
# session-source: a run whose find never ran is no resume candidate, so the
# start opens a new run as with no session here and cancels the imported one.
# record/host takes the source's workspace, session and template hash, and the
# output is `imported=<session>`,
# `resumed=1`, `session=<it>`, then `state=<the run's state>` and, when the run
# waits at the hub, `tick=moved`: the first tick, which sends it through a full
# reconcile on this host. A run at reconcile reconciles again by itself; one
# anywhere else does when it reaches the hub, whose directive checks for a
# reconcile still owed (`reconcile-report-get.sh --check` exits 3) on every
# visit. A state koto doesn't report reads `state=unknown`. A resume or a
# carry on the same host prints neither line: nothing moved.
#
# Tokens, in order, from a JSON array of strings in <args-file>:
#   <roadmap-path>               roadmap scope (docs/roadmaps/.../ROADMAP-<name>.md)
#   --discipline <name>          discipline scope
#   --host <owner/repo>          the record's host (discipline scope; at roadmap
#                                scope it is the repository this runs in)
#   --cap <n>, --parked-bound <n>, --rotation-days <n>
#   --reports-to <topic>         the dispatch topic of the coordinator this run
#                                reports to; without it the run reports to a
#                                person. Fixed for the run: every escalation goes
#                                there (REPORTS_TO)
#   --continues <run>            the run a takeover continues; it must be the
#                                scope's newest member (not with --import)
#   --import <session>, --from <workspace path>, [--trust-template]
#                                import that run from the bucket (with the
#                                roadmap path, or a discipline's --discipline
#                                and --host; no other setting)
#   --                           everything after it is the human's decisions:
#                                shown to the coordinator, never a setting
# At roadmap scope it also sets ROADMAP_FORM, milestone when the roadmap file
# in the working tree is a milestone roadmap, roadmap/v2 or roadmap/v3
# (milestone.sh is-milestone), else feature; no token sets it.
# Values reach koto only through a vars file, mapped with jq; koto checks each
# against its variable's pattern and refuses a bad or repeated one at init,
# with no session left behind.
#
# Usage: coordinate-open.sh [--plugin-root <path>] [--dispatched-by <name>] <args-file>
# Prints koto-open.sh's result line, then `session=<name>` on success. At
# discipline scope with no --host it opens nothing and prints
# `ask=host`: ask the human once, with a recommendation, and re-invoke with
# --host. It never defaults to the repository it runs in there.
#
# --dispatched-by <name> names the coordinator run that dispatched this one, a
# message-path worker whose brief carries this invocation with the name filled
# in (render-brief.sh). It is any koto session name (^[A-Za-z0-9][A-Za-z0-9._-]*$,
# at most 200 bytes), its form checked before any koto call, and never the
# run's own name, checked once that name is known and before the run is opened,
# resumed or imported. Once the run is open, carried, resumed or imported, the
# opener runs
# `koto session link <run> --dispatched-by <name>`, which writes the link into
# the run's own session, so koto keeps the run while its dispatcher's
# hierarchy is alive. A failed link is run once more; a second failure prints
# `warning=link-failed dispatched_by=<name>` after session=<name>, records the
# same two facts in the run's key session/link-warning, and leaves the exit
# code as it was: the run goes on, only outside the dispatcher's hierarchy.
# The retry, warning and record are scripts/lib/dispatch-link.sh's. Without the
# flag no link is written for a dispatcher.
#
# A carried run (a recycled coordinator: a new run holding an earlier run's
# record) is linked the same way to the run it carried, with
# `--dispatched-by <the earlier run>` written in the new run's session, with
# the same retry and warning. That link is written as soon as the carry lands,
# so its warning (`warning=link-failed dispatched_by=<the earlier run>`)
# prints right after carried=, before session= and any --dispatched-by link.
# The order matters only for reading the output; the session/link-warning key
# keeps one line per dispatcher either way (dispatch-link.sh).
#
# Exit codes: 0 opened or resumed; 10 the human must name the host first; 2
# this koto lacks the session store's features (`refused=store-unsupported`),
# or the legacy importer refused the start (`refused=record-unreadable` or
# `refused=several`); 1 the shipped template didn't compile
# (`failed=template_compile`), this host's runs couldn't be read
# (`failed=resume_candidate`), a cancel failed, a carry failed after the new
# run opened (`failed=carry`), or the legacy import failed (`failed=import`);
# koto-open.sh's own codes otherwise (2 refused, 64 usage, 127 koto or jq
# missing). An import exits 0
# imported; 2 refused, by this script or by koto; 1 koto couldn't read or push
# the run or mark its source (koto's own exit 1), the shipped template didn't
# compile (`failed=template_compile`), this host's runs couldn't be listed
# (`failed=live_sessions`), the imported run's log couldn't be read
# (`failed=directed_read`), or record/host wasn't written (`failed=host_facts`).
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KOTO_OPEN="$HERE/../../../scripts/koto-open.sh"
WORDING="$HERE/coordinate-open.wording.tsv"
KOTO="${KOTO_BIN:-koto}"
# shellcheck source=../../../scripts/lib/dispatch-link.sh
. "$HERE/../../../scripts/lib/dispatch-link.sh" || exit 64

usage() { echo "coordinate-open: $1" >&2; exit 64; }

PLUGIN_ROOT=
ARGS_FILE=
DISPATCHER=
HAVE_DISPATCHER=0
while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-root) [ $# -ge 2 ] || usage "--plugin-root needs a path"; PLUGIN_ROOT=$2; shift 2 ;;
        --dispatched-by) [ $# -ge 2 ] || usage "--dispatched-by needs the dispatcher's session name"
                         HAVE_DISPATCHER=$((HAVE_DISPATCHER + 1)); DISPATCHER=$2; shift 2 ;;
        --*) usage "unknown option $1" ;;
        *) [ -z "$ARGS_FILE" ] || usage "expected one <args-file>"; ARGS_FILE=$1; shift ;;
    esac
done
[ -n "$ARGS_FILE" ] && [ -r "$ARGS_FILE" ] || usage "expected a readable <args-file>"
[ "$HAVE_DISPATCHER" -le 1 ] || usage "--dispatched-by given more than once"
[ "$HAVE_DISPATCHER" -eq 0 ] || dl_valid_dispatcher "$DISPATCHER" \
    || usage "--dispatched-by must name a koto session: ^[A-Za-z0-9][A-Za-z0-9._-]*\$, at most 200 bytes, got [$DISPATCHER]"
# not_self <run>: refuse, before the run is touched, a dispatcher that names it.
not_self() {
    [ "$HAVE_DISPATCHER" -eq 0 ] || [ "$DISPATCHER" != "$1" ] \
        || usage "--dispatched-by names $1 itself; a run is not its own dispatcher"
}
# link_dispatcher <run>: record the dispatcher in the run's own session. A
# failed link has printed its warning and recorded it; the run stands.
link_dispatcher() {
    [ "$HAVE_DISPATCHER" -eq 0 ] || dl_link "$KOTO" "$1" "$DISPATCHER" || true
}
[ -n "$PLUGIN_ROOT" ] || PLUGIN_ROOT=$(cd "$HERE/../../.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "failed=jq_missing"; exit 127; }

# Tokens before `--` are settings, each one variable pair (so a repeated flag
# reaches koto as a duplicate it refuses); tokens after it are decisions.
MAP='
if (type != "array") or (map(type == "string") | all | not) then error("not a JSON array of strings") else . end
| (index("--") // length) as $cut
| .[:$cut] as $s
| reduce range(0; $s | length) as $i ({pairs: [], skip: false, positional: [], bad: null, import: {}, continues: []};
    if .skip then .skip = false
    elif $s[$i] == "--continues" then
      if $i + 1 >= ($s | length) then .bad = "--continues needs a value"
      else .skip = true | .continues += [$s[$i + 1]] end
    elif ($s[$i] | IN("--import", "--from")) then
      if $i + 1 >= ($s | length) then .bad = "\($s[$i]) needs a value"
      else .skip = true | .import[$s[$i] | ltrimstr("--")] += [$s[$i + 1]] end
    elif $s[$i] == "--trust-template" then .import.trust += [true]
    elif ($s[$i] | IN("--discipline", "--host", "--cap", "--parked-bound", "--rotation-days", "--reports-to")) then
      if $i + 1 >= ($s | length) then .bad = "\($s[$i]) needs a value"
      else .skip = true
        | .pairs += [[({"--discipline": "DISCIPLINE", "--host": "HOST_REPO", "--cap": "CAP",
                        "--parked-bound": "PARKED_BOUND", "--rotation-days": "ROTATION_DAYS", "--reports-to": "REPORTS_TO"})[$s[$i]], $s[$i + 1]]]
      end
    elif ($s[$i] | startswith("--")) then .bad = "unknown option \($s[$i])"
    else .positional += [$s[$i]] end)
'
MAPPED=$(jq -c "$MAP" < "$ARGS_FILE") || usage "the args file is not a JSON array of strings"
rm -f -- "$ARGS_FILE"
BAD=$(printf '%s' "$MAPPED" | jq -r '.bad // empty')
[ -z "$BAD" ] || usage "$BAD"

# An import (PRD R14): --import <session> --from <workspace path>, and
# --trust-template only when the operator passes it. It resumes an existing run,
# so it takes no setting.
IMPORT= FROM= TRUST=
if [ "$(printf '%s' "$MAPPED" | jq '.import | length')" -gt 0 ]; then
    [ "$(printf '%s' "$MAPPED" | jq '[.import.import // [], .import.from // [], .import.trust // []] | map(length) | max')" -le 1 ] \
        || usage "--import, --from and --trust-template each go once"
    IMPORT=$(printf '%s' "$MAPPED" | jq -r '.import.import[0] // ""')
    FROM=$(printf '%s' "$MAPPED" | jq -r '.import.from[0] // ""')
    [ "$(printf '%s' "$MAPPED" | jq '.import.trust // [] | length')" -eq 0 ] || TRUST=1
    [ -n "$IMPORT" ] && [ -n "$FROM" ] || usage "--import <session> takes --from <workspace path>, and --from and --trust-template go only with --import"
    case "$FROM" in /*) ;; *) usage "--from takes the source workspace's absolute path" ;; esac
    # A discipline's import names the scope (--discipline, and --host, which a
    # discipline scope always takes); every other setting is the imported run's.
    [ "$(printf '%s' "$MAPPED" | jq '[.pairs[] | select(.[0] != "DISCIPLINE" and .[0] != "HOST_REPO")] | length')" -eq 0 ] \
        || usage "--import resumes the imported run with its own settings; give none with it but a discipline's --discipline and --host"
fi
# --continues <run>: the predecessor a takeover names, which must be the
# scope's newest member (checked once the scope is known). Without it the
# predecessor is the newest member of the scope's one unfinished run.
NAMED=
case "$(printf '%s' "$MAPPED" | jq '.continues | length')" in
    0) ;;
    1) [ -z "$IMPORT" ] || usage "--continues names a run to take over here; it doesn't go with --import"
       NAMED=$(printf '%s' "$MAPPED" | jq -r '.continues[0]') ;;
    *) usage "--continues goes once" ;;
esac

NPOS=$(printf '%s' "$MAPPED" | jq '.positional | length')
DISC=$(printf '%s' "$MAPPED" | jq -r '[.pairs[] | select(.[0] == "DISCIPLINE")] | length')
if [ "$DISC" -gt 0 ]; then
    [ "$NPOS" -eq 0 ] || usage "give a roadmap path or --discipline, not both"
    SCOPE=discipline
    NAME=$(printf '%s' "$MAPPED" | jq -r '[.pairs[] | select(.[0] == "DISCIPLINE")][0][1]')
    if [ "$(printf '%s' "$MAPPED" | jq '[.pairs[] | select(.[0] == "HOST_REPO")] | length')" -eq 0 ]; then
        echo "ask=host"
        echo "coordinate-open: a discipline's host repository is the human's decision; ask once, with a recommendation, then re-invoke with --host <owner/repo>" >&2
        exit 10
    fi
    HOST=$(printf '%s' "$MAPPED" | jq -r '[.pairs[] | select(.[0] == "HOST_REPO")][0][1]')
    EXTRA='[]'
else
    [ "$NPOS" -eq 1 ] || usage "expected one roadmap path, or --discipline <name>"
    SCOPE=roadmap
    ROADMAP=$(printf '%s' "$MAPPED" | jq -r '.positional[0]')
    NAME=$(basename -- "$ROADMAP" .md); NAME=${NAME#ROADMAP-}
    # The roadmap's record lives in the roadmap's own repository.
    HOST=$(bash "$HERE/../../execute/scripts/record-write-set.sh" --print 2>/dev/null) || HOST=
    [ -n "$HOST" ] || usage "could not read this repository's owner/repo from its origin remote"
    # The roadmap's form, from its schema in the working tree: milestone for
    # a milestone roadmap (roadmap/v2 or roadmap/v3), feature otherwise (and
    # when the file isn't here to read).
    # It picks guidance and the no-pull-request route only; roadmap-status.sh
    # reads the schema on the default branch for anything it writes.
    FORM=feature
    if [ -r "$ROADMAP" ] && bash "$HERE/milestone.sh" is-milestone "$ROADMAP" >/dev/null 2>&1; then FORM=milestone; fi
    EXTRA=$(jq -nc --arg r "$ROADMAP" --arg h "$HOST" --arg f "$FORM" '[["ROADMAP", $r], ["HOST_REPO", $h], ["ROADMAP_FORM", $f]]')
fi

# The scope slug, derived where every write script's live-session check
# derives it.
SLUG=$(bash "$HERE/coord-log.sh" slug --scope "$SCOPE" --name "$NAME") || usage "could not derive the scope slug"
SESSION="coordinate-$SLUG-$(date -u +%Y%m%dT%H%M%SZ)"
TEMPLATE="$PLUGIN_ROOT/skills/coordinate/koto-templates/coordinate.md"

refuse_import() { # refuse_import <code> <why>
    echo "refused=$1"; echo "coordinate-open: $2" >&2; exit 2
}

# rebind_root <run>: re-attach <run> with this plugin's root, for a run whose
# PLUGIN_ROOT is another plugin root and whose compiled template declares it
# rebindable (coord-log.sh plugin-root). koto checks the run's origin and its
# fixed variables and re-applies PLUGIN_ROOT, so its gates run this plugin's
# scripts from now on. Prints koto-open.sh's rebound= line (the variables koto
# changed, e.g. rebound={"PLUGIN_ROOT":"<this root>"}); returns non-zero, having
# printed koto's refusal on stderr, when koto refuses the attach.
rebind_root() {
    local d out rc
    d=$(bash "$KOTO_OPEN" --alloc-dir) || return 1
    jq -nc --arg r "$PLUGIN_ROOT" '[["PLUGIN_ROOT", $r]]' > "$d/rebind-vars.json" || { rm -rf "$d"; return 1; }
    out=$(bash "$KOTO_OPEN" "$1" "$TEMPLATE" "$d/rebind-vars.json" --attach-live --wording "$WORDING")
    rc=$?
    rm -rf "$d"
    [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 's/^opened=//p')" = attached ] || {
        echo "coordinate-open: $1 couldn't be re-attached with this plugin's root ($(printf '%s' "$out" | tr '\n' ' '))" >&2
        return 1
    }
    printf '%s\n' "$out" | grep '^rebound=' || true
}

# compat_line <run>: "<run's compat> <shipped compat> <template hash>" from the
# compat table (coord-log.sh compat), for a refusal to name both sides.
compat_line() { bash "$HERE/coord-log.sh" compat --session "$1" 2>/dev/null; }

# The session store's koto features, read by feature before anything else
# (PRD R2): `context list --prefix` and `session import`. The help text is
# captured whole before it is matched: piped into `grep -q` under pipefail,
# koto could take SIGPIPE when grep stops at its match, and the probe would
# read a feature it has as missing (shirabe#855).
MISSING=
HELP=$("$KOTO" context list --help < /dev/null 2>/dev/null) || HELP=
case "$HELP" in *--prefix*) ;; *) MISSING="context list --prefix" ;; esac
"$KOTO" session import --help < /dev/null > /dev/null 2>&1 || MISSING="$MISSING${MISSING:+, }session import"
[ -z "$MISSING" ] || refuse_import store-unsupported "this koto lacks $MISSING, which the coordinator's session store needs; install a koto that has it"
# The import: the session another host ran, from the bucket, then resumed here
# (PRD R14). The name and a live run of the scope are refused before koto runs;
# koto's own refusals are printed with its code and leave no session; then the
# imported run must be one a start here would resume, and record/host takes the
# source's facts, so every report up names them for the next import.
if [ -n "$IMPORT" ]; then
    [[ $IMPORT =~ ^coordinate-$SLUG-[0-9]{8}T[0-9]{6}Z$ ]] \
        || refuse_import session-name "$IMPORT is not a run of $SLUG (coordinate-$SLUG-<YYYYMMDDTHHMMSSZ>)"
    not_self "$IMPORT"
    # The import's own target is the one live run it may find: koto keeps it
    # after `import_unmarked`, and the same import run again only marks the
    # source.
    LIVE=$(bash "$HERE/coord-log.sh" live-session --scope-slug "$SLUG" --all 2>/dev/null)
    case $? in
        0) [ "$LIVE" = "$IMPORT" ] || refuse_import session-live "a run of $SLUG is live on this host ($(printf '%s' "$LIVE" | tr '\n' ' ')); an import would make two" ;;
        1) ;;
        *) echo "failed=live_sessions"; echo "coordinate-open: could not list the live runs of $SLUG" >&2; exit 1 ;;
    esac
    COMPILED=$("$KOTO" template compile "$TEMPLATE" 2>/dev/null </dev/null) || COMPILED=
    SHIPPED=$(basename -- "$COMPILED" .json)
    [[ $SHIPPED =~ ^[0-9a-f]{64}$ ]] || { echo "failed=template_compile"; echo "coordinate-open: the shipped template didn't compile; nothing was imported" >&2; exit 1; }
    DIR=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-import.XXXXXX") || usage "could not make a scratch directory"
    set -- session import "$IMPORT" --from "$FROM"
    [ -z "$TRUST" ] || set -- "$@" --trust-template
    "$KOTO" "$@" </dev/null > "$DIR/out" 2> "$DIR/err"
    RC=$?
    if [ $RC -ne 0 ]; then
        CODE=$(jq -r '.error.code // empty' "$DIR/out" 2>/dev/null)
        [[ $CODE =~ ^[a-z_]+$ ]] || CODE=import_failed
        TEXT=$(awk -F'\t' -v c="$CODE" '$1 == c { print $2; exit }' "$WORDING")
        [ -n "$TEXT" ] || TEXT=$(jq -r '.error.message // empty' "$DIR/out" 2>/dev/null | head -c 400)
        echo "refused=$CODE"; echo "coordinate-open: koto refused the import: ${TEXT:-exit $RC}" >&2
        rm -rf "$DIR"
        # koto's exit 1 is a read, push or marker failure worth retrying;
        # everything else it refuses is exit 2, as this script's own refusals.
        [ $RC -eq 1 ] && exit 1
        exit 2
    fi
    rm -rf "$DIR"
    # koto has imported it by now: a refusal below leaves it on this host, the
    # only copy (the source is marked migrated), and a plain start here carries
    # its record into a new run on this host's template and plugin, all but
    # session-source's, which holds no session-store record to carry.
    HASH=$(bash "$HERE/coord-log.sh" template-hash --session "$IMPORT" 2>/dev/null)
    # The template: the shipped one, or one the compat table beside it lists
    # at the shipped compat number (coord-log.sh compat), so a change to
    # directive text alone no longer stops an import.
    if [ "$HASH" != "$SHIPPED" ] && ! bash "$HERE/coord-log.sh" compat --session "$IMPORT" >/dev/null 2>&1; then
        read -r RUN_COMPAT SHIP_COMPAT _ <<EOF
$(compat_line "$IMPORT")
EOF
        refuse_import template-incompatible \
            "$IMPORT was compiled from coordinate.md at compat ${RUN_COMPAT:--} (template ${HASH:-unknown}); this plugin ships compat ${SHIP_COMPAT:--} (template $SHIPPED), so it can't drive the run; it stays on this host, and a plain start carries its record into a new run"
    fi
    # The plugin root: a run opened from another plugin root, whose template
    # lets koto rebind it, is re-attached with this one before provenance runs.
    ROOTS=$(bash "$HERE/coord-log.sh" plugin-root --session "$IMPORT" 2>/dev/null) || ROOTS=
    RUN_ROOT=
    [ -n "$ROOTS" ] && RUN_ROOT=$(printf '%s' "$ROOTS" | jq -r '.root')
    # A root that no longer exists on this host is another plugin's: cd's
    # complaint about it says nothing the comparison doesn't.
    if [ -n "$ROOTS" ] && [ "$(printf '%s' "$ROOTS" | jq -r '.rebind')" = true ] \
        && [ "$(cd "$RUN_ROOT" 2>/dev/null && pwd -P)" != "$(cd "$PLUGIN_ROOT" && pwd -P)" ]; then
        rebind_root "$IMPORT" || refuse_import session-provenance \
            "$IMPORT's plugin root couldn't be moved to this host's; it stays on this host, and a plain start carries its record into a new run"
    fi
    bash "$HERE/coord-log.sh" provenance --session "$IMPORT" >/dev/null 2>&1 || refuse_import session-provenance \
        "$IMPORT wasn't opened from this host's plugin (its plugin root differs); it stays on this host, and a plain start carries its record into a new run"
    [ "$("$KOTO" context get "$IMPORT" coord/source.json < /dev/null 2>/dev/null | jq -r '.source // empty' 2>/dev/null)" = session ] \
        || refuse_import session-source "$IMPORT's find didn't record the session; it holds no record to continue"
    # A run moved with `koto next --to` refuses every write, so it isn't one to
    # continue either (the resume candidate's own last check).
    bash "$HERE/coord-log.sh" directed-since --session "$IMPORT" --from 0 > /dev/null 2>&1
    case $? in
        0) ;;
        1) refuse_import session-directed "$IMPORT has a directed transition in its log; it stays on this host, and a plain start carries its record into a new run" ;;
        *) echo "failed=directed_read"; echo "coordinate-open: $IMPORT's log couldn't be read for directed transitions" >&2; exit 1 ;;
    esac
    bash "$HERE/state-stored-set.sh" --session "$IMPORT" --host source_workspace "$FROM" --host source_session "$IMPORT" \
        --host template_hash "$HASH" > /dev/null 2>&1 \
        || { echo "failed=host_facts"; echo "coordinate-open: $IMPORT is imported, but record/host wasn't written; run state-stored-set.sh --host for it" >&2; exit 1; }
    printf 'imported=%s\nresumed=1\nsession=%s\n' "$IMPORT" "$IMPORT"
    link_dispatcher "$IMPORT"
    # The run reconciles again on this host. At reconcile it does so by itself
    # (its sealed report names another host's import facts). The hub takes the
    # `moved` tick, and its directive checks for a reconcile still owed on
    # every visit, so a run anywhere else gets the reconcile when it reaches
    # the hub; that check reads the run's own keys, so a restart keeps it.
    AT=$("$KOTO" status "$IMPORT" 2>/dev/null </dev/null | jq -r '.current_state // empty' 2>/dev/null)
    printf 'state=%s\n' "${AT:-unknown}"
    case "$AT" in
        reconcile|reconcile_pass) ;;
        wait) echo "tick=moved" ;;
        *) echo "coordinate-open: $IMPORT is at ${AT:-an unreadable state}; it reconciles on this host when it next reaches wait, whose check sends it through moved" >&2 ;;
    esac
    exit 0
fi

# The takeover. The caller is the Claude session running this opener
# (CLAUDE_CODE_SESSION_ID); its name, the messaging address workers report
# to, is the one its job state file gives it (dc_claude_name). A resumable run
# is the caller's own when its record/meta names the caller as its driver, or,
# with no driver recorded (a run no one has taken over), when its coordinator
# row names the caller. It is another session's when it names another driver,
# or no driver and another coordinator than the caller's name. A caller with
# no Claude session id can't tell itself from another session: a run a
# takeover has touched (a driver recorded, or the run continues a predecessor)
# refuses it `taken-over`, the safe side, and a run no takeover has touched
# resumes as it did before takeovers existed.
# shellcheck source=dispatch-common.sh
. "$HERE/dispatch-common.sh" || exit 64
CALLER=${CLAUDE_CODE_SESSION_ID:-}
[[ $CALLER =~ ^[0-9a-f][0-9a-f-]{7,63}$ ]] || CALLER=
CALLER_NAME=
[ -z "$CALLER" ] || CALLER_NAME=$(dc_claude_name "${DC_CLAUDE_HOME:-$HOME/.claude}" "$CALLER") || CALLER_NAME=
# The record is read through its readers, never key by key here: record/meta
# through state-read.sh --meta, the Run section through state-stored-set.sh
# --list (as dispatch-worker.sh reads the address).
# meta_json <run>: the run's record/meta, {} when it holds none, "" when the
# read fails.
meta_json() {
    bash "$HERE/state-read.sh" --session "$1" --meta < /dev/null 2> /dev/null
}
# meta_field <run> <field>: a string field of the run's record/meta, "" when absent.
meta_field() {
    jq -r --arg f "$2" '.[$f] // "" | if type == "string" or type == "boolean" then tostring else "" end' <<< "$(meta_json "$1")" 2> /dev/null
}
# run_address <run>: the address in the run's coordinator row, "" when none.
run_address() {
    jq -r '[(.run // [])[] | select(.key == "coordinator") | .value][0] // ""' \
        <<< "$(bash "$HERE/state-stored-set.sh" --session "$1" --list < /dev/null 2> /dev/null)" 2> /dev/null
}
driven_by_another() {
    local d a
    [ -n "$CALLER" ] || return 1
    d=$(meta_field "$1" driver)
    if [ -n "$d" ]; then [ "$d" != "$CALLER" ]; return; fi
    a=$(run_address "$1")
    [ -n "$a" ] && [ -n "$CALLER_NAME" ] && [ "$a" != "$CALLER_NAME" ]
}
# meta_set <run> <jq filter> [jq args...]: rewrite the run's record/meta with
# the filter applied, through the write core (core_write_meta), in a subshell
# since the core exits on a refusal. Only the opener writes these fields,
# while no one drives the run (between the fence and the end of the
# takeover), and every record write after keeps them.
meta_set() {
    ( PROG=coordinate-open SESSION=$1 SKIP_CHECKS=0 REPO=${HOST:-}
      . "$HERE/state-common.sh" && . "$HERE/state-write-core.sh" && core_write_meta "$@" ) > /dev/null 2>&1
}
refuse_takeover() { # refuse_takeover <reason> <why>: nothing was written
    printf 'outcome=refused\nreason=%s\n' "$1"; echo "coordinate-open: $2" >&2; exit 2
}
# fence_of <run>: set FENCE to the run's fence (coord-log.sh fence), "" when
# it has none, and FENCE_BY and FENCE_ACTOR to its successor and the Claude
# session that fenced it. A log that can't be read stops the opener.
fence_of() {
    FENCE=$(bash "$HERE/coord-log.sh" fence --session "$1" < /dev/null 2> /dev/null)
    case $? in
        0|1) ;;
        *) echo "failed=takeover_read"; echo "coordinate-open: $1's log couldn't be read for a fence; nothing was written" >&2; exit 1 ;;
    esac
    FENCE_BY=$(jq -r '.by // ""' <<< "${FENCE:-null}" 2> /dev/null)
    FENCE_ACTOR=$(jq -r '.claude_session // ""' <<< "${FENCE:-null}" 2> /dev/null)
}
# pred_of <run>: the run it continues (koto's continues relation), "" when none.
pred_of() {
    "$KOTO" session hierarchy "$1" < /dev/null 2> /dev/null | sed -n 's/^continues: //p' | head -1
}
# koto_takeover_missing: the init flags a takeover needs that this koto lacks,
# "" when it has them all (requires.tsv's mode:takeover record).
koto_takeover_missing() {
    local help f missing=
    help=$("$KOTO" init --help < /dev/null 2> /dev/null) || help=
    for f in --continues --supersede --expect-state --carry; do
        case "$help" in *"$f"*) ;; *) missing="$missing${missing:+ }$f" ;; esac
    done
    printf '%s' "$missing"
}
# compat_refusal <run> <why-prefix>: refuse template-incompatible, naming the
# template and both sides' compat numbers and compiled hashes, and this
# plugin's shirabe version.
compat_refusal() {
    local rc sc ver hash
    read -r rc sc _ <<EOF
$(compat_line "$1")
EOF
    hash=$(bash "$HERE/coord-log.sh" template-hash --session "$1" 2> /dev/null)
    ver=$(jq -r '.version // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2> /dev/null)
    refuse_takeover template-incompatible \
        "$2: $1 runs coordinate.md at compat ${rc:--} (template ${hash:-unknown}); this plugin (shirabe ${ver:-unknown}) ships coordinate.md at compat ${sc:--} (template $SHIPPED), so it can't drive the run; nothing was written and $1 still drives"
}
# finish_takeover <successor> <predecessor> <yes|no>: the successor's own
# record changes after the fence, each written once, so a re-run after a crash
# finishes what is missing: the driver (first, so a re-run knows the run is
# its own), the coordinator row naming the caller, which clears the told set,
# one takeover entry, and record/meta's takeover_done last. Then the result.
finish_takeover() {
    local succ=$1 pred=$2 stopped=$3 d
    if [ "$(meta_field "$succ" driver)" != "$CALLER" ] || [ "$(meta_field "$succ" takeover_done)" = true ]; then
        meta_set "$succ" '.driver = $c | .takeover_done = false | .takeover = {predecessor: $p, predecessor_stopped: $st}' \
            --arg c "$CALLER" --arg p "$pred" --arg st "$stopped" \
            || { echo "failed=takeover_record"; echo "coordinate-open: $pred is fenced and $succ holds its record, but $succ's record/meta wasn't written; run the opener again from this session to finish" >&2; exit 1; }
    fi
    if [ -n "$CALLER_NAME" ]; then
        if [ "$(run_address "$succ")" != "$CALLER_NAME" ]; then
            bash "$HERE/state-stored-set.sh" --session "$succ" --run coordinator "$CALLER_NAME" --by "$CALLER_NAME" > /dev/null 2> "$T_ERR" \
                || { echo "failed=takeover_record"; echo "coordinate-open: $succ's coordinator row wasn't written: $(head -c 400 "$T_ERR"); run the opener again from this session to finish" >&2; exit 1; }
        fi
    else
        echo "coordinate-open: this session's name couldn't be read, so $succ's coordinator row still names the predecessor's; write yours with state-stored-set.sh --run coordinator" >&2
    fi
    if ! bash "$HERE/state-entry.sh" --session "$succ" --list 2> "$T_ERR" \
            | jq -e --arg p "takeover $succ:" 'any(.[]; .kind == "takeover" and (.text | startswith($p)))' > /dev/null; then
        d=$(mktemp "${TMPDIR:-/tmp}/coordinate-open-entry.XXXXXX") || { echo "failed=takeover_record"; exit 1; }
        printf 'takeover %s: %s continues %s, which it fenced; %s was %s when it was taken over.\n' \
            "$succ" "$succ" "$pred" "$pred" "$([ "$stopped" = yes ] && echo live || echo "not live")" > "$d"
        bash "$HERE/state-entry.sh" --session "$succ" --kind takeover --text-file "$d" > /dev/null 2> "$T_ERR" \
            || { rm -f "$d"; echo "failed=takeover_record"; echo "coordinate-open: $succ's takeover entry wasn't written: $(head -c 400 "$T_ERR"); run the opener again from this session to finish" >&2; exit 1; }
        rm -f "$d"
    fi
    meta_set "$succ" '.takeover_done = true' \
        || { echo "failed=takeover_record"; echo "coordinate-open: $succ's takeover wasn't marked done; run the opener again from this session to finish" >&2; exit 1; }
    printf 'outcome=continued\npredecessor=%s\nsession=%s\npredecessor_stopped=%s\n' "$pred" "$succ" "$stopped"
    link_dispatcher "$succ"
    exit 0
}
# takeover <predecessor>: continue the predecessor's run in a new session
# through koto's fence (koto init --continues --supersede), carrying the
# record and the legs from the fenced state, then finish_takeover. The
# predecessor's liveness is read before the fence, by the liveness probe
# (dc_session_live), against the driver its record/meta names or, with none,
# its coordinator row. A predecessor that moved state between the read and the
# fence (stale_state) is read again once. With <successor> given, this
# session's own takeover was cut short after the fence: the same init runs
# again under that name, and koto creates or carries whatever is missing.
# Before anything is written it refuses `koto-too-old` on a koto without the
# fence's flags, and `template-incompatible` when the predecessor sits in a
# state the shipped template doesn't have (Decision 2).
takeover() {
    local pred=$1 given=${2:-} pd pa state stopped succ out rc code tries=0 d why missing
    missing=$(koto_takeover_missing)
    [ -z "$missing" ] || refuse_takeover koto-too-old \
        "this koto ($("$KOTO" --version < /dev/null 2> /dev/null | head -1)) lacks koto init $missing; taking $pred over needs koto 0.28.0 or later; nothing was written and $pred still drives"
    pd=$(meta_field "$pred" driver); pa=$(run_address "$pred")
    while :; do
        state=$("$KOTO" status "$pred" < /dev/null 2> /dev/null | jq -r '.current_state // empty' 2> /dev/null)
        [ -n "$state" ] || { echo "failed=takeover_read"; echo "coordinate-open: $pred's state couldn't be read; nothing was written" >&2; exit 1; }
        [ -n "$given" ] || jq -e --arg s "$state" '.states | has($s)' "$COMPILED" > /dev/null 2>&1 \
            || compat_refusal "$pred" "$pred is at $state, a state this plugin's coordinate.md doesn't have"
        if dc_session_live "$pred" "$pd" "$pa" > "$T_ERR" 2>&1; then stopped=yes; else stopped=no; fi
        if [ -n "$given" ]; then succ=$given
        else
            succ="coordinate-$SLUG-$(date -u +%Y%m%dT%H%M%SZ)"
            # Named to the second: a takeover in the second the run opened waits.
            while [ "$succ" = "$pred" ]; do sleep 1; succ="coordinate-$SLUG-$(date -u +%Y%m%dT%H%M%SZ)"; done
        fi
        not_self "$succ"
        d=$(bash "$KOTO_OPEN" --alloc-dir) || usage "could not allocate a vars directory"
        bash "$HERE/coord-log.sh" vars --session "$pred" 2> /dev/null \
            | jq -c --arg r "$PLUGIN_ROOT" '. + {PLUGIN_ROOT: $r} | to_entries | map([.key, (.value | tostring)])' > "$d/vars.json" \
            || { rm -rf "$d"; echo "failed=takeover_read"; echo "coordinate-open: $pred's variables couldn't be read; nothing was written" >&2; exit 1; }
        set -- init "$succ" --template "$TEMPLATE" --vars-file "$d/vars.json" --continues "$pred" --supersede \
            --expect-state "$state" --carry record/ --carry legs/ --carry taken_legs --carry leg_children
        case "${SHIRABE_KOTO_LEGACY_ENVIRONMENT:-}" in ''|0|false) ;; *) set -- "$@" --legacy-environment ;; esac
        out=$("$KOTO" "$@" < /dev/null 2> "$T_ERR")
        rc=$?
        rm -rf "$d"
        [ $rc -eq 0 ] && break
        code=$(printf '%s' "$out" | jq -r '.error.code // .code // empty' 2> /dev/null)
        case "$rc:$code" in
            2:stale_state) [ $tries -eq 0 ] || refuse_takeover predecessor-unstoppable "$pred kept moving between its state read and the fence; nothing was written"
                           tries=1 ;;
            3:*) refuse_takeover predecessor-unstoppable "$pred's log lock couldn't be taken (fence_unavailable); nothing was written and $pred still drives" ;;
            *) if printf '%s' "$out" | jq -e '.superseded_by // empty' > /dev/null 2>&1; then
                   refuse_takeover taken-over "$pred was already taken over by $(printf '%s' "$out" | jq -r '.superseded_by'); nothing was written"
               fi
               why=$(jq -r '.error | if type == "object" then .message // empty else . // empty end' <<< "$out" 2> /dev/null)
               refuse_takeover "${code:-koto-refused}" "koto refused the takeover of $pred (exit $rc): ${why:0:400}" ;;
        esac
    done
    # koto knows a re-run by the successor's name alone, so a rival named in
    # the same second as this one can find its fence and take it for ours:
    # the fence's actor says whose it is, and a rival's is refused.
    fence_of "$pred"
    [ "$FENCE_BY" = "$succ" ] && [ -n "$CALLER" ] && [ "$FENCE_ACTOR" = "$CALLER" ] \
        || refuse_takeover taken-over "$pred was taken over by ${FENCE_BY:-another session} from another Claude session; continue in it"
    finish_takeover "$succ" "$pred" "$stopped"
}
# takeover_check <run> <action> <code>: what a start does with the scope's
# newest run that holds a record (state-read.sh --candidate's session, action
# and code), before it resumes or carries it. It exits when the start is a
# takeover or finishes one, or refuses, and returns when the run is this
# session's own (or no takeover has touched it and this session can't tell),
# so the start resumes or carries it as before. In order:
#   - the run is fenced: a takeover of it started, and its successor holds no
#     record yet. This session's own (the fence's actor) runs koto init again
#     under the fence's name, which creates and carries what is missing; any
#     other's refuses taken-over.
#   - the run continues a predecessor whose fence this session ran: this
#     session's own takeover, finished when its record/meta names this
#     session as driver with takeover_done, else finished now (koto init again
#     when the carry's marker is missing). One another session ran and hasn't
#     finished refuses taken-over.
#   - with no Claude session id, a run a takeover has touched refuses
#     taken-over; one it hasn't is this session's, as before.
#   - a run another session drives is taken over when it could be resumed;
#     with another live run of the scope it refuses ambiguous-scope, and on a
#     template this plugin can't drive template-incompatible. A run carried
#     for another reason (finished, cancelled, provenance, a directed
#     transition) is carried as before.
takeover_check() {
    local run=$1 action=$2 code=$3 p stopped
    fence_of "$run"
    if [ -n "$FENCE" ]; then
        if [ -n "$CALLER" ] && [ "$FENCE_ACTOR" = "$CALLER" ]; then not_self "$FENCE_BY"; takeover "$run" "$FENCE_BY"; fi
        refuse_takeover taken-over "$run was taken over by $FENCE_BY from another Claude session, and that takeover hasn't finished; nothing was written"
    fi
    p=$(pred_of "$run")
    if [ -n "$p" ]; then
        fence_of "$p"
        if [ "$FENCE_BY" = "$run" ] && [ -n "$CALLER" ] && [ "$FENCE_ACTOR" = "$CALLER" ]; then
            [ "$(meta_field "$run" driver)" = "$CALLER" ] && [ "$(meta_field "$run" takeover_done)" = true ] && return 0
            "$KOTO" context exists "$run" koto/superseded-carry-complete < /dev/null > /dev/null 2>&1 || takeover "$p" "$run"
            # The probe's reading before the fence, once the driver holds it;
            # read again when the cut came before the driver was written.
            if [ "$(meta_field "$run" driver)" = "$CALLER" ]; then
                stopped=$(jq -r '.takeover.predecessor_stopped // "no"' <<< "$(meta_json "$run")")
            elif dc_session_live "$p" "$(meta_field "$p" driver)" "$(run_address "$p")" > /dev/null 2>&1; then stopped=yes
            else stopped=no; fi
            finish_takeover "$run" "$p" "$stopped"
        fi
        if [ "$FENCE_BY" = "$run" ] && { [ "$(meta_field "$run" takeover_done)" != true ] || [ "$(meta_field "$run" driver)" != "$FENCE_ACTOR" ]; }; then
            refuse_takeover taken-over "$run is taking $p over from another Claude session, and that takeover hasn't finished; nothing was written"
        fi
    fi
    if [ -z "$CALLER" ]; then
        if [ -n "$p" ] || [ -n "$(meta_field "$run" driver)" ]; then
            refuse_takeover taken-over "this session has no Claude session id (CLAUDE_CODE_SESSION_ID), so it can't tell itself from $run's driver; nothing was written"
        fi
        return 0
    fi
    driven_by_another "$run" || return 0
    case "$action:$code" in
        resume:*) takeover "$run" ;;
        carry:several-live) refuse_takeover ambiguous-scope \
            "more than one run of $SLUG is unfinished here ($(bash "$HERE/coord-log.sh" live-session --scope-slug "$SLUG" --all 2> /dev/null | tr '\n' ' ')), so which to take over is ambiguous; nothing was written" ;;
        carry:template) compat_refusal "$run" "$run's template isn't one this plugin's compat table lists at its compat number" ;;
    esac
}
T_ERR=$(mktemp "${TMPDIR:-/tmp}/coordinate-open-err.XXXXXX") || usage "could not make a scratch file"
trap 'rm -f "$T_ERR"' EXIT

# The record lives in a run's session on this host, so a start first looks
# here for the scope's run that holds it
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 6; PRD R12).
# state-read.sh --candidate decides, against the shipped template's hash:
# resume keeps that run (no new session, no cancel, and the run keeps its
# stamp); carry opens a new run below and copies its record/ and legs/ keys in;
# none opens a new run, a fresh start. At discipline scope the window rule decides
# first (rs_resume_candidate): a start inside the newest rotation's window is a
# restart of that rotation, resumed or carried as above, and a start after it
# ended (by date, or by closing) opens the next rotation as a new run, whose find
# carries the predecessor.
CARRY_FROM=
# FRESH: no session here holds the scope's record (the candidate names none).
# Only a fresh start asks the legacy importer.
FRESH=0
if [ "$SCOPE" = roadmap ] || [ "$SCOPE" = discipline ]; then
    COMPILED=$("$KOTO" template compile "$TEMPLATE" 2>/dev/null </dev/null) || COMPILED=
    SHIPPED=$(basename -- "$COMPILED" .json)
    [[ $SHIPPED =~ ^[0-9a-f]{64}$ ]] || { echo "failed=template_compile"; echo "coordinate-open: the shipped template didn't compile; nothing was opened" >&2; exit 1; }
    CAND=$(bash "$HERE/state-read.sh" --candidate --scope "$SCOPE" --name "$NAME" --hash "$SHIPPED" 2>/dev/null) \
        || { echo "failed=resume_candidate"; echo "coordinate-open: could not read this host's runs of $SLUG; nothing was opened" >&2; exit 1; }
    [ "$(printf '%s' "$CAND" | jq -r '.session // empty')" = "" ] && FRESH=1
    ACTION=$(printf '%s' "$CAND" | jq -r '.action')
    OLD=$(printf '%s' "$CAND" | jq -r '.session // empty')
    # A named predecessor (--continues) must be the scope's newest member: the
    # run the candidate names, one that holds the record.
    if [ -n "$NAMED" ]; then
        [[ $NAMED =~ ^coordinate-$SLUG-[0-9]{8}T[0-9]{6}Z$ ]] \
            || refuse_takeover not-newest-member "$NAMED is not a run of $SLUG (coordinate-$SLUG-<YYYYMMDDTHHMMSSZ>); nothing was written"
        { [ -n "$OLD" ] && [ "$ACTION" != none ]; } \
            || refuse_takeover not-newest-member "$NAMED isn't the newest member of an unfinished run of $SLUG: no run of it here holds a record to continue; nothing was written"
        [ "$NAMED" = "$OLD" ] \
            || refuse_takeover not-newest-member "$NAMED isn't the newest member of $SLUG's run, $OLD is; name it, or name none; nothing was written"
    fi
    # The takeover decision (takeover_check exits on a takeover, a finished
    # interrupted one, or a refusal). It comes before any rebind: the takeover
    # passes this plugin root to the new run itself, and a run this session
    # doesn't drive is never written.
    if [ -n "$OLD" ] && [ "$ACTION" != none ]; then
        not_self "$OLD"
        takeover_check "$OLD" "$ACTION" "$(printf '%s' "$CAND" | jq -r '.code // empty')"
    fi
    case "$ACTION" in
        resume)
            # A run from another plugin root is re-attached with this one
            # first; a refused attach carries it instead, as before.
            if [ "$(printf '%s' "$CAND" | jq -r '.rebind // false')" = true ] && ! rebind_root "$OLD"; then
                CAND=$(printf '%s' "$CAND" | jq -c '.action = "carry" | .reason = "its plugin root couldn'"'"'t be moved to this plugin'"'"'s"')
            fi
        ;;
    esac
    case "$(printf '%s' "$CAND" | jq -r '.action')" in
        resume)
            [ "$(printf '%s' "$MAPPED" | jq '.pairs | length')" -eq 0 ] \
                || echo "coordinate-open: $OLD is resumed with the settings it opened with; the ones given here are not applied" >&2
            printf 'outcome=resumed\nresumed=1\nsession=%s\n' "$OLD"
            link_dispatcher "$OLD"
            exit 0 ;;
        carry) CARRY_FROM=$(printf '%s' "$CAND" | jq -r '.session')
               echo "coordinate-open: carrying $CARRY_FROM into a new run: $(printf '%s' "$CAND" | jq -r '.reason')" >&2 ;;
    esac
fi

not_self "$SESSION"
DIR=$(bash "$KOTO_OPEN" --alloc-dir) || usage "could not allocate a vars directory"
printf '%s' "$MAPPED" | jq -c --arg scope "$SCOPE" --arg root "$PLUGIN_ROOT" --argjson extra "$EXTRA" \
    '[["SCOPE", $scope]] + .pairs + $extra + [["PLUGIN_ROOT", $root]]' > "$DIR/coordinate-vars.json"
OUT=$(bash "$KOTO_OPEN" "$SESSION" "$TEMPLATE" "$DIR/coordinate-vars.json" --wording "$WORDING")
RC=$?
[ -n "$OUT" ] && printf '%s\n' "$OUT"
[ $RC -eq 0 ] || exit $RC

# Only once the new run is open (so a refused invocation leaves the live run
# alone): cancel, never clean up, every other live run of this scope
# (coord-log.sh live-session --all, the scan every write script's check
# makes), so its log stays readable.
LIVE=$(bash "$HERE/coord-log.sh" live-session --scope-slug "$SLUG" --all 2>/dev/null)
case $? in 0|1) ;; *) echo "failed=live_sessions"; echo "coordinate-open: could not list the live runs of $SLUG" >&2; exit 1 ;; esac
for id in $LIVE; do
    [ "$id" = "$SESSION" ] && continue
    "$KOTO" cancel "$id" </dev/null >/dev/null || { echo "failed=cancel"; echo "coordinate-open: could not cancel the live run $id" >&2; exit 1; }
    echo "cancelled=$id"
done

# The carry: the previous run's record into this one, through the write core's
# checks (core_carry), as the run that now holds it writes it. The previous
# run's log stays readable; a carry cut short leaves this run holding no record,
# and the next start carries again.
if [ -n "$CARRY_FROM" ]; then
    PROG=coordinate-open SKIP_CHECKS=0 REPO=$HOST
    . "$HERE/state-common.sh"
    lib_write_guard
    T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-open.XXXXXX") || { echo "failed=carry"; exit 1; }
    trap 'rm -rf "$T" "$T_ERR"' EXIT
    . "$HERE/state-write-core.sh"
    ( core_carry "$CARRY_FROM" "$SESSION" ) || { RC=$?; echo "failed=carry"; echo "coordinate-open: $SESSION is open, but $CARRY_FROM's record wasn't carried into it (exit $RC); start again to carry it" >&2; exit 1; }
    echo "carried=$CARRY_FROM"
    # The recycled coordinator: the new run is joined to the run it carried,
    # a dispatched-by link in the new run's own session, so the earlier run
    # and the workers it dispatched stay in one hierarchy with it. A failed
    # link has printed its warning and recorded it; the carry stands.
    dl_link "$KOTO" "$SESSION" "$CARRY_FROM" || true
elif [ "$FRESH" = 1 ]; then
    # A fresh start: no session here holds the scope's record (a discipline's
    # next rotation, whose ended rotation's session is here, isn't one). The legacy
    # importer (docs/designs/current/DESIGN-coordinator-record-teardown.md, "The
    # legacy importer") looks once for a coordinator record still open on
    # GitHub and, finding one, imports its state into this run before the run's
    # find reads it. Its refusal stops the start, and so does a failure part
    # way: the new run is cancelled, so it can't go on without the record's
    # state, and the next start imports again.
    IMP="$HERE/../legacy-import/import.sh"
    IMP_ERR=$(mktemp "${TMPDIR:-/tmp}/coordinate-open-import.XXXXXX") \
        || { echo "failed=import"; echo "coordinate-open: could not make a scratch file" >&2; exit 1; }
    trap 'rm -f "$IMP_ERR" "$T_ERR"' EXIT
    stop_fresh() { # stop_fresh <refused|failed> <code> <why>
        "$KOTO" cancel "$SESSION" </dev/null >/dev/null 2>&1 || echo "coordinate-open: $SESSION couldn't be cancelled; cancel it before starting again" >&2
        echo "$1=$2"; echo "coordinate-open: $3" >&2
        [ "$1" = refused ] && exit 2
        exit 1
    }
    LOOK=$(bash "$IMP" --lookup --session "$SESSION" --scope "$SCOPE" --name "$NAME" --repo "$HOST" 2> "$IMP_ERR")
    RC=$?
    # A lookup may have skipped a candidate whose author has no write access,
    # which it names on stderr; that reaches the operator whatever the lookup
    # answered (a failure's own message below quotes it too).
    if [ -s "$IMP_ERR" ]; then head -c 1000 "$IMP_ERR" >&2; fi
    case "$RC:$LOOK" in
        "0:none"|"0:resume") ;;
        "0:record "*)
            REF=${LOOK#record }
            [[ $REF =~ ^[1-9][0-9]*$ ]] || stop_fresh failed import "the legacy importer's lookup named no record number: $LOOK"
            IMPORTED=$(bash "$IMP" --session "$SESSION" --scope "$SCOPE" --name "$NAME" --repo "$HOST" --ref "$REF" 2> "$IMP_ERR")
            RC=$?
            # Any refusal (65) is the record's: a body that doesn't parse, or
            # one whose state the write core's checks refuse.
            case "$RC:$IMPORTED" in
                "0:imported=$REF "*) echo "record-imported=$REF" ;;
                65:*) stop_fresh refused record-unreadable \
                    "the coordinator record $HOST#$REF on GitHub can't be read into this run: $(head -c 400 "$IMP_ERR"); fix or close it, then start again" ;;
                *) stop_fresh failed import "the import of the coordinator record $HOST#$REF stopped part way (exit $RC): $(head -c 400 "$IMP_ERR"); start again to import it" ;;
            esac ;;
        "65:several "*) stop_fresh refused several \
            "$HOST holds more than one open coordinator record for this scope (${LOOK#several }); close all but one, then start again" ;;
        *) stop_fresh failed import "the legacy importer's lookup failed (exit $RC): $(head -c 400 "$IMP_ERR"); start again" ;;
    esac
fi
printf 'session=%s\n' "$SESSION"
link_dispatcher "$SESSION"
exit 0

#!/usr/bin/env bash
# coordinate-open.sh -- /coordinate's entry: the invocation's tokens to the
# session's variables, and a fresh per-run session.
#
# For a record on GitHub every invocation is a new run. A restart after a crash
# gets its own session, its own start time (the session header's created_at),
# and a full start, find and reconcile; continuity lives on GitHub, where the
# new run's find adopts the record the previous run opened. So this script
# cancels (never cleans up) any live coordinate session for the same scope,
# keeping its log readable, and opens `coordinate-<scope-slug>-<UTC stamp>`.
#
# A record on the session store lives in a run's session on this host
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 6; PRD R12), so
# at roadmap scope a start first asks record-source.sh --candidate about this
# host's runs of the scope that hold a record, against the shipped template's
# hash. The newest, live, the scope's only live run, compiled from that hash,
# passing provenance, sealed to the session store and with no directed
# transition, is resumed: no session opens and none is cancelled, the run keeps
# its stamp, and the output is `resumed=1` then `session=<it>` (settings given
# with the invocation aren't applied to it). One that fails any of those is
# carried: a new run opens and the live runs are cancelled as above, and then
# every record/ and legs/ key of the old run is copied into the new one through
# the write core (core_carry), printing `carried=<old>`. The old run's log
# stays readable. A carry cut short exits 1 (`failed=carry`) with the new run
# holding no record, and the next start carries again.
#
# An import (PRD R14) moves a run another host started here: `--import
# <session> --from <workspace path>` with the roadmap path, and no setting.
# Before koto runs, the opener refuses, in this order: discipline scope
# (`refused=store-discipline`, as the arguments are read), a name that isn't a
# run of this scope (`refused=session-name`), another live run of the scope
# here (`refused=session-live`; the import's own target may be live, after
# koto's import_unmarked, since the same import run again only marks the
# source) and a koto without `session import` (`refused=store-unsupported`).
# koto's `session import` then brings the
# run from the bucket, taking the template from the bucket only under
# `--trust-template`, and marks the source migrated; its refusals print
# `refused=<koto code>`. The imported run must pass what a resume needs, or it
# stays here refused: the shipped template's hash (`refused=template-mismatch`),
# provenance (`refused=session-provenance`), the session store
# (`refused=session-source`) and no directed transition
# (`refused=session-directed`). A plain start then carries it, except after
# session-source: a run not on the session store is no resume candidate, so the
# start opens a new run as with no session here and cancels the imported one. record/host takes the source's workspace,
# session and template hash, and the output is `imported=<session>`,
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
#   --store github|session       where a new scope's record keeps its state
#                                (STORE); a found record's own store row decides
#                                for an existing one, and this flag is then
#                                reported ignored. Roadmap scope only; without
#                                it a new record is on GitHub
#   --import <session>, --from <workspace path>, [--trust-template]
#                                import that run from the bucket (roadmap scope,
#                                no other setting)
#   --                           everything after it is the human's decisions:
#                                shown to the coordinator, never a setting
# At roadmap scope it also sets ROADMAP_FORM, milestone when the roadmap file
# in the working tree reads `schema: roadmap/v2` (milestone.sh schema), else
# feature; no token sets it.
# Values reach koto only through a vars file, mapped with jq; koto checks each
# against its variable's pattern and refuses a bad or repeated one at init,
# with no session left behind.
#
# Usage: coordinate-open.sh [--plugin-root <path>] <args-file>
# Prints koto-open.sh's result line, then `session=<name>` on success. At
# discipline scope with no --host it opens nothing and prints
# `ask=host`: ask the human once, with a recommendation, and re-invoke with
# --host. It never defaults to the repository it runs in there.
#
# Exit codes: 0 opened or resumed; 10 the human must name the host first; 1
# the shipped template didn't compile (`failed=template_compile`), this host's
# runs couldn't be read (`failed=resume_candidate`), a cancel failed, or a carry
# failed after the new run opened (`failed=carry`); koto-open.sh's own codes
# otherwise (2 refused, 64 usage, 127 koto or jq missing). An import exits 0
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

usage() { echo "coordinate-open: $1" >&2; exit 64; }

PLUGIN_ROOT=
ARGS_FILE=
while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-root) [ $# -ge 2 ] || usage "--plugin-root needs a path"; PLUGIN_ROOT=$2; shift 2 ;;
        --*) usage "unknown option $1" ;;
        *) [ -z "$ARGS_FILE" ] || usage "expected one <args-file>"; ARGS_FILE=$1; shift ;;
    esac
done
[ -n "$ARGS_FILE" ] && [ -r "$ARGS_FILE" ] || usage "expected a readable <args-file>"
[ -n "$PLUGIN_ROOT" ] || PLUGIN_ROOT=$(cd "$HERE/../../.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "failed=jq_missing"; exit 127; }

# Tokens before `--` are settings, each one variable pair (so a repeated flag
# reaches koto as a duplicate it refuses); tokens after it are decisions.
MAP='
if (type != "array") or (map(type == "string") | all | not) then error("not a JSON array of strings") else . end
| (index("--") // length) as $cut
| .[:$cut] as $s
| reduce range(0; $s | length) as $i ({pairs: [], skip: false, positional: [], bad: null, import: {}};
    if .skip then .skip = false
    elif ($s[$i] | IN("--import", "--from")) then
      if $i + 1 >= ($s | length) then .bad = "\($s[$i]) needs a value"
      else .skip = true | .import[$s[$i] | ltrimstr("--")] += [$s[$i + 1]] end
    elif $s[$i] == "--trust-template" then .import.trust += [true]
    elif ($s[$i] | IN("--discipline", "--host", "--cap", "--parked-bound", "--rotation-days", "--reports-to", "--store")) then
      if $i + 1 >= ($s | length) then .bad = "\($s[$i]) needs a value"
      else .skip = true
        | .pairs += [[({"--discipline": "DISCIPLINE", "--host": "HOST_REPO", "--cap": "CAP",
                        "--parked-bound": "PARKED_BOUND", "--rotation-days": "ROTATION_DAYS", "--reports-to": "REPORTS_TO",
                        "--store": "STORE"})[$s[$i]], $s[$i + 1]]]
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
# so it takes no setting, and it is for a roadmap's session-store record only.
IMPORT= FROM= TRUST=
if [ "$(printf '%s' "$MAPPED" | jq '.import | length')" -gt 0 ]; then
    [ "$(printf '%s' "$MAPPED" | jq '[.import.import // [], .import.from // [], .import.trust // []] | map(length) | max')" -le 1 ] \
        || usage "--import, --from and --trust-template each go once"
    IMPORT=$(printf '%s' "$MAPPED" | jq -r '.import.import[0] // ""')
    FROM=$(printf '%s' "$MAPPED" | jq -r '.import.from[0] // ""')
    [ "$(printf '%s' "$MAPPED" | jq '.import.trust // [] | length')" -eq 0 ] || TRUST=1
    [ -n "$IMPORT" ] && [ -n "$FROM" ] || usage "--import <session> takes --from <workspace path>, and --from and --trust-template go only with --import"
    case "$FROM" in /*) ;; *) usage "--from takes the source workspace's absolute path" ;; esac
    if [ "$(printf '%s' "$MAPPED" | jq '[.pairs[] | select(.[0] == "DISCIPLINE")] | length')" -gt 0 ]; then
        echo "refused=store-discipline"
        echo "coordinate-open: --import is for a roadmap's session-store record; a discipline rotation's record stays on GitHub" >&2
        exit 2
    fi
    [ "$(printf '%s' "$MAPPED" | jq '.pairs | length')" -eq 0 ] || usage "--import resumes the imported run with its own settings; give none with it"
fi

# The store (docs/designs/DESIGN-coordinator-session-record.md, Decision 2):
# roadmap scope only. koto checks the value's shape; this refusal comes first so
# nothing opens. GitHub stays the default: only `--store session` opens a new
# scope's record on the session store.
STORE_FLAG=$(printf '%s' "$MAPPED" | jq -r '[.pairs[] | select(.[0] == "STORE") | .[1]] | last // ""')
if [ -n "$STORE_FLAG" ]; then
    if [ "$(printf '%s' "$MAPPED" | jq '[.pairs[] | select(.[0] == "DISCIPLINE")] | length')" -gt 0 ]; then
        echo "refused=store-discipline"
        echo "coordinate-open: --store is for roadmap scope; a discipline rotation's record stays on GitHub" >&2
        exit 2
    fi
fi

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
    # roadmap/v2, feature otherwise (and when the file isn't here to read).
    # It picks guidance and the no-pull-request route only; roadmap-status.sh
    # reads the schema on the default branch for anything it writes.
    FORM=feature
    if [ -r "$ROADMAP" ] && [ "$(bash "$HERE/milestone.sh" schema "$ROADMAP" 2>/dev/null)" = roadmap/v2 ]; then FORM=milestone; fi
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
# The import: the session another host ran, from the bucket, then resumed here
# (PRD R14). The name and a live run of the scope are refused before koto runs;
# koto's own refusals are printed with its code and leave no session; then the
# imported run must be one a start here would resume, and record/host takes the
# source's facts, so every report up names them for the next import.
if [ -n "$IMPORT" ]; then
    [[ $IMPORT =~ ^coordinate-$SLUG-[0-9]{8}T[0-9]{6}Z$ ]] \
        || refuse_import session-name "$IMPORT is not a run of $SLUG (coordinate-$SLUG-<YYYYMMDDTHHMMSSZ>)"
    # The import's own target is the one live run it may find: koto keeps it
    # after `import_unmarked`, and the same import run again only marks the
    # source.
    LIVE=$(bash "$HERE/coord-log.sh" live-session --scope-slug "$SLUG" --all 2>/dev/null)
    case $? in
        0) [ "$LIVE" = "$IMPORT" ] || refuse_import session-live "a run of $SLUG is live on this host ($(printf '%s' "$LIVE" | tr '\n' ' ')); an import would make two" ;;
        1) ;;
        *) echo "failed=live_sessions"; echo "coordinate-open: could not list the live runs of $SLUG" >&2; exit 1 ;;
    esac
    [ "$(bash "$HERE/record-source.sh" --probe | jq -r '.session_import // false')" = true ] \
        || refuse_import store-unsupported "this koto has no \`session import\`; install a koto that has it"
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
    [ "$HASH" = "$SHIPPED" ] || refuse_import template-mismatch \
        "$IMPORT was compiled from another template than the one shipped here; it stays on this host, and a plain start carries its record into a new run"
    bash "$HERE/coord-log.sh" provenance --session "$IMPORT" >/dev/null 2>&1 || refuse_import session-provenance \
        "$IMPORT wasn't opened from this host's plugin (its plugin root differs); it stays on this host, and a plain start carries its record into a new run"
    [ "$(bash "$HERE/coord-log.sh" run-store --session "$IMPORT" 2>/dev/null)" = session ] \
        || refuse_import session-source "$IMPORT's find didn't record the session store; it holds no session-store record to continue"
    # A run moved with `koto next --to` refuses every write, so it isn't one to
    # continue either (the resume candidate's own last check).
    bash "$HERE/coord-log.sh" directed-since --session "$IMPORT" --from 0 > /dev/null 2>&1
    case $? in
        0) ;;
        1) refuse_import session-directed "$IMPORT has a directed transition in its log; it stays on this host, and a plain start carries its record into a new run" ;;
        *) echo "failed=directed_read"; echo "coordinate-open: $IMPORT's log couldn't be read for directed transitions" >&2; exit 1 ;;
    esac
    bash "$HERE/record-state.sh" --session "$IMPORT" --host source_workspace "$FROM" --host source_session "$IMPORT" \
        --host template_hash "$HASH" > /dev/null 2>&1 \
        || { echo "failed=host_facts"; echo "coordinate-open: $IMPORT is imported, but record/host wasn't written; run record-state.sh --host for it" >&2; exit 1; }
    printf 'imported=%s\nresumed=1\nsession=%s\n' "$IMPORT" "$IMPORT"
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

# A record on the session store lives in a run's session on this host, so a
# start first looks here for the scope's run that holds it
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 6; PRD R12).
# record-source.sh --candidate decides, against the shipped template's hash:
# resume keeps that run (no new session, no cancel, and the run keeps its
# stamp); carry opens a new run below and copies its record/ and legs/ keys in;
# none opens a new run as on GitHub. Roadmap scope only: a discipline record is
# on GitHub.
CARRY_FROM=
if [ "$SCOPE" = roadmap ]; then
    COMPILED=$("$KOTO" template compile "$TEMPLATE" 2>/dev/null </dev/null) || COMPILED=
    SHIPPED=$(basename -- "$COMPILED" .json)
    [[ $SHIPPED =~ ^[0-9a-f]{64}$ ]] || { echo "failed=template_compile"; echo "coordinate-open: the shipped template didn't compile; nothing was opened" >&2; exit 1; }
    CAND=$(bash "$HERE/record-source.sh" --candidate --scope roadmap --name "$NAME" --hash "$SHIPPED" 2>/dev/null) \
        || { echo "failed=resume_candidate"; echo "coordinate-open: could not read this host's runs of $SLUG; nothing was opened" >&2; exit 1; }
    case "$(printf '%s' "$CAND" | jq -r '.action')" in
        resume)
            OLD=$(printf '%s' "$CAND" | jq -r '.session')
            [ "$(printf '%s' "$MAPPED" | jq '.pairs | length')" -eq 0 ] \
                || echo "coordinate-open: $OLD is resumed with the settings it opened with; the ones given here are not applied" >&2
            printf 'resumed=1\nsession=%s\n' "$OLD"
            exit 0 ;;
        carry) CARRY_FROM=$(printf '%s' "$CAND" | jq -r '.session')
               echo "coordinate-open: carrying $CARRY_FROM into a new run: $(printf '%s' "$CAND" | jq -r '.reason')" >&2 ;;
    esac
fi

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
    . "$HERE/record-common.sh"
    lib_write_guard
    T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-open.XXXXXX") || { echo "failed=carry"; exit 1; }
    trap 'rm -rf "$T"' EXIT
    . "$HERE/record-write-core.sh"
    ( core_carry "$CARRY_FROM" "$SESSION" ) || { RC=$?; echo "failed=carry"; echo "coordinate-open: $SESSION is open, but $CARRY_FROM's record wasn't carried into it (exit $RC); start again to carry it" >&2; exit 1; }
    echo "carried=$CARRY_FROM"
fi
printf 'session=%s\n' "$SESSION"
exit 0

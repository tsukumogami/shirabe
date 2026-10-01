#!/usr/bin/env bash
# panel-scope.sh -- for /work-on: which review seats a panel round actually
# needs, decided from git rather than from the agent's judgment.
#
# Before this, a blocking finding from any of the three panels cleared all three
# verdicts and the run walked back through all seven seats: three scrutiny,
# three review, one QA. Two retries could spawn 21 reviewers for one issue, and
# a QA finding about one test re-ran reviewers on code they had already passed.
#
# Now each seat's verdict is kept in a ledger, and on every panel entry this
# script decides, per seat, what the round does:
#
#   full     no verdict on record yet (the first round): a fresh full review
#   recheck  the seat raised a blocking finding last time: it checks only
#            whether that finding is fixed, given the finding and the fix diff
#            (a blocking seat that recorded no findings is rerun instead)
#   rerun    the seat passed, but the fix touched what it judged: a fresh review
#   keep     the seat passed and the fix touched nothing it judged: its verdict
#            carries and the seat is not spawned
#
# "Touched" is objective. The fix diff is `git diff <judged_at> HEAD`, where
# judged_at is the commit the seat's verdict was given at. A passed seat is
# rerun when any of these holds, checked in this order:
#
#   0. the working tree has uncommitted changes (the fix may not be committed,
#      and the diff below would miss it), or there are no commits since
#      impl_base (nothing for a pass to rest on; scrutiny's has_commits gate
#      must not be slipped past by a carried verdict)
#   1. the acceptance criteria or the plan changed since it judged (the git
#      hash of the `context.md` and `plan.md` context keys differs). context.md
#      is written at setup and plan.md at analysis, so in practice this fires
#      when a scope_expanded_retry or scope_changed_retry rewrote the plan
#   2. judged_at is no longer a commit, or no longer an ancestor of HEAD
#      (a rebase or reset rewrote what it judged)
#   3. the fix diff changes more than THRESHOLD_LINES lines in total -- a fix
#      that large is new work, not a fix. It is also the only check that sees
#      files a fix adds, since a new file was never cited. 200 is a judgment,
#      not a measurement: about one screenful of diff per seat to re-read
#   4. the fix diff overlaps what it cited: a cited path with a line range is
#      touched when a fix hunk's old-side range overlaps it; a cited path with
#      no range is touched when the fix changes the file at all; a seat that
#      cited nothing is taken to have cited every path in the diff it reviewed
#      (impl_base..judged_at). The locations of findings the seat raised are
#      checked too, on top of either.
#
# Renames are off (`--no-renames`), so moving a cited file counts as touching
# it. A pure insertion (`@@ -a,0 ...`) sits between lines a and a+1 and touches
# a range containing either.
#
# The template runs it twice per panel state, and the agent once per round:
#
#   --plan <panel> <session>     default_action on `scrutiny`, `review` and
#                                `qa_validation`. Writes `<panel>_scope.json`
#                                and appends the round's decisions, with their
#                                reasons, to the ledger's history. When every
#                                seat is `keep` it also writes
#                                `<panel>_results.json`, marked carried.
#   --carried <panel> <session>  the `<panel>_carried` gate. Exit 0 when the
#                                scope written for this HEAD keeps every seat,
#                                so koto advances the panel with no spawn.
#   --record <panel> <session> <round-file>
#                                the agent, at aggregation, for every seat it
#                                spawned this round, passed or blocking. Stamps
#                                judged_at=HEAD and the criteria hash and merges
#                                the verdicts into the ledger.
#
# Usage: panel-scope.sh --plan    <panel> <koto-session-name>
#        panel-scope.sh --carried <panel> <koto-session-name>
#        panel-scope.sh --record  <panel> <koto-session-name> <round-file>
#
# <panel> is scrutiny, review or qa (the qa_validation state).
#
# ## The round file
#
# A JSON array, one object per spawned seat:
#
#   [{"seat": "completeness", "blocking_count": 1,
#     "cited": [{"path": "src/a.sh", "lines": "10-24"}, {"path": "README.md"}],
#     "findings": [{"summary": "...", "path": "src/a.sh", "lines": "12-12"}]}]
#
# `cited` is what the seat judged: the paths and, where it can say, the line
# ranges ("N" or "N-M", in HEAD's numbering) its verdict rests on. Findings'
# locations are kept beside it, as `finding_locations`, so a seat that cited
# nothing still falls back to the whole diff it judged. Both carry forward from
# earlier rounds, so a seat's judged scope only grows; an earlier line range in
# a file that has changed since is carried as the bare path, because its
# numbers no longer name the same code. `blocking_count > 0` records the seat
# as blocking.
#
# ## Context keys
#
#   verdict_ledger.json   {"rev": N, "seats": {"<panel>/<seat>": {...}},
#                          "history": [{"panel", "round", "head", "rev",
#                          "spawned", "decisions": [{seat, decision, reason}]}]}
#                         Never cleared by a retry: it is what survives one.
#   <panel>_scope.json    this entry's decisions, for the agent to act on
#   <panel>_results.json  only when every seat is kept; otherwise the agent
#                         writes it at aggregation as before
#
# A `--plan` re-run at the same HEAD with no `--record` in between (a tick
# without evidence, say) replaces its own history entry instead of adding one,
# so the history counts rounds, not ticks.
#
# Diagnostics go to stderr. --plan prints the scope it wrote on stdout, for a
# human running it by hand; the other modes print nothing.
#
# Exit codes:
#   0   -- --plan/--record: written. --carried: every seat is kept.
#   1   -- --carried only: something has to run, the working tree is dirty, or
#          the scope is missing, stale or unreadable. --carried exits nothing else: a gate exit the template
#          does not route would hold the state, and "run the panel" is the safe
#          answer to every doubt.
#   64  -- not a git repository, or HEAD names no commit
#   65  -- the round file is missing or is not a JSON array of seats
#   66  -- a `koto context add` failed; koto's own stderr says why
#   67  -- a mode, panel or argument is missing or unrecognised
#   127 -- jq is not on PATH
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

THRESHOLD_LINES=200
LEDGER=verdict_ledger.json

die() {
    # $1 exit code, $2 message
    echo "panel-scope: $2" >&2
    exit "$1"
}

MODE="${1:-}"
PANEL="${2:-}"
SESSION="${3:-}"

# --carried answers 1 to every doubt, usage errors included; see Exit codes.
refuse() {
    # $1 exit code for the other modes, $2 message
    [ "$MODE" = "--carried" ] && { echo "panel-scope: $2" >&2; exit 1; }
    die "$1" "$2"
}

case "$MODE" in
    --plan|--carried|--record) ;;
    "") die 67 "missing mode: expected --plan, --carried or --record" ;;
    *)  die 67 "unrecognised mode [$MODE]: expected --plan, --carried or --record" ;;
esac

case "$PANEL" in
    scrutiny) SEATS="completeness justification intent" ;;
    review)   SEATS="pragmatic architect maintainer" ;;
    qa)       SEATS="tester" ;;
    "") refuse 67 "missing panel" ;;
    *)  refuse 67 "unrecognised panel [$PANEL]: expected scrutiny, review or qa" ;;
esac
[ -n "$SESSION" ] || refuse 67 "missing session argument for $MODE"
command -v jq >/dev/null || refuse 127 "jq not on PATH"

HEAD=$(git rev-parse --verify -q "HEAD^{commit}") \
    || refuse 64 "not a git repository, or HEAD names no commit"

# A missing key reads as empty. `koto context exists` exits 1, silently, for an
# absent key.
ctx_get() {
    if koto context exists "$SESSION" "$1" 2>/dev/null; then
        koto context get "$SESSION" "$1" 2>/dev/null
    fi
}

# ---------------------------------------------------------------- --carried ---

if [ "$MODE" = "--carried" ]; then
    [ -z "$(git status --porcelain | head -1)" ] \
        || refuse 1 "the working tree has uncommitted changes"
    scope=$(ctx_get "${PANEL}_scope.json")
    [ -n "$scope" ] || refuse 1 "no ${PANEL}_scope.json for this round"
    printf '%s' "$scope" | jq -e --arg head "$HEAD" '
        .head == $head and (.decisions | length > 0)
        and all(.decisions[]; .decision == "keep")' >/dev/null 2>&1 \
        || refuse 1 "${PANEL}_scope.json does not keep every seat at HEAD"
    koto context exists "$SESSION" "${PANEL}_results.json" 2>/dev/null \
        || refuse 1 "every seat is kept but ${PANEL}_results.json is absent"
    exit 0
fi

WORK=$(mktemp -d) || die 64 "could not create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

AC_SHA=$( { ctx_get context.md; printf '\n--- plan ---\n'; ctx_get plan.md; } | git hash-object --stdin)

LEDGER_JSON=$(ctx_get "$LEDGER")
if [ -z "$LEDGER_JSON" ] || ! printf '%s' "$LEDGER_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
    [ -n "$LEDGER_JSON" ] && echo "panel-scope: $LEDGER is unreadable; starting a new ledger" >&2
    LEDGER_JSON='{"rev": 0, "seats": {}, "history": []}'
fi

put() {
    # $1 key, $2 file
    koto context add "$SESSION" "$1" < "$2" >/dev/null \
        || die 66 "koto context add failed for $1 on session [$SESSION]"
}

# ---------------------------------------------------------------- --record ----

if [ "$MODE" = "--record" ]; then
    ROUND_FILE="${4:-}"
    [ -n "$ROUND_FILE" ] || die 67 "missing round file for --record"
    [ -f "$ROUND_FILE" ] || die 65 "round file [$ROUND_FILE] not found"
    jq -e 'type == "array" and length > 0 and all(.[]; (.seat | type) == "string")' \
        "$ROUND_FILE" >/dev/null 2>&1 \
        || die 65 "round file [$ROUND_FILE] is not a JSON array of seats"
    for s in $(jq -r '.[].seat' "$ROUND_FILE"); do
        case " $SEATS " in
            *" $s "*) ;;
            *) die 65 "seat [$s] is not a $PANEL seat (expected one of: $SEATS)" ;;
        esac
    done
    # A seat's earlier citations carry forward, but their line ranges are in
    # the numbering of the commit it judged then. Where the file has changed
    # since, the range no longer names the same code, so only the path is
    # carried: coarser, never wrong.
    : > "$WORK/moved"
    for s in $(jq -r '.[].seat' "$ROUND_FILE"); do
        old=$(printf '%s' "$LEDGER_JSON" | jq -r --arg k "$PANEL/$s" '.seats[$k].judged_at // empty')
        [ -n "$old" ] || continue
        if git rev-parse --verify -q "${old}^{commit}" >/dev/null; then
            git diff --no-renames --name-only "$old" HEAD | jq -R --arg s "$s" '{seat: $s, path: .}'
        else
            jq -n --arg s "$s" '{seat: $s, path: "*"}'
        fi >> "$WORK/moved"
    done
    printf '%s' "$LEDGER_JSON" | jq --arg panel "$PANEL" --arg head "$HEAD" \
        --arg ac "$AC_SHA" --slurpfile round "$ROUND_FILE" --slurpfile moved "$WORK/moved" '
        def norm: map(select(.path | type == "string")
                      | {path} + (if .lines then {lines: (.lines | tostring)} else {} end));
        def carry($seat): map(. as $c
            | if any($moved[]; .seat == $seat and (.path == $c.path or .path == "*"))
              then {path: $c.path} else $c end);
        .rev = ((.rev // 0) + 1)
        | .seats = (.seats // {})
        | reduce $round[0][] as $s (.;
            ($panel + "/" + $s.seat) as $k
            | ((.seats[$k].cited // []) | carry($s.seat)) as $old_cited
            | ((.seats[$k].finding_locations // []) | carry($s.seat)) as $old_locs
            | .seats[$k] = {
                panel: $panel,
                seat: $s.seat,
                verdict: (if ($s.blocking_count // 0) > 0 then "blocking" else "passed" end),
                judged_at: $head,
                ac_sha: $ac,
                cited: ($old_cited + (($s.cited // []) | norm) | unique),
                finding_locations: ($old_locs
                    + ([($s.findings // [])[] | select(.path) | {path, lines}] | norm) | unique),
                findings: ($s.findings // [])
              })' > "$WORK/ledger" || die 65 "could not merge [$ROUND_FILE] into the ledger"
    put "$LEDGER" "$WORK/ledger"
    exit 0
fi

# ---------------------------------------------------------------- --plan ------

IMPL_BASE=$(ctx_get impl_base | tr -d '[:space:]')
TAB=$(printf '\t')

# Does the fix diff from $1 to HEAD touch a cited entry? Reads the cited list
# (one "path<TAB>lines" per line, lines possibly empty) on stdin. Prints the
# first touched entry and returns 0, or returns 1. A diff that fails to run
# counts as touching: the safe answer is to review again.
touches() {
    local from="$1" path lines lo hi
    git diff --no-renames --name-only "$from" HEAD > "$WORK/fixpaths" \
        || { echo "(git diff failed)"; return 0; }
    while IFS="$TAB" read -r path lines; do
        [ -n "$path" ] || continue
        grep -Fxq -- "$path" "$WORK/fixpaths" || continue
        if [ -z "$lines" ]; then
            printf '%s\n' "$path"
            return 0
        fi
        lo=${lines%%-*}
        hi=${lines#*-}
        case "$lo$hi" in *[!0-9]*|"") printf '%s\n' "$path"; return 0 ;; esac
        # Old-side range of each fix hunk in this file: `@@ -a,b +c,d @@`. A
        # missing b means 1; b == 0 is an insertion between lines a and a+1.
        if git diff --no-renames -U0 "$from" HEAD -- "$path" | awk -v lo="$lo" -v hi="$hi" '
            /^@@ / {
                n = split(substr($2, 2), o, ",")
                a = o[1] + 0
                b = (n > 1) ? o[2] + 0 : 1
                if (b == 0) { s = a; e = a + 1 } else { s = a; e = a + b - 1 }
                if (s <= hi + 0 && e >= lo + 0) { found = 1; exit }
            }
            END { exit found ? 0 : 1 }'; then
            printf '%s:%s\n' "$path" "$lines"
            return 0
        fi
    done
    return 1
}

# Two facts that hold for every seat this entry. A dirty tree means the fix
# may not be committed yet, and the diff below would not see it. No commits
# since impl_base, or none recorded, means there is nothing to have passed: the has_commits gate
# on scrutiny's passed edge holds, and a carried verdict must not slip past it.
DIRTY=""
[ -n "$(git status --porcelain | head -1)" ] && DIRTY=1
NOCOMMITS=""
if [ -z "$IMPL_BASE" ] || [ "$(git rev-list --count "$IMPL_BASE..HEAD" || echo 0)" = 0 ]; then
    NOCOMMITS=1
fi

: > "$WORK/decisions"
for seat in $SEATS; do
    entry=$(printf '%s' "$LEDGER_JSON" | jq -c --arg k "$PANEL/$seat" '.seats[$k] // empty')
    if [ -z "$entry" ]; then
        decision=full
        reason="no verdict on record for this seat"
    else
        verdict=$(printf '%s' "$entry" | jq -r '.verdict')
        judged=$(printf '%s' "$entry" | jq -r '.judged_at // ""')
        ac=$(printf '%s' "$entry" | jq -r '.ac_sha // ""')
        short=$(printf '%.12s' "$judged")
        nfind=$(printf '%s' "$entry" | jq '.findings | length')
        if [ "$verdict" = "blocking" ] && [ "$nfind" -gt 0 ]; then
            decision=recheck
            reason="raised $nfind blocking finding(s) at $short; re-check them against the fix diff"
            [ -n "$DIRTY" ] && reason="$reason (the working tree has uncommitted changes the fix diff does not include: commit the fix first)"
        elif [ "$verdict" = "blocking" ]; then
            decision=rerun
            reason="blocked at $short but recorded no findings to re-check"
        elif [ -n "$DIRTY" ]; then
            decision=rerun
            reason="the working tree has uncommitted changes, so the fix diff cannot be judged: commit the fix and tick again"
        elif [ -n "$NOCOMMITS" ]; then
            decision=rerun
            reason="no commits since impl_base, or impl_base is unrecorded (has_commits fails either way); nothing to carry a pass for"
        elif [ "$ac" != "$AC_SHA" ]; then
            decision=rerun
            reason="acceptance criteria changed since it judged at $short"
        elif ! git rev-parse --verify -q "${judged}^{commit}" >/dev/null \
            || ! git merge-base --is-ancestor "$judged" HEAD; then
            decision=rerun
            reason="the commit it judged ($short) is not an ancestor of HEAD"
        else
            changed=$(git diff --no-renames --numstat "$judged" HEAD \
                | awk '{ a = ($1 == "-") ? 1 : $1; d = ($2 == "-") ? 1 : $2; n += a + d } END { print n + 0 }')
            nfiles=$(git diff --no-renames --name-only "$judged" HEAD | wc -l | tr -d ' ')
            # The seat's own citations decide whether it fell back to the diff
            # it judged; the locations of findings it raised are added either
            # way, so a fix near a finding re-checks the seat that raised it.
            printf '%s' "$entry" | jq -r '.cited[]? | [.path, (.lines // "" | tostring)] | @tsv' > "$WORK/cited"
            cited_what="what it cited"
            if [ ! -s "$WORK/cited" ] && [ -n "$IMPL_BASE" ]; then
                git diff --no-renames --name-only "$IMPL_BASE" "$judged" \
                    | awk -v t="$TAB" '{ print $0 t }' > "$WORK/cited"
                cited_what="the diff it judged"
            fi
            printf '%s' "$entry" | jq -r '.finding_locations[]? | [.path, (.lines // "" | tostring)] | @tsv' >> "$WORK/cited"
            if [ "$changed" -eq 0 ]; then
                decision=keep
                reason="nothing changed since it passed at $short"
            elif [ "$changed" -gt "$THRESHOLD_LINES" ]; then
                decision=rerun
                reason="fix diff since $short changes $changed lines, over the $THRESHOLD_LINES-line threshold"
            elif [ ! -s "$WORK/cited" ]; then
                decision=rerun
                reason="cited nothing, and the diff it judged is empty"
            elif hit=$(touches "$judged" < "$WORK/cited"); then
                decision=rerun
                reason="fix diff since $short touches $hit, in $cited_what"
            else
                decision=keep
                reason="fix diff since $short ($changed lines in $nfiles files) touches nothing in $cited_what"
            fi
        fi
    fi
    jq -nc --arg seat "$seat" --arg d "$decision" --arg r "$reason" --argjson e "${entry:-null}" '
        {seat: $seat, decision: $d, reason: $r}
        + (if $d == "recheck" then {findings: ($e.findings // []), fix_diff_from: $e.judged_at} else {} end)
        + (if $d == "rerun" or $d == "keep" then {judged_at: $e.judged_at} else {} end)
        ' >> "$WORK/decisions"
    entry=""
done

jq -s --arg panel "$PANEL" --arg head "$HEAD" '{panel: $panel, head: $head, decisions: .}' \
    "$WORK/decisions" > "$WORK/scope"

# The history entry for this round. Replaced, not appended, when the previous
# entry for this panel is at the same HEAD and nothing was recorded since.
printf '%s' "$LEDGER_JSON" | jq --slurpfile scope "$WORK/scope" '
    ($scope[0]) as $s
    | .history = (.history // [])
    | (.rev // 0) as $rev
    | ([.history | to_entries[] | select(.value.panel == $s.panel)] | last) as $prev
    | {panel: $s.panel, head: $s.head, rev: $rev,
       spawned: ([$s.decisions[] | select(.decision != "keep")] | length),
       decisions: [$s.decisions[] | {seat, decision, reason}]} as $entry
    | if $prev != null and $prev.value.head == $s.head and $prev.value.rev == $rev
      then .history[$prev.key] = ($entry + {round: $prev.value.round})
      else .history += [$entry + {round: ([.history[] | select(.panel == $s.panel)] | length + 1)}]
      end' > "$WORK/ledger" || die 65 "could not update the ledger history"

# Order matters for the gate: the carried results go in before the scope, so a
# scope that keeps every seat is never visible without them.
if jq -e 'all(.decisions[]; .decision == "keep")' "$WORK/scope" >/dev/null; then
    jq '{passed: true, carried: true, head: .head,
         seats: [.decisions[] | {seat, decision, reason}]}' "$WORK/scope" > "$WORK/results"
    put "${PANEL}_results.json" "$WORK/results"
fi
put "$LEDGER" "$WORK/ledger"
put "${PANEL}_scope.json" "$WORK/scope"
cat "$WORK/scope"
exit 0

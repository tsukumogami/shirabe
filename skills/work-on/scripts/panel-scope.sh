#!/usr/bin/env bash
# panel-scope.sh -- for /work-on: which review seats a panel round actually
# needs, decided from git rather than from the agent's judgment.
#
# Without it, a blocking finding from any of the three panels would clear all
# three verdicts and send the run back through all seven seats: three
# scrutiny, three review, one QA. Two retries could spawn 21 reviewers for one
# issue, and a QA finding about one test would re-run reviewers on code they
# had already passed.
#
# Each seat's verdict is kept in a ledger, and on every panel entry this
# script decides, per seat, what the round does:
#
#   full     no verdict on record yet (the first round): a fresh full review
#   recheck  the seat raised a blocking finding last time: it checks only
#            whether that finding is fixed, given the finding and the fix diff.
#            A blocking seat goes through checks 0-3 below first, and is rerun
#            if any holds, or if it recorded no findings
#   rerun    the seat passed, but the fix touched what it judged: a fresh review
#   keep     the seat passed and the fix touched nothing it judged: its verdict
#            carries and the seat is not spawned
#
# "Touched" is objective. The fix diff is `git diff <judged_at> HEAD`, where
# judged_at is the commit the seat's verdict was given at. A passed seat is
# rerun when any of these holds, checked in this order:
#
#   0. the working tree has uncommitted changes, untracked files included
#      (the fix may not be committed, and the diff below would miss it), or
#      there are no commits since impl_base or no impl_base recorded (nothing
#      for a pass to rest on; scrutiny's has_commits gate must not be slipped
#      past by a carried verdict)
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
#      (impl_base..judged_at), and is rerun if that diff is empty. The
#      locations of findings the seat raised are checked too, on top of
#      either.
#
# Renames are off (`--no-renames`), so moving a cited file counts as touching
# it. A pure insertion (`@@ -a,0 ...`) sits between lines a and a+1 and touches
# a range containing either.
#
# The template runs --plan on each entry to a panel state, and --carried,
# --recorded and --verdict as that state's gates (evaluated on every tick
# there); the agent runs --record once per round:
#
#   --plan <panel> <session>     default_action on `scrutiny`, `review`,
#                                `qa_validation` and `light_review`. Writes
#                                `<panel>_scope.json`
#                                and appends the round's decisions, with their
#                                reasons, to the ledger's history. When every
#                                seat is `keep` it also writes
#                                `<panel>_results.json`, marked carried.
#   --carried <panel> <session>  the `<panel>_carried` gate. Exit 0 when the
#                                tree is clean, the scope written for this
#                                HEAD keeps every seat, and the carried results
#                                are in place, so koto advances the panel with
#                                no spawn.
#   --recorded <panel> <session> the `<panel>_recorded` gate on the passed and
#                                blocking_retry edges. Exit 1 while a seat the
#                                scope spawned holds a verdict recorded before
#                                the scope was planned: this round was not
#                                recorded.
#   --verdict <panel> <session>  the `<panel>_verdict` gate: the panel's pass,
#                                computed from the ledger rather than reported
#                                by the agent (DESIGN-output-gates Decision 4).
#                                Exit 0 when every seat of the panel has a
#                                recorded verdict and none is blocking, 1 when
#                                a seat is blocking (one finding per blocking
#                                finding), 2 when the round is not fully
#                                recorded or the keys can't be read.
#   --record <panel> <session> <round-file>
#                                the agent, at aggregation, for every seat it
#                                spawned this round, passed or blocking. Stamps
#                                judged_at=HEAD and the criteria hash and merges
#                                the verdicts into the ledger. A seat's verdict
#                                is derived from its findings' severity.
#
# Usage: panel-scope.sh --plan    <panel> <koto-session-name>
#        panel-scope.sh --carried <panel> <koto-session-name>
#        panel-scope.sh --recorded <panel> <koto-session-name>
#        panel-scope.sh --verdict <panel> <koto-session-name>
#        panel-scope.sh --record  <panel> <koto-session-name> <round-file>
#
# <panel> is scrutiny, review, qa (the qa_validation state) or light (the
# light_review state, the `light` review level's one seat).
#
# ## The round file
#
# A JSON array, one object per spawned seat:
#
#   [{"seat": "completeness",
#     "cited": [{"path": "src/a.sh", "lines": "10-24"}, {"path": "README.md"}],
#     "findings": [{"severity": "blocking", "summary": "...",
#                   "path": "src/a.sh", "lines": "12-12"}]}]
#
# `cited` is what the seat judged: the paths and, where it can say, the line
# ranges ("N" or "N-M", in HEAD's numbering) its verdict rests on. Findings'
# locations are kept beside it, as `finding_locations`, so a seat that cited
# nothing still falls back to the whole diff it judged. Both carry forward from
# earlier rounds, so a seat's judged scope only grows; an earlier line range in
# a file that has changed since is carried as the bare path, because its
# numbers no longer name the same code.
#
# Every finding carries a `severity`, `blocking` or `advisory`, and a seat is
# recorded as blocking exactly when one of its findings is `blocking`. A finding
# with no severity, or any other value, makes --record refuse the whole round
# (65), so a seat can't be recorded as passing by leaving the field out.
# `blocking_count`, `passed` and any other summary field are ignored: the
# verdict is the findings', not the agent's count of them.
#
# ## Context keys
#
#   verdict_ledger.json   {"rev": N, "seats": {"<panel>/<seat>": {...}},
#                          "history": [{"panel", "round", "head", "rev",
#                          "spawned", "decisions": [{seat, decision, reason}]}]}
#                         Never cleared by a retry: it is what survives one.
#   <panel>_scope.json    this entry's decisions, for the agent to act on
#   <panel>_results.json  only when every seat is kept, read by --carried;
#                         otherwise the agent may write it at aggregation as
#                         the round's summary. No gate reads it for the pass:
#                         --verdict reads the ledger
#
# A `--plan` re-run at the same HEAD with no `--record` in between (a tick
# without evidence, say) replaces its own history entry instead of adding one,
# so the history counts rounds, not ticks. A --plan re-run at the same HEAD,
# on a clean tree and unchanged criteria, after every seat the round spawned
# was recorded and one of them blocked, leaves the scope as it is: that round
# is complete, and the <panel>_verdict gate reports its block.
#
# Diagnostics go to stderr. --plan prints the scope it wrote on stdout, for a
# human running it by hand; --verdict prints its findings on stdout; the other
# modes print nothing.
#
# --verdict prints one koto finding per blocking finding:
#   ::koto-finding::{"rule_id":"panel/blocking-finding","level":"error",
#                    "message":"<rule summary>: <panel>/<seat>: <summary>","path":"src/a.sh",
#                    "line":12,"rule_ref":"<path>#L<a>-L<b>@<revision>"}
# with the rule resolved through scripts/lib/rule-findings.sh, which exits 2 when
# it can't be; `path` and `line` only when the finding names them.
#
# Exit codes:
#   0   -- --plan/--record: written. --carried: every seat is kept.
#          --recorded: every spawned seat was recorded this round, or there is no
#          scope or ledger to check. --verdict: every seat of the panel has a
#          recorded verdict and none is blocking.
#   1   -- --carried: something has to run, the working tree is dirty, or
#          the scope is missing, stale, unreadable or has no carried results
#          beside it. --recorded: a spawned seat wasn't recorded this round,
#          or the keys can't be read. --verdict: a seat is blocking. --carried
#          and --recorded exit nothing else: a gate exit the template does not
#          route would hold the state, and the safe answer to every doubt is
#          "run the panel" or "record the round".
#   2   -- --verdict only, for every doubt it has: a seat the round's scope
#          spawned has no verdict recorded since the scope was planned, a seat
#          of the panel has no verdict at all, the ledger or the scope can't be
#          read, or a usage error. It is the first mode to use 2: a verdict it
#          can't compute holds the panel state, where a 1 would send the agent
#          to a retry or an escalation on a guess.
#   64  -- not a git repository, HEAD names no commit, or mktemp failed
#   65  -- a JSON step failed: --record's round file is missing, is not a
#          JSON array of seats, names a seat outside the panel, or holds a
#          finding whose severity is missing or is not `blocking` or
#          `advisory`, or (--plan or --record) jq could not merge the result
#          into the ledger
#   66  -- a `koto context add` failed; koto's own stderr says why
#   67  -- a mode, panel or argument is missing or unrecognised
#   68  -- --record only: HEAD moved since the panel's scope was planned, so
#          the round's verdicts are about a commit that is no longer HEAD
#   127 -- jq is not on PATH
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

THRESHOLD_LINES=200
LEDGER=verdict_ledger.json
# The one registry rule --verdict reports (references/rule-registry.json).
RULE_IDS="panel/blocking-finding"
# A ledger entry's blocking findings, as a jq expression over the entry. A
# finding with no severity counts: it comes from a ledger written before
# severity existed, when the agent listed only blocking findings. --record
# admits no such finding now.
BLOCKING_FINDINGS='(.findings // [])[] | select(type == "object" and ((.severity // "blocking") == "blocking"))'

die() {
    # $1 exit code, $2 message
    echo "panel-scope: $2" >&2
    exit "$1"
}

MODE="${1:-}"
PANEL="${2:-}"
SESSION="${3:-}"

# The gate modes answer every doubt, usage errors included, with one exit: 1
# for --carried and --recorded, 2 for --verdict. See Exit codes.
refuse() {
    # $1 exit code for the other modes, $2 message
    case "$MODE" in
        --carried|--recorded) echo "panel-scope: $2" >&2; exit 1 ;;
        --verdict) echo "panel-scope: $2" >&2; exit 2 ;;
    esac
    die "$1" "$2"
}

case "$MODE" in
    --plan|--carried|--recorded|--verdict|--record) ;;
    "") die 67 "missing mode: expected --plan, --carried, --recorded, --verdict or --record" ;;
    *)  die 67 "unrecognised mode [$MODE]: expected --plan, --carried, --recorded, --verdict or --record" ;;
esac

case "$PANEL" in
    scrutiny) SEATS="completeness justification intent" ;;
    review)   SEATS="pragmatic architect maintainer" ;;
    qa)       SEATS="tester" ;;
    light)    SEATS="reviewer" ;;
    "") refuse 67 "missing panel" ;;
    *)  refuse 67 "unrecognised panel [$PANEL]: expected scrutiny, review, qa or light" ;;
esac
[ -n "$SESSION" ] || refuse 67 "missing session argument for $MODE"
command -v jq >/dev/null || refuse 127 "jq not on PATH"

HEAD=$(git rev-parse --verify -q "HEAD^{commit}") \
    || refuse 64 "not a git repository, or HEAD names no commit"

# A missing key reads as empty. `koto context exists` exits 1, silently, for an
# absent key.
ctx_get() {
    if koto context exists "$SESSION" "$1"; then
        koto context get "$SESSION" "$1"
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
        and all(.decisions[]; .decision == "keep")' >/dev/null \
        || refuse 1 "${PANEL}_scope.json does not keep every seat at HEAD"
    koto context exists "$SESSION" "${PANEL}_results.json" \
        || refuse 1 "every seat is kept but ${PANEL}_results.json is absent"
    exit 0
fi

# ---------------------------------------------------------------- --recorded --

# Refuses while a seat this round spawned still holds a verdict recorded
# before the scope was planned: that is a round whose --record was skipped,
# and the seat's old verdict -- a pass, possibly, for a seat that has just
# blocked -- would be read as current next round. A spawned seat with no entry
# at all passes: skipping its record costs a full review next round, never a
# wrong carry. No scope passes too, with nothing to compare.
#
# HEAD moving while the panel is open is --record's concern, not this gate's:
# --record refuses to stamp a round across a moved HEAD (68), and a round
# recorded before the move keeps its own judged_at, so the next round's fix
# diff includes the commit no seat saw.
if [ "$MODE" = "--recorded" ]; then
    scope=$(ctx_get "${PANEL}_scope.json")
    [ -n "$scope" ] || exit 0
    ledger=$(ctx_get "$LEDGER")
    [ -n "$ledger" ] || exit 0
    # Compared by ledger revision, not by commit: a panel re-entered at an
    # unchanged HEAD (a fix left uncommitted, say) would otherwise find the
    # seat's previous verdict already "at HEAD" and let a skipped record by.
    stale=$(jq -nr --argjson s "$scope" --argjson l "$ledger" --arg panel "$PANEL" '
        [$s.decisions[] | select(.decision != "keep") | .seat
         | select(($l.seats[$panel + "/" + .] // null) as $e
                  | $e != null and (($e.rev // -1) <= ($s.rev // -1)))] | join(" ")') \
        || refuse 1 "could not read ${PANEL}_scope.json or $LEDGER"
    [ -z "$stale" ] || refuse 1 "no verdict recorded this round for: $stale (run panel-scope.sh --record $PANEL)"
    exit 0
fi

# ---------------------------------------------------------------- --verdict ---

# The panel's pass, from the ledger. Unlike --recorded, a spawned seat with no
# entry at all holds here: --recorded only stops a stale verdict from being
# read as this round's, while this gate has to have a verdict for every seat
# before it can say the panel passed. With no scope (the --plan fallback path)
# there is nothing to date the verdicts against, so only their presence is
# checked.
if [ "$MODE" = "--verdict" ]; then
    # The rule resolves before the ledger is read, so a registry problem holds
    # the gate whether or not a seat is blocking.
    undecided() { refuse 2 "$*"; }
    # shellcheck source=../../../scripts/lib/rule-findings.sh
    . "$(cd "$(dirname "$0")" && pwd)/../../../scripts/lib/rule-findings.sh" || undecided "cannot load scripts/lib/rule-findings.sh"
    rf_require panel/blocking-finding
    ledger=$(ctx_get "$LEDGER")
    [ -n "$ledger" ] || refuse 2 "no $LEDGER: no $PANEL seat has a recorded verdict (run panel-scope.sh --record $PANEL)"
    printf '%s' "$ledger" | jq -e 'type == "object"' >/dev/null \
        || refuse 2 "$LEDGER is unreadable"
    scope=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$scope" ]; then
        unrecorded=$(jq -nr --argjson s "$scope" --argjson l "$ledger" --arg panel "$PANEL" '
            [$s.decisions[] | select(.decision != "keep") | .seat
             | select(($l.seats[$panel + "/" + .] // null) as $e
                      | $e == null or (($e.rev // -1) <= ($s.rev // -1)))] | join(" ")') \
            || refuse 2 "could not read ${PANEL}_scope.json against $LEDGER"
        [ -z "$unrecorded" ] \
            || refuse 2 "no verdict recorded since ${PANEL}_scope.json was planned for: $unrecorded (run panel-scope.sh --record $PANEL)"
    fi
    missing=""
    for seat in $SEATS; do
        v=$(printf '%s' "$ledger" | jq -r --arg k "$PANEL/$seat" '.seats[$k].verdict // empty') \
            || refuse 2 "$LEDGER is unreadable"
        case "$v" in passed|blocking) ;; *) missing="$missing $seat" ;; esac
    done
    [ -z "$missing" ] || refuse 2 "no verdict on record for$missing (run panel-scope.sh --record $PANEL)"

    ref=$(rf_ref panel/blocking-finding) || exit 2
    summary=$(rf_summary panel/blocking-finding) || exit 2
    # One finding per blocking finding. A seat recorded as blocking with no
    # finding marked blocking (a ledger from before severity) still blocks, and
    # gets one finding naming the seat. The message is the rule's summary, then
    # the panel, seat and the seat's own summary, control characters replaced:
    # the same shape rf_finding in scripts/lib/rule-findings.sh builds, built
    # here because one ledger read yields every finding. rf_emit refuses a line
    # that strays from it.
    findings=$(printf '%s' "$ledger" | jq -c --arg panel "$PANEL" --arg seats "$SEATS" --arg ref "$ref" \
        --arg rule_summary "$summary" \
        "def blocking_findings: [$BLOCKING_FINDINGS];"'
        [($seats | split(" "))[] as $seat
         | (.seats[$panel + "/" + $seat]) as $e
         | select($e.verdict == "blocking")
         | ($e | blocking_findings) as $bf
         | if ($bf | length) > 0 then ($bf[] | {seat: $seat, f: .})
           else {seat: $seat, f: {summary: "recorded as blocking, with no finding marked blocking"}} end]
        | .[]
        | ((.f.lines // "") | tostring | (capture("^(?<n>[1-9][0-9]*)") // null)) as $line
        | {rule_id: "panel/blocking-finding", level: "error",
           message: ($rule_summary + ": "
                     + (($panel + "/" + .seat + ": " + ((.f.summary // "a blocking finding") | tostring))
                        | gsub("[\u0000-\u001f\u007f]"; " ")))}
          + (if (.f.path | type) == "string" and .f.path != "" then {path: .f.path}
               + (if $line != null then {line: ($line.n | tonumber)} else {} end)
             else {} end)
          + {rule_ref: $ref}') \
        || refuse 2 "could not read the blocking findings in $LEDGER"
    [ -n "$findings" ] || exit 0
    while IFS= read -r f; do
        rf_emit "$f"
    done <<EOF
$findings
EOF
    exit 1
fi

WORK=$(mktemp -d) || die 64 "could not create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

AC_SHA=$( { ctx_get context.md; printf '\n--- plan ---\n'; ctx_get plan.md; } | git hash-object --stdin)

LEDGER_JSON=$(ctx_get "$LEDGER")
if [ -z "$LEDGER_JSON" ] || ! printf '%s' "$LEDGER_JSON" | jq -e 'type == "object"' >/dev/null; then
    [ -n "$LEDGER_JSON" ] && echo "panel-scope: $LEDGER is unreadable; starting a new ledger" >&2
    LEDGER_JSON='{"rev": 0, "seats": {}, "history": []}'
fi

put() {
    # $1 key, $2 file
    koto context add "$SESSION" "$1" < "$2" >/dev/null \
        || die 66 "koto context add failed for $1 on session [$SESSION]"
}

# The decider shadow for the round just recorded: review-shadow.py's site
# command reads these verdicts from the ledger and records the decider's beside
# them (docs/designs/DESIGN-jev-closed-criteria.md). It runs in the background
# with its output discarded, so --record's status, ledger and timing are what
# they would be without it; it runs whether or not REVIEW_SHADOW_SITES opts in,
# because the site command records an unset opt-in rather than staying silent.
# REVIEW_SHADOW_SITE_CMD replaces the command, for tests.
shadow_site() {
    local cmd root
    case "$PANEL" in scrutiny|review|light) ;; *) return 0 ;; esac
    # This script lives at skills/work-on/scripts/ under the plugin root.
    cmd="${REVIEW_SHADOW_SITE_CMD:-$(cd "$(dirname "$0")/../../.." && pwd)/scripts/review-shadow/review-shadow.py}"
    [ -x "$cmd" ] || return 0
    # A stand-in command needs no python3; the real script does.
    [ -n "${REVIEW_SHADOW_SITE_CMD:-}" ] || command -v python3 >/dev/null 2>&1 || return 0
    # HEAD resolved above, so this is a work tree and the call can't fail here.
    root=$(git rev-parse --show-toplevel) || return 0
    # The shadow's own output is discarded on purpose: nothing reads it, and its
    # result is the record it writes.
    ( "$cmd" site work-on --session "$SESSION" --panel "$PANEL" --head "$HEAD" --repo-path "$root" \
        </dev/null >/dev/null 2>&1 & )
    return 0
}

# ---------------------------------------------------------------- --record ----

if [ "$MODE" = "--record" ]; then
    ROUND_FILE="${4:-}"
    # The seats judged the commit the scope was planned at. If HEAD has moved
    # since, stamping their verdicts with it would vouch for a commit none of
    # them saw. No scope (the --plan fallback path) has nothing to compare.
    scope_head=$(ctx_get "${PANEL}_scope.json" | jq -r '.head // empty')
    [ -z "$scope_head" ] || [ "$scope_head" = "$HEAD" ] \
        || die 68 "HEAD moved since ${PANEL}_scope.json was planned at $scope_head; tick koto without evidence to re-plan, then run the round again"
    [ -n "$ROUND_FILE" ] || die 67 "missing round file for --record"
    [ -f "$ROUND_FILE" ] || die 65 "round file [$ROUND_FILE] not found"
    jq -e 'type == "array" and length > 0 and all(.[]; (.seat | type) == "string")' \
        "$ROUND_FILE" >/dev/null \
        || die 65 "round file [$ROUND_FILE] is not a JSON array of seats"
    for s in $(jq -r '.[].seat' "$ROUND_FILE"); do
        case " $SEATS " in
            *" $s "*) ;;
            *) die 65 "seat [$s] is not a $PANEL seat (expected one of: $SEATS)" ;;
        esac
    done
    # The verdict is derived from severity below, so a finding without one
    # would be counted as advisory by omission. Refuse the round instead.
    unsevered=$(jq -r '[.[] | .seat as $s | (.findings // [])
            | if type == "array" then .[] else "not-an-array" end
            | select(type != "object" or (.severity != "blocking" and .severity != "advisory"))
            | $s] | unique | join(" ")' "$ROUND_FILE") \
        || die 65 "could not read the findings in round file [$ROUND_FILE]"
    [ -z "$unsevered" ] \
        || die 65 "round file [$ROUND_FILE]: a finding of seat(s) [$unsevered] has no severity, or one that is not blocking or advisory"
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
                verdict: (if any(($s.findings // [])[]; .severity == "blocking")
                          then "blocking" else "passed" end),
                judged_at: $head,
                rev: .rev,
                ac_sha: $ac,
                cited: ($old_cited + (($s.cited // []) | norm) | unique),
                finding_locations: ($old_locs
                    + ([($s.findings // [])[] | select(.path) | {path, lines}] | norm) | unique),
                findings: ($s.findings // [])
              })' > "$WORK/ledger" || die 65 "could not merge [$ROUND_FILE] into the ledger"
    put "$LEDGER" "$WORK/ledger"
    shadow_site
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
# since impl_base, or none recorded, means there is nothing to have passed:
# the has_commits gate on scrutiny's passed edge holds, and a carried verdict
# must not slip past it.
DIRTY=""
[ -n "$(git status --porcelain | head -1)" ] && DIRTY=1
NOCOMMITS=""
if [ -z "$IMPL_BASE" ] || [ "$(git rev-list --count "$IMPL_BASE..HEAD" || echo 0)" = 0 ]; then
    NOCOMMITS=1
fi

# A blocking round already recorded at this HEAD is not planned again. koto
# runs --plan on every tick that carries no evidence, and the agent ticks with
# none once the round is recorded, so the <panel>_verdict gate can route it. A
# fresh plan there would turn the seat that just blocked into a new round's
# recheck, with no fix to re-check, and --verdict would hold the panel (exit 2)
# on a round that is complete instead of reporting the block (exit 1). The
# scope stands while HEAD, a clean tree and the criteria are what the round
# was recorded against, every seat it spawned has a verdict recorded since it
# was planned, and one of them is blocking. Anything else plans as before: a
# commit, an uncommitted change, rewritten criteria or a seat still unrecorded
# start a new round, and a recorded round with no blocking seat re-plans to
# keep every seat, which is the carried route.
if [ -z "$DIRTY" ]; then
    prev_scope=$(ctx_get "${PANEL}_scope.json")
    if [ -n "$prev_scope" ] && [ "$(jq -n --argjson s "$prev_scope" --argjson l "$LEDGER_JSON" \
            --arg panel "$PANEL" --arg head "$HEAD" --arg ac "$AC_SHA" '
            [$s.decisions[] | select(.decision != "keep") | $l.seats[$panel + "/" + .seat] // null] as $spawned
            | $s.head == $head
              and ($spawned | length > 0)
              and all($spawned[]; . != null and ((.rev // -1) > ($s.rev // -1)) and .ac_sha == $ac)
              and any($spawned[]; .verdict == "blocking")')" = true ]; then
        echo "panel-scope: the $PANEL round planned at $(printf '%.12s' "$HEAD") is recorded with a blocking seat; its scope stands" >&2
        printf '%s\n' "$prev_scope"
        exit 0
    fi
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
        # The blocking findings only: an advisory one is not what the seat
        # blocked on, and a re-check is about what it blocked on. A finding
        # with no severity is from a ledger written before severity existed,
        # when every recorded finding was a blocking one.
        nfind=$(printf '%s' "$entry" | jq "[$BLOCKING_FINDINGS] | length")
        # A blocking seat goes through the same invalidation checks as a
        # passed one before it is offered the narrow re-check: a re-check that
        # passes stamps the seat passed at HEAD, so anything that would make a
        # passed seat re-run must not reach it disguised as a fix.
        if [ "$verdict" = "blocking" ] && [ "$nfind" -eq 0 ]; then
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
            if [ "$verdict" = "blocking" ]; then
                if [ "$changed" -gt "$THRESHOLD_LINES" ]; then
                    decision=rerun
                    reason="raised $nfind blocking finding(s) at $short, but the fix diff changes $changed lines, over the $THRESHOLD_LINES-line threshold"
                else
                    decision=recheck
                    reason="raised $nfind blocking finding(s) at $short; re-check them against the fix diff ($changed lines in $nfiles files)"
                fi
            else
                # The seat's own citations decide whether it fell back to the diff
                # it judged; the locations of findings it raised are added either
                # way, so a fix near a finding re-checks the seat that raised it.
                printf '%s' "$entry" | jq -r '.cited[]? | [.path, (.lines // "" | tostring)] | @tsv' > "$WORK/cited"
                cited_what="what it cited"
                if [ ! -s "$WORK/cited" ]; then
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
    fi
    # scripts/review-packet.sh recheck reads a recheck decision's `findings`
    # and `fix_diff_from` to build that seat's packet, and relies on
    # fix_diff_from being an ancestor of HEAD (checked above). Renaming either
    # field, or offering recheck on a commit off HEAD's history, changes what
    # that packet holds; panel-scope_test.sh drives the two scripts together.
    jq -nc --arg seat "$seat" --arg d "$decision" --arg r "$reason" --argjson e "${entry:-null}" \
        "def blocking_findings: [$BLOCKING_FINDINGS];"'
        {seat: $seat, decision: $d, reason: $r}
        + (if $d == "recheck" then {findings: ($e | blocking_findings), fix_diff_from: $e.judged_at} else {} end)
        + (if $d == "rerun" or $d == "keep" then {judged_at: $e.judged_at} else {} end)
        ' >> "$WORK/decisions"
    entry=""
done

jq -s --arg panel "$PANEL" --arg head "$HEAD" --argjson rev "$(printf '%s' "$LEDGER_JSON" | jq '.rev // 0')" \
    '{panel: $panel, head: $head, rev: $rev, decisions: .}' \
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

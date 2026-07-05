#!/usr/bin/env bash
#
# work-summary.sh - Single reusable "work in flight" summary component.
#
# Owns capture (parsing PR identity from `gh` command output into a private
# per-session ledger), a two-level emission gate, and rendering the standardized
# summary block from the ledger plus live `gh` reads. It is the single
# implementation invoked by both the /inflight skill (via ${CLAUDE_PLUGIN_ROOT})
# and, later, by thin dot-niwa hooks (via a niwa-injected absolute path exposed
# as the env var SHIRABE_WORK_SUMMARY). Its CLI is therefore a cross-layer
# contract: keep the entrypoint path and subcommand signatures stable.
#
# FAIL-SAFE CONTRACT: every invocation exits 0 on any non-fatal error. It must
# never abort a hook or turn. Errors degrade to "no output" or a best-effort
# block, never to a non-zero exit.
#
# Requires: bash (>=4.3 for namerefs), jq, gh, flock, sha256sum (coreutils),
# sed, awk, grep, date.
#
# Subcommands (each takes --session <id>):
#   capture   - read PostToolUse hook JSON on stdin; append a captured PR URL to
#               the ledger, then run the gate and emit the block if it changed.
#   render    - always render the current block from the ledger, refreshing each
#               item's live state; ends with a freshness line. Empty ledger =>
#               no output.
#   absence   - UserPromptSubmit path; emit the block if idle beyond the absence
#               threshold and the ledger is non-empty.
#   compact   - SessionStart(compact) path; emit the block if the ledger is
#               non-empty (caller wraps as additionalContext-only).
#   help      - print the block format spec (single source of truth).
#
# Environment:
#   WS_RENDER_INTERVAL   second-level gate interval, seconds (default 300)
#   WS_ABSENCE_THRESHOLD absence threshold, seconds (default 1800)
#   GH                   override the `gh` binary (test seam; default "gh")
#   WS_STORE_DIR         override the store directory (test seam; default is the
#                        pinned per-user runtime path below)
#   WS_NOW               override "now" as a unix epoch (test seam)
#
# Store dir: ${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/shirabe-work-summary
#   created mode 0700, files 0600, symlinked store dir refused.
# Ledger: <store>/<sid>.ledger  rows: repo\tnumber\turl\tfirst_seen\tterminal_shown
# State:  <store>/<sid>.state   keys: last_emitted_ledger_hash, last_rendered_hash,
#                                     last_render_ts, last_activity
#
# Exit codes: always 0 (fail-safe).

# --- constants -------------------------------------------------------------

MARKER='=== WORK IN FLIGHT ==='

# US (unit separator, 0x1f) is the field delimiter we `read` on. @tsv escapes
# any tab/newline in the data and emits exactly four separator tabs; we convert
# only those separator tabs to US before reading. A non-whitespace delimiter is
# required because `read` collapses runs of IFS-whitespace (tab/space/newline),
# which would drop an empty reviewDecision field and shift the title.
US=$'\x1f'

# jq program: given `gh pr view --json state,isDraft,statusCheckRollup,
# reviewDecision,title` output, emit a TSV row:
#   state <TAB> isDraft <TAB> ci-rollup <TAB> reviewDecision <TAB> title
# The CI rollup normalizes both CheckRun (status/conclusion) and StatusContext
# (state) shapes into failing/pending/passing/"".
JQ_PROG='
def norm:
  if (.conclusion // "") != "" then
     (.conclusion|ascii_upcase) as $c
     | (if (["FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"]|index($c)) then "fail"
        elif ((.status // "COMPLETED")|ascii_upcase) != "COMPLETED" then "pending"
        else "pass" end)
  elif (.state // "") != "" then
     (.state|ascii_upcase) as $s
     | (if (["FAILURE","ERROR"]|index($s)) then "fail"
        elif (["PENDING","EXPECTED"]|index($s)) then "pending"
        else "pass" end)
  elif (.status // "") != "" then
     (if (.status|ascii_upcase) != "COMPLETED" then "pending" else "pass" end)
  else "pass" end;
([ (.statusCheckRollup // [])[] | norm ]) as $c
| (if ($c|index("fail")) then "failing"
   elif ($c|index("pending")) then "pending"
   elif (($c|length) > 0) then "passing"
   else "" end) as $ci
| [ (.state // ""), (.isDraft|tostring), $ci, (.reviewDecision // ""), (.title // "") ]
| @tsv
'

# --- small utilities -------------------------------------------------------

sha256() { sha256sum | awk '{print $1}'; }

# Dedup hash of a rendered block for the emission gate. Hashes ONLY the PR-line
# CONTENT: the volatile "updated <ISO>" freshness line and the offline
# "(best-effort: live state unavailable)" marker line are excluded, so a stable
# summary with no state change is not re-emitted every WS_RENDER_INTERVAL merely
# because its timestamp advanced. The timestamp stays in the DISPLAYED block
# (user-facing); it is kept out of the dedup key only.
block_dedup_hash() {
    printf '%s' "$1" \
        | grep -vE '^updated ' \
        | grep -vxF '(best-effort: live state unavailable)' \
        | sha256
}

ws_now() {
    if [[ -n "${WS_NOW:-}" ]]; then
        printf '%s' "$WS_NOW"
    else
        date +%s
    fi
}

ws_iso() {
    if [[ -n "${WS_NOW:-}" ]]; then
        date -u -d "@${WS_NOW}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ
    else
        date -u +%Y-%m-%dT%H:%M:%SZ
    fi
}

# Validate a session id before it composes any path (reject otherwise).
validate_sid() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# Anchored PR URL validation. owner/repo per the F2 GitHub charset (alphanumeric
# first char, then [A-Za-z0-9._-]). The alphanumeric-first anchor prevents an
# extracted owner/repo from being read as a `gh` flag.
validate_pr_url() {
    [[ "$1" =~ ^https://github\.com/[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*/pull/[0-9]+$ ]]
}

# Extract the first valid anchored PR URL from surrounding text (stdout scrape
# for capture only). Rejects (does not sanitize) a non-match; the anchored
# grep pattern also rejects the `git push` /pull/new/ hint by construction.
extract_pr_url() {
    local text="$1" cand
    cand=$(printf '%s' "$text" \
        | grep -oE 'https://github\.com/[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*/pull/[0-9]+' \
        | head -1) || true
    [[ -z "$cand" ]] && return 1
    validate_pr_url "$cand" || return 1
    printf '%s' "$cand"
}

# Terminal-safety sanitizer. Every gh-sourced field (especially PR title) passes
# through this before entering the block.
#   1. Strip ANSI CSI escape sequences (7-bit ESC[ form) FIRST.
#   2. Strip C1 controls (U+0080-U+009F) encoded as valid UTF-8 two-byte
#      sequences (0xC2 0x80 .. 0xC2 0x9F). These pass a C0-only filter yet drive
#      OSC-8 hyperlinks / cursor moves on terminals honoring 8-bit C1. Done
#      before the raw-byte pass so the lead 0xC2 is removed with its payload.
#   3. Strip C0 controls, DEL, and any RAW C1 bytes (0x80-0x9F). Raw C1
#      stripping is defense-in-depth for 8-bit / non-UTF-8 terminals; it may
#      also drop a stray UTF-8 continuation byte, an acceptable trade for a
#      terminal-safety filter over a truncated summary title.
#   4. Remove the `|` cell separator.
#   5. Forbid the literal marker substring (so a crafted title cannot forge rows
#      or inject a second marker).
#   6. Truncate to ~50 chars LAST (strip-before-truncate: all control stripping
#      runs BEFORE truncation so a boundary split cannot leave a live sequence).
sanitize() {
    local s="$1"
    s=$(printf '%s' "$s" | LC_ALL=C sed -E $'s/\x1b\\[[0-9;?=]*[A-Za-z]//g')
    s=$(printf '%s' "$s" | LC_ALL=C sed -E $'s/\xc2[\x80-\x9f]//g')
    s=$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\037\177\200-\237')
    s=${s//|/}
    s=${s//"$MARKER"/}
    if (( ${#s} > 50 )); then
        s=${s:0:50}
    fi
    printf '%s' "$s"
}

# Detect a command that actually INVOKES `gh ... pr create`. This gates only
# whether capture scrapes stdout at all; the anchored URL validation remains the
# real security boundary.
#
# Heuristic: split the command on shell boundaries (; | & and their doubled
# forms, plus newlines), and for each segment strip leading `VAR=val `
# env-assignments, then require the segment to START with the `gh` command and
# to contain `pr` and `create` (in that order) as bare, whitespace-delimited
# argv tokens -- NOT inside a quoted string. This rejects the obvious false
# positives where `gh pr create` is data rather than the invoked command, e.g.
# `grep 'gh pr create' notes.txt`, `cat gh-pr-create.log`, `echo gh pr create`.
#
# Residual (documented, accepted): this is not a real shell parser. `gh` reached
# via an alias/function, or `pr`/`create` assembled from variables, may be
# missed; a contrived unquoted `gh ... pr ... create` in a non-invoking position
# may be mis-detected. Both are acceptable: the result only decides whether to
# ATTEMPT a stdout scrape, and every captured URL is anchor-validated before use.
is_pr_create() {
    local cmd="$1" seg
    local -a segs=()
    # Over-splitting is safe: each segment is validated independently below.
    mapfile -t segs < <(printf '%s\n' "$cmd" | tr ';|&' '\n\n\n')
    for seg in "${segs[@]}"; do
        # Strip leading whitespace.
        seg="${seg#"${seg%%[![:space:]]*}"}"
        # Strip any run of leading VAR=val env-assignments.
        while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
            seg="${seg#"${BASH_REMATCH[0]}"}"
        done
        # The leading token must be exactly the `gh` command.
        [[ "$seg" =~ ^gh([[:space:]]|$) ]] || continue
        # Drop single/double-quoted spans so a quoted `pr create` is not counted
        # as argv tokens, then require pr then create as bare tokens.
        local bare
        bare=$(printf '%s' "$seg" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
        local -a toks=()
        read -ra toks <<< "$bare"
        local pr_i=-1 cr_i=-1 j
        for j in "${!toks[@]}"; do
            if [[ "${toks[$j]}" == "pr" && $pr_i -lt 0 ]]; then pr_i=$j; fi
            if [[ "${toks[$j]}" == "create" && $pr_i -ge 0 && $cr_i -lt 0 ]]; then cr_i=$j; fi
        done
        if (( pr_i >= 0 && cr_i > pr_i )); then
            return 0
        fi
    done
    return 1
}

# --- storage ---------------------------------------------------------------

# Resolve (and create) the store dir. Refuses a symlinked store dir. Returns the
# path on stdout, non-zero on failure.
ensure_store() {
    local dir
    dir="${WS_STORE_DIR:-${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/shirabe-work-summary}"
    if [[ -L "$dir" ]]; then
        return 1
    fi
    mkdir -p "$dir" 2>/dev/null || return 1
    chmod 0700 "$dir" 2>/dev/null || true
    printf '%s' "$dir"
}

ledger_path() { printf '%s/%s.ledger' "$1" "$2"; }

# Defense-in-depth: refuse to operate through a symlinked per-session file. The
# store dir is already symlink-checked, but the ledger/state/lock files are
# opened with plain `>>`/`>`/`9>` redirections that would otherwise follow a
# symlink to write outside the store. Same-user threat model; a check here plus
# the 0700 store dir is enough. TOCTOU-tolerant on purpose: we are not defending
# against the same user actively racing us, only against a pre-planted symlink.
refuse_symlinked_files() {
    local store="$1" sid="$2" p
    for p in "$store/$sid.ledger" "$store/$sid.state" "$store/$sid.lock"; do
        [[ -L "$p" ]] && return 1
    done
    return 0
}

# Hash of ledger contents (stable hash of "" when the ledger does not exist).
ledger_hash() {
    local f="$1"
    if [[ -f "$f" ]]; then
        sha256sum "$f" | awk '{print $1}'
    else
        printf '' | sha256
    fi
}

# State is read into globals ST_LE / ST_LR / ST_LTS / ST_LA and written back
# wholesale. All callers hold the session flock.
read_state() {
    local f="$1/$2.state" k v
    ST_LE=""; ST_LR=""; ST_LTS="0"; ST_LA="0"
    [[ -f "$f" ]] || return 0
    while IFS='=' read -r k v; do
        case "$k" in
            last_emitted_ledger_hash) ST_LE="$v" ;;
            last_rendered_hash)       ST_LR="$v" ;;
            last_render_ts)           ST_LTS="$v" ;;
            last_activity)            ST_LA="$v" ;;
        esac
    done < "$f"
}

write_state() {
    local f="$1/$2.state"
    {
        printf 'last_emitted_ledger_hash=%s\n' "$ST_LE"
        printf 'last_rendered_hash=%s\n' "$ST_LR"
        printf 'last_render_ts=%s\n' "$ST_LTS"
        printf 'last_activity=%s\n' "$ST_LA"
    } > "$f" 2>/dev/null || true
    chmod 0600 "$f" 2>/dev/null || true
}

# Append a captured PR URL to the ledger, dedup by URL. repo/number are derived
# from the already-validated URL.
append_ledger() {
    local store="$1" sid="$2" url="$3"
    local ledger; ledger=$(ledger_path "$store" "$sid")
    if [[ -f "$ledger" ]] && cut -f3 "$ledger" 2>/dev/null | grep -qxF "$url"; then
        return 0
    fi
    local rest owner repo number now
    rest="${url#https://github.com/}"
    owner="${rest%%/*}"; rest="${rest#*/}"
    repo="${rest%%/*}"
    number="${url##*/}"
    now=$(ws_now)
    printf '%s\t%s\t%s\t%s\t%s\n' "$owner/$repo" "$number" "$url" "$now" "0" >> "$ledger"
    chmod 0600 "$ledger" 2>/dev/null || true
}

# --- gh access -------------------------------------------------------------

# Read-only gh view of a single PR as JSON. argv array, never a shell string;
# never interpolate an extracted value into eval/sh -c/backticks.
gh_view_json() {
    local url="$1"
    "${GH_BIN}" pr view "$url" \
        --json state,isDraft,statusCheckRollup,reviewDecision,title 2>/dev/null
}

# --- rendering -------------------------------------------------------------

# Best-effort, ledger-only block when live gh state is unreachable (R13).
render_offline() {
    local ledger="$1"
    local c_repo c_num c_url c_seen c_shown
    printf '%s\n' "$MARKER"
    printf '(best-effort: live state unavailable)\n'
    while IFS=$'\t' read -r c_repo c_num c_url c_seen c_shown; do
        [[ -z "$c_url" ]] && continue
        printf '%s#%s | unknown | | %s\n' "$c_repo" "$c_num" "$c_url"
    done < "$ledger"
    printf 'updated %s\n' "$(ws_iso)"
}

# Rewrite the ledger with updated terminal_shown flags. Caller holds the lock.
persist_ledger() {
    local ledger="$1"
    local -n _repo=$2 _num=$3 _url=$4 _seen=$5 _shown=$6
    local tmp i
    tmp=$(mktemp 2>/dev/null) || return 0
    for (( i=0; i<${#_url[@]}; i++ )); do
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "${_repo[$i]}" "${_num[$i]}" "${_url[$i]}" "${_seen[$i]}" "${_shown[$i]}" >> "$tmp"
    done
    mv "$tmp" "$ledger" 2>/dev/null || rm -f "$tmp"
    chmod 0600 "$ledger" 2>/dev/null || true
}

# Render the current block to stdout from the ledger + live gh reads. Caller
# holds the lock. Empty ledger => no output.
#
# Third arg `consume` (default 1) selects the AMBIENT vs ON-DEMAND semantics:
#   consume=1 (ambient: capture/absence/compact) -- honors terminal-drop (R3):
#     excludes a terminal PR already shown once, marks newly-shown terminal PRs,
#     and rewrites the ledger's terminal_shown flags.
#   consume=0 (on-demand: /inflight render) -- a pure READ: shows current
#     terminal PRs WITHOUT marking them shown and WITHOUT rewriting the ledger,
#     so repeated on-demand renders are idempotent and never consume R3's single
#     post-transition showing that the ambient paths own.
render_block() {
    local store="$1" sid="$2" consume="${3:-1}"
    local ledger; ledger=$(ledger_path "$store" "$sid")
    [[ -s "$ledger" ]] || return 0

    local -a a_repo=() a_num=() a_url=() a_seen=() a_shown=()
    local c_repo c_num c_url c_seen c_shown
    while IFS=$'\t' read -r c_repo c_num c_url c_seen c_shown; do
        [[ -z "$c_url" ]] && continue
        a_repo+=("$c_repo"); a_num+=("$c_num"); a_url+=("$c_url")
        a_seen+=("$c_seen"); a_shown+=("${c_shown:-0}")
    done < "$ledger"

    local n=${#a_url[@]}
    (( n == 0 )) && return 0

    local offline=0
    local -a new_shown=("${a_shown[@]}")
    local -a o_line=() o_bucket=() o_seen=()
    local i
    for (( i=0; i<n; i++ )); do
        local json parsed
        json=$(gh_view_json "${a_url[$i]}") || { offline=1; break; }
        [[ -z "$json" ]] && { offline=1; break; }
        parsed=$(printf '%s' "$json" | jq -r "$JQ_PROG" 2>/dev/null | tr '\t' "$US") \
            || { offline=1; break; }
        [[ -z "$parsed" ]] && { offline=1; break; }

        local st isd ci rev title
        IFS="$US" read -r st isd ci rev title <<< "$parsed"
        st=${st^^}

        local terminal=0
        [[ "$st" == "MERGED" || "$st" == "CLOSED" ]] && terminal=1

        # terminal-drop (ambient only): a terminal PR already shown once is
        # excluded. On-demand render (consume=0) never drops, so an explicit
        # read always reflects the current terminal PRs.
        if (( consume )) && (( terminal )) && [[ "${a_shown[$i]}" == "1" ]]; then
            continue
        fi

        local base
        if   [[ "$st" == "MERGED" ]]; then base="merged"
        elif [[ "$st" == "CLOSED" ]]; then base="closed"
        elif [[ "$isd" == "true" ]];  then base="draft"
        else base="open"; fi

        # R2: every entry carries a status indication. Terminal PRs carry it
        # via their base token (merged/closed); non-terminal PRs always show a
        # ci:* token, falling back to ci:none when the rollup is empty.
        local tokens="$base"
        if (( ! terminal )); then
            if [[ -n "$ci" ]]; then
                tokens="$tokens ci:$ci"
            else
                tokens="$tokens ci:none"
            fi
        fi
        local rvu="${rev^^}"
        if   [[ "$rvu" == "CHANGES_REQUESTED" ]]; then tokens="$tokens review:changes_requested"
        elif [[ "$rvu" == "APPROVED" ]];          then tokens="$tokens review:approved"; fi

        # attention-first buckets: 1=needs attention, 2=in progress, 3=settled.
        local bucket=2
        if (( terminal )); then
            bucket=3
        elif [[ "$ci" == "failing" || "$rvu" == "CHANGES_REQUESTED" ]]; then
            bucket=1
        fi

        local stitle; stitle=$(sanitize "$title")
        o_line+=("$(printf '%s#%s | %s | %s | %s' \
            "${a_repo[$i]}" "${a_num[$i]}" "$tokens" "$stitle" "${a_url[$i]}")")
        o_bucket+=("$bucket")
        local seenv="${a_seen[$i]:-0}"
        [[ "$seenv" =~ ^[0-9]+$ ]] || seenv=0
        o_seen+=("$seenv")

        if (( consume )) && (( terminal )) && [[ "${a_shown[$i]}" != "1" ]]; then
            new_shown[$i]=1
        fi
    done

    if (( offline )); then
        render_offline "$ledger"
        return 0
    fi

    (( consume )) && persist_ledger "$ledger" a_repo a_num a_url a_seen new_shown

    local m=${#o_line[@]}
    (( m == 0 )) && return 0

    # Stable order by bucket, then first_seen, then original index.
    local -a keyed=()
    for (( i=0; i<m; i++ )); do
        keyed+=("$(printf '%d|%020d|%d' "${o_bucket[$i]}" "${o_seen[$i]}" "$i")")
    done
    local -a sorted=()
    mapfile -t sorted < <(printf '%s\n' "${keyed[@]}" | sort -t'|' -k1,1n -k2,2n -k3,3n)

    local sectioned=0
    (( m > 6 )) && sectioned=1

    printf '%s\n' "$MARKER"
    local last_bucket="" s bkt orig
    for s in "${sorted[@]}"; do
        bkt="${s%%|*}"
        orig="${s##*|}"
        if (( sectioned )) && [[ "$bkt" != "$last_bucket" ]]; then
            case "$bkt" in
                1) printf '## Needs attention\n' ;;
                2) printf '## In progress\n' ;;
                3) printf '## Recently settled\n' ;;
            esac
            last_bucket="$bkt"
        fi
        printf '%s\n' "${o_line[$orig]}"
    done
    printf 'updated %s\n' "$(ws_iso)"
}

# --- subcommands (each runs under the session flock) -----------------------

_capture_locked() {
    local sid="$1" store="$2"
    read_state "$store" "$sid"
    local now; now=$(ws_now)

    local input command stdout
    input=$(cat)
    command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || command=""
    stdout=$(printf '%s' "$input" | jq -r '.tool_response.stdout // ""' 2>/dev/null) || stdout=""

    if is_pr_create "$command"; then
        local url
        url=$(extract_pr_url "$stdout") || url=""
        if [[ -n "$url" ]]; then
            append_ledger "$store" "$sid" "$url"
        fi
    fi

    # Always refresh last_activity, even on a suppressed fire.
    ST_LA="$now"

    local ledger; ledger=$(ledger_path "$store" "$sid")
    local lh_before; lh_before=$(ledger_hash "$ledger")

    if [[ "$lh_before" != "$ST_LE" ]]; then
        # Cheap level: ledger changed -> render and emit.
        local block; block=$(render_block "$store" "$sid")
        [[ -n "$block" ]] && printf '%s\n' "$block"
        ST_LR=$(block_dedup_hash "$block")
        ST_LTS="$now"
        ST_LE=$(ledger_hash "$ledger")
    elif (( now - ${ST_LTS:-0} > WS_RENDER_INTERVAL )); then
        # Expensive level: ledger unchanged but interval elapsed -> re-render,
        # emit only if the rendered block changed; update render ts regardless.
        local block bhash
        block=$(render_block "$store" "$sid")
        bhash=$(block_dedup_hash "$block")
        if [[ -n "$block" && "$bhash" != "$ST_LR" ]]; then
            printf '%s\n' "$block"
        fi
        ST_LR="$bhash"
        ST_LTS="$now"
        ST_LE=$(ledger_hash "$ledger")
    fi

    write_state "$store" "$sid"
}

# On-demand render for /inflight. A pure READ: no ledger rewrite, no gate-state
# write, no terminal_shown consumption. It shows the current terminal PRs
# without consuming R3's single post-transition showing (owned by the ambient
# paths) and without resetting the ambient emission gate (ST_LR/ST_LTS/ST_LE) or
# activity clock (ST_LA). See render_block's consume=0 mode.
_render_locked() {
    local sid="$1" store="$2"
    local ledger; ledger=$(ledger_path "$store" "$sid")
    [[ -s "$ledger" ]] || return 0
    local block; block=$(render_block "$store" "$sid" 0)
    [[ -n "$block" ]] && printf '%s\n' "$block"
}

_absence_locked() {
    local sid="$1" store="$2"
    read_state "$store" "$sid"
    local now prev elapsed
    now=$(ws_now)
    prev="${ST_LA:-0}"
    elapsed=$(( now - prev ))
    ST_LA="$now"
    local ledger; ledger=$(ledger_path "$store" "$sid")
    if (( elapsed > WS_ABSENCE_THRESHOLD )) && [[ -s "$ledger" ]]; then
        local block; block=$(render_block "$store" "$sid")
        [[ -n "$block" ]] && printf '%s\n' "$block"
        ST_LR=$(block_dedup_hash "$block")
        ST_LTS="$now"
        ST_LE=$(ledger_hash "$ledger")
    fi
    write_state "$store" "$sid"
}

_compact_locked() {
    local sid="$1" store="$2"
    local ledger; ledger=$(ledger_path "$store" "$sid")
    if [[ -s "$ledger" ]]; then
        local block; block=$(render_block "$store" "$sid")
        [[ -n "$block" ]] && printf '%s\n' "$block"
    fi
    read_state "$store" "$sid"
    ST_LA=$(ws_now)
    write_state "$store" "$sid"
}

print_help() {
    cat <<EOF
work-summary.sh - session "work in flight" summary component

Block format (single source of truth):

    $MARKER
    owner/repo#N | <state-tokens> | <title> | <bare-url>
    ... (one line per tracked PR)
    updated <ISO-8601 UTC timestamp>

  - The first line is always the fixed literal marker "$MARKER".
  - state-tokens are derived from live \`gh pr view\` state, e.g.
    "open ci:passing", "draft ci:pending", "merged",
    "closed review:changes_requested".
  - The bare URL is LAST on every line so it survives plain-text scrollback
    and wraps intact on narrow terminals.
  - Ordering is attention-first: failing CI / changes-requested, then
    open/draft awaiting, then terminal (merged/closed) last.
  - A merged/closed PR appears in exactly ONE summary after transitioning,
    then is dropped from later renders.
  - Renovate-style section headers (## Needs attention, ## In progress,
    ## Recently settled) appear only when there are more than 6 items;
    the block is flat otherwise.
  - The final "updated ..." freshness line is always present.
  - When live state is unreachable, a best-effort ledger-only block is
    printed, marked "(best-effort: live state unavailable)".

Subcommands: capture | render | absence | compact | help
Each (except help) takes --session <id>.

Environment: WS_RENDER_INTERVAL (default 300), WS_ABSENCE_THRESHOLD
(default 1800), GH, WS_STORE_DIR, WS_NOW.
EOF
}

# --- entrypoint ------------------------------------------------------------

main() {
    umask 077
    set -uo pipefail
    trap 'exit 0' EXIT

    WS_RENDER_INTERVAL="${WS_RENDER_INTERVAL:-300}"
    WS_ABSENCE_THRESHOLD="${WS_ABSENCE_THRESHOLD:-1800}"
    GH_BIN="${GH:-gh}"

    local sub="${1:-}"
    [[ $# -gt 0 ]] && shift

    case "$sub" in
        help|-h|--help) print_help; exit 0 ;;
        *) : ;;
    esac

    local sid=""
    while (( $# )); do
        case "$1" in
            --session)   sid="${2:-}"; shift 2 || shift ;;
            --session=*) sid="${1#--session=}"; shift ;;
            *)           shift ;;
        esac
    done

    [[ -z "$sid" ]] && exit 0
    validate_sid "$sid" || exit 0

    local store
    store=$(ensure_store) || exit 0
    refuse_symlinked_files "$store" "$sid" || exit 0
    local lock="$store/$sid.lock"

    case "$sub" in
        capture) ( flock -w 5 9 || exit 0; _capture_locked "$sid" "$store" ) 9>"$lock" ;;
        render)  ( flock -w 5 9 || exit 0; _render_locked  "$sid" "$store" ) 9>"$lock" ;;
        absence) ( flock -w 5 9 || exit 0; _absence_locked "$sid" "$store" ) 9>"$lock" ;;
        compact) ( flock -w 5 9 || exit 0; _compact_locked "$sid" "$store" ) 9>"$lock" ;;
        *)       exit 0 ;;
    esac
    exit 0
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    main "$@"
fi

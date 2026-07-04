#!/usr/bin/env bash
# work-summary.sh -- deterministic capture+render pipeline prototype for a
# "work in flight" summary. Three subcommands:
#
#   capture        read PostToolUse hook JSON on stdin; append any PR refs
#                  found in the tool output to a session-scoped ledger.
#   render         refresh each ledger entry via read-only `gh pr view` and
#                  print the WORK IN FLIGHT block. (--parallel for concurrent
#                  fetches, --session <id>, --stale-ok to render from cache
#                  columns when gh fails)
#   should-render  gating check: exit 0 (render due) iff the ledger changed
#                  since last render or more than $WS_RENDER_INTERVAL seconds
#                  elapsed. `mark-rendered` records a render.
#
# READ-ONLY gh usage: only `gh pr view`. Never mutates anything.
set -u

WS_DIR="${WS_DIR:-${XDG_RUNTIME_DIR:-/tmp}/work-summary}"
WS_RENDER_INTERVAL="${WS_RENDER_INTERVAL:-300}"   # seconds
WS_GH_TIMEOUT="${WS_GH_TIMEOUT:-8}"               # per-fetch cap, seconds

die() { echo "work-summary: $*" >&2; exit 2; }

need_jq() { command -v jq >/dev/null 2>&1 || die "jq not found"; }

ledger_path() { echo "$WS_DIR/$1.tsv"; }
state_path()  { echo "$WS_DIR/$1.state"; }

# ---------------------------------------------------------------- capture --
# stdin: PostToolUse hook JSON. Fail-open: any parse problem exits 0 silently
# (a hook must never break the tool call it observes).
cmd_capture() {
  need_jq
  local payload session tool cmdline out
  payload="$(cat)" || exit 0
  session="$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null)" || exit 0
  tool="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)" || exit 0
  [ -n "$session" ] && [ "$tool" = "Bash" ] || exit 0

  cmdline="$(jq -r '.tool_input.command // empty' <<<"$payload")"
  # Only observe gh pr subcommands. `git push` hint URLs are additionally
  # excluded by the /pull/<digits> regex (hints are /pull/new/<branch>).
  case "$cmdline" in
    *"gh pr "*|*"gh pr"|*"gh api "*) ;;
    *) exit 0 ;;
  esac

  # Scan stdout + stderr + the command itself (covers `gh pr merge <url>`
  # whose success message has no URL).
  out="$(jq -r '((.tool_response.stdout // "") + "\n" + (.tool_response.stderr // "") + "\n" + (.tool_input.command // ""))' <<<"$payload")"

  local refs
  refs="$(grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' <<<"$out" | sort -u)"
  [ -n "$refs" ] || exit 0

  mkdir -p "$WS_DIR"
  local ledger; ledger="$(ledger_path "$session")"
  touch "$ledger"
  local url repo num now added=0
  now="$(date +%s)"
  while IFS= read -r url; do
    grep -qF "	$url	" "$ledger" && continue      # dedupe on url
    repo="$(sed -E 's#https://github\.com/([^/]+/[^/]+)/pull/[0-9]+#\1#' <<<"$url")"
    num="${url##*/}"
    printf '%s\t%s\t%s\t%s\n' "$repo" "$num" "$url" "$now" >> "$ledger"
    added=$((added+1))
  done <<<"$refs"
  exit 0
}

# ----------------------------------------------------------------- render --
# One PR -> one formatted line. Fetch is read-only; on failure prints a
# degraded line from ledger data alone.
fetch_line() {
  local repo="$1" num="$2" url="$3"
  local json
  json="$(timeout "$WS_GH_TIMEOUT" gh pr view "$url" \
            --json state,title,url,statusCheckRollup,reviewDecision,isDraft \
            2>/dev/null)" || {
    echo "- ${repo}#${num} | unknown (gh unavailable) | | ${url}"
    return 0
  }
  jq -r --arg repo "$repo" --arg num "$num" '
    def ci_tokens:
      (.statusCheckRollup // []) as $c
      | ($c | length) as $total
      | if $total == 0 then empty else
          ([$c[] | select((.conclusion? // .state? // "") as $s
              | $s=="SUCCESS" or $s=="NEUTRAL" or $s=="SKIPPED")] | length) as $ok
          | ([$c[] | select((.conclusion? // .state? // "") as $s
              | $s=="FAILURE" or $s=="ERROR" or $s=="CANCELLED"
                or $s=="TIMED_OUT" or $s=="ACTION_REQUIRED")] | length) as $bad
          | if $bad > 0 then "ci-fail \($ok)/\($total)"
            elif $ok == $total then "ci-pass"
            else "ci-run \($ok)/\($total)" end
        end;
    def review_token:
      if .reviewDecision == "APPROVED" then "approved"
      elif .reviewDecision == "CHANGES_REQUESTED" then "changes-req"
      elif .reviewDecision == "REVIEW_REQUIRED" then "review-wait"
      else empty end;
    def tokens:
      if .state == "MERGED" then "merged"
      elif .state == "CLOSED" then "closed"
      else ([ (if .isDraft then "draft" else "open" end),
              ci_tokens, review_token ] | join(" "))
      end;
    def trunc60: if length > 60 then .[0:57] + "..." else . end;
    "- \($repo)#\($num) | \(tokens) | \(.title | trunc60) | \(.url)"
  ' <<<"$json"
}

cmd_render() {
  need_jq
  local session="" parallel=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --parallel) parallel=1; shift ;;
      *) die "render: unknown arg $1" ;;
    esac
  done
  [ -n "$session" ] || die "render: --session required"
  local ledger; ledger="$(ledger_path "$session")"
  [ -s "$ledger" ] || exit 0   # nothing in flight -> print nothing

  if ! command -v gh >/dev/null 2>&1; then
    echo "=== WORK IN FLIGHT ==="
    awk -F'\t' '{print "- " $1 "#" $2 " | unknown (gh not installed) | | " $3}' "$ledger"
    exit 0
  fi

  echo "=== WORK IN FLIGHT ==="
  if [ "$parallel" = 1 ]; then
    local tmp; tmp="$(mktemp -d)"
    local i=0
    while IFS=$'\t' read -r repo num url _ts; do
      fetch_line "$repo" "$num" "$url" > "$tmp/$i" &
      i=$((i+1))
    done < "$ledger"
    wait
    local j=0
    while [ $j -lt $i ]; do cat "$tmp/$j"; j=$((j+1)); done
    rm -rf "$tmp"
  else
    while IFS=$'\t' read -r repo num url _ts; do
      fetch_line "$repo" "$num" "$url"
    done < "$ledger"
  fi
}

# ---------------------------------------------------------- should-render --
# exit 0  -> render is due (ledger changed OR interval elapsed, and ledger
#            is non-empty)
# exit 1  -> skip
ledger_hash() {
  local ledger="$1"
  [ -f "$ledger" ] && sha256sum "$ledger" | cut -d' ' -f1 || echo "empty"
}

cmd_should_render() {
  local session="${1:-}"; [ -n "$session" ] || die "should-render: session id required"
  local ledger state now hash last_ts last_hash
  ledger="$(ledger_path "$session")"; state="$(state_path "$session")"
  [ -s "$ledger" ] || exit 1                 # nothing tracked -> never render
  hash="$(ledger_hash "$ledger")"
  now="$(date +%s)"
  if [ ! -f "$state" ]; then exit 0; fi      # never rendered -> due
  read -r last_ts last_hash < "$state" || exit 0
  [ "$hash" != "$last_hash" ] && exit 0      # ledger changed -> due
  [ $((now - last_ts)) -gt "$WS_RENDER_INTERVAL" ] && exit 0
  exit 1
}

cmd_mark_rendered() {
  local session="${1:-}"; [ -n "$session" ] || die "mark-rendered: session id required"
  mkdir -p "$WS_DIR"
  printf '%s %s\n' "$(date +%s)" "$(ledger_hash "$(ledger_path "$session")")" \
    > "$(state_path "$session")"
}

case "${1:-}" in
  capture)        shift; cmd_capture "$@" ;;
  render)         shift; cmd_render "$@" ;;
  should-render)  shift; cmd_should_render "$@" ;;
  mark-rendered)  shift; cmd_mark_rendered "$@" ;;
  *) die "usage: work-summary.sh {capture|render --session <id> [--parallel]|should-render <id>|mark-rendered <id>}" ;;
esac

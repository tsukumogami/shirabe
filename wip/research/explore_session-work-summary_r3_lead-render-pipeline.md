# Lead: Does a deterministic capture+render pipeline work end to end?

Verdict: **yes**. A ~180-line bash script with jq handles the whole data path — capture from PostToolUse stdin, session-scoped TSV ledger, live read-only render via `gh pr view`, and hash+interval gating — with no LLM involvement anywhere. Built and tested in `/home/dangazineu/.claude/jobs/a050f0e4/tmp/render-lab/` against real PRs in tsukumogami/shirabe, tsukumogami/niwa, tsukumogami/tsuku, tsukumogami/koto (read-only: `gh pr list` and `gh pr view` only).

## Findings

### Subcommand 1: capture

**Approach.** Read the hook JSON from stdin with jq; bail out (exit 0, fail-open) unless `tool_name == "Bash"` and the command mentions `gh pr`. Then grep stdout + stderr + the command text itself for `https://github\.com/[^/]+/[^/]+/pull/[0-9]+`, dedupe against the ledger, and append `repo \t number \t url \t first-seen-epoch` to `${XDG_RUNTIME_DIR:-/tmp}/work-summary/<session_id>.tsv`.

Two design choices carry the robustness:

1. **Digits-only regex kills the git-push false positive for free.** `git push` prints `https://github.com/owner/repo/pull/new/<branch>` — `new` is not `[0-9]+`, so it can never match. The command gate (`git push` is not a `gh pr` command) is a second independent barrier.
2. **Scanning the command text covers merge/close.** `gh pr merge`/`gh pr close` print their success message to **stderr** and it contains only `#N`, not a URL. But agents habitually run `gh pr merge <url> --squash`, so the URL rides in on `tool_input.command`.

**Test results — 12/12 pass:**

| # | case | result |
|---|------|--------|
| 1 | `gh pr create`: URL alone on stdout last line, progress on stderr (real gh shape) | captured |
| 2 | `git push && gh pr create --fill`: URL after noise lines | captured |
| 3 | same PR seen twice (create then `gh pr view --json url`) | 1 ledger row (dedupe on URL) |
| 4 | `gh pr create --json url -q .url` machine output | captured |
| 5 | `gh pr merge <url> --squash` (stderr `✓ Squashed and merged #213`, no URL in output) | captured from command text |
| 6 | `gh pr merge 999 --squash` (bare number, no URL anywhere) | correctly no row — **known gap, see Surprises** |
| 7 | `gh pr close <url>` | captured |
| 8 | `git push` with `Create a pull request ... /pull/new/my-feature` hint | NOT captured (both barriers verified) |
| 9 | non-Bash tool (Read) with a PR URL in output | ignored |
| 10 | malformed stdin (`not json at all`) | exit 0, no crash — hook-safe |
| 11 | missing `session_id` | ignored cleanly |
| 12 | ledger content after suite | 5 rows, correct repo/number/url/ts columns |

### Subcommand 2: render

**Approach.** Read the ledger; for each row run `timeout 8 gh pr view <url> --json state,title,url,statusCheckRollup,reviewDecision,isDraft` and format one line entirely in jq. Token rules: `merged` / `closed` terminal; otherwise `open`|`draft` + CI token (`ci-pass`, `ci-fail OK/TOTAL`, `ci-run OK/TOTAL` — FAILURE/ERROR/CANCELLED/TIMED_OUT/ACTION_REQUIRED count as bad; NEUTRAL/SKIPPED count as ok; handles both CheckRun `.conclusion` and StatusContext `.state`) + review token (`approved`/`changes-req`/`review-wait`, omitted when the repo has no review requirement). Title truncated to 60 chars. `--parallel` fans each fetch into a background job writing to a per-index temp file, then concatenates in ledger order (stable output). Fetch failure degrades to a per-line `unknown (gh unavailable)` with the ledger's URL; missing gh degrades the whole block from ledger data alone; empty ledger prints nothing (exit 0).

**Real render output** (5 real PRs, 3 repos, mixed states — parallel, 0.99s):

```
=== WORK IN FLIGHT ===
- tsukumogami/tsuku#2427 | open ci-fail 86/90 | Bump the github-actions group across 1 directory with 15 ... | https://github.com/tsukumogami/tsuku/pull/2427
- tsukumogami/niwa#157 | open ci-pass | test(functional): use system claude auth locally, API key... | https://github.com/tsukumogami/niwa/pull/157
- tsukumogami/shirabe#193 | open ci-fail 4/5 | chore(ci): update design doc validation | https://github.com/tsukumogami/shirabe/pull/193
- tsukumogami/tsuku#2425 | closed | build(deps): bump the github-actions group across 1 direc... | https://github.com/tsukumogami/tsuku/pull/2425
- tsukumogami/shirabe#216 | merged | fix(execute): self-resolve plugin root in preflight.sh | https://github.com/tsukumogami/shirabe/pull/216
```

Multi-repo cwd handling confirmed: render ran from the lab directory, never from any repo checkout — `gh pr view <full-url>` needs no repo context, so the session-scoped ledger with owner/repo-carrying URLs is fully repo-independent.

**Degradation tests:**

| scenario | behavior | time |
|----------|----------|------|
| gh not on PATH | full block from ledger, `unknown (gh not installed)` per line | <10ms |
| gh present, network dead (proxy to 127.0.0.1:9) | block renders, `unknown (gh unavailable)` per line | 35ms (connection refused fails fast) |
| network *hangs* (worst case) | bounded by `timeout 8` per fetch; parallel keeps total ≈ 8s | by construction |
| nonexistent PR (koto#99999) | degraded line for that entry only | 0.24s |
| empty/absent ledger | prints nothing, exit 0 | ~5ms |

### Subcommand 3: should-render

**Approach.** State file `<session_id>.state` holds `last_render_epoch ledger_sha256`. Exit 0 (due) iff ledger is non-empty AND (never rendered, OR hash differs, OR elapsed > `WS_RENDER_INTERVAL`, default 300s). A `mark-rendered` helper records renders — separating check from mark lets the caller only mark after a render actually displayed.

**Test results — 8/8 pass:** absent ledger→skip; empty ledger→skip; new entry never rendered→due; just rendered unchanged→skip; ledger grew→due; re-marked→skip; interval elapsed (backdated state)→due; larger interval env override→skip. Check latency ~5ms.

### End-to-end smoke

capture(`gh pr create` fixture) → should-render says due → render shows `open ci-fail 4/5` from live gh → mark-rendered → should-render says skip → capture(`gh pr merge <url>` fixture) → should-render says due again → render shows both PRs, the merged one now `merged`. The full loop works with no state passed between steps except the files.

### Latency table

| operation | wall time |
|-----------|-----------|
| capture, non-matching command (the common case) | ~8.5 ms |
| capture, matching `gh pr` command | ~16 ms |
| should-render check | ~5 ms |
| render 1 PR | 0.40 s |
| render 5 PRs, sequential, 2 repos | 2.04–2.45 s |
| render 5 PRs, parallel, 2–3 repos | 0.45–0.99 s |
| render offline (2 entries, degraded) | 0.035 s |

**Hook time-budget fit.** Capture at 8–16ms is negligible against the 60s default hook timeout — it belongs in PostToolUse. Render's 0.4–1s (parallel) is fine for a display-moment hook (UserPromptSubmit / Stop / statusline) but is the wrong thing to put in PostToolUse: it would fire after every Bash call and pay network latency each time. The right split, now measured: **capture stays offline-only in PostToolUse; render is deferred to the display moment and gated by should-render**, which costs 5ms to say "skip". Worst-case render (hung network) is bounded at ~8s by the per-fetch timeout, still inside display-hook budgets; the dead-network case fails in 35ms.

**Dependencies.** jq 1.7 and gh 2.82.1 were present. jq is required for safe JSON parsing of hook stdin; both absence cases degrade rather than break (capture exits 2 loudly only via `die`; render without gh prints the ledger-only block).

### The prototype (deliverable)

```bash
#!/usr/bin/env bash
# work-summary.sh -- deterministic capture+render pipeline prototype for a
# "work in flight" summary. Three subcommands:
#
#   capture        read PostToolUse hook JSON on stdin; append any PR refs
#                  found in the tool output to a session-scoped ledger.
#   render         refresh each ledger entry via read-only `gh pr view` and
#                  print the WORK IN FLIGHT block. (--parallel for concurrent
#                  fetches, --session <id>)
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
  local url repo num now
  now="$(date +%s)"
  while IFS= read -r url; do
    grep -qF "	$url	" "$ledger" && continue      # dedupe on url
    repo="$(sed -E 's#https://github\.com/([^/]+/[^/]+)/pull/[0-9]+#\1#' <<<"$url")"
    num="${url##*/}"
    printf '%s\t%s\t%s\t%s\n' "$repo" "$num" "$url" "$now" >> "$ledger"
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
```

## Implications

- The "scripts can do the whole data path" claim holds. No LLM step is needed anywhere between a tool call finishing and the summary block appearing; the design doc can commit to a fully deterministic pipeline.
- The architecture question the lead posed — render in PostToolUse vs deferred — is now answered by numbers: capture (8–16ms) in PostToolUse, render (0.4–1s parallel, 8s hung-network ceiling) at the display moment behind the 5ms should-render gate. Putting gh network calls in the PostToolUse hot path is *technically* within budget but wasteful and adds a hang risk to every Bash call for no benefit.
- `--parallel` should be the default: 2.2s → 0.5–1.0s for 5 PRs is the difference between "noticeable pause" and "instant" at prompt-submit time, and the ordered temp-file concatenation keeps output deterministic.
- The ledger schema (repo, number, url, first-seen) is sufficient. Render needs only the URL; repo#number exist purely for the degraded line, which justifies keeping them.
- The state-file split (should-render vs mark-rendered) lets the display hook be idempotent and cheap: callers check, render only when due, and mark only on success.

## Surprises

- **The git-push false positive costs zero defensive code.** The hint URL is `/pull/new/<branch>`; the `[0-9]+` in the capture regex makes it unmatchable. I expected to need a negative filter.
- **`gh pr merge`/`close` output is capture-hostile:** the success message goes to stderr and contains only `#N`, never a URL. Capture works for these commands only because agents pass the URL as the argument. `gh pr merge 216` (bare number) is invisible to the pipeline — acceptable because a PR being merged was almost always captured at creation, and render pulls live state regardless.
- **Offline failure is fast, not slow.** A dead network (connection refused) degraded the whole render in 35ms. The 8s worst case only materializes when packets silently drop; `timeout` is still worth keeping.
- **My invented "ghost" fixture koto#42 turned out to be a real closed PR** — which accidentally proved render is fully cwd- and repo-independent (rendered a koto PR from a ledger built in a shirabe worktree, running from a scratch directory).
- All tested tsukumogami PRs had empty `reviewDecision` (no required reviews configured), so `review-wait`/`approved` tokens never fired on real data — the logic is only fixture-verified against gh's documented enum.

## Open Questions

- **Capture gate width.** Currently any `gh pr`/`gh api` command feeds capture, so `gh pr view <other-pr>` (inspecting someone else's PR) pollutes the ledger. Narrow to `gh pr (create|merge|close|ready|reopen)`? That trades noise for missing `gh api repos/.../pulls` creations.
- **Terminal-entry retention.** Should render drop MERGED/CLOSED entries after showing them once (or after N minutes), so long sessions don't accumulate a tail of merged lines? Needs a product decision — "show merged once as confirmation, then evict" seems right and is a 5-line change (render rewrites the ledger).
- **Where does session_id come from at display time?** UserPromptSubmit and statusline payloads both carry it, so wiring should be trivial, but the display-hook integration itself was out of scope here.
- **`gh pr create --web`** opens a browser and prints no URL to stdout; the PR is created interactively and never captured. Probably out of scope for agent sessions (agents don't use `--web`), worth a line in the design doc.
- **CI count semantics.** `statusCheckRollup` totals include skipped/neutral checks (counted as ok, matching gh's own rollup); a `2/14` display therefore reflects check topology, not just pass rate. Fine for a glance-level token, but worth documenting.

## Summary

Built and tested a 3-subcommand `work-summary.sh` prototype: all 12 capture fixtures pass (including the `git push` `/pull/new/` hint correctly rejected by the digits-only regex), render produced correct state tokens (`open ci-fail 86/90`, `ci-pass`, `merged`, `closed`) against 5 real PRs across 3 public tsukumogami repos, and all 8 should-render gating cases pass. Latency: capture 8–16ms, should-render check 5ms, 5-PR multi-repo render 2.2s sequential vs 0.5–1.0s parallel, offline degradation 35ms with a graceful ledger-only block — so capture fits the PostToolUse hot path trivially while render belongs at the display moment behind the gate. The deterministic-pipeline claim is proven end to end; the one real gap is that `gh pr merge <bare-number>` leaves no capturable URL (output goes to stderr as `#N` only), which is benign since PRs are captured at creation and render refreshes state live.

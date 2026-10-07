#!/usr/bin/env bash
# release-eval-check_test.sh -- test harness for scripts/release-eval-check.sh
#
# Usage: bash scripts/release-eval-check_test.sh
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# No model, no network. Each case builds a throwaway git repository holding a
# copy of release-eval-check.sh and scripts/lib/eval-pass-rates.py, with an
# origin remote on github.com, and puts a stub gh and a stub run-evals.sh first
# on PATH; the repository's scripts/run-evals.sh is a copy of that stub, since
# the check runs the harness that sits next to it. Both stubs log every call,
# so a case can assert which calls were made, and that none was a
# `gh release upload`.
#
# The stub harness reads, from $STUB_DIR:
#   selection        what --list-changed prints (missing: nothing selected)
#   list-rc          --list-changed's exit code (default 0)
#   result.<skill>   "<exit> <assertions passed> <assertions graded>"
#   nosummary.<skill>  present: write no summary for that skill
# The stub gh copies $STUB_DIR/asset as the downloaded asset, or fails when
# there is none.

set -uo pipefail

unset RELEASE_VERSION RELEASE_LAST_TAG RELEASE_CONFIRMED_DROPS

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK_SRC="$SCRIPT_DIR/release-eval-check.sh"
RECORD_SRC="$SCRIPT_DIR/lib/eval-pass-rates.py"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/release-eval-check-test.XXXXXX")
T=$(cd "$T" && pwd -P)
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

BIN="$T/bin"
mkdir -p "$BIN"

cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$STUB_LOG"
if [ "$1" = release ] && [ "$2" = download ]; then
  dir=""
  while [ $# -gt 0 ]; do
    if [ "$1" = --dir ]; then dir="$2"; fi
    shift
  done
  [ -f "$STUB_DIR/asset" ] || { echo "release asset not found" >&2; exit 1; }
  cp "$STUB_DIR/asset" "$dir/eval-pass-rates.json"
  exit 0
fi
exit 0
EOF

cat >"$BIN/run-evals.sh" <<'EOF'
#!/usr/bin/env bash
echo "run-evals $*" >>"$STUB_LOG"
if [ "$1" = --list-changed ]; then
  [ ! -f "$STUB_DIR/selection" ] || cat "$STUB_DIR/selection"
  exit "$(cat "$STUB_DIR/list-rc" 2>/dev/null || echo 0)"
fi
runs=1 out="" skill=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) runs="$2"; shift 2 ;;
    --summary-out) out="$2"; shift 2 ;;
    *) skill="$1"; shift ;;
  esac
done
set -- $(cat "$STUB_DIR/result.$skill" 2>/dev/null || echo "0 1 1")
code=$1 passed=$2 graded=$3
runs_passed=0
[ "$code" -ne 0 ] || runs_passed=$runs
if [ ! -f "$STUB_DIR/nosummary.$skill" ]; then
  cat >"$out" <<JSON
{"schema": "run-evals-summary/v1", "skills": {"$skill": {"runs": $runs,
 "runs_passed": $runs_passed, "assertions_passed": $passed,
 "assertions_graded": $graded, "models": ["sonnet"], "exit_code": $code}}}
JSON
fi
exit "$code"
EOF
chmod +x "$BIN/gh" "$BIN/run-evals.sh"

export PATH="$BIN:$PATH"

N=0
REPO=""
export STUB_DIR STUB_LOG

new_case() { # new_case -- a fresh repository and stub state
  N=$((N + 1))
  REPO="$T/repo$N"
  STUB_DIR="$T/stub$N"
  STUB_LOG="$STUB_DIR/log"
  mkdir -p "$REPO/scripts/lib" "$STUB_DIR"
  : >"$STUB_LOG"
  cp "$CHECK_SRC" "$REPO/scripts/release-eval-check.sh"
  cp "$RECORD_SRC" "$REPO/scripts/lib/eval-pass-rates.py"
  cp "$BIN/run-evals.sh" "$REPO/scripts/run-evals.sh"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$REPO" remote add origin git@github.com:example-org/example-repo.git
  STATE="$REPO/.git/shirabe-release"
}

new_commit() {
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m next
}

RC=0
OUT=""
run_check() { # run_check <last tag> <version> [<confirmed>] -- the check, critical work-on,scope
  RC=0
  OUT=$(cd "$REPO" && RELEASE_LAST_TAG="$1" RELEASE_VERSION="$2" \
    RELEASE_CONFIRMED_DROPS="${3:-}" \
    bash scripts/release-eval-check.sh --critical work-on,scope --critical-runs 3 2>&1) || RC=$?
}

run_finalize() { # run_finalize <last tag> <version>
  RC=0
  OUT=$(cd "$REPO" && RELEASE_LAST_TAG="$1" RELEASE_VERSION="$2" \
    bash scripts/release-eval-check.sh --finalize 2>&1) || RC=$?
}

record_field() { # record_field <python expression over r> -- read the state record
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' \
    "$STATE/eval-pass-rates.json" "$1" 2>/dev/null
}

write_asset() { # write_asset <skill> <passed> <graded> <rate> [<measured_at>]
  cat >"$STUB_DIR/asset" <<JSON
{"schema": "eval-pass-rates/v1", "version": "0.23.0", "last_tag": "v0.22.0",
 "skills": {"$1": {"runs": 1, "runs_passed": 1, "assertions_passed": $2,
 "assertions_graded": $3, "pass_rate": $4, "models": ["sonnet"],
 "measured_at": "${5:-0.23.0}"}}}
JSON
}

harness_calls() { grep -c '^run-evals --runs' "$STUB_LOG" || true; }
list_calls() { grep -c '^run-evals --list-changed' "$STUB_LOG" || true; }
last_line() { printf '%s\n' "$OUT" | tail -n 1; }

# -- host notice, empty last tag ----------------------------------------------

new_case
echo "brief" >"$STUB_DIR/selection"
echo "0 9 10" >"$STUB_DIR/result.brief"
run_check "" 0.24.0
HOST=$(hostname 2>/dev/null || uname -n)
if printf '%s\n' "$OUT" | grep -qxF "Eval check host: $HOST"; then
  pass "prints the host it runs on"
else
  fail "host line missing: $OUT"
fi
if printf '%s\n' "$OUT" | grep -q 'access to its stored credentials (gh logins, git credential helpers, SSH keys on disk); only GH_TOKEN, GITHUB_TOKEN and SSH_AUTH_SOCK are unset'; then
  pass "states what the nested sessions can reach"
else
  fail "credential line missing: $OUT"
fi
HOST_AT=$(printf '%s\n' "$OUT" | grep -n '^Eval check host:' | cut -d: -f1)
FIRST_EVAL_AT=$(printf '%s\n' "$OUT" | grep -n '^== brief' | head -n 1 | cut -d: -f1)
if [ -n "$HOST_AT" ] && [ -n "$FIRST_EVAL_AT" ] && [ "$HOST_AT" -lt "$FIRST_EVAL_AT" ]; then
  pass "the notice comes before any eval runs"
else
  fail "notice order: $OUT"
fi
if [ "$RC" -eq 0 ] && ! grep -q '^gh ' "$STUB_LOG" \
  && printf '%s\n' "$OUT" | grep -q 'no baseline: no last tag' \
  && [ "$(record_field 'r["skills"]["brief"]["pass_rate"]')" = 0.9 ] \
  && [ "$(record_field 'r["last_tag"]')" = "" ]; then
  pass "empty last tag: no download, no baseline, record written, exit 0"
else
  fail "empty last tag (rc=$RC): $OUT"
fi

# -- selection, run counts, download arguments ---------------------------------

new_case
printf 'work-on\nbrief\n' >"$STUB_DIR/selection"
write_asset brief 9 10 0.9
run_check v0.23.0 0.24.0
if [ "$RC" -eq 0 ] && grep -qx 'run-evals --runs 3 --summary-out .*/1.json work-on' "$STUB_LOG" \
  && grep -qx 'run-evals --runs 1 --summary-out .*/2.json brief' "$STUB_LOG"; then
  pass "a critical skill runs --critical-runs times, another once, summaries named by index"
else
  fail "run counts (rc=$RC): $(cat "$STUB_LOG")"
fi
if grep -q '^gh release download v0.23.0 --repo example-org/example-repo --pattern eval-pass-rates.json --dir ' "$STUB_LOG"; then
  pass "downloads the previous record by tag, pinned repo and exact asset name"
else
  fail "download call: $(cat "$STUB_LOG")"
fi
DL_DIR=$(sed -n 's/^gh release download .* --dir //p' "$STUB_LOG")
case "$DL_DIR" in
  "$REPO"*) fail "downloaded inside the repository: $DL_DIR" ;;
  *) [ ! -e "$DL_DIR" ] && pass "downloads into a temporary directory outside the repository, removed after" \
    || fail "download dir left behind: $DL_DIR" ;;
esac
if grep -qx "head $(git -C "$REPO" rev-parse HEAD)" "$STATE/marker" \
  && grep -qx 'last_tag v0.23.0' "$STATE/marker" \
  && grep -qx 'skill 1 work-on' "$STATE/marker" && grep -qx 'skill 2 brief' "$STATE/marker"; then
  pass "the marker names HEAD, the last tag and the measured skills"
else
  fail "marker: $(cat "$STATE/marker" 2>/dev/null)"
fi

# -- equal rate, drop, confirmations -------------------------------------------

new_case
echo brief >"$STUB_DIR/selection"
echo "0 9 10" >"$STUB_DIR/result.brief"
write_asset brief 9 10 0.9
run_check v0.23.0 0.24.0
[ "$RC" -eq 0 ] && pass "an equal rate is not a drop" || fail "equal rate (rc=$RC): $OUT"

new_case
printf 'brief\nscope\n' >"$STUB_DIR/selection"
echo "1 8 10" >"$STUB_DIR/result.brief"
write_asset brief 9 10 0.9
run_check v0.23.0 0.24.0
if [ "$RC" -eq 5 ] && [ "$(last_line)" = "confirm: RELEASE_CONFIRMED_DROPS=brief" ]; then
  pass "a drop exits 5 ending with the confirm line"
else
  fail "drop (rc=$RC): $OUT"
fi
BEFORE=$(harness_calls)
BEFORE_LIST=$(list_calls)
run_check v0.23.0 0.24.0 scope
if [ "$RC" -eq 5 ] && [ "$(harness_calls)" = "$BEFORE" ] && [ "$(list_calls)" = "$BEFORE_LIST" ]; then
  pass "a drop with a different skill confirmed still exits 5, with no harness call"
else
  fail "other skill confirmed (rc=$RC): $OUT"
fi
run_check v0.23.0 0.24.0 brief
if [ "$RC" -eq 0 ] && [ "$(harness_calls)" = "$BEFORE" ] && [ "$(list_calls)" = "$BEFORE_LIST" ] \
  && printf '%s\n' "$OUT" | grep -q 'Confirmation re-run'; then
  pass "a confirmed drop exits 0 and the re-run makes no harness call"
else
  fail "confirmed drop (rc=$RC): $OUT"
fi

new_case
echo brief >"$STUB_DIR/selection"
echo "1 8 10" >"$STUB_DIR/result.brief"
write_asset brief 9 10 0.9
run_check v0.23.0 0.24.0
new_commit
run_check v0.23.0 0.24.0 brief
if [ "$RC" -eq 0 ] && [ "$(harness_calls)" = 2 ]; then
  pass "a confirmation for another HEAD measures again"
else
  fail "confirmation after a new commit (rc=$RC): $(cat "$STUB_LOG")"
fi

# -- harness exits -----------------------------------------------------------

for code in 2 3 4; do
  new_case
  printf 'brief\nscope\n' >"$STUB_DIR/selection"
  echo "$code 0 0" >"$STUB_DIR/result.brief"
  echo "1 1 10" >"$STUB_DIR/result.scope"
  write_asset scope 9 10 0.9
  run_check v0.23.0 0.24.0
  if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "infrastructure failure: brief (harness exit $code)" \
    && [ "$(harness_calls)" = 2 ] \
    && [ "$(record_field '"pass_rate" in r["skills"]["brief"]')" = False ] \
    && [ "$(record_field 'r["skills"]["brief"]["exit_code"]')" = "$code" ]; then
    pass "harness exit $code: exit 1 naming the skill, other skills still run, outranks a drop, no pass_rate"
  else
    fail "harness exit $code (rc=$RC): $OUT"
  fi
done

new_case
echo brief >"$STUB_DIR/selection"
echo "1 9 10" >"$STUB_DIR/result.brief"
write_asset brief 8 10 0.8
run_check v0.23.0 0.24.0
[ "$RC" -eq 0 ] && pass "harness exit 1 without a drop exits 0" || fail "exit 1 no drop (rc=$RC): $OUT"

new_case
echo brief >"$STUB_DIR/selection"
touch "$STUB_DIR/nosummary.brief"
run_check v0.23.0 0.24.0
if [ "$RC" -eq 1 ] && [ "$(harness_calls)" = 1 ] \
  && printf '%s\n' "$OUT" | grep -q 'infrastructure failure: brief (no summary, recorded as exit 2)'; then
  pass "a selected skill with no summary is an infrastructure failure"
else
  fail "missing summary (rc=$RC): $OUT"
fi

new_case
echo brief >"$STUB_DIR/selection"
git -C "$REPO" remote set-url origin https://example.com/example-org/example-repo.git
run_check v0.23.0 0.24.0
if [ "$RC" -eq 1 ] && [ "$(harness_calls)" = 0 ] && [ "$(list_calls)" = 0 ]; then
  pass "an origin that isn't on GitHub fails before any eval runs"
else
  fail "non-GitHub origin (rc=$RC): $OUT"
fi

new_case
echo 2 >"$STUB_DIR/list-rc"
run_check v0.23.0 0.24.0
[ "$RC" -eq 1 ] && pass "a failing selection is an infrastructure failure" || fail "list fails (rc=$RC): $OUT"

# -- baselines ---------------------------------------------------------------

new_case
echo brief >"$STUB_DIR/selection"
echo "0 1 10" >"$STUB_DIR/result.brief"
run_check v0.23.0 0.24.0
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'no baseline: no eval-pass-rates.json could be downloaded from v0.23.0'; then
  pass "no asset: no baseline with a warning, exit 0"
else
  fail "no asset (rc=$RC): $OUT"
fi

new_case
echo brief >"$STUB_DIR/selection"
echo "0 1 10" >"$STUB_DIR/result.brief"
echo '{not json' >"$STUB_DIR/asset"
run_check v0.23.0 0.24.0
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'no baseline: the file does not parse'; then
  pass "an unparseable asset: no baseline, exit 0"
else
  fail "unparseable asset (rc=$RC): $OUT"
fi

new_case
echo brief >"$STUB_DIR/selection"
echo "0 1 10" >"$STUB_DIR/result.brief"
echo '{"schema": "eval-pass-rates/v9", "version": "0.23.0", "last_tag": "", "skills": {}}' >"$STUB_DIR/asset"
run_check v0.23.0 0.24.0
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'no baseline: schema is not eval-pass-rates/v1'; then
  pass "an unknown schema: no baseline, exit 0"
else
  fail "unknown schema (rc=$RC): $OUT"
fi

# -- stale state, empty selection ------------------------------------------------

new_case
mkdir -p "$STATE"
echo stale >"$STATE/eval-pass-rates.json"
echo stale >"$STATE/7.json"
run_check v0.23.0 0.24.0
if [ "$RC" -eq 0 ] && [ ! -e "$STATE/7.json" ] && [ "$(record_field 'r["version"]')" = 0.24.0 ]; then
  pass "a fresh run removes a stale record and summaries"
else
  fail "stale state (rc=$RC): $OUT"
fi

new_case
write_asset brief 9 10 0.9 0.22.0
run_check v0.23.0 0.24.0
if [ "$RC" -eq 0 ] && [ "$(harness_calls)" = 0 ] \
  && [ "$(record_field 'r["version"]')" = 0.24.0 ] \
  && [ "$(record_field 'r["skills"]["brief"]["measured_at"]')" = 0.22.0 ]; then
  pass "an empty selection still writes a record carrying the previous one forward"
else
  fail "empty selection (rc=$RC): $OUT"
fi

# -- finalize ----------------------------------------------------------------

new_case
echo work-on >"$STUB_DIR/selection"
write_asset brief 9 10 0.9 0.22.0
run_check v0.23.0 0.24.0
run_finalize v0.23.0 0.24.1
if [ "$RC" -eq 0 ] && [ "$(last_line)" = "asset: $STATE/eval-pass-rates.json" ] \
  && [ "$(record_field 'r["version"]')" = 0.24.1 ] \
  && [ "$(record_field 'r["skills"]["work-on"]["measured_at"]')" = 0.24.1 ] \
  && [ "$(record_field 'r["skills"]["brief"]["measured_at"]')" = 0.22.0 ]; then
  pass "--finalize with a matching marker stamps the record and prints the asset line"
else
  fail "finalize (rc=$RC): $OUT"
fi
run_finalize v0.22.0 0.24.1
[ "$RC" -eq 1 ] && pass "--finalize refuses a marker for another last tag" || fail "finalize other tag (rc=$RC): $OUT"
new_commit
run_finalize v0.23.0 0.24.1
[ "$RC" -eq 1 ] && pass "--finalize refuses a marker for another HEAD" || fail "finalize other HEAD (rc=$RC): $OUT"

new_case
echo work-on >"$STUB_DIR/selection"
run_check v0.23.0 0.24.0
rm -f "$STATE/eval-pass-rates.json"
run_finalize v0.23.0 0.24.0
[ "$RC" -eq 1 ] && pass "--finalize refuses with no record" || fail "finalize no record (rc=$RC): $OUT"

new_case
run_finalize v0.23.0 0.24.0
[ "$RC" -eq 1 ] && pass "--finalize refuses with no marker" || fail "finalize no marker (rc=$RC): $OUT"

# -- usage ---------------------------------------------------------------------

new_case
run_check 0.23.0 0.24.0
[ "$RC" -eq 2 ] && pass "a last tag off the pattern is a usage error" || fail "bad tag (rc=$RC): $OUT"
run_check v0.23.0 v0.24.0
[ "$RC" -eq 2 ] && pass "a version off the pattern is a usage error" || fail "bad version (rc=$RC): $OUT"
run_check v0.23.0 0.24.0 'Bad;name'
[ "$RC" -eq 2 ] && pass "an invalid confirmed name is a usage error" || fail "bad confirmed (rc=$RC): $OUT"
RC=0
OUT=$(cd "$REPO" && RELEASE_VERSION=0.24.0 bash scripts/release-eval-check.sh 2>&1) || RC=$?
[ "$RC" -eq 2 ] && pass "no mode is a usage error" || fail "no mode (rc=$RC): $OUT"
if [ "$(harness_calls)" = 0 ] && [ "$(list_calls)" = 0 ]; then
  pass "usage errors run nothing"
else
  fail "usage errors ran the harness: $(cat "$STUB_LOG")"
fi

# -- never uploads -------------------------------------------------------------

if cat "$T"/stub*/log | grep -q '^gh release upload'; then
  fail "a case called gh release upload"
else
  pass "no case called gh release upload"
fi

echo ""
echo "release-eval-check: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

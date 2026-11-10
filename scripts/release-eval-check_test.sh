#!/usr/bin/env bash
# release-eval-check_test.sh -- test harness for scripts/release-eval-check.sh
#
# Usage: bash scripts/release-eval-check_test.sh
#        /bin/bash scripts/release-eval-check_test.sh   (macOS: the bash 3.2 floor)
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed
#
# No model, no network, no koto. Each case builds a throwaway git repository
# holding copies of release-eval-check.sh, scripts/lib/eval-pass-rates.py and
# the real scripts/lib/script-cases.py, with an origin remote on github.com,
# and fixture skills:
#   alpha  script cases one and two
#   beta   script case one
#   gamma  one graded case and no script case
#   delta  no evals.json
# Every script case runs the tracked fixture script scripts/cases/fixture.sh,
# which appends "<skill> <case>" to .git/case-runs and fails when
# .git/case-control/fail.<skill>.<case> exists. The control lives in the
# fixture repository because the runner gives a case a closed environment
# with none of this suite's variables.
#
# A stub gh, a stub koto and a claude stub that exits 1 sit first on PATH, and
# the repository's scripts/run-evals.sh is a stub too. Each stub appends its
# call to $T/calls.log (this case) and $T/all-calls.log (every case), found
# from its own location, so a call from inside a case's closed environment is
# recorded as well. The stub gh reads $T/stub/:
#   asset.<tag>      copied as that release's eval-pass-rates.json
#   gh-error.<tag>   its text is the error of a failed download of that tag
# and otherwise fails as "no assets match the file pattern".
#
# The check runs under this suite's own shell ($BASH), so running the suite
# with /bin/bash on macOS checks the check on bash 3.2.

set -uo pipefail

unset RELEASE_VERSION RELEASE_LAST_TAG RELEASE_CONFIRMED_DROPS

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CHECK_SRC="$SCRIPT_DIR/release-eval-check.sh"
RECORD_SRC="$SCRIPT_DIR/lib/eval-pass-rates.py"
RUNNER_SRC="$SCRIPT_DIR/lib/script-cases.py"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/release-eval-check-test.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */release-eval-check-test.*) rm -rf "$T" ;; esac; return 0; }
trap cleanup EXIT

BIN="$T/bin"
NOKOTO="$T/nokoto"
STUB="$T/stub"
CALLS="$T/calls.log"
mkdir -p "$BIN" "$NOKOTO" "$STUB"
: >"$T/all-calls.log"

# A stub's log lines go next to its own directory: $T/bin/.. and
# $T/nokoto/.. are both $T.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")/.." && pwd)
echo "gh $*" >>"$here/calls.log"
echo "gh $*" >>"$here/all-calls.log"
if [ "$1" = release ] && [ "$2" = download ]; then
  tag="$3"
  dir=""
  while [ $# -gt 0 ]; do
    if [ "$1" = --dir ]; then dir="$2"; fi
    shift
  done
  if [ -f "$here/stub/gh-error.$tag" ]; then cat "$here/stub/gh-error.$tag" >&2; exit 1; fi
  if [ -f "$here/stub/asset.$tag" ]; then
    cp "$here/stub/asset.$tag" "$dir/eval-pass-rates.json"
    exit 0
  fi
  echo "no assets match the file pattern" >&2
  exit 1
fi
exit 0
EOF

cat >"$BIN/koto" <<'EOF'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")/.." && pwd)
echo "koto $*" >>"$here/calls.log"
echo "koto $*" >>"$here/all-calls.log"
exit 0
EOF

cat >"$BIN/claude" <<'EOF'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")/.." && pwd)
echo "claude $*" >>"$here/calls.log"
echo "claude $*" >>"$here/all-calls.log"
exit 1
EOF

# The fixture repository's scripts/run-evals.sh: $T is two levels up.
cat >"$T/run-evals-stub" <<'EOF'
#!/usr/bin/env bash
here=$(cd "$(dirname "$0")/../.." && pwd)
echo "run-evals $*" >>"$here/calls.log"
echo "run-evals $*" >>"$here/all-calls.log"
exit 1
EOF

cat >"$T/fixture.sh" <<'EOF'
#!/usr/bin/env bash
# fixture.sh <skill> <case> -- a fixture script case: logs its run, and fails
# when the case's control file exists.
echo "$1 $2" >>.git/case-runs
[ ! -e ".git/case-control/fail.$1.$2" ]
EOF

# asset.py <out> <version> [--pad <bytes>] <entry>... -- a release record.
# Entries: alpha-script-pass and alpha-script-fail (alpha's script cases one
# and two, two passing or failing), alpha-graded (a graded alpha entry), and
# scope-script (a script entry for a skill this run doesn't have). --pad fills
# the file with spaces to exactly that many bytes.
cat >"$T/asset.py" <<'EOF'
import json
import sys

out, version = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
pad = None
if args[:1] == ["--pad"]:
    pad = int(args[1])
    args = args[2:]


def script(cases):
    passed = sum(1 for _, verdict in cases if verdict == "pass")
    return {"runs": 1, "runs_passed": 1 if passed == len(cases) else 0,
            "assertions_passed": passed, "assertions_graded": len(cases),
            "pass_rate": round(passed / len(cases), 4), "models": ["script"],
            "cases": [{"name": n, "verdict": v} for n, v in cases],
            "measured_at": version}


skills = {}
for kind in args:
    if kind == "alpha-script-pass":
        skills["alpha"] = script([("one", "pass"), ("two", "pass")])
    elif kind == "alpha-script-fail":
        skills["alpha"] = script([("one", "pass"), ("two", "fail")])
    elif kind == "alpha-graded":
        skills["alpha"] = {"runs": 1, "runs_passed": 1, "assertions_passed": 9,
                           "assertions_graded": 10, "pass_rate": 0.9,
                           "models": ["sonnet"], "measured_at": version}
    elif kind == "scope-script":
        skills["scope"] = script([("one", "pass")])
    else:
        sys.exit("unknown entry " + kind)
text = json.dumps({"schema": "eval-pass-rates/v1", "version": version,
                   "last_tag": "", "skills": skills})
if pad is not None:
    text += " " * (pad - len(text.encode("utf-8")))
with open(out, "w", encoding="utf-8") as fh:
    fh.write(text)
EOF

chmod +x "$BIN/gh" "$BIN/koto" "$BIN/claude" "$T/run-evals-stub" "$T/fixture.sh"

# The no-koto PATH: the gh and claude stubs, git and python3, then the system
# directories.
cp "$BIN/gh" "$BIN/claude" "$NOKOTO/"
ln -s "$(command -v git)" "$NOKOTO/git"
ln -s "$(command -v python3)" "$NOKOTO/python3"

export PATH="$BIN:$PATH"

N=0
REPO=""
STATE=""

write_evals() { # write_evals <skill> <json> -- skills/<skill>/evals/evals.json
  mkdir -p "$REPO/skills/$1/evals"
  printf '%s\n' "$2" >"$REPO/skills/$1/evals/evals.json"
}

script_case() { # script_case <id> <skill> <case> -- one script case's JSON
  printf '{"id": %s, "name": "%s", "grader": "script", "run": "scripts/cases/fixture.sh %s %s"}' \
    "$1" "$3" "$2" "$3"
}

commit_all() {
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$1"
}

new_case() { # new_case -- a fresh fixture repository and stub state
  N=$((N + 1))
  REPO="$T/repo$N"
  STATE="$REPO/.git/shirabe-release"
  rm -rf "$STUB"
  mkdir -p "$STUB" "$REPO/scripts/lib" "$REPO/scripts/cases" "$REPO/skills/delta"
  : >"$CALLS"
  cp "$CHECK_SRC" "$REPO/scripts/release-eval-check.sh"
  cp "$RECORD_SRC" "$REPO/scripts/lib/eval-pass-rates.py"
  cp "$RUNNER_SRC" "$REPO/scripts/lib/script-cases.py"
  cp "$T/run-evals-stub" "$REPO/scripts/run-evals.sh"
  cp "$T/fixture.sh" "$REPO/scripts/cases/fixture.sh"
  write_evals alpha "{\"skill_name\": \"alpha\", \"evals\": [$(script_case 1 alpha one), $(script_case 2 alpha two)]}"
  write_evals beta "{\"skill_name\": \"beta\", \"evals\": [$(script_case 1 beta one)]}"
  write_evals gamma '{"skill_name": "gamma", "evals": [{"id": 1, "name": "graded-one", "prompt": "do the thing", "assertions": ["it did the thing"]}]}'
  echo "# delta" >"$REPO/skills/delta/SKILL.md"
  git -C "$REPO" init -q
  commit_all init
  git -C "$REPO" remote add origin git@github.com:example-org/example-repo.git
}

new_commit() {
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m next
}

tag_head() { # tag_head <tag>... -- a new commit carrying each tag
  local tag
  for tag in "$@"; do
    new_commit
    git -C "$REPO" tag "$tag"
  done
}

fail_case() { # fail_case <skill> <case> -- make that fixture case fail
  mkdir -p "$REPO/.git/case-control"
  : >"$REPO/.git/case-control/fail.$1.$2"
}

asset() { # asset <tag> [--pad <bytes>] <entry>... -- that release's record
  local tag=$1
  shift
  python3 "$T/asset.py" "$STUB/asset.$tag" "${tag#v}" "$@"
}

RC=0
OUT=""
run_check() { # run_check <last tag> <version> [<confirmed>] -- the check, no argument
  RC=0
  OUT=$(cd "$REPO" && RELEASE_LAST_TAG="$1" RELEASE_VERSION="$2" \
    RELEASE_CONFIRMED_DROPS="${3:-}" "$BASH" scripts/release-eval-check.sh 2>&1) || RC=$?
}

run_args() { # run_args <arg>... -- the check with arguments, last tag v0.40.0
  RC=0
  OUT=$(cd "$REPO" && RELEASE_LAST_TAG=v0.40.0 RELEASE_VERSION=0.41.0 \
    "$BASH" scripts/release-eval-check.sh "$@" 2>&1) || RC=$?
}

run_finalize() { # run_finalize <last tag> <version>
  RC=0
  OUT=$(cd "$REPO" && RELEASE_LAST_TAG="$1" RELEASE_VERSION="$2" \
    "$BASH" scripts/release-eval-check.sh --finalize 2>&1) || RC=$?
}

record_field() { # record_field <python expression over r> -- read the state record
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' \
    "$STATE/eval-pass-rates.json" "$1" 2>/dev/null
}

case_runs() { # the fixture case runs so far, sorted, comma-separated
  if [ -f "$REPO/.git/case-runs" ]; then
    sort "$REPO/.git/case-runs" | tr '\n' ,
  fi
}
run_count() {
  if [ -f "$REPO/.git/case-runs" ]; then
    wc -l <"$REPO/.git/case-runs" | tr -d ' '
  else
    echo 0
  fi
}
calls() { grep -c "^$1 " "$CALLS" || true; }
download_tags() { sed -n 's/^gh release download \([^ ]*\) .*/\1/p' "$CALLS" | tr '\n' ' '; }
last_line() { printf '%s\n' "$OUT" | tail -n 1; }
has_line() { grep -qxF -- "$1" <<<"$OUT"; }
has_text() { grep -qF -- "$1" <<<"$OUT"; }

# -- every skill's script cases run, and nothing else -------------------------

new_case
run_check "" 0.41.0
HOST=$(hostname 2>/dev/null || uname -n)
if [ "$RC" -eq 0 ] && has_line "Eval check host: $HOST" \
  && has_line "PASS 1 one" && has_line "PASS 2 two" \
  && [ "$(grep -c '^PASS ' <<<"$OUT")" = 3 ] \
  && has_line "REFUSED 1 graded-one: graded cases don't run" \
  && has_line "script cases: 3 of 3 passed" \
  && [ "$(grep -cx 'script cases: 3 of 3 passed' <<<"$OUT")" = 2 ] \
  && has_line "model-graded cases: not run" \
  && has_text "no baseline: no last tag, so no previous release"; then
  pass "a clean run prints the host, the runner's lines, the totals, the graded line and no baseline, and exits 0"
else
  fail "clean run (rc=$RC): $OUT"
fi
if ! grep -qiE 'nested|credential' <<<"$OUT"; then
  pass "no line about nested eval sessions"
else
  fail "nested-session line printed: $OUT"
fi
if [ "$(record_field 'sorted(r["skills"])')" = "['alpha', 'beta', 'gamma']" ] \
  && [ "$(record_field 'all(e["models"] == ["script"] for e in r["skills"].values())')" = True ] \
  && [ "$(record_field '(r["skills"]["gamma"]["assertions_passed"], r["skills"]["gamma"]["assertions_graded"], r["skills"]["gamma"]["cases"], "pass_rate" in r["skills"]["gamma"])')" = "(0, 0, [], False)" ]; then
  pass "the record holds exactly alpha, beta and gamma, each on models [script], gamma with zero counts"
else
  fail "record: $(cat "$STATE/eval-pass-rates.json" 2>/dev/null)"
fi
EXPECTED_MARKER=$(printf 'head %s\nlast_tag \nskill alpha\nskill beta\nskill gamma' "$(git -C "$REPO" rev-parse HEAD)")
if [ "$(cat "$STATE/marker" 2>/dev/null)" = "$EXPECTED_MARKER" ]; then
  pass "the marker names HEAD, the empty last tag and the three skills with evals.json"
else
  fail "marker: $(cat "$STATE/marker" 2>/dev/null)"
fi
if [ "$(case_runs)" = "alpha one,alpha two,beta one," ] \
  && [ "$(calls claude)" = 0 ] && [ "$(calls run-evals)" = 0 ] && [ "$(calls gh)" = 0 ]; then
  pass "each script case ran once; no claude, run-evals.sh or gh call"
else
  fail "case runs $(case_runs); calls: $(cat "$CALLS")"
fi

# -- any failing case stops the check until a person confirms it --------------

new_case
fail_case alpha two
run_check "" 0.41.0
if [ "$RC" -eq 5 ] && has_line "FAIL 2 two: exited 1" \
  && has_line "script cases: 2 of 3 passed" && has_line "model-graded cases: not run" \
  && has_line "case alpha/two: failing, no baseline" \
  && [ "$(last_line)" = "confirm: RELEASE_CONFIRMED_DROPS=alpha" ]; then
  pass "a failing case exits 5 with its label and the confirm line last"
else
  fail "failing case (rc=$RC): $OUT"
fi
BEFORE=$(run_count)
run_check "" 0.41.0 beta
if [ "$RC" -eq 5 ] && [ "$(last_line)" = "confirm: RELEASE_CONFIRMED_DROPS=alpha" ] \
  && [ "$(run_count)" = "$BEFORE" ]; then
  pass "confirming another skill still exits 5 with the same confirm line"
else
  fail "other skill confirmed (rc=$RC): $OUT"
fi
run_check "" 0.41.0 alpha
if [ "$RC" -eq 0 ] \
  && has_line "Confirmation re-run: comparing the saved summary, running no case." \
  && [ "$(run_count)" = "$BEFORE" ] \
  && has_line "script cases: 2 of 3 passed" && has_line "model-graded cases: not run" \
  && has_line "confirmed: alpha" && ! grep -q '^Eval check host:' <<<"$OUT"; then
  pass "confirming the failing skill compares the saved summary, runs no case and exits 0"
else
  fail "confirmed (rc=$RC): $OUT"
fi
new_commit
run_check "" 0.41.0 alpha
if [ "$(run_count)" = $((BEFORE + 3)) ] && ! has_text "Confirmation re-run"; then
  pass "after a new commit a confirmation runs the cases again"
else
  fail "confirmation after a new commit (rc=$RC): $OUT"
fi

new_case
fail_case alpha two
fail_case beta one
run_check "" 0.41.0
if [ "$RC" -eq 5 ] && [ "$(last_line)" = "confirm: RELEASE_CONFIRMED_DROPS=alpha,beta" ]; then
  pass "failing cases in two skills name both in the confirm line"
else
  fail "two failing skills (rc=$RC): $OUT"
fi
run_check "" 0.41.0 alpha
[ "$RC" -eq 5 ] && pass "confirming one of two failing skills still exits 5" \
  || fail "one of two confirmed (rc=$RC): $OUT"
run_check "" 0.41.0 alpha,beta
[ "$RC" -eq 0 ] && pass "confirming both failing skills exits 0" || fail "both confirmed (rc=$RC): $OUT"

# -- the baseline picks the label and never the exit ---------------------------

check_label() { # check_label <description> <expected label> <expected no-baseline text or ->
  if [ "$RC" -eq 5 ] && has_line "case alpha/two: $2" \
    && [ "$(last_line)" = "confirm: RELEASE_CONFIRMED_DROPS=alpha" ] \
    && { [ "$3" = - ] || has_text "$3"; }; then
    pass "$1"
  else
    fail "$1 (rc=$RC): $OUT"
  fi
}

new_case
asset v0.40.0 alpha-script-pass
fail_case alpha two
run_check v0.40.0 0.41.0
check_label "a case that passed in the baseline is regressed" regressed -
if grep -q '^gh release download v0.40.0 --repo example-org/example-repo --pattern eval-pass-rates.json --dir ' "$CALLS"; then
  pass "downloads the previous record by tag, pinned repo and exact asset name"
else
  fail "download call: $(cat "$CALLS")"
fi
DL_DIR=$(sed -n 's/^gh release download .* --dir //p' "$CALLS")
case "$DL_DIR" in
  "$REPO"*) fail "downloaded inside the repository: $DL_DIR" ;;
  "") fail "no download directory: $(cat "$CALLS")" ;;
  *) [ ! -e "$DL_DIR" ] && pass "downloads into a temporary directory outside the repository, removed after" \
    || fail "download dir left behind: $DL_DIR" ;;
esac

new_case
asset v0.40.0 alpha-script-fail
fail_case alpha two
run_check v0.40.0 0.41.0
check_label "a case that failed in the baseline is still failing" "still failing" -

new_case
fail_case alpha two
run_check v0.40.0 0.41.0
check_label "no asset on the last release: failing, no baseline" "failing, no baseline" \
  "no baseline: no eval-pass-rates.json on the v0.40.0 release"

new_case
asset v0.40.0 alpha-graded
fail_case alpha two
run_check v0.40.0 0.41.0
check_label "a graded baseline entry is no baseline for a script case" "failing, no baseline" -

for kind in alpha-script-pass alpha-script-fail none alpha-graded; do
  new_case
  [ "$kind" = none ] || asset v0.40.0 "$kind"
  run_check v0.40.0 0.41.0
  if [ "$RC" -eq 0 ] && ! grep -q '^case ' <<<"$OUT"; then
    pass "every case passing exits 0 against the $kind baseline"
  else
    fail "all passing against $kind (rc=$RC): $OUT"
  fi
done

new_case
tag_head v0.39.0 v0.40.0 v0.41.0
asset v0.41.0 alpha-graded
asset v0.40.0 alpha-script-pass scope-script
fail_case alpha two
run_check v0.41.0 0.42.0
if [ "$(download_tags)" = "v0.41.0 v0.40.0 v0.39.0 " ]; then
  pass "walks the last tag then the older tags, newest first"
else
  fail "download order: $(download_tags)"
fi
check_label "an older release's script entry labels the case when the last release's is graded" regressed -
if [ "$(record_field 'sorted(r["skills"])')" = "['alpha', 'beta', 'gamma']" ]; then
  pass "a baseline record's scope entry doesn't reach this run's record"
else
  fail "record skills: $(record_field 'sorted(r["skills"])')"
fi

# -- a record over the size cap is skipped before it is read -------------------

new_case
asset v0.40.0 --pad 1048577 alpha-script-pass
fail_case alpha two
run_check v0.40.0 0.41.0
if [ "$(wc -c <"$STUB/asset.v0.40.0" | tr -d ' ')" = 1048577 ]; then
  check_label "a record one byte over the cap is no baseline" "failing, no baseline" \
    "no baseline: the file is over the 1048576-byte size cap"
else
  fail "fixture size: $(wc -c <"$STUB/asset.v0.40.0")"
fi

new_case
asset v0.40.0 --pad 1048576 alpha-script-pass
fail_case alpha two
run_check v0.40.0 0.41.0
if [ "$(wc -c <"$STUB/asset.v0.40.0" | tr -d ' ')" = 1048576 ]; then
  check_label "a record of exactly the cap is read" regressed -
else
  fail "fixture size: $(wc -c <"$STUB/asset.v0.40.0")"
fi

# -- a missing prerequisite or a failed download exits 1 -----------------------

new_case
if PATH="/usr/bin:/bin" command -v koto >/dev/null 2>&1; then
  echo "SKIP: koto sits in /usr/bin or /bin, so the no-koto case can't build its PATH"
else
  RC=0
  OUT=$(cd "$REPO" && PATH="$NOKOTO:/usr/bin:/bin" RELEASE_LAST_TAG=v0.40.0 \
    RELEASE_VERSION=0.41.0 "$BASH" scripts/release-eval-check.sh 2>&1) || RC=$?
  if [ "$RC" -eq 1 ] && has_text koto && [ "${OUT%run the check again}" != "$OUT" ] \
    && [ "$(run_count)" = 0 ] && [ "$(calls gh)" = 0 ] && [ ! -e "$STATE/eval-pass-rates.json" ]; then
    pass "no koto on PATH exits 1 naming koto, before any case, gh call or record"
  else
    fail "no koto (rc=$RC): $OUT"
  fi
fi

new_case
write_evals alpha '{not json'
commit_all broken
run_check "" 0.41.0
if [ "$RC" -eq 1 ] && has_text "exited 2" && [ "${OUT%run the check again}" != "$OUT" ] \
  && [ ! -e "$STATE/eval-pass-rates.json" ] && [ "$(run_count)" = 0 ]; then
  pass "a runner exit 2 exits 1 naming the exit code, with no record"
else
  fail "runner exit 2 (rc=$RC): $OUT"
fi

new_case
write_evals Bad_Name '{"skill_name": "Bad_Name", "evals": []}'
commit_all bad-name
run_check "" 0.41.0
if [ "$RC" -eq 1 ] && has_text "Bad_Name" && [ "$(run_count)" = 0 ]; then
  pass "a skill directory off the name pattern exits 1 before any case runs"
else
  fail "bad skill name (rc=$RC): $OUT"
fi

new_case
echo 'HTTP 502: bad gateway' >"$STUB/gh-error.v0.40.0"
run_check v0.40.0 0.41.0
if [ "$RC" -eq 1 ] \
  && has_text "could not download eval-pass-rates.json from the v0.40.0 release: HTTP 502: bad gateway" \
  && [ "${OUT%run the check again}" != "$OUT" ] && ! has_text "no baseline"; then
  pass "a download error that is not not-found exits 1 with gh's reason, not no baseline"
else
  fail "download error (rc=$RC): $OUT"
fi

new_case
git -C "$REPO" remote set-url origin https://example.com/example-org/example-repo.git
run_check v0.40.0 0.41.0
if [ "$RC" -eq 1 ] && [ "$(run_count)" = 0 ]; then
  pass "an origin that isn't on GitHub fails before any case runs"
else
  fail "non-GitHub origin (rc=$RC): $OUT"
fi

# -- the check takes no options ---------------------------------------------------

new_case
for bad in "--critical work-on" "--critical-runs 1" "--model sonnet" "--tolerance 0.05" \
  "--all" "alpha" "--finalize --model sonnet"; do
  # shellcheck disable=SC2086 # each case is one or more words by design
  run_args $bad
  if [ "$RC" -eq 2 ] && has_text "Usage:"; then
    pass "$bad is a usage error"
  else
    fail "$bad (rc=$RC): $OUT"
  fi
done
run_check 0.40.0 0.41.0
[ "$RC" -eq 2 ] && pass "a last tag off the pattern is a usage error" || fail "bad tag (rc=$RC): $OUT"
run_check v0.40.0 v0.41.0
[ "$RC" -eq 2 ] && pass "a version off the pattern is a usage error" || fail "bad version (rc=$RC): $OUT"
run_check v0.40.0 0.41.0 'Bad;name'
[ "$RC" -eq 2 ] && pass "an invalid confirmed name is a usage error" || fail "bad confirmed (rc=$RC): $OUT"
if [ "$(run_count)" = 0 ] && [ "$(calls gh)" = 0 ] && [ ! -e "$STATE" ]; then
  pass "usage errors run no case and call no gh"
else
  fail "usage errors ran something: $(case_runs) $(cat "$CALLS")"
fi

# -- --finalize ----------------------------------------------------------------

new_case
run_check "" 0.41.0
run_finalize "" 0.41.1
if [ "$RC" -eq 0 ] && [ "$(last_line)" = "asset: $STATE/eval-pass-rates.json" ] \
  && [ "$(record_field 'r["version"]')" = 0.41.1 ] \
  && [ "$(record_field 'sorted(set(e["measured_at"] for e in r["skills"].values()))')" = "['0.41.1']" ]; then
  pass "--finalize stamps the version and every skill's measured_at, and prints the asset line"
else
  fail "finalize (rc=$RC): $OUT"
fi
run_finalize v0.40.0 0.41.1
[ "$RC" -eq 1 ] && pass "--finalize refuses a marker for another last tag" || fail "finalize other tag (rc=$RC): $OUT"
new_commit
run_finalize "" 0.41.1
[ "$RC" -eq 1 ] && pass "--finalize refuses a marker for another HEAD" || fail "finalize other HEAD (rc=$RC): $OUT"

new_case
run_check "" 0.41.0
rm -f "$STATE/eval-pass-rates.json"
run_finalize "" 0.41.0
[ "$RC" -eq 1 ] && pass "--finalize refuses with no record" || fail "finalize no record (rc=$RC): $OUT"

new_case
run_finalize "" 0.41.0
[ "$RC" -eq 1 ] && pass "--finalize refuses with no marker" || fail "finalize no marker (rc=$RC): $OUT"

new_case
mkdir -p "$STATE"
echo stale >"$STATE/eval-pass-rates.json"
echo stale >"$STATE/7.json"
run_check "" 0.41.0
if [ "$RC" -eq 0 ] && [ ! -e "$STATE/7.json" ] && [ "$(record_field 'r["version"]')" = 0.41.0 ]; then
  pass "a fresh check removes a stale record and stale files"
else
  fail "stale state (rc=$RC): $OUT"
fi

# -- never uploads, never names the graded harness or the model CLI -------------

if grep -q '^gh release upload' "$T/all-calls.log"; then
  fail "a case called gh release upload"
else
  pass "no case called gh release upload"
fi
if grep -nE 'run-evals|claude' "$CHECK_SRC" >/dev/null; then
  fail "the check names run-evals.sh or claude: $(grep -nE 'run-evals|claude' "$CHECK_SRC")"
else
  pass "the check names neither run-evals.sh nor claude"
fi

echo ""
echo "release-eval-check: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

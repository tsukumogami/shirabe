#!/usr/bin/env bash
# Wall-clock for the two full declarations, mean of 20 runs.
export PATH="$HOME/.tsuku/tools/current:$PATH"

workon_calls() {
  shirabe --help; shirabe transition --help; shirabe validate --help
  shirabe work-summary --help; koto --help; koto session --help; koto context --help
  command -v gh; command -v jq; command -v git
}
scope_calls() {
  shirabe --help; shirabe validate --help; shirabe transition --help
  shirabe finalize-chain --help; shirabe roadmap --help; shirabe roadmap populate --help
  command -v gh
}
# Worst realistic case: a skill that also touches gh's surface (20ms tool)
workon_plus_gh() { workon_calls; gh --help; git --help; }

bench() {
  local label="$1"; shift
  "$@" >/dev/null 2>&1
  local s e; s=$(/usr/bin/python3 -c 'import time;print(time.time())')
  local i; for i in $(seq 1 20); do "$@" >/dev/null 2>&1; done
  e=$(/usr/bin/python3 -c 'import time;print(time.time())')
  /usr/bin/python3 -c "print(f'{($e-$s)*50:8.1f} ms   $label')"
}

echo "=== full declaration wall time (mean of 20, sequential) ==="
bench "/work-on   (7 help + 3 command -v)" workon_calls
bench "/scope     (6 help + 1 command -v)" scope_calls
bench "/work-on + gh/git surface (9 help)" workon_plus_gh

echo
echo "=== cold cache (first run after page-cache drop is not testable; "
echo "    reporting first-invocation-of-session instead) ==="

#!/usr/bin/env bash
export PATH="$HOME/.tsuku/tools/current:$PATH"
# The 10 levels the REAL /work-on declaration reaches, sequential.
workon10() {
  koto --help; koto init --help; koto next --help
  koto decisions --help; koto decisions record --help
  koto context --help; koto context add --help
  koto overrides --help
  shirabe --help; shirabe validate --help
  command -v gh; command -v git; command -v jq
}
# The 3 levels the REAL /scope declaration reaches.
scope3() {
  shirabe --help; shirabe validate --help; shirabe slug-prefix-detect --help
  command -v gh; command -v git
}
# Absolute worst case in the corpus: add gh + git surface probes (20ms/10ms tools)
worst() { workon10; gh --help; git --help; }

bench() {
  local label="$1"; shift
  "$@" >/dev/null 2>&1
  local s e; s=$(/usr/bin/python3 -c 'import time;print(time.time())')
  local i; for i in $(seq 1 20); do "$@" >/dev/null 2>&1; done
  e=$(/usr/bin/python3 -c 'import time;print(time.time())')
  /usr/bin/python3 -c "print(f'{($e-$s)*50:8.1f} ms   $label')"
}
echo "=== real declarations, mean of 20 runs, warm ==="
bench "/work-on  10 help calls + 3 command -v" workon10
bench "/scope     3 help calls + 2 command -v" scope3
bench "worst case 12 help calls (incl gh,git)" worst

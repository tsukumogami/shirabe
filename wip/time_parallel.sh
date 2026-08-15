#!/usr/bin/env bash
# Is parallelising the probes worth the complexity?
export PATH="$HOME/.tsuku/tools/current:$PATH"

seq_run() {
  shirabe --help; shirabe transition --help; shirabe validate --help
  shirabe work-summary --help; koto --help; koto session --help; koto context --help
  gh --help; git --help
}
par_run() {
  { shirabe --help; } & { shirabe transition --help; } & { shirabe validate --help; } &
  { shirabe work-summary --help; } & { koto --help; } & { koto session --help; } &
  { koto context --help; } & { gh --help; } & { git --help; } &
  wait
}
bench() {
  local label="$1"; shift
  "$@" >/dev/null 2>&1
  local s e; s=$(/usr/bin/python3 -c 'import time;print(time.time())')
  local i; for i in $(seq 1 20); do "$@" >/dev/null 2>&1; done
  e=$(/usr/bin/python3 -c 'import time;print(time.time())')
  /usr/bin/python3 -c "print(f'{($e-$s)*50:8.1f} ms   $label')"
}
bench "9 probes, sequential" seq_run
bench "9 probes, parallel"   par_run

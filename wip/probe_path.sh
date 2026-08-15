#!/usr/bin/env bash
# Establishes the R18/R28 mechanic: distinguishing absent-from-host from
# present-under-a-known-root-but-off-PATH, with the root overridable.

# R28 override: the roots the check consults, in order.
: "${SHIRABE_PREFLIGHT_ROOTS:=$HOME/.tsuku/tools/current:$HOME/.shirabe/bin:$HOME/.local/bin}"

resolve() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'ON_PATH\t%s\n' "$(command -v "$tool")"; return 0
  fi
  local IFS=:
  local d
  for d in $SHIRABE_PREFLIGHT_ROOTS; do
    if [ -x "$d/$tool" ]; then printf 'OFF_PATH\t%s\n' "$d/$tool"; return 0; fi
  done
  printf 'ABSENT\t-\n'; return 1
}

echo "=== with a PATH that excludes tsuku (the unsourced-env shell) ==="
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
for t in shirabe koto gh jq git python3; do printf '%-8s ' "$t"; resolve "$t"; done

echo
echo "=== timing: resolve() over 6 tools, off-PATH worst case ==="
s=$(/usr/bin/python3 -c 'import time;print(time.time())')
for i in 1 2 3 4 5 6 7 8 9 10; do
  for t in shirabe koto gh jq git python3; do resolve "$t" >/dev/null 2>&1; done
done
e=$(/usr/bin/python3 -c 'import time;print(time.time())')
/usr/bin/python3 -c "print(f'{($e-$s)*100:.2f} ms per full 6-tool resolution pass')"

echo
echo "=== R28 override honoured: empty roots => everything ABSENT ==="
SHIRABE_PREFLIGHT_ROOTS="/nonexistent"
for t in shirabe koto; do printf '%-8s ' "$t"; resolve "$t"; done

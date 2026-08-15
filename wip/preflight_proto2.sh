#!/usr/bin/env bash
# End-to-end preflight prototype, v2: file-backed memo so the call counter and
# the cache survive command-substitution subshells.
export PATH="$HOME/.tsuku/tools/current:$PATH"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
COUNT="$WORK/count"

reset() { : > "$COUNT"; rm -f "$WORK"/lvl.*; }
calls() { wc -l < "$COUNT" | tr -d ' '; }

# One --help call per LEVEL, memoized on disk.
level() {
  local key; key=$(printf '%s_' "$@" | tr -c 'A-Za-z0-9_' '_')
  local f="$WORK/lvl.$key"
  if [ ! -f "$f" ]; then
    echo "$*" >> "$COUNT"
    local help; help=$("$@" --help 2>&1)
    {
      printf 'SUBS: '
      printf '%s\n' "$help" | awk '/^Commands:/{b=1;next} /^[A-Za-z].*:$/{b=0} b&&/^  [a-z]/{printf "%s ",$1}'
      printf '\nFLAGS: '
      printf '%s\n' "$help" | awk '/^Options:/{b=1;next} /^[A-Za-z].*:$/{b=0}
        b&&match($0,/^ {2,6}(-[a-zA-Z], )?--[a-z0-9][a-z0-9-]*/){l=$0;sub(/^ +/,"",l);
        sub(/^-[a-zA-Z], /,"",l); split(l,a,/[ =<]/); printf "%s ",a[1]}'
      printf '\n'
    } > "$f"
  fi
  cat "$f"
}

subs_of()  { level "$@" | sed -n 's/^SUBS: //p'; }
flags_of() { level "$@" | sed -n 's/^FLAGS: //p'; }

# check_path <tool> <sub...> [-- <flag...>]
check_path() {
  local -a path=() flags=(); local seen=0 a
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen=1; continue; fi
    if [ "$seen" = 1 ]; then flags+=("$a"); else path+=("$a"); fi
  done
  local -a cur=("${path[0]}"); local i seg
  for ((i=1;i<${#path[@]};i++)); do
    seg="${path[$i]}"
    local subs=" $(subs_of "${cur[@]}") "
    case "$subs" in *" $seg "*) ;; *) echo "  MISSING-SUB  ${cur[*]} -> $seg"; return 1;; esac
    cur+=("$seg")
  done
  if [ "${#flags[@]}" -gt 0 ]; then
    local fl=" $(flags_of "${cur[@]}") "; local f
    for f in "${flags[@]}"; do
      case "$fl" in *" $f "*) ;; *) echo "  MISSING-FLAG ${cur[*]} $f"; return 1;; esac
    done
  fi
  return 0
}

presence() { command -v "$1" >/dev/null 2>&1 || echo "  MISSING-TOOL $1"; }

time_it() {
  local label="$1"; shift
  reset
  local s e; s=$(/usr/bin/python3 -c 'import time;print(time.time())')
  "$@"
  e=$(/usr/bin/python3 -c 'import time;print(time.time())')
  /usr/bin/python3 -c "print(f'  {label!r:24} -> {int(open('$COUNT').read().count(chr(10)))} help calls, {($e-$s)*1000:6.1f} ms')" 2>/dev/null \
    || echo "  $label -> $(calls) help calls"
}

workon() {
  presence gh; presence jq; presence git
  check_path shirabe transition -- --reason
  check_path shirabe validate -- --pr-body
  check_path shirabe work-summary render
  check_path koto next
  check_path koto session start
  check_path koto context get
  check_path koto context add
  check_path koto status
}

scope() {
  presence gh
  check_path shirabe validate -- --lifecycle-chain --coordination-body --merge-gate
  check_path shirabe transition -- --reason
  check_path shirabe finalize-chain -- --dry-run
  check_path shirabe slug-prefix-detect
  check_path shirabe roadmap populate -- --no-issues --issues
}

echo "=== /work-on ==="; time_it "/work-on" workon
echo; echo "  levels actually probed:"; sed 's/^/    /' "$COUNT"

echo; echo "=== /scope ==="; time_it "/scope" scope
echo; echo "  levels actually probed:"; sed 's/^/    /' "$COUNT"

echo; echo "=== shirabe#279: koto context set ==="
reset; check_path koto context set; echo "  calls: $(calls)"

echo; echo "=== missing flag: shirabe validate --nonexistent-flag ==="
reset; check_path shirabe validate -- --nonexistent-flag; echo "  calls: $(calls)"

#!/usr/bin/env bash
# Probe the REAL declarations for /work-on and /scope, as enumerated from the
# skill trees. Reports call count and any missing surface found.
export PATH="$HOME/.tsuku/tools/current:$PATH"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT; COUNT="$WORK/count"; : > "$COUNT"
reset() { : > "$COUNT"; rm -f "$WORK"/lvl.*; }
calls() { wc -l < "$COUNT" | tr -d ' '; }

level() {
  local key; key=$(printf '%s_' "$@" | tr -c 'A-Za-z0-9_' '_'); local f="$WORK/lvl.$key"
  if [ ! -f "$f" ]; then
    echo "$*" >> "$COUNT"
    local help; help=$("$@" --help 2>&1)
    { printf 'SUBS: '
      printf '%s\n' "$help" | awk '/^Commands:/{b=1;next} /^[A-Za-z].*:$/{b=0} b&&/^  [a-z]/{printf "%s ",$1}'
      printf '\nFLAGS: '
      printf '%s\n' "$help" | awk '/^Options:/{b=1;next} /^[A-Za-z].*:$/{b=0}
        b&&match($0,/^ {2,6}(-[a-zA-Z], )?--[a-z0-9][a-z0-9-]*/){l=$0;sub(/^ +/,"",l);
        sub(/^-[a-zA-Z], /,"",l); split(l,a,/[ =<]/); printf "%s ",a[1]}'
      printf '\n'; } > "$f"
  fi; cat "$f"
}
subs_of()  { level "$@" | sed -n 's/^SUBS: //p'; }
flags_of() { level "$@" | sed -n 's/^FLAGS: //p'; }

check() {
  local -a path=() flags=(); local seen=0 a
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen=1; continue; fi
    if [ "$seen" = 1 ]; then flags+=("$a"); else path+=("$a"); fi; done
  local -a cur=("${path[0]}"); local i seg ok=0
  for ((i=1;i<${#path[@]};i++)); do
    seg="${path[$i]}"; local subs=" $(subs_of "${cur[@]}") "
    case "$subs" in *" $seg "*) ;; *) echo "  !! MISSING SUBCOMMAND: '${cur[*]} $seg'"; return 1;; esac
    cur+=("$seg"); done
  if [ "${#flags[@]}" -gt 0 ]; then
    local fl=" $(flags_of "${cur[@]}") "; local f
    for f in "${flags[@]}"; do
      case "$fl" in *" $f "*) ;; *) echo "  !! MISSING FLAG: '$f' on '${cur[*]}'"; ok=1;; esac
    done; fi
  return $ok
}

echo "=== /work-on real declaration ==="
reset
check koto version
check koto init      -- --template --var
check koto next      -- --with-data
check koto rewind
check koto workflows
check koto decisions record -- --with-data
check koto context add      -- --from-file
check koto context get
check koto context exists
check koto context remove
check koto overrides list
check shirabe validate -- --pr-body --pr-title
check shirabe pr-body-hook
echo "  help calls: $(calls)"; sed 's/^/    probed: /' "$COUNT"

echo
echo "=== /scope real declaration ==="
reset
check shirabe validate -- --format --visibility --coordination-body --merge-gate
check shirabe slug-prefix-detect -- --docs-root
echo "  help calls: $(calls)"; sed 's/^/    probed: /' "$COUNT"

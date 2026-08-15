#!/usr/bin/env bash
# R12/R27: single entry point, zero bytes across stdout+stderr when satisfied.
export PATH="$HOME/.tsuku/tools/current:$PATH"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

level() {
  local key; key=$(printf '%s_' "$@" | tr -c 'A-Za-z0-9_' '_'); local f="$WORK/lvl.$key"
  [ -f "$f" ] || { local h; h=$("$@" --help 2>&1)
    { printf 'SUBS: '; printf '%s\n' "$h" | awk '/^Commands:/{b=1;next}/^[A-Za-z].*:$/{b=0}b&&/^  [a-z]/{printf "%s ",$1}'
      printf '\nFLAGS: '; printf '%s\n' "$h" | awk '/^Options:/{b=1;next}/^[A-Za-z].*:$/{b=0}
      b&&match($0,/^ {2,6}(-[a-zA-Z], )?--[a-z0-9][a-z0-9-]*/){l=$0;sub(/^ +/,"",l);sub(/^-[a-zA-Z], /,"",l);
      split(l,a,/[ =<]/);printf "%s ",a[1]}'; printf '\n'; } > "$f"; }
  cat "$f"
}
check() {
  local -a p=() fl=(); local seen=0 a
  for a in "$@"; do [ "$a" = "--" ] && { seen=1; continue; }
    [ "$seen" = 1 ] && fl+=("$a") || p+=("$a"); done
  local -a cur=("${p[0]}"); local i
  for ((i=1;i<${#p[@]};i++)); do
    case " $(level "${cur[@]}" | sed -n 's/^SUBS: //p') " in *" ${p[$i]} "*) ;; *) return 1;; esac
    cur+=("${p[$i]}"); done
  local f; for f in "${fl[@]}"; do
    case " $(level "${cur[@]}" | sed -n 's/^FLAGS: //p') " in *" $f "*) ;; *) return 1;; esac; done
}
# SATISFIED declaration (/scope's real one, all present on this host)
entrypoint_satisfied() {
  check shirabe validate -- --format --visibility --coordination-body --merge-gate || echo "finding"
  check shirabe slug-prefix-detect -- --docs-root || echo "finding"
  command -v gh >/dev/null 2>&1 || echo "finding"
  command -v git >/dev/null 2>&1 || echo "finding"
}
out=$(entrypoint_satisfied 2>&1)
printf 'combined stdout+stderr byte count: %s\n' "$(printf '%s' "$out" | wc -c | tr -d ' ')"
[ -z "$out" ] && echo "R12 SATISFIED: zero bytes" || { echo "R12 VIOLATED, emitted:"; printf '%s\n' "$out"; }

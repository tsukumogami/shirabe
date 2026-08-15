#!/usr/bin/env bash
# R19: an emitted command must be one established to work on THIS host.
# This enumerates the candidate routes and probes each for availability.
export PATH="$HOME/.tsuku/bin:$HOME/.tsuku/tools/current:$PATH"

probe() { # probe <label> <cmd...>
  local label="$1"; shift
  if command -v "$1" >/dev/null 2>&1; then
    printf 'AVAILABLE   %-22s (%s)\n' "$label" "$(command -v "$1")"
  else
    printf 'UNAVAILABLE %-22s (%s not found)\n' "$label" "$1"
  fi
}

echo "=== candidate install routes on this host ==="
probe "tsuku"      tsuku
probe "homebrew"   brew
probe "cargo"      cargo
probe "apt-get"    apt-get
probe "curl (net)" curl

echo
echo "=== os ==="
uname -s; uname -m

echo
echo "=== does tsuku know these recipes? ==="
for r in koto shirabe gh; do
  printf '%-8s ' "$r"
  tsuku info "$r" 2>&1 | head -2 | tr '\n' ' '
  echo
done

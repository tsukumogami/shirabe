#!/usr/bin/env bash
# Strict extractor: only flags DEFINED in the Options block count, never flags
# merely MENTIONED in a description. Definition lines carry 2-6 leading spaces;
# wrapped descriptions carry 8+.
export PATH="$HOME/.tsuku/tools/current:$PATH"

flags_strict() {
  "$@" --help 2>&1 | awk '
    /^Options:/ {inblock=1; next}
    /^[A-Za-z].*:$/ {inblock=0}
    inblock && match($0, /^ {2,6}(-[a-zA-Z], )?--[a-z0-9][a-z0-9-]*/) {
      line=$0
      sub(/^ +/, "", line)
      sub(/^-[a-zA-Z], /, "", line)
      split(line, a, /[ =<]/)
      print a[1]
    }
  ' | sort -u
}

echo "### STRICT flags: shirabe roadmap populate"
flags_strict shirabe roadmap populate
echo
echo "### STRICT flags: shirabe validate"
flags_strict shirabe validate
echo
echo "### STRICT flags: shirabe transition"
flags_strict shirabe transition
echo
echo "### LOOSE-vs-STRICT diff on 'shirabe roadmap' GROUP help"
echo "-- loose (grep anywhere) picks up prose mentions:"
shirabe roadmap --help 2>&1 | grep -oE '(^|[ ,`])--[a-z0-9][a-z0-9-]*' | tr -d ' ,`' | sort -u
echo "-- strict (Options block, definition position only):"
flags_strict shirabe roadmap

#!/usr/bin/env bash
# Fail when a SKILL.md carries a load-time injected command that can abort the
# skill it belongs to.
#
# A backtick-quoted command written after a `!` at column 0 is not prose. The
# harness executes it while loading the skill, and a non-zero exit from it
# aborts the whole invocation -- the model never sees the body. Two live defects
# in skills/inflight/SKILL.md came from that, both now fixed:
#
#   - A documentation line, `!`shirabe work-summary track <pr-url> ...``, that
#     was written to show a verb the agent should run later. `<pr-url>` is not a
#     placeholder to a shell, it is an input redirection from a file that does
#     not exist. The skill had not loaded on any host since the line landed.
#   - A bare `!`shirabe work-summary render``. The binary always exits 0 once it
#     runs, but on a host without it the shell returns 127 and the skill dies
#     rather than degrading to the empty-state its own body documents.
#
# Both are cheap to reintroduce and invisible when reintroduced -- the failure
# mode is a skill that silently does not exist. So the invariant is held here
# instead of by review. Three rules, checked per injected line:
#
#   1. GUARD. The line's last subcommand must be one that cannot exit non-zero
#      (`true`, `:`, `echo`, `printf`), and it must not sit behind `&&`, which
#      skips it on exactly the failure it would have absorbed. That is the
#      `|| true` / `|| echo ...` shape.
#   2. DECLARATION. Every subcommand -- split on `&&`, `||`, `;`, `|`, `&` --
#      must be covered by an `allowed-tools:` entry in the same file's
#      frontmatter. Permission patterns do NOT compose across shell operators:
#      each side of a `||` is matched on its own, and an uncovered subcommand
#      deletes the skill silently rather than degrading it.
#   3. NO REDIRECTION. No unquoted `<` or `>` outside the stream-merge idioms
#      (`2>&1`, `>/dev/null`, `2>/dev/null`, `&>/dev/null`). This is the rule
#      the documentation defect teaches: injection syntax is for commands
#      intended to execute at load, and a command shown to the reader as an
#      example must never carry a leading `!` at column 0.
#
# Markdown fencing is not honored. The harness does not parse markdown before
# resolving injections, so a `!`-prefixed line inside a fenced block is injected
# exactly like one in running prose, and this scan treats it the same way.
#
# Usage:
#   scripts/check-skill-injection.sh                # scans <repo>/skills
#   scripts/check-skill-injection.sh PATH [PATH...] # scans files or directories
#
# Exit codes:
#   0 -- every injected line satisfies all three rules
#   1 -- at least one injected line violates a rule
#   2 -- usage error (a named path does not exist)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Commands that cannot exit non-zero, so a line ending in one cannot abort a
# skill load. Kept deliberately short: every addition widens the guard rule.
ALWAYS_ZERO="true : echo printf"

# Redirection spellings an injected line may legitimately use. `2>&1` is in the
# rollout's own canonical line -- it merges the streams under the script's
# control so the satisfied case is unambiguously empty.
ALLOWED_REDIRECTS='2>&1 2>/dev/null &>/dev/null >/dev/null'

errors=0
files_scanned=0
lines_scanned=0

# ---------------------------------------------------------------------------
# Small helpers. Every one assigns to a global rather than echoing into a
# subshell, so the scan stays a single process on a large skills tree.
# ---------------------------------------------------------------------------

TAB=$'\t'

TRIMMED=""
trim() {
  local s="$1"
  while :; do
    case "$s" in
      ' '*|"$TAB"*) s="${s#?}" ;;
      *' '|*"$TAB") s="${s%?}" ;;
      *) break ;;
    esac
  done
  TRIMMED="$s"
}

# Build a same-length projection of a command in which every character that the
# shell would treat as quoted (or escaped) is replaced by `Q`. Operator
# splitting and the redirection scan both run against the projection, so a `||`
# or a `>` inside a quoted string is never mistaken for shell syntax.
MASKED=""
MASK_STATE=""
mask_command() {
  local s="$1" n=${#1} i=0 c state="none" out=""
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    case "$state" in
      none)
        case "$c" in
          "'") state="single"; out="${out}Q" ;;
          '"') state="double"; out="${out}Q" ;;
          '\')
            out="${out}Q"
            if [ "$((i + 1))" -lt "$n" ]; then
              out="${out}Q"
              i=$((i + 1))
            fi
            ;;
          *) out="${out}${c}" ;;
        esac
        ;;
      single)
        if [ "$c" = "'" ]; then state="none"; fi
        out="${out}Q"
        ;;
      double)
        case "$c" in
          '"') state="none"; out="${out}Q" ;;
          '\')
            out="${out}Q"
            if [ "$((i + 1))" -lt "$n" ]; then
              out="${out}Q"
              i=$((i + 1))
            fi
            ;;
          *) out="${out}Q" ;;
        esac
        ;;
    esac
    i=$((i + 1))
  done
  MASKED="$out"
  MASK_STATE="$state"
}

# Split a command into subcommands on the shell operators that end a permission
# pattern's reach. SEGS[i] is a subcommand; OPS[i] is the operator that precedes
# it (empty for the first).
SEGS=()
OPS=()
split_command() {
  local raw="$1" mask="$2"
  local n=${#2} i=0 start=0 c c2 prev op pending=""
  SEGS=()
  OPS=()
  while [ "$i" -lt "$n" ]; do
    c="${mask:$i:1}"
    c2=""
    if [ "$((i + 1))" -lt "$n" ]; then c2="${mask:$i:2}"; fi
    op=""
    if [ "$c2" = "&&" ]; then
      op="&&"
    elif [ "$c2" = "||" ]; then
      op="||"
    elif [ "$c" = ";" ]; then
      op=";"
    elif [ "$c" = "|" ]; then
      op="|"
    elif [ "$c" = "&" ]; then
      op="&"
    fi
    # A `&` or `|` immediately after a redirection operator is part of it
    # (`2>&1`, `>|out`), not a subcommand boundary.
    if [ ${#op} -eq 1 ] && [ "$i" -gt 0 ]; then
      prev="${mask:$((i - 1)):1}"
      if [ "$prev" = ">" ] || [ "$prev" = "<" ]; then op=""; fi
    fi
    if [ -n "$op" ]; then
      SEGS+=("${raw:$start:$((i - start))}")
      OPS+=("$pending")
      pending="$op"
      i=$((i + ${#op}))
      start=$i
      continue
    fi
    i=$((i + 1))
  done
  SEGS+=("${raw:$start}")
  OPS+=("$pending")
}

# Pull the `Bash(...)` patterns out of a single-line `allowed-tools:` value.
# Entries that are not Bash tool patterns (`Read`, `Glob`, ...) cannot cover a
# subcommand, so they are ignored rather than parsed.
PATTERNS=()
extract_patterns() {
  local rest="$1" inner
  PATTERNS=()
  while [ -n "$rest" ]; do
    case "$rest" in
      *"Bash("*) ;;
      *) break ;;
    esac
    rest="${rest#*Bash(}"
    case "$rest" in
      *")"*) ;;
      *) break ;;
    esac
    inner="${rest%%)*}"
    PATTERNS+=("$inner")
    rest="${rest#*)}"
  done
}

# Is one subcommand covered by one of the declared patterns? Two pattern shapes
# are recognized, matching the harness: `Bash(tool:*)` covers any invocation of
# `tool`, and anything else is a glob against the whole command line.
covered() {
  local sub="$1" p prefix
  local i=0
  while [ "$i" -lt "${#PATTERNS[@]}" ]; do
    p="${PATTERNS[$i]}"
    i=$((i + 1))
    case "$p" in
      *":*")
        prefix="${p%:\*}"
        if [ "$sub" = "$prefix" ]; then return 0; fi
        case "$sub" in
          "$prefix "*) return 0 ;;
        esac
        ;;
      *"*"*)
        case "$sub" in
          $p) return 0 ;;
        esac
        ;;
      *)
        if [ "$sub" = "$p" ]; then return 0; fi
        ;;
    esac
  done
  return 1
}

is_always_zero() {
  local head="$1" w
  for w in $ALWAYS_ZERO; do
    if [ "$head" = "$w" ]; then return 0; fi
  done
  return 1
}

report() {
  echo "FAIL: $1" >&2
  errors=$((errors + 1))
}

# ---------------------------------------------------------------------------
# The scan
# ---------------------------------------------------------------------------

check_line() {
  local rel="$1" lineno="$2" line="$3"
  local cmd body head sub op m pat
  local i last

  # The command runs from the opening backtick to the first closing one, which
  # is how the harness pairs them; anything after that is prose. A line that
  # opens an injection and never closes it is a defect on its own -- the
  # harness has no command to run and the author gets no feedback.
  body="${line#!\`}"
  case "$body" in
    *'`'*) ;;
    *)
      report "$rel:$lineno: injected line opens with '!\`' but never closes the backtick"
      echo "  $line" >&2
      echo "  An injection must be a single backtick-quoted command on one line." >&2
      return
      ;;
  esac
  cmd="${body%%\`*}"

  trim "$cmd"
  cmd="$TRIMMED"
  if [ -z "$cmd" ]; then
    report "$rel:$lineno: injected line carries an empty command"
    return
  fi

  lines_scanned=$((lines_scanned + 1))

  mask_command "$cmd"
  if [ "$MASK_STATE" != "none" ]; then
    report "$rel:$lineno: injected command has an unterminated ${MASK_STATE} quote"
    echo "  $cmd" >&2
    echo "  The harness runs this through a shell; an unbalanced quote is a syntax error," >&2
    echo "  and a syntax error is a non-zero exit that aborts the skill." >&2
    return
  fi
  m="$MASKED"

  # Rule 3 -- no unquoted redirection outside the stream-merge idioms.
  for pat in $ALLOWED_REDIRECTS; do
    m="${m//$pat}"
  done
  case "$m" in
    *"<"*|*">"*)
      report "$rel:$lineno: injected command contains an unquoted redirection"
      echo "  $cmd" >&2
      echo "  '<' and '>' are shell redirections, not placeholders. A line written to" >&2
      echo "  document a command the agent should run later must not carry a leading '!'" >&2
      echo "  at column 0 -- injection syntax is for commands intended to execute at load." >&2
      echo "  Allowed spellings: $ALLOWED_REDIRECTS" >&2
      ;;
  esac

  split_command "$cmd" "$MASKED"

  # Rule 1 -- the line must terminate in something that cannot exit non-zero.
  last=$(( ${#SEGS[@]} - 1 ))
  trim "${SEGS[$last]}"
  sub="$TRIMMED"
  head="${sub%%[ $TAB]*}"
  if ! is_always_zero "$head"; then
    report "$rel:$lineno: injected command has no exit-0 guard"
    echo "  $cmd" >&2
    echo "  A non-zero exit from an injected command aborts the entire skill invocation," >&2
    echo "  so the model never sees the body. End the line in '|| true' or '|| echo ...'." >&2
    echo "  Guard commands: $ALWAYS_ZERO" >&2
  elif [ "$last" -gt 0 ] && [ "${OPS[$last]}" = "&&" ]; then
    report "$rel:$lineno: injected command's guard is unreachable on failure"
    echo "  $cmd" >&2
    echo "  The final '$head' is preceded by '&&', so it does not run when the command" >&2
    echo "  before it fails -- and that failure is what the line exits with. Use '||'." >&2
  fi

  # Rule 2 -- every subcommand covered by an allowed-tools entry.
  if [ "${#PATTERNS[@]}" -eq 0 ]; then
    report "$rel:$lineno: file has an injected command but no Bash(...) allowed-tools entry"
    echo "  $cmd" >&2
    echo "  An injected command the frontmatter does not declare is refused by the" >&2
    echo "  permission check, which deletes the skill silently." >&2
    return
  fi
  i=0
  while [ "$i" -lt "${#SEGS[@]}" ]; do
    trim "${SEGS[$i]}"
    sub="$TRIMMED"
    op="${OPS[$i]}"
    i=$((i + 1))
    if [ -z "$sub" ]; then continue; fi
    if covered "$sub"; then continue; fi
    head="${sub%%[ $TAB]*}"
    report "$rel:$lineno: subcommand '$head' is not covered by allowed-tools"
    echo "  $cmd" >&2
    echo "  Uncovered subcommand: $sub" >&2
    if [ -n "$op" ]; then
      echo "  Permission patterns do not compose across shell operators: '$op' splits the" >&2
      echo "  line, and each side is matched against allowed-tools on its own." >&2
    fi
    echo "  Declared: ${PATTERNS[*]}" >&2
  done
}

check_file() {
  local file="$1"
  local rel="${file#"$REPO_ROOT"/}"
  local lineno=0 in_fm=0 fm_done=0 allowed=""
  local line
  local injected_lines=""

  files_scanned=$((files_scanned + 1))

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [ "$fm_done" -eq 0 ]; then
      if [ "$lineno" -eq 1 ] && [ "$line" = "---" ]; then
        in_fm=1
        continue
      fi
      if [ "$in_fm" -eq 1 ]; then
        if [ "$line" = "---" ]; then
          in_fm=0
          fm_done=1
          continue
        fi
        case "$line" in
          "allowed-tools:"*) allowed="${line#allowed-tools:}" ;;
        esac
        continue
      fi
      fm_done=1
    fi
    case "$line" in
      '!`'*) injected_lines="${injected_lines}${lineno} ${line}"$'\n' ;;
    esac
  done < "$file"

  if [ -z "$injected_lines" ]; then
    return
  fi

  trim "$allowed"
  extract_patterns "$TRIMMED"

  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    check_line "$rel" "${line%% *}" "${line#* }"
  done <<EOF
$injected_lines
EOF
}

main() {
  local target
  local -a targets
  targets=()
  if [ "$#" -eq 0 ]; then
    targets=("$REPO_ROOT/skills")
  else
    for target in "$@"; do
      targets+=("$target")
    done
  fi

  for target in "${targets[@]}"; do
    if [ -f "$target" ]; then
      check_file "$target"
    elif [ -d "$target" ]; then
      while IFS= read -r f; do
        if [ -z "$f" ]; then continue; fi
        check_file "$f"
      done <<EOF
$(find "$target" -type f -name 'SKILL.md' | LC_ALL=C sort)
EOF
    else
      echo "FAIL: no such file or directory: $target" >&2
      exit 2
    fi
  done

  if [ "$errors" -gt 0 ]; then
    echo >&2
    echo "$errors injected-line violation(s). An injected command runs at skill load;" >&2
    echo "a non-zero exit from one aborts the skill invocation entirely." >&2
    exit 1
  fi

  echo "check-skill-injection: OK ($files_scanned SKILL.md scanned, $lines_scanned injected line(s))"
}

main "$@"

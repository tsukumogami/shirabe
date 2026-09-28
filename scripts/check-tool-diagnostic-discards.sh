#!/usr/bin/env bash
# Fail when a call site for a declared tool discards that tool's diagnostic
# output without being enumerated in references/tool-diagnostic-discards.md.
#
# `shirabe#279` was silent because its call site redirected stderr to
# /dev/null and did not check the exit status. Both halves were needed, so
# forbidding one alone leaves the incident reproducible. The exemption route is
# an enumeration, not a marker at the call site: "the fallback is not a masked
# failure" was the exact judgment whoever wrote the #279 site made and got
# wrong, so this scan makes NO judgment about whether a discard was
# reasonable. It only asks whether the judgment is written down where a named
# reviewer reads it.
#
# Two detection arms:
#
#   1. REDIRECT. Four shapes -- `2>/dev/null`, `&>/dev/null`,
#      `2>&1 >/dev/null`, `>/dev/null 2>&1`. The fourth is in scope because the
#      rule forbids redirection to /dev/null in any spelling, and it discards
#      stderr just as completely. A bare `>/dev/null` is NOT in scope: only
#      stdout goes, and the diagnostic still reaches the reader.
#   2. UNREAD VARIABLE. `VAR=$(... tool ...)` where `$VAR` is never read
#      anywhere in the file. This arm runs against *.sh ONLY. In .md templates
#      it false-positives on the first file it touches:
#      skills/execute/koto-templates/execute.md assigns CASCADE_STATUS and
#      never references it in shell, but the surrounding prose instructs the
#      agent to submit it, so the consumer is an agent reading prose.
#      Arm 1 has the mirror-image carve-out, for the same reason and at a
#      narrower width: an inline-code span holding ONLY a redirect shape is
#      the document naming the shape, and is removed before the shape test.
#      Unfenced .md lines stay in scope, because a koto template's YAML
#      `command:` field is a real call site and is not in a fence.
#
# Scope rules that are stated coverage limits rather than oversights:
#
#   - The declared-tool test never sees a `path:lineno:` prefix. Where a
#     `grep -n` pipeline would have to strip it, this scan reads each file
#     directly and tests the source line alone -- the same guarantee, obtained
#     by construction. It is required either way:
#     `skills/work-on/koto-templates/work-on.md`'s `go test ./... 2>/dev/null`
#     is charged to `koto` the moment the prefix is in the text, because `koto`
#     appears in the directory name. The enumeration must itself cover
#     koto-templates/, so that false-positive class is guaranteed to recur.
#   - `command -v <tool>` is carved out, measured not assumed: zero bytes across
#     both streams, exit 1, no diagnostic to discard, and the declared tool
#     never executed. The carve-out removes the `command -v <word>` text before
#     the tool test rather than dropping the line, so a line that probes and
#     then calls the tool for real still counts.
#   - Tool names come from skills/*/requires.tsv, never a hardcoded list, so
#     the scan's scope grows with the declarations.
#   - Test files are out of scope: *_test.sh and anything under evals/.
#   - A tool called through a variable is charged to the tool the variable's
#     assignment resolves to (shirabe#418), in both arms. The assignment is
#     read, never run. Traced, on a line whose first word is the assignment,
#     with an optional export/readonly/local/declare/typeset and optional
#     quotes around the value:
#         VAR=tool                      VAR=$(command -v tool)
#         VAR=${OTHER:-tool}            VAR=${OTHER:-$(command -v tool)}
#         VAR=/any/path/tool            VAR="$DIR/tool"
#     `$(which tool)`, the backtick spellings and a probe carrying its own
#     `2>/dev/null` count like `$(command -v tool)`. The `:=`, `-` and `=`
#     expansions count like `:-`, and OTHER is charged with VAR, since it is
#     the override for the same tool. A value that only contains the name
#     (`koto-open.sh`, `"koto failed"`) is not a binding.
#     A file also takes the bindings of every file it sources with `.` or
#     `source`, recursively, where the path is literal or starts with one
#     `$NAME/`, `${NAME}/`, `$(dirname "$0")/` or
#     `$(dirname "${BASH_SOURCE[0]}")/` read as the sourcing file's
#     directory; a sourced file's `local` bindings stay in its functions.
#     A variable is charged only at command position: `$VAR`, `"$VAR"`,
#     `${VAR}` or `"${VAR}"` at the start of the line, after a one-line case
#     arm's pattern (`a|b)`), or after `;`, `&`, `|`, `(`, `{`, `!`, a
#     backtick, or then/do/else/elif/if/while/until/exec/command/time. A name
#     held as data (an argument, a message, a directory with a path after
#     it) is not, and `command -v "$VAR"` falls under the carve-out below.
#     NOT traced, and enumerated by hand if a site ever depends on one: a
#     copy (`A=$B`), an array element, indirect expansion, eval, a nested
#     default, an assignment that is not the line's first word
#     (`[ -n "$X" ] || K=koto`, `local a K=koto`), a variable set only by a
#     caller or the environment, a call behind an env prefix
#     (`FOO=1 "$VAR" ...`) or a runner (timeout, xargs, env, nohup, sudo), a
#     tool wrapped in a shell function, a case arm whose pattern is quoted or
#     expands a variable, and a source path spelled any other way. Any traced
#     assignment charges the variable, even if another assignment in the
#     file gives it a different value.
#   - Like a literal call, a call is judged on the line holding the redirect.
#     A command continued with `\` whose redirect sits on a later line than
#     the tool is not seen, whether the tool is named or held.
#
# The join key is path + trimmed source line + occurrence count, never
# `path:lineno`. Line numbers drift whenever anything above a site is edited,
# which would break the build on unrelated changes and would leave a stale key
# silencing whichever site drifted into that number. Keying on the trimmed line
# tolerates reindentation but breaks on an edit to the command itself, which is
# correct: changing what the command does forces the exemption back through
# review.
#
# Both directions are reported. An unenumerated site fails, and a record
# matching nothing also fails, so the list cannot rot into a permanent
# allowlist.
#
# Usage:
#   scripts/check-tool-diagnostic-discards.sh                # scans <repo>/skills
#   scripts/check-tool-diagnostic-discards.sh PATH [PATH...] # files or directories
#   scripts/check-tool-diagnostic-discards.sh --enumeration FILE [PATH...]
#   scripts/check-tool-diagnostic-discards.sh --declarations DIR [PATH...]
#
# Exit codes:
#   0 -- the live sites and the records agree exactly
#   1 -- at least one unenumerated site, stale record, count mismatch, or
#        malformed record
#   2 -- usage error (a named path does not exist, or the enumeration has no
#        record block)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENUM_FILE="$REPO_ROOT/references/tool-diagnostic-discards.md"
DECL_DIR=""

TAB=$'\t'

errors=0
files_scanned=0

report() {
  echo "FAIL: $1" >&2
  errors=$((errors + 1))
}

usage_error() {
  echo "FAIL: $1" >&2
  exit 2
}

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Declared tools
# ---------------------------------------------------------------------------

# Field one of every non-comment record in every requires.tsv found under the
# declaration roots. A hardcoded list would freeze the scan's scope at the
# moment it was written; the declarations are the thing that grows.
#
# `evals/` is excluded, matching list_files below and the sibling declaration
# scan. An eval fixture declares tools to make a fixture behave, not to
# describe what this repo calls: skills/inflight/evals/fixtures/ declares `sh`
# so a satisfied-prerequisite twin resolves on any host, and folding that into
# the vocabulary would charge every `sh -c ... 2>/dev/null` in the tree to a
# declaration that exists to test something else.
TOOLS=""
collect_tools() {
  local root f tool
  local found=0
  for root in "$@"; do
    [ -d "$root" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      found=1
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
          '#'*|'') continue ;;
        esac
        tool="${line%%"$TAB"*}"
        [ -n "$tool" ] || continue
        case " $TOOLS " in
          *" $tool "*) ;;
          *) TOOLS="$TOOLS $tool" ;;
        esac
      done < "$f"
    done <<EOF
$(find "$root" -type f -name 'requires.tsv' ! -path '*/evals/*' | LC_ALL=C sort)
EOF
  done
  return $((1 - found))
}

# An alternation that matches a tool name as a word, with `/`, `.` and `-`
# excluded from the leading boundary so a path segment never counts, and `-`
# excluded from the trailing boundary so `koto-templates` never matches `koto`.
TOOL_RE=""
build_tool_re() {
  local t alt=""
  for t in $TOOLS; do
    if [ -z "$alt" ]; then alt="$t"; else alt="$alt|$t"; fi
  done
  TOOL_RE="(^|[^A-Za-z0-9_/.-])($alt)([^A-Za-z0-9_-]|$)"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

# Does a command line name a declared tool, literally or through a variable
# the file holds it in (VAR_RE, set per file by bind_file_vars)? The
# `command -v <word>` text, `command -v "$VAR"` included, is removed first, so
# a pure builtin probe drops out while a line that probes and then calls the
# tool survives.
names_declared_tool() {
  local probe
  probe=$(printf '%s\n' "$1" \
    | sed -E 's/command -v ("?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?|[A-Za-z0-9_.-]*)//g')
  printf '%s\n' "$probe" | grep -qE "$TOOL_RE" && return 0
  [ -n "$VAR_RE" ] || return 1
  printf '%s\n' "$probe" | grep -qE "$VAR_RE"
}

# ---------------------------------------------------------------------------
# Variable-held tools
# ---------------------------------------------------------------------------

# A script that has to locate a tool resolves it first and calls it through a
# variable -- `KOTO=${KOTO_BIN:-koto}` and then `"$KOTO" status "$id"
# 2>/dev/null` -- and that call has no literal name for the tool test to find.
# This pass reads each file's assignments, without running anything, and
# charges a variable to a declared tool when its value resolves to one. The
# shapes it resolves and the ones it leaves alone are listed in the header.

# own_bindings FILE -- print `V<TAB>name<TAB>global|local` for every traced
# assignment in FILE and `S<TAB>path` for every `.`/`source` of a literal
# path. Only lines whose first word is the assignment (after an optional
# export/readonly/local/declare/typeset) are read.
own_bindings() {
  awk -v tools=" $TOOLS " '
    function istool(w) { return w != "" && index(tools, " " w " ") > 0 }
    function unq(v) {
      if (length(v) >= 2 && ((v ~ /^".*"$/) || (v ~ /^\047.*\047$/)))
        return substr(v, 2, length(v) - 2)
      return v
    }
    # The declared tool a value resolves to, or "".
    function resolve(v,   w, n, parts) {
      # $(command -v tool), $(which tool) and the backtick spellings, with or
      # without a 2>/dev/null of their own.
      if (v ~ /^\$\(.*\)$/ || v ~ /^`.*`$/) {
        w = (substr(v, 1, 1) == "`") ? substr(v, 2, length(v) - 2) : substr(v, 3, length(v) - 3)
        sub(/[ \t]+2>\/dev\/null$/, "", w)
        if (!sub(/^(command -v|which)[ \t]+/, "", w)) return ""
        if (w ~ /[ \t]/) return ""
        w = unq(w)
        return istool(w) ? w : ""
      }
      if (istool(v)) return v
      if (v ~ /\// && v !~ /[ \t]/) {
        n = split(v, parts, "/")
        if (istool(parts[n])) return parts[n]
      }
      return ""
    }
    # The value token of an assignment: up to the closing quote or `)` of a
    # quoted, `${...}`, `$(...)` or backtick value, else up to the first
    # blank or operator.
    function token(v,   i, c, q) {
      if (substr(v, 1, 3) == "\"$(") {
        i = index(v, ")\""); return i ? substr(v, 1, i + 1) : v
      }
      if (substr(v, 1, 3) == "\"${") {
        i = index(v, "}\""); return i ? substr(v, 1, i + 1) : v
      }
      if (substr(v, 1, 2) == "${") {
        i = index(v, "}"); return i ? substr(v, 1, i) : v
      }
      if (substr(v, 1, 1) == "`") {
        i = index(substr(v, 2), "`"); return i ? substr(v, 1, i + 1) : v
      }
      if (substr(v, 1, 2) == "$(") {
        i = index(v, ")"); return i ? substr(v, 1, i) : v
      }
      c = substr(v, 1, 1)
      if (c == "\"" || c == "\047") {
        q = index(substr(v, 2), c); return q ? substr(v, 1, q + 1) : v
      }
      if (match(v, /[ \t;|&)]/)) return substr(v, 1, RSTART - 1)
      return v
    }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^#/) next

      if (match(line, /^(\.|source)[ \t]+/)) {
        v = token(substr(line, RLENGTH + 1))
        if (v != "") printf "S\t%s\n", unq(v)
        next
      }

      scope = "global"
      if (match(line, /^(export|readonly|local|declare|typeset)([ \t]+-[A-Za-z]+)*[ \t]+/)) {
        if (line ~ /^local/) scope = "local"
        line = substr(line, RLENGTH + 1)
      }
      if (!match(line, /^[A-Za-z_][A-Za-z0-9_]*=/)) next
      name = substr(line, 1, RLENGTH - 1)
      v = unq(token(substr(line, RLENGTH + 1)))

      # ${OTHER:-tool}, and the :=, - and = forms. Both names hold the tool:
      # OTHER is the override, VAR the resolved value.
      if (match(v, /^\$\{[A-Za-z_][A-Za-z0-9_]*:?[-=]/) && v ~ /\}$/) {
        other = substr(v, 3, RLENGTH - 2)
        sub(/:?[-=]$/, "", other)
        if (resolve(unq(substr(v, RLENGTH + 1, length(v) - RLENGTH - 1))) != "") {
          printf "V\t%s\t%s\n", name, scope
          printf "V\t%s\t%s\n", other, scope
        }
        next
      }
      if (resolve(v) != "") printf "V\t%s\t%s\n", name, scope
    }
  ' "$1"
}

# resolve_source FROM PATH -- print the file a `.`/`source` of PATH in FROM
# names, or nothing. A literal path is read relative to FROM's directory, and
# so is a path under one leading `$NAME/`, `${NAME}/`, `$(dirname "$0")/` or
# `$(dirname "${BASH_SOURCE[0]}")/`, the ways a script names its own
# directory. Anything else computed at run time is not resolved.
resolve_source() {
  local from="$1" p="$2" dir
  dir="$(dirname "$from")"
  case "$p" in
    '$(dirname "$0")/'*) p="${p#*)/}" ;;
    '$(dirname "${BASH_SOURCE[0]}")/'*|'$(dirname "$BASH_SOURCE")/'*) p="${p#*)/}" ;;
    '${'*'}/'*) p="${p#*\}/}" ;;
    '$'*/*) p="${p#*/}" ;;
  esac
  case "$p" in
    *'$'*|*'`'*|'') return 0 ;;
    /*) ;;
    *) p="$dir/$p" ;;
  esac
  [ -f "$p" ] || return 0
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}

# file_vars FILE WITH_LOCAL SEEN -- print the variable names FILE holds a
# declared tool in, its own and those of every file it sources. A sourced
# file's `local` bindings belong to its functions, not to the caller.
file_vars() {
  local file="$1" with_local="$2" seen="$3"
  local kind a b src
  case "$seen" in *"|$file|"*) return 0 ;; esac
  seen="$seen|$file|"
  while IFS="$TAB" read -r kind a b; do
    case "$kind" in
      V)
        if [ "$b" = global ] || [ "$with_local" = 1 ]; then echo "$a"; fi
        ;;
      S)
        src=$(resolve_source "$file" "$a")
        [ -n "$src" ] && file_vars "$src" 0 "$seen"
        ;;
    esac
  done <<EOF
$(own_bindings "$file")
EOF
}

# bind_file_vars FILE -- set VAR_RE to match a reference to any of FILE's
# tool-holding variables at command position: at the start of the line,
# after a one-line case arm's pattern (`a|b)`), or after an operator or a
# keyword that starts a command. A variable holding a
# tool's name as data -- an argument, a message -- is not at command position
# and is not charged.
VAR_RE=""
bind_file_vars() {
  local v alt=""
  VAR_RE=""
  for v in $(file_vars "$1" 1 "" | LC_ALL=C sort -u); do
    if [ -z "$alt" ]; then alt="$v"; else alt="$alt|$v"; fi
  done
  [ -n "$alt" ] || return 0
  VAR_RE="(^|^[[:space:]]*\\(?[^()\"\$\`;&[:space:]]+\\)|[;&|({!\`]|(^|[^A-Za-z0-9_])(then|do|else|elif|if|while|until|exec|command|time))[[:space:]]*\"?\\\$(\\{($alt)\\}|($alt))\"?([^A-Za-z0-9_/\"]|\$)"
}

# The files a scan target contributes. Test files are out of scope; a fixture
# that exercises the check must not be charged as a live site.
list_files() {
  find "$1" -type f \
    \( -name '*.sh' -o -name '*.bash' -o -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
    ! -name '*_test.sh' \
    ! -path '*/evals/*' \
    ! -path '*/tests/*' \
    | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Arm 1 -- redirect shapes
# ---------------------------------------------------------------------------

scan_redirects() {
  local file="$1" rel="$2"
  local lineno=0 line probe

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # An inline-code span whose ENTIRE content is one of the four shapes is the
    # document naming the redirect, not running it -- prose explaining this
    # rule, or a template paragraph justifying the call in the block above it.
    # It is removed before the shape test the same way `command -v <word>` is
    # removed before the tool test: strip the text that is not a call, then
    # judge what is left. A span with a command inside it (`foo 2>/dev/null`)
    # keeps its redirect and is still a site, and a bare redirect outside
    # backticks is untouched -- which is what keeps the unfenced call sites in
    # koto-template YAML (`command: "... 2>/dev/null"`) in scope.
    probe=$(printf '%s\n' "$line" \
      | sed 's|`2>/dev/null`||g; s|`&>/dev/null`||g; s|`2>&1 >/dev/null`||g; s|`>/dev/null 2>&1`||g')
    case "$probe" in
      *'2>/dev/null'*|*'&>/dev/null'*|*'2>&1 >/dev/null'*|*'>/dev/null 2>&1'*) ;;
      *) continue ;;
    esac
    # `path:lineno:` never entered $line -- the file is read directly rather
    # than through grep -n -- which is the same guarantee stripping the prefix
    # would give, obtained by construction.
    trim "$line"
    [ -n "$TRIMMED" ] || continue
    names_declared_tool "$TRIMMED" || continue
    printf '%s\t%s\n' "$rel" "$TRIMMED" >> "$WORK/live.raw"
  done < "$file"
}

# ---------------------------------------------------------------------------
# Arm 2 -- a capture nobody reads (*.sh only)
# ---------------------------------------------------------------------------

scan_unread_vars() {
  local file="$1" rel="$2"
  local lineno=0 line var uses

  case "$file" in
    *.sh|*.bash) ;;
    *) return ;;
  esac

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in
      *'=$('*) ;;
      *) continue ;;
    esac
    var=$(printf '%s\n' "$line" \
      | sed -n 's/^[ 	]*\(local[ 	][ 	]*\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=\$(.*/\2/p')
    [ -n "$var" ] || continue
    trim "$line"
    names_declared_tool "$TRIMMED" || continue
    # A read is any `$VAR` or `${VAR}` anywhere in the file. The assignment
    # itself cannot match, because there the name is bare.
    uses=$(grep -c "\\\$[{]\\{0,1\\}$var\\([^A-Za-z0-9_]\\|\$\\)" "$file")
    [ "$uses" -eq 0 ] || continue
    printf '%s\t%s\n' "$rel" "$TRIMMED" >> "$WORK/live.raw"
  done < "$file"
}

# ---------------------------------------------------------------------------
# The enumeration
# ---------------------------------------------------------------------------

# Extract the single ```tsv fenced block. More than one is a usage error: the
# scan must not have to guess which block is canonical.
read_enumeration() {
  local file="$1"
  local fences

  [ -f "$file" ] || usage_error "no such enumeration file: $file"

  fences=$(grep -c '^```tsv$' "$file")
  if [ "$fences" -eq 0 ]; then
    usage_error "$file has no \`\`\`tsv record block"
  fi
  if [ "$fences" -gt 1 ]; then
    usage_error "$file has $fences \`\`\`tsv blocks; exactly one is canonical"
  fi

  awk '/^```tsv$/ { inb = 1; next } inb && /^```$/ { inb = 0 } inb' "$file" \
    > "$WORK/enum.block"

  local lineno=0 line nf path cmd count status why cite
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in
      '#'*|'') continue ;;
    esac

    nf=$(printf '%s\n' "$line" | awk -F'\t' '{print NF}')
    if [ "$nf" -ne 6 ]; then
      report "$file record $lineno has $nf tab-separated fields, expected 6"
      echo "  $line" >&2
      continue
    fi

    path="${line%%"$TAB"*}"
    local rest="${line#*"$TAB"}"
    cmd="${rest%%"$TAB"*}"
    rest="${rest#*"$TAB"}"
    count="${rest%%"$TAB"*}"
    rest="${rest#*"$TAB"}"
    status="${rest%%"$TAB"*}"
    rest="${rest#*"$TAB"}"
    why="${rest%%"$TAB"*}"
    cite="${rest#*"$TAB"}"

    # The join key must never be a line number. A `path:lineno` key would go on
    # silencing whichever site drifted into that number.
    case "$path" in
      *:[0-9]*)
        report "$file record $lineno: path field carries a ':lineno' suffix"
        echo "  $path" >&2
        echo "  The join key is path plus the trimmed command, never path:lineno." >&2
        continue
        ;;
    esac

    case "$count" in
      ''|*[!0-9]*)
        report "$file record $lineno: count field '$count' is not a positive integer"
        continue
        ;;
    esac
    if [ "$count" -lt 1 ]; then
      report "$file record $lineno: count field must be at least 1"
      continue
    fi

    if [ -z "$status" ] || [ "$status" = "-" ]; then
      report "$file record $lineno: exit-status field is empty"
      echo "  A record must name the status its fallback is entered on." >&2
      continue
    fi

    if [ -z "$why" ] || [ "$why" = "-" ]; then
      report "$file record $lineno: justification field is empty"
      echo "  Field five is one sentence saying why this site may discard." >&2
      continue
    fi

    if [ -z "$cite" ] || [ "$cite" = "-" ]; then
      report "$file record $lineno: citation field is empty or '-'"
      echo "  Field six is mandatory and never '-'. A discard with no incident" >&2
      echo "  behind it is an unexamined discard." >&2
      continue
    fi

    printf '%s\t%s\t%s\n' "$path" "$cmd" "$count" >> "$WORK/enum.keys"
  done < "$WORK/enum.block"
}

# ---------------------------------------------------------------------------
# The join
# ---------------------------------------------------------------------------

compare() {
  # Keyed on FILENAME rather than the NR==FNR idiom. With an empty enumeration
  # -- the state a repo is in the first time somebody adds a discard -- NR==FNR
  # stays true into the second file, and every unenumerated site is misreported
  # as a stale record. That inverts the one direction that matters.
  awk -F'\t' -v ef="$WORK/enum.keys" '
    FILENAME == ef { have[$1 FS $2] = $3; next }
    {
      k = $1 FS $2
      if (!(k in have)) { print "MISSING\t" $1 "\t" $2 "\t" $3; next }
      if (have[k] != $3) { print "COUNT\t" $1 "\t" $2 "\t" $3 "\t" have[k] }
      seen[k] = 1
    }
    END {
      for (k in have) {
        if (!(k in seen)) {
          split(k, p, FS)
          print "STALE\t" p[1] "\t" p[2] "\t" have[k]
        }
      }
    }
  ' "$WORK/enum.keys" "$WORK/live.keys" | LC_ALL=C sort
}

# ---------------------------------------------------------------------------

main() {
  local target
  local -a targets
  targets=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --enumeration)
        [ "$#" -ge 2 ] || usage_error "--enumeration needs a file"
        ENUM_FILE="$2"; shift 2 ;;
      --declarations)
        [ "$#" -ge 2 ] || usage_error "--declarations needs a directory"
        DECL_DIR="$2"; shift 2 ;;
      --*)
        usage_error "unknown option: $1" ;;
      *)
        targets+=("$1"); shift ;;
    esac
  done

  if [ "${#targets[@]}" -eq 0 ]; then
    targets=("$REPO_ROOT/skills")
  fi

  WORK=$(mktemp -d)
  : > "$WORK/live.raw"
  : > "$WORK/enum.keys"

  # Declarations: an explicit root, else whatever the scan targets carry, else
  # the repo's own skills tree. A fixture tree supplies its own requires.tsv.
  if [ -n "$DECL_DIR" ]; then
    collect_tools "$DECL_DIR" || usage_error "no requires.tsv under $DECL_DIR"
  elif ! collect_tools "${targets[@]}"; then
    collect_tools "$REPO_ROOT/skills" \
      || usage_error "no requires.tsv found; nothing declares a tool to scan for"
  fi
  build_tool_re

  for target in "${targets[@]}"; do
    if [ -f "$target" ]; then
      files_scanned=$((files_scanned + 1))
      bind_file_vars "$target"
      scan_redirects "$target" "${target#"$REPO_ROOT"/}"
      scan_unread_vars "$target" "${target#"$REPO_ROOT"/}"
    elif [ -d "$target" ]; then
      local base
      base="$(cd "$target" && pwd)"
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        files_scanned=$((files_scanned + 1))
        local rel="${f#"$REPO_ROOT"/}"
        if [ "$rel" = "$f" ]; then rel="${f#"$base"/}"; fi
        bind_file_vars "$f"
        scan_redirects "$f" "$rel"
        scan_unread_vars "$f" "$rel"
      done <<EOF
$(list_files "$target")
EOF
    else
      usage_error "no such file or directory: $target"
    fi
  done

  # Collapse to the join key: path + trimmed command + occurrence count.
  awk -F'\t' '{ n[$1 FS $2]++ } END { for (k in n) print k FS n[k] }' \
    "$WORK/live.raw" | LC_ALL=C sort > "$WORK/live.keys"

  read_enumeration "$ENUM_FILE"

  local out
  out=$(compare)

  local kind path cmd a b
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="${line%%"$TAB"*}"
    local rest="${line#*"$TAB"}"
    path="${rest%%"$TAB"*}"
    rest="${rest#*"$TAB"}"
    cmd="${rest%%"$TAB"*}"
    rest="${rest#*"$TAB"}"
    a="${rest%%"$TAB"*}"
    b="${rest#*"$TAB"}"
    case "$kind" in
      MISSING)
        report "$path: discards a declared tool's diagnostics and is not enumerated"
        echo "  $cmd" >&2
        echo "  Occurrences: $a" >&2
        echo "  Add a record to ${ENUM_FILE#"$REPO_ROOT"/} naming the site, the exit" >&2
        echo "  status its fallback is entered on, why the discard is safe, and the" >&2
        echo "  issue behind it -- in its own commit, so it is reviewable as a decision." >&2
        ;;
      STALE)
        report "${ENUM_FILE#"$REPO_ROOT"/}: record matches no live site"
        echo "  $path" >&2
        echo "  $cmd" >&2
        echo "  The site was removed or its command changed. Delete the record, or" >&2
        echo "  re-adjudicate the new command: an exemption does not carry over an edit." >&2
        ;;
      COUNT)
        report "$path: enumerated $b time(s), found $a"
        echo "  $cmd" >&2
        echo "  A byte-identical copy appeared or disappeared. Update the count field" >&2
        echo "  so each copy is one somebody looked at." >&2
        ;;
    esac
  done <<EOF
$out
EOF

  if [ "$errors" -gt 0 ]; then
    echo >&2
    echo "$errors tool-diagnostic-discard finding(s). A discarded diagnostic is a" >&2
    echo "failure nobody sees; the enumeration is what makes each one a reviewed" >&2
    echo "decision rather than a judgment made silently at the call site." >&2
    exit 1
  fi

  local live_n enum_n
  live_n=$(awk -F'\t' '{ n += $3 } END { print n + 0 }' "$WORK/live.keys")
  enum_n=$(wc -l < "$WORK/enum.keys" | tr -d ' ')
  echo "check-tool-diagnostic-discards: OK ($files_scanned file(s) scanned, $live_n site(s) in $enum_n record(s), tools:$TOOLS)"
}

main "$@"

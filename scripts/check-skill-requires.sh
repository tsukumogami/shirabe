#!/usr/bin/env bash
# check-skill-requires.sh -- the conformance scan over skills/*/requires.tsv.
#
# The declarations are descriptions of calls that exist, not predictions about
# calls somebody will write, which is what makes them hard to rot. The one
# failure they keep is omission: an author who adds a `shirabe` or `koto` call
# and forgets the record gets no finding from the declaration itself. Catching
# that is this scan's job, and it is why the flag check extracts from the
# skill's own command lines instead of trusting the sidecar to be complete.
#
# Seven checks, the first six being the six that
# references/tool-declaration-policy.md names:
#
#   1. SIDECAR     every directory under skills/ has a requires.tsv. An absent
#                  file is undeclared, which is a different state from the
#                  schema line alone, and the difference is decidable by `ls`.
#   2. SCHEMA      the first line is `#schema<TAB>skill-requires/v1`, compared
#                  literally.
#   3. FIELDS      every record carries exactly four tab-separated fields.
#   4. ALLOWLIST   every field matches its character allowlist, and field four
#                  is `always` or `mode:<name>`.
#   5. ROUTED      field one names a tool in scripts/lib/tool-routes.tsv's tool
#                  column, which is the closed set.
#   6. CADENCE     a tool coupled to shirabe's release cadence carries a
#                  subcommand; a tool with an independent cadence carries `-`
#                  in fields two and three. The failure text names the policy
#                  file, because the split is a stated rule and not something
#                  to infer from someone else's sidecar.
#   7. MODES       a `mode:<name>` record's name appears in the skill's own
#                  files. The mode name is an interface.
#
# Plus the parity check, which is the one with teeth:
#
#   8. PARITY      every flag on a `shirabe` or `koto` command line inside a
#                  skill's own directory appears in that skill's declaration.
#                  One-directional on purpose: a declared flag with no
#                  extracted call site is not a finding, because a call can
#                  live in prose the extractor does not read, and because
#                  over-declaring costs a probe rather than a missed
#                  prerequisite.
#
# Checks 4, 5 and part of 3 are delegated to scripts/lib/preflight-read.sh --
# the same validators the load-time reader runs. They are not reimplemented
# here. Two copies of an alphabet drift, and the load-time copy is the
# load-bearing one: a reviewer with the plugin root pointed at a pull-request
# checkout loads that branch's declarations before CI has seen them.
#
# ---------------------------------------------------------------------------
# What the parity check can and cannot decide
# ---------------------------------------------------------------------------
#
# A skill's files hold two kinds of `shirabe validate --x` text, and no
# mechanical signal separates them:
#
#   a call site   the skill runs this command
#   a citation    the skill names the command as the authority for a rule, or
#                 describes what CI or another skill runs
#
# `skills/plan/SKILL.md`'s "- `shirabe validate --lifecycle <ROOT>` --
# whole-tree mode" documents a CLI surface /plan never invokes; two files away,
# `skills/design/`'s "`shirabe validate --lifecycle-chain <prd-path>`" is a call
# /design makes. Same shape, same punctuation, opposite answer. Reporting both
# would demand declarations that are wrong; reporting neither would gut the
# check.
#
# So the extractor narrows mechanically where a mechanical rule exists, and
# every remaining citation is exempted by name in the declaration itself. The
# mechanical narrowings:
#
#   - `evals/` is out of scope. Eval scenarios quote `gh --json`, cargo's
#     `--release`, and slash-command flags like `/scope --coordinated`, and
#     including them surfaces all three as undeclared shirabe/koto flags across
#     eight skills.
#   - `*_test.sh` is out of scope, as it is for the sibling discard scan. A
#     fixture is not a call site.
#   - The skill boundary is hard. `/execute` referencing `/work-on`'s template
#     does not put `/work-on`'s calls into `/execute`'s declaration; a
#     declaration is not inherited.
#   - A shell comment is not a command line. In `*.sh` a `#` line is skipped,
#     which is what keeps `extract-context.sh`'s "# Stores content via koto
#     context add (if --session)" from demanding a `--session` record for a
#     flag that is the script's own argument.
#   - In Markdown, a command must be inside an inline-code span or a fenced
#     block. Prose that happens to run the word `koto` past a `--auto` further
#     down a table row is not a command line.
#
# The exemption, written in the declaration next to the records it qualifies:
#
#   #not-a-call-site<TAB>PATH<TAB>TOOL<TAB>FLAG<TAB>REASON
#
# It is a comment line, so the load-time reader already skips it. PATH is
# repo-relative and must sit inside the declaring skill's own directory, so an
# exemption cannot reach across a skill boundary. An exemption matching no
# extracted flag fails as stale, in the same both-directions spirit as the
# discard enumeration: the list cannot rot into a permanent allowlist.
#
# Usage:
#   scripts/check-skill-requires.sh                    # scans <repo>/skills
#   scripts/check-skill-requires.sh --skills DIR
#   scripts/check-skill-requires.sh --routes FILE
#   scripts/check-skill-requires.sh --policy FILE
#   scripts/check-skill-requires.sh --lib DIR
#
# Exit codes:
#   0 -- every declaration conforms
#   1 -- at least one finding
#   2 -- usage error (a named path does not exist, or the policy file's cadence
#        table cannot be read)
#
# bash 3.2 floor: no associative arrays, no namerefs, no mapfile. macOS ships
# 3.2.57 as /bin/bash and .github/workflows/check-preflight-scripts.yml runs an
# explicit /bin/bash leg.

set -uo pipefail

LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILLS_DIR="$REPO_ROOT/skills"
ROUTES_FILE="$REPO_ROOT/scripts/lib/tool-routes.tsv"
POLICY_FILE="$REPO_ROOT/references/tool-declaration-policy.md"
LIB_DIR="$SCRIPT_DIR/lib"
POLICY_REL="references/tool-declaration-policy.md"

TAB=$(printf '\t')

errors=0
skills_seen=0
records_seen=0
flags_extracted=0
exemptions_used=0

report() {
  echo "FAIL: $1" >&2
  errors=$((errors + 1))
}

detail() { echo "  $1" >&2; }

usage_error() {
  echo "FAIL: $1" >&2
  exit 2
}

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# The cadence split, read from the policy file
# ---------------------------------------------------------------------------
#
# "Editing this file is how a tool moves. There's no configuration key and no
# per-skill override." A hardcoded copy here would make that sentence false --
# the edit would move the tool in the prose and nowhere else. The table's two
# rows are parsed instead, and a table this scan cannot read is a usage error
# rather than a silent fallback to whatever the last author remembered.

COUPLED_TOOLS=""
INDEPENDENT_TOOLS=""

read_cadence() {
  local file="$1" line cell
  [ -r "$file" ] || usage_error "cannot read the policy file: $file"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '| Coupled'*) ;;
      '| Independent'*) ;;
      *) continue ;;
    esac
    # Field two of the markdown row, backticks and commas removed.
    cell=$(printf '%s\n' "$line" | awk -F'|' '{print $3}' | tr -d '`,')
    case "$line" in
      '| Coupled'*)     COUPLED_TOOLS="$COUPLED_TOOLS $cell" ;;
      '| Independent'*) INDEPENDENT_TOOLS="$INDEPENDENT_TOOLS $cell" ;;
    esac
  done < "$file"

  # Collapse whitespace so membership tests can use a padded substring match.
  COUPLED_TOOLS=$(printf '%s\n' "$COUPLED_TOOLS" | tr -s ' \t' ' ' | sed 's/^ //; s/ $//')
  INDEPENDENT_TOOLS=$(printf '%s\n' "$INDEPENDENT_TOOLS" | tr -s ' \t' ' ' | sed 's/^ //; s/ $//')

  [ -n "$COUPLED_TOOLS" ] || usage_error \
    "$POLICY_REL has no '| Coupled' cadence row; the scan will not guess the split"
  [ -n "$INDEPENDENT_TOOLS" ] || usage_error \
    "$POLICY_REL has no '| Independent' cadence row; the scan will not guess the split"
}

is_coupled()     { case " $COUPLED_TOOLS " in *" $1 "*) return 0 ;; esac; return 1; }
is_independent() { case " $INDEPENDENT_TOOLS " in *" $1 "*) return 0 ;; esac; return 1; }

# ---------------------------------------------------------------------------
# Flag extraction
# ---------------------------------------------------------------------------

# The files inside one skill that can hold a command line. `evals/` and
# `*_test.sh` are out of scope, and so is the declaration itself -- its comment
# block quotes the very command text it is adjudicating, and charging a file
# for the prose that explains it would make every adjudication self-defeating.
list_skill_files() {
  find "$1" -type f \
    \( -name '*.sh' -o -name '*.bash' -o -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
    ! -name '*_test.sh' \
    ! -name 'requires.tsv' \
    ! -path '*/evals/*' \
    | LC_ALL=C sort
}

# extract_segments <line> <in-fence> <is-shell>
#
# Prints the parts of a line that may hold a command. In a shell file or inside
# a fenced block the whole line qualifies; in Markdown prose only the spans
# between backticks do, which is the narrowing that keeps a table row's stray
# `--auto` from being read as a flag on a `koto` three columns to its left.
extract_segments() {
  local line="$1" in_fence="$2" is_shell="$3"
  local trimmed rest span

  trimmed="${line#"${line%%[![:space:]]*}"}"

  if [ "$is_shell" = "1" ] || [ "$in_fence" = "1" ]; then
    # A comment is not a command line, in a script or in a fenced block.
    case "$trimmed" in '#'*) return 0 ;; esac
    printf '%s\n' "$line"
    return 0
  fi

  # Markdown prose: inline-code spans only.
  rest="$line"
  while :; do
    case "$rest" in
      *'`'*) ;;
      *) break ;;
    esac
    rest="${rest#*\`}"
    case "$rest" in
      *'`'*) span="${rest%%\`*}"; rest="${rest#*\`}" ;;
      *) break ;;
    esac
    [ -n "$span" ] && printf '%s\n' "$span"
  done
}

# segment_flags <segment> <tool>
#
# Prints one flag per line for each invocation of <tool> in <segment>. The
# remainder after the tool is cut at the first shell separator, so a
# `shirabe validate --format json | jq -r .x` pipeline never charges `-r` to
# shirabe. `=value` is dropped and trailing prose punctuation is stripped, so
# `--visibility=private` and "`--check`." both reduce to the flag itself.
segment_flags() {
  local seg="$1" tool="$2"
  local rest="$seg" head cut tok

  while :; do
    case "$rest" in
      *"$tool "*) ;;
      *) break ;;
    esac
    head="${rest%%"$tool "*}"
    rest="${rest#*"$tool "}"

    # The tool has to sit at a word boundary. A path segment (`.../koto/x`), a
    # hyphenated name (`koto-templates`) and an argument to something else
    # (`cargo build -p shirabe`) are all rejected here.
    case "$head" in
      ''|*[!A-Za-z0-9_/.-]) ;;
      *) continue ;;
    esac

    cut="$rest"
    # Cut at the first shell separator or closing delimiter.
    cut="${cut%%|*}"
    cut="${cut%%;*}"
    cut="${cut%%&*}"
    cut="${cut%%>*}"
    cut="${cut%%<*}"
    cut="${cut%%\`*}"
    cut="${cut%%)*}"

    for tok in $cut; do
      case "$tok" in
        --|-) continue ;;
        -*) ;;
        *) continue ;;
      esac
      tok="${tok%%=*}"
      # Strip prose punctuation a flag can pick up at the end of a sentence.
      while :; do
        case "$tok" in
          *[!A-Za-z0-9-]) tok="${tok%?}" ;;
          *) break ;;
        esac
      done
      preflight_valid_flag_token "$tok" || continue
      printf '%s\n' "$tok"
    done
  done
}

# extract_skill_flags <skill> <skill-dir>
#
# Appends `skill<TAB>tool<TAB>flag<TAB>relpath` rows to $WORK/live.flags.
extract_skill_flags() {
  local skill="$1" dir="$2"
  local f rel line in_fence is_shell seg tool flag

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$SCAN_BASE"/}"
    is_shell=0
    case "$f" in *.sh|*.bash) is_shell=1 ;; esac
    in_fence=0

    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        '```'*|'~~~'*)
          if [ "$is_shell" = "0" ]; then
            if [ "$in_fence" = "1" ]; then in_fence=0; else in_fence=1; fi
            continue
          fi
          ;;
      esac
      case "$line" in
        *shirabe*|*koto*) ;;
        *) continue ;;
      esac

      while IFS= read -r seg; do
        [ -n "$seg" ] || continue
        for tool in shirabe koto; do
          case "$seg" in
            *"$tool "*) ;;
            *) continue ;;
          esac
          while IFS= read -r flag; do
            [ -n "$flag" ] || continue
            printf '%s\t%s\t%s\t%s\n' "$skill" "$tool" "$flag" "$rel" >> "$WORK/live.flags"
          done <<EOF
$(segment_flags "$seg" "$tool")
EOF
        done
      done <<EOF
$(extract_segments "$line" "$in_fence" "$is_shell")
EOF
    done < "$f"
  done <<EOF
$(list_skill_files "$dir")
EOF
}

# ---------------------------------------------------------------------------
# One declaration
# ---------------------------------------------------------------------------

# Newline-bracketed accumulators, rebuilt per skill.
DECLARED_FLAGS=""   # \n<tool> <flag>\n
DECLARED_MODES=""   # \n<name>\n
EXEMPT_KEYS=""      # \n<path>|<tool>|<flag>\n

check_declaration() {
  local skill="$1" file="$2"
  local line lineno=0 tabs tool sub flags when
  local rel="skills/$skill/requires.tsv"
  local d_path d_tool d_flag d_reason rest tok

  DECLARED_FLAGS="$NL"
  DECLARED_MODES="$NL"
  EXEMPT_KEYS="$NL"

  if ! preflight_check_schema "$file" "skill-requires/v1"; then
    report "$rel: first line is not '#schema<TAB>skill-requires/v1'"
    detail "The schema token is compared literally, so a version bump is a"
    detail "deliberate, visible act rather than a best-effort parse."
    return
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    preflight_strip "$line"
    line="$PREFLIGHT_STRIPPED"
    [ -n "$line" ] || continue

    case "$line" in
      '#not-a-call-site'*)
        # directive TAB path TAB tool TAB flag TAB reason
        preflight_tab_count "$line"
        if [ "$PREFLIGHT_TABCOUNT" != "4" ]; then
          report "$rel line $lineno: a #not-a-call-site directive needs five tab-separated fields"
          detail "#not-a-call-site<TAB>PATH<TAB>TOOL<TAB>FLAG<TAB>REASON"
          continue
        fi
        rest="${line#*"$TAB"}"
        d_path="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
        d_tool="${rest%%"$TAB"*}"; rest="${rest#*"$TAB"}"
        d_flag="${rest%%"$TAB"*}"; d_reason="${rest#*"$TAB"}"
        case "$d_path" in
          "skills/$skill/"*) ;;
          *)
            report "$rel line $lineno: exemption path '$d_path' is outside skills/$skill/"
            detail "An exemption cannot reach across a skill boundary; a declaration is"
            detail "not inherited."
            continue
            ;;
        esac
        if ! preflight_valid_name "$d_tool" || ! preflight_valid_flag_token "$d_flag"; then
          report "$rel line $lineno: exemption names a malformed tool or flag"
          continue
        fi
        if [ -z "$d_reason" ] || [ "$d_reason" = "-" ]; then
          report "$rel line $lineno: exemption has no reason"
          detail "An exemption with no reason is an unexamined exemption."
          continue
        fi
        EXEMPT_KEYS="$EXEMPT_KEYS$d_path|$d_tool|$d_flag$NL"
        continue
        ;;
      '#'*) continue ;;
    esac

    preflight_tab_count "$line"
    tabs=$PREFLIGHT_TABCOUNT
    if [ "$tabs" != "3" ]; then
      report "$rel line $lineno: expected exactly 4 tab-separated fields (3 tabs), found $((tabs + 1))"
      detail "A record is four fields with '-' as the explicit empty value. A field"
      detail "separated by spaces rather than a tab reads as one field and fails here"
      detail "and at load."
      continue
    fi

    IFS="$TAB" read -r tool sub flags when <<EOF
$line
EOF
    preflight_strip "$sub"
    preflight_collapse_spaces "$PREFLIGHT_STRIPPED"
    sub="$PREFLIGHT_COLLAPSED"

    records_seen=$((records_seen + 1))

    if ! preflight_valid_name "$tool"; then
      report "$rel line $lineno, field 1 (tool): expected [A-Za-z0-9._-]+ with no leading dash"
      continue
    fi
    if ! preflight_tool_is_routed "$tool"; then
      report "$rel line $lineno, field 1 (tool): '$tool' is not in scripts/lib/tool-routes.tsv"
      detail "That column is the closed set of tool names a declaration may name, so a"
      detail "new executable name takes a reviewed edit to the route table."
      continue
    fi
    if ! preflight_valid_subcommand "$sub"; then
      report "$rel line $lineno, field 2 (subcommand): expected '-' or space-separated tokens matching [A-Za-z0-9._-]+ with no leading dash"
      continue
    fi
    if ! preflight_valid_flags "$flags"; then
      report "$rel line $lineno, field 3 (flags): expected '-' or a comma-separated list of flags matching --?[A-Za-z0-9][A-Za-z0-9-]*"
      continue
    fi
    if ! preflight_valid_when "$when"; then
      report "$rel line $lineno, field 4 (when): expected 'always' or 'mode:<name>' with a name matching [a-z0-9-]+"
      continue
    fi

    # Check 6 -- the cadence split.
    if is_coupled "$tool"; then
      if [ "$sub" = "-" ]; then
        report "$rel line $lineno: '$tool' is coupled to shirabe's release cadence and must name a subcommand"
        detail "A coupled tool gets one record per subcommand the skill calls, naming the"
        detail "flags that call depends on. See $POLICY_REL."
        continue
      fi
    elif is_independent "$tool"; then
      if [ "$sub" != "-" ] || [ "$flags" != "-" ]; then
        report "$rel line $lineno: '$tool' has an independent release cadence and takes '-' in fields two and three"
        detail "It is verified for presence and nothing else, however many subcommands the"
        detail "skill calls. See $POLICY_REL."
        continue
      fi
    else
      report "$rel line $lineno: '$tool' appears in no cadence row of $POLICY_REL"
      detail "A tool moves between the lists by an edit to that file, in the same PR as"
      detail "the declaration changes the move forces."
      continue
    fi

    case "$when" in
      mode:*) DECLARED_MODES="$DECLARED_MODES${when#mode:}$NL" ;;
    esac

    if [ "$flags" != "-" ]; then
      rest="$flags"
      while [ -n "$rest" ]; do
        tok="${rest%%,*}"
        if [ "$tok" = "$rest" ]; then rest=""; else rest="${rest#*,}"; fi
        DECLARED_FLAGS="$DECLARED_FLAGS$tool $tok$NL"
      done
    fi
  done < "$file"
}

# ---------------------------------------------------------------------------
# Check 7 -- mode names
# ---------------------------------------------------------------------------
#
# The mode name has to appear in the skill's own files. This is a presence test
# rather than a proof that the string selects that mode: nothing mechanical
# reads a phase and reports which modes it can enter. It catches the failure
# worth catching -- a mode name invented in the declaration and used nowhere --
# and says so rather than claiming more.
check_modes() {
  local skill="$1" dir="$2" mode rest

  rest="${DECLARED_MODES#"$NL"}"
  while [ -n "$rest" ]; do
    mode="${rest%%"$NL"*}"
    rest="${rest#*"$NL"}"
    [ -n "$mode" ] || continue
    if ! grep -rqi -- "$mode" "$dir" --include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml' 2>/dev/null; then
      report "skills/$skill/requires.tsv: mode name '$mode' appears nowhere in the skill's own files"
      detail "A mode name is an interface: it has to match a mode string the skill's own"
      detail "phases use, or nothing can ever select the records it gates."
    fi
  done
}

# ---------------------------------------------------------------------------
# Check 8 -- parity
# ---------------------------------------------------------------------------

check_parity() {
  local skill="$1"
  local row tool flag path key seen_exempt

  seen_exempt="$NL"

  while IFS="$TAB" read -r _s tool flag path; do
    [ -n "$flag" ] || continue
    flags_extracted=$((flags_extracted + 1))
    case "$DECLARED_FLAGS" in
      *"$NL$tool $flag$NL"*) continue ;;
    esac
    key="$path|$tool|$flag"
    case "$EXEMPT_KEYS" in
      *"$NL$key$NL"*)
        exemptions_used=$((exemptions_used + 1))
        case "$seen_exempt" in
          *"$NL$key$NL"*) ;;
          *) seen_exempt="$seen_exempt$key$NL" ;;
        esac
        continue
        ;;
    esac
    report "skills/$skill/requires.tsv: '$tool $flag' is used in $path and is not declared"
    detail "Add the flag to the record for that subcommand, in the same change as the"
    detail "call. If the text is a citation rather than a call -- naming what CI or"
    detail "another skill runs -- record that judgment instead:"
    detail "#not-a-call-site<TAB>$path<TAB>$tool<TAB>$flag<TAB><reason>"
  done < "$WORK/skill.flags"

  # Stale exemptions. Both directions are reported so the list cannot rot into
  # a permanent allowlist: an exemption whose text was edited or deleted has to
  # come back through review rather than go on silencing whatever moved into
  # its place.
  local rest ekey
  rest="${EXEMPT_KEYS#"$NL"}"
  while [ -n "$rest" ]; do
    ekey="${rest%%"$NL"*}"
    rest="${rest#*"$NL"}"
    [ -n "$ekey" ] || continue
    case "$seen_exempt" in
      *"$NL$ekey$NL"*) continue ;;
    esac
    report "skills/$skill/requires.tsv: exemption '$ekey' matches no extracted flag"
    detail "The text was removed or edited. Delete the exemption, or re-adjudicate the"
    detail "new line: an exemption does not carry over an edit."
  done
}

# ---------------------------------------------------------------------------

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skills) [ "$#" -ge 2 ] || usage_error "--skills needs a directory"; SKILLS_DIR="$2"; shift 2 ;;
      --routes) [ "$#" -ge 2 ] || usage_error "--routes needs a file"; ROUTES_FILE="$2"; shift 2 ;;
      --policy) [ "$#" -ge 2 ] || usage_error "--policy needs a file"; POLICY_FILE="$2"; shift 2 ;;
      --lib)    [ "$#" -ge 2 ] || usage_error "--lib needs a directory"; LIB_DIR="$2"; shift 2 ;;
      *) usage_error "unknown argument: $1" ;;
    esac
  done

  [ -d "$SKILLS_DIR" ] || usage_error "no such skills directory: $SKILLS_DIR"

  # Every path the scan prints, and every path an exemption names, is relative
  # to the parent of the skills tree. On the real tree that is the repo root; on
  # a fixture tree it is the fixture root, so a fixture's exemption reads
  # `skills/<name>/<file>` exactly as the committed ones do.
  SKILLS_DIR="$(cd "$SKILLS_DIR" && pwd)"
  SCAN_BASE="$(cd "$SKILLS_DIR/.." && pwd)"
  [ -r "$LIB_DIR/preflight-read.sh" ] || usage_error "cannot read $LIB_DIR/preflight-read.sh"

  # shellcheck source=scripts/lib/preflight-read.sh
  . "$LIB_DIR/preflight-read.sh"
  NL="$PREFLIGHT_NL"

  if ! preflight_read_routes "$ROUTES_FILE" 2>/dev/null; then
    usage_error "cannot read the route table: $ROUTES_FILE"
  fi
  read_cadence "$POLICY_FILE"

  WORK=$(mktemp -d)
  : > "$WORK/live.flags"

  local dir skill decl
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    skill="$(basename "$dir")"
    skills_seen=$((skills_seen + 1))
    decl="$dir/requires.tsv"

    # Check 1 -- the sidecar exists.
    if [ ! -f "$decl" ]; then
      report "skills/$skill/requires.tsv is missing"
      detail "Every skill declares. An absent file is undeclared, which is a different"
      detail "state from a file holding the schema line alone -- that one is an explicit"
      detail "empty declaration. The difference is decidable by \`ls\`, and this is the"
      detail "check that makes it matter."
      continue
    fi
    if [ ! -r "$decl" ]; then
      report "skills/$skill/requires.tsv exists but cannot be read"
      continue
    fi

    check_declaration "$skill" "$decl"
    check_modes "$skill" "$dir"

    : > "$WORK/skill.flags"
    : > "$WORK/live.flags"
    extract_skill_flags "$skill" "$dir"
    LC_ALL=C sort -u "$WORK/live.flags" > "$WORK/skill.flags"
    check_parity "$skill"
  done <<EOF
$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
EOF

  if [ "$skills_seen" -eq 0 ]; then
    usage_error "no skill directories under $SKILLS_DIR"
  fi

  if [ "$errors" -gt 0 ]; then
    echo >&2
    echo "$errors declaration finding(s). A declaration describes a call that exists;" >&2
    echo "the failure it can still have is omission, which is what the flag check is" >&2
    echo "for. The split rule and the record format are in $POLICY_REL." >&2
    exit 1
  fi

  echo "check-skill-requires: OK ($skills_seen skill(s), $records_seen record(s), $flags_extracted extracted flag use(s), $exemptions_used exempted)"
}

main "$@"

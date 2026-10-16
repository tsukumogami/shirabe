# rule-findings-testlib.sh -- the checks every gate script's test suite runs on
# the findings it prints. Sourced by those suites, after they define pass and
# fail.
#
#   rf_test_setup <dir>        start a findings log in <dir> and export
#                              SHIRABE_FINDINGS_LOG, so every finding the suite's
#                              runs print is appended there (rule-findings.sh
#                              passes each to rule-registry.sh log-finding)
#   rf_test_verify <label> [<stage-source>]
#                              rule-registry.sh verify-findings on that log: every
#                              logged finding names an active rule, carries the
#                              ref the reader computes, starts with the rule's
#                              summary, and carries the level of its rule's
#                              stage (or of <stage-source>'s stage, passed as
#                              --stage-source); an empty log fails
#   rf_test_stage_copy <dest> <id> <stage> <path>...
#                              a lean scratch copy of the plugin at <dest>
#                              (removed and made afresh) whose registry sets
#                              <id>'s stage to <stage>, for running a gate
#                              script with one rule at a stage other than the
#                              real registry's. It holds links to the reader,
#                              the library, plugin.json and each
#                              plugin-relative <path> (the gate script and
#                              anything else it reads), and copies of the
#                              registry and the files its rules point at;
#                              nothing else, and nothing copied recursively.
#                              Returns 1, with the reason on stderr, when a
#                              file can't be copied or the copy's reader
#                              doesn't give <id> that stage
#   rf_test_verify_copy <label> <copy> <log> [<stage-source>]
#                              verify-findings on <log> with <copy>'s own
#                              reader, so findings a copy printed are checked
#                              against the copy's registry and refs
#   rf_test_expected_range <id>
#                              <path>#L<a>-L<b> for the rule, found with grep -F
#                              on its anchors: a second way to the range, so a
#                              bug in the reader's resolver can't pass both
#   rf_test_refusals <label> <script path relative to the plugin root> <id> <arg>...
#                              in a scratch copy of the plugin, the script run
#                              with <arg>... (from the current directory) exits
#                              2 when <id> is dropped from its RULE_IDS line,
#                              when the registry marks <id> retired, when
#                              <id>'s first anchor no longer resolves, and when
#                              scripts/lib/rule-findings.sh is missing; <arg>...
#                              must name a mode that reports <id>
#
# Needs bash, jq, grep, awk. Written for the bash 3.2 floor.

RF_TEST_ROOT="$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
RF_TEST_HELPER="$RF_TEST_ROOT/scripts/rule-registry.sh"
RF_TEST_REGISTRY="$RF_TEST_ROOT/references/rule-registry.json"
RF_TEST_DIR=""

# rf_test_setup <dir>: <dir> is the suite's own scratch directory under $TMPDIR,
# which the suite already removes on exit.
rf_test_setup() {
    RF_TEST_DIR="$1/rule-findings"
    mkdir -p "$RF_TEST_DIR" || return 1
    RF_TEST_DIR=$(CDPATH='' cd -P -- "$RF_TEST_DIR" && pwd -P)
    SHIRABE_FINDINGS_LOG="$RF_TEST_DIR/findings.log"
    export SHIRABE_FINDINGS_LOG
}

rf_test_verify() {
    rf_test_verify_with "$1" "$RF_TEST_HELPER" "$SHIRABE_FINDINGS_LOG" "${2-}"
}

rf_test_verify_copy() {
    rf_test_verify_with "$1" "$2/scripts/rule-registry.sh" "$3" "${4-}"
}

# rf_test_verify_with <label> <reader> <log> [<stage-source>]
rf_test_verify_with() {
    local out rc
    if [ -n "${4-}" ]; then
        out=$("$2" verify-findings --stage-source "$4" "$3" 2>&1); rc=$?
    else
        out=$("$2" verify-findings "$3" 2>&1); rc=$?
    fi
    if [ $rc -eq 0 ]; then
        pass "$1: every finding printed names a registered rule, its computed rule_ref, its summary and its stage's level"
    else
        fail "$1: findings log verification: $out"
    fi
}

# rf_test_stage_copy <dest> <id> <stage> <path>.... Nothing is copied
# recursively: a full copy of references/ and skills/ per case is slow and
# loads the host, since every file written is scanned. The scripts (the
# library, the reader and each <path>) are symlinks to the real files: each
# finds its siblings through its own path, which stays inside <dest>, so the
# copy's reader and registry are the ones used. Only two kinds of file are
# real copies. The registry is one, since it is edited. The rules' text files
# are the other, because the reader refuses a symlinked text file. Those are
# all copied, not just <id>'s, because the gate resolves every rule its mode
# can report before it checks anything. Retired entries may name files that
# no longer exist; those are skipped.
#
# The reader holds a guarded rule below block at block unless stage_backstops
# covers each protected guard with another file (scripts/rule-registry.sh's
# "Effective stage"), so below block the copy also gives every guard but
# `none` a backstop naming the copy's registry file: any existing file other
# than the rule's own check satisfies the reader, and this copy exists only to
# run a suite. The stage is then read back through the copy's reader, so a
# copy that didn't take the stage fails here rather than passing a suite at
# the wrong stage.
rf_test_stage_copy() {
    local d=$1 id=$2 stage=$3 reg got rel
    shift 3
    case "$stage" in
        shadow|warn|block|retired) ;;
        *) echo "rf_test_stage_copy: [$stage] is not a stage" >&2; return 1 ;;
    esac
    rm -rf "$d"
    mkdir -p "$d/scripts/lib" "$d/references" "$d/.claude-plugin" || return 1
    for rel in "$RF_TEST_ROOT"/scripts/lib/*.sh; do
        ln -s "$rel" "$d/scripts/lib/${rel##*/}" || return 1
    done
    ln -s "$RF_TEST_HELPER" "$d/scripts/rule-registry.sh" || return 1
    ln -s "$RF_TEST_ROOT/.claude-plugin/plugin.json" "$d/.claude-plugin/plugin.json" || return 1
    cp "$RF_TEST_REGISTRY" "$d/references/rule-registry.json" || return 1
    while IFS= read -r rel; do
        [ -f "$RF_TEST_ROOT/$rel" ] || continue
        mkdir -p "$d/$(dirname -- "$rel")" && cp "$RF_TEST_ROOT/$rel" "$d/$rel" || return 1
    done <<EOF
$(jq -r '[.rules[].text.path | select(type == "string")] | unique | .[]' "$RF_TEST_REGISTRY")
EOF
    for rel in "$@"; do
        [ -f "$RF_TEST_ROOT/$rel" ] || { echo "rf_test_stage_copy: no file $rel to link" >&2; return 1; }
        # A rule's text file is already a copy, which the reader needs.
        [ -e "$d/$rel" ] && continue
        mkdir -p "$d/$(dirname -- "$rel")" && ln -s "$RF_TEST_ROOT/$rel" "$d/$rel" || return 1
    done
    reg="$d/references/rule-registry.json"
    jq --arg id "$id" --arg stage "$stage" '
        .rules |= map(if .id == $id then
            .stage = $stage
            | if $stage == "block" then del(.stage_backstops)
              else .stage_backstops = [(.guards // [])[] | select(. != "none")
                                       | {before: ., check: "references/rule-registry.json"}]
              end
          else . end)' "$reg" > "$reg.tmp" && mv "$reg.tmp" "$reg" || return 1
    got=$("$d/scripts/rule-registry.sh" stage "$id" 2>&1) || {
        echo "rf_test_stage_copy: the copy's reader has no stage for $id: $got" >&2; return 1; }
    [ "$got" = "$stage" ] || {
        echo "rf_test_stage_copy: the copy's reader gives $id stage [$got], not [$stage]" >&2; return 1; }
}

rf_test_expected_range() {
    local id=$1 path first last file a b
    path=$(jq -r --arg id "$id" '.rules[] | select(.id == $id) | .text.path' "$RF_TEST_REGISTRY")
    first=$(jq -r --arg id "$id" '.rules[] | select(.id == $id) | .text.first' "$RF_TEST_REGISTRY")
    last=$(jq -r --arg id "$id" '.rules[] | select(.id == $id) | .text.last // ""' "$RF_TEST_REGISTRY")
    file="$RF_TEST_ROOT/$path"
    a=$(grep -n -F -- "$first" "$file" | head -n 1 | cut -d: -f1)
    if [ -z "$last" ]; then
        b=$a
    else
        b=$(tail -n "+$a" "$file" | grep -n -F -- "$last" | head -n 1 | cut -d: -f1)
        b=$((a + b - 1))
    fi
    printf '%s#L%s-L%s' "$path" "$a" "$b"
}

# rf_test_copy_plugin <dest>: the parts of the plugin a gate script and the
# registry's anchors read, as a plain directory (an installed-style copy).
rf_test_copy_plugin() {
    local d=$1
    mkdir -p "$d/scripts" "$d/docs" "$d/.claude-plugin"
    cp -R "$RF_TEST_ROOT/scripts/lib" "$d/scripts/"
    cp "$RF_TEST_HELPER" "$d/scripts/"
    cp -R "$RF_TEST_ROOT/references" "$RF_TEST_ROOT/skills" "$d/"
    cp -R "$RF_TEST_ROOT/docs/guides" "$d/docs/"
    cp "$RF_TEST_ROOT/CLAUDE.md" "$d/"
    cp "$RF_TEST_ROOT/.claude-plugin/plugin.json" "$d/.claude-plugin/"
}

rf_test_refusals() {
    local label=$1 rel=$2 id=$3 p script rc tmp
    shift 3
    p="$RF_TEST_DIR/plugin.$$"
    rm -rf "$p"; rf_test_copy_plugin "$p"
    script="$p/$rel"
    tmp="$RF_TEST_DIR/edit.$$"

    # Every run below clears SHIRABE_FINDINGS_LOG: a scratch copy's findings
    # carry the copy's refs, and the suite's verify-findings would check them
    # against the real registry and fail.
    #
    # The control: the unaltered copy decides (0 or 1). Without it, a scratch
    # copy too broken to run at all would make every refusal below pass.
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>"$tmp.err"; rc=$?
    case $rc in
        0|1) pass "$label: the unaltered scratch copy decides (exit $rc)" ;;
        *) fail "$label: the unaltered scratch copy exited $rc; the refusals below would prove nothing: $(head -c 400 "$tmp.err")" ;;
    esac
    rm -f "$tmp.err"

    awk -v id="$id" '
        /^RULE_IDS="/ {
            sub(/^RULE_IDS="/, ""); sub(/"$/, "")
            n = split($0, ids, " "); out = ""
            for (i = 1; i <= n; i++) if (ids[i] != id) out = out (out == "" ? "" : " ") ids[i]
            print "RULE_IDS=\"" out "\""; next
        }
        { print }' "$script" > "$tmp" && cat "$tmp" > "$script"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a rule missing from RULE_IDS exits 2" \
        || fail "$label: rule outside RULE_IDS exited $rc, want 2"

    rm -rf "$p"; rf_test_copy_plugin "$p"
    jq --arg id "$id" '.rules |= map(if .id == $id then .status = "retired" else . end)' \
        "$p/references/rule-registry.json" > "$tmp" && cat "$tmp" > "$p/references/rule-registry.json"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a retired rule exits 2" \
        || fail "$label: retired rule exited $rc, want 2"

    rm -rf "$p"; rf_test_copy_plugin "$p"
    jq --arg id "$id" '.rules |= map(if .id == $id then .text.first = "no line holds this anchor" else . end)' \
        "$p/references/rule-registry.json" > "$tmp" && cat "$tmp" > "$p/references/rule-registry.json"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a rule whose text no longer resolves exits 2 before checking" \
        || fail "$label: unresolvable rule exited $rc, want 2"

    rm -rf "$p"; rf_test_copy_plugin "$p"
    rm -f "$p/scripts/lib/rule-findings.sh"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a missing scripts/lib/rule-findings.sh exits 2" \
        || fail "$label: missing library exited $rc, want 2"
    rm -rf "$p" "$tmp"
}

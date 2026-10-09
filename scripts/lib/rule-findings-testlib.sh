# rule-findings-testlib.sh -- the checks every gate script's test suite runs on
# the findings it prints. Sourced by those suites, after they define pass and
# fail.
#
#   rf_test_setup <dir>        start a findings log in <dir> and export
#                              SHIRABE_FINDINGS_LOG, so every finding the suite's
#                              runs print is appended there (rule-findings.sh
#                              passes each to rule-registry.sh log-finding)
#   rf_test_verify <label>     rule-registry.sh verify-findings on that log: every
#                              logged finding names an active rule, carries the
#                              ref the reader computes, and starts with the
#                              rule's summary; an empty log fails
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
    local out rc
    out=$("$RF_TEST_HELPER" verify-findings "$SHIRABE_FINDINGS_LOG" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then
        pass "$1: every finding printed names a registered rule, its computed rule_ref and its summary"
    else
        fail "$1: findings log verification: $out"
    fi
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

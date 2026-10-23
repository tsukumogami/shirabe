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
#   rf_test_stages <label> <id> <block-exit> <stage-source> <runner> <path>...
#                              the gate's answer at each of <id>'s four stages:
#                              for block, warn, shadow and retired, a
#                              rf_test_stage_copy with <id> at that stage
#                              (linking <path>...), then `<runner> <copy>`, a
#                              function the suite defines that runs the gate
#                              script under <copy> on input breaking only rules
#                              that take <id>'s stage. At block every finding
#                              prints at error, the exit is <block-exit> and
#                              stderr carries the dispute hint; at warn and
#                              shadow every finding prints at warning or info,
#                              the exit is 0 and there is no hint; at retired
#                              nothing prints or logs and the exit is 0. Each
#                              printed finding is verified against the copy's
#                              registry, with <stage-source> (empty for none)
#                              as --stage-source
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
#   rf_test_ladder_log <file> <state> <gate> [<rule> <session>]...
#                              write a koto session log for the escalation
#                              ladder: the header, a transition into <state>,
#                              and one failed gate_evaluated of <gate> in
#                              <state> per <rule> <session> pair, recording
#                              rule_counts[<rule>].session = <session>; the
#                              gate run against it with SHIRABE_GATE_LOG=<file>
#                              and SHIRABE_GATE_NAME=<gate> sees count
#                              <session> + 1 for <rule>; visit is written equal
#                              to session because the ladder reads session only
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
    # The switch reader the PR-body gate asks before it scans for workflow
    # records.
    ln -s "$RF_TEST_ROOT/scripts/pr-workflow-content.sh" "$d/scripts/pr-workflow-content.sh" || return 1
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

# The line rf_dispute_hint prints, as far as a suite needs to find it.
RF_TEST_HINT='to dispute a finding you believe is wrong, run '

# rf_test_level <stage>: the level a finding of a rule at <stage> prints at,
# as the suites expect it; nothing for retired, and error for a stage this
# library doesn't know. The third copy of the stage-to-level map, beside
# scripts/lib/rule-findings.sh's rf_level and scripts/rule-registry.sh's
# stage_level; scripts/rule-registry_test.sh holds the three to each other.
rf_test_level() {
    case "$1" in
        warn) printf 'warning' ;;
        shadow) printf 'info' ;;
        retired) ;;
        *) printf 'error' ;;
    esac
}

rf_test_stages() {
    local label=$1 id=$2 block_rc=$3 source=$4 runner=$5 stage want_rc want_level
    local d="$RF_TEST_DIR/stages.$$" log="$RF_TEST_DIR/stages.$$.log"
    local out="$RF_TEST_DIR/stages.$$.out" err="$RF_TEST_DIR/stages.$$.err" rc levels hints
    shift 5
    for stage in block warn shadow retired; do
        want_level=$(rf_test_level "$stage")
        case "$stage" in
            block) want_rc=$block_rc ;;
            *) want_rc=0 ;;
        esac
        if ! rf_test_stage_copy "$d" "$id" "$stage" "$@" 2>"$err"; then
            fail "$label: could not make a plugin copy with $id at $stage: $(cat "$err")"
            continue
        fi
        : > "$log"
        ( SHIRABE_FINDINGS_LOG="$log"; export SHIRABE_FINDINGS_LOG; "$runner" "$d" ) >"$out" 2>"$err"
        rc=$?
        levels=$(sed -n 's/^::koto-finding:://p' "$out" | jq -r '.level' 2>/dev/null | sort -u | tr '\n' ' ')
        hints=$(grep -c -F -- "$RF_TEST_HINT" "$err")
        if [ -z "$want_level" ]; then
            if [ -z "$levels" ] && [ ! -s "$log" ] && [ "$rc" -eq 0 ] && [ "$hints" -eq 0 ]; then
                pass "$label: with $id at retired nothing prints or logs, and the gate passes (exit 0) with no dispute hint"
            else
                fail "$label: with $id at retired: exit $rc, levels [$levels], hints $hints, log [$(cat "$log")], stderr: $(head -c 400 "$err")"
            fi
        else
            if [ "$levels" = "$want_level " ] && [ "$rc" -eq "$want_rc" ]; then
                pass "$label: with $id at $stage every finding prints at $want_level and the gate exits $want_rc"
            else
                fail "$label: with $id at $stage: exit $rc (want $want_rc), levels [$levels] (want [$want_level ]), stderr: $(head -c 400 "$err")"
            fi
            if [ "$stage" = block ]; then
                [ "$hints" -eq 1 ] && pass "$label: failing at block prints the dispute hint once on stderr" \
                    || fail "$label: at block the dispute hint printed $hints times: $(head -c 400 "$err")"
            else
                [ "$hints" -eq 0 ] && pass "$label: passing at $stage prints no dispute hint" \
                    || fail "$label: at $stage the dispute hint printed: $(head -c 400 "$err")"
            fi
            rf_test_verify_copy "$label at $stage" "$d" "$log" "$source"
        fi
    done
    rm -rf "$d" "$log" "$out" "$err"
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
        b=$(tail -n "+$a" "$file" | grep -n -F -- "$last" | cut -d: -f1); b=${b%%$'\n'*}
        b=$((a + b - 1))
    fi
    printf '%s#L%s-L%s' "$path" "$a" "$b"
}

# rf_test_copy_plugin <dest>: the parts of the plugin a gate script and the
# registry's anchors read, as a plain directory (an installed-style copy) that
# a test may edit. It is a sparse git worktree, not a recursive copy: a
# checkout writes only the paths below, where a copy of references/ and
# skills/ wrote over a thousand files per call, each scanned by the host. The
# worktree is cut from `git stash create` when the checkout has uncommitted
# changes to tracked files, so it holds what the suite is testing rather than
# the last commit; a new file nothing has added yet is not in it. The paths
# are the registry, the reader, the library, the PR workflow content switch
# reader, plugin.json, CLAUDE.md, the
# writing-style rules, the scripts of the skills whose gate scripts report
# registry rules (and the scripts they call), and every file a rule's text
# points at. <dest> must not exist; rf_test_drop_plugin removes it.
rf_test_copy_plugin() {
    local d=$1 base
    git -C "$RF_TEST_ROOT" worktree prune 2>/dev/null
    base=$(git -C "$RF_TEST_ROOT" stash create 2>/dev/null) || base=""
    [ -n "$base" ] || base=$(git -C "$RF_TEST_ROOT" rev-parse HEAD) || return 1
    git -C "$RF_TEST_ROOT" worktree add --quiet --detach --no-checkout "$d" "$base" || return 1
    {
        printf '%s\n' /scripts/lib/ /scripts/rule-registry.sh /scripts/pr-workflow-content.sh /references/rule-registry.json \
            /.claude-plugin/plugin.json /CLAUDE.md /skills/writing-style/ \
            /skills/work-on/scripts/ /skills/scope/scripts/ /skills/execute/scripts/
        jq -r '[.rules[].text.path | select(type == "string")] | unique | .[] | "/" + .' \
            "$RF_TEST_REGISTRY"
    } > "$d.sparse" || return 1
    git -C "$d" sparse-checkout set --no-cone --stdin < "$d.sparse" || return 1
    rm -f "$d.sparse"
    git -C "$d" checkout --quiet "$base" || return 1
}

# rf_test_drop_plugin <dest>: removes a copy rf_test_copy_plugin made.
rf_test_drop_plugin() {
    git -C "$RF_TEST_ROOT" worktree remove --force "$1" 2>/dev/null || rm -rf "$1"
    git -C "$RF_TEST_ROOT" worktree prune 2>/dev/null
    return 0
}

# rf_test_restore <dest> <path>...: puts edited paths in a copy back as they
# were checked out, so one copy serves every case.
rf_test_restore() {
    local d=$1
    shift
    git -C "$d" checkout --quiet -- "$@"
}

rf_test_refusals() {
    local label=$1 rel=$2 id=$3 p script rc tmp
    shift 3
    p="$RF_TEST_DIR/plugin.$$"
    rf_test_drop_plugin "$p"; rf_test_copy_plugin "$p" \
        || { fail "$label: could not make the scratch copy of the plugin"; return; }
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

    rf_test_restore "$p" "$rel"
    jq --arg id "$id" '.rules |= map(if .id == $id then .status = "retired" else . end)' \
        "$p/references/rule-registry.json" > "$tmp" && cat "$tmp" > "$p/references/rule-registry.json"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a retired rule exits 2" \
        || fail "$label: retired rule exited $rc, want 2"

    rf_test_restore "$p" references/rule-registry.json
    jq --arg id "$id" '.rules |= map(if .id == $id then .text.first = "no line holds this anchor" else . end)' \
        "$p/references/rule-registry.json" > "$tmp" && cat "$tmp" > "$p/references/rule-registry.json"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a rule whose text no longer resolves exits 2 before checking" \
        || fail "$label: unresolvable rule exited $rc, want 2"

    rf_test_restore "$p" references/rule-registry.json
    rm -f "$p/scripts/lib/rule-findings.sh"
    SHIRABE_FINDINGS_LOG="" "$script" "$@" >/dev/null 2>&1; rc=$?
    [ $rc -eq 2 ] && pass "$label: a missing scripts/lib/rule-findings.sh exits 2" \
        || fail "$label: missing library exited $rc, want 2"
    rf_test_drop_plugin "$p"
    rm -f "$tmp"
}

# rf_test_ladder_log <file> <state> <gate> [<rule> <session>]...
rf_test_ladder_log() {
    local f=$1 state=$2 gate=$3 seq=2
    shift 3
    printf '%s\n' '{"schema_version":1,"workflow":"w","template_hash":"h","created_at":"2026-10-16T00:00:00Z"}' > "$f" || return 1
    printf '{"seq":1,"timestamp":"t","type":"transitioned","payload":{"from":"start","to":"%s"}}\n' "$state" >> "$f"
    while [ $# -ge 2 ]; do
        jq -cn --argjson seq "$seq" --arg state "$state" --arg gate "$gate" --arg rule "$1" --argjson n "$2" \
            '{seq: $seq, timestamp: "t", type: "gate_evaluated",
              payload: {state: $state, gate: $gate, outcome: "failed", attempt: $seq, visit_attempt: $seq,
                        rule_counts: {($rule): {visit: $n, session: $n}}}}' >> "$f" || return 1
        seq=$((seq + 1))
        shift 2
    done
}

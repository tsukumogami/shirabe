# lib.sh -- helpers for scripts/check-koto-floor.sh, its scenarios, and its test
#
# Sourced, never run. Three groups:
#
#   install   -- fetch koto's install.sh from a pinned koto commit, check its
#                SHA-256, run it into a directory of the caller's choosing, check
#                the binary it installed against a SHA-256 recorded here, and
#                assert the version the binary reports. `install_koto` takes the
#                version and the directory as arguments, so a second koto can be
#                installed beside the floor one without touching the first.
#
#   templates -- discover the templates, strip `decider` blocks with yq, detect
#                whether a template declares any, and collect escape values.
#                Discovery is a glob, never a list, so a declaration added to
#                any shipped template is covered with no change here.
#
#   scenarios -- git fixtures, koto ticks that write one transcript line each,
#                and the assertions a scenario ends with.
#
# Every function reports on stderr with a `check-koto-floor:` prefix and
# returns non-zero on failure rather than exiting, so the test can call each
# one on its own.
#
# Bash 3.2: no associative arrays, no mapfile, no ${var,,}.

# -- install ------------------------------------------------------------------

# The floor this repository states in its README.
KOTO_FLOOR_VERSION="v0.12.2"

# The first koto release that reads `decider` blocks: it compiles them, enforces
# the E-DECIDER-* rules, and refuses an `auto` answer on a route the floor
# forbids. scripts/check-koto-release.sh installs it beside the floor to prove
# shirabe's declarations are valid where they are read, not only ignored where
# they are not.
KOTO_DECIDER_RELEASE_VERSION="v0.13.0"

# The koto commit install.sh is fetched from: the commit koto's v0.12.2 tag
# points at. A full SHA, never a branch name, so the script that runs cannot
# change underneath this check. KOTO_INSTALLER_SHA256 is that file's SHA-256;
# changing the commit means recomputing it.
KOTO_INSTALLER_COMMIT="1ca8c980a1cbeb032cbb93e5e4e6405e240d8fd8"
KOTO_INSTALLER_SHA256="5f8c62f618f8181fa4b48e0e600e1208dddd1f0dab668a73e1b52ae7b52ba319"
KOTO_INSTALLER_URL="https://raw.githubusercontent.com/tsukumogami/koto/${KOTO_INSTALLER_COMMIT}/install.sh"

# install.sh checks the binary it downloads against the release's own
# checksums.txt, which comes from the same place as the binary. The binary is
# also pinned here: koto_binary_sha256 records the expected SHA-256 per
# version and platform, and install_koto checks the installed file against it.
# A version or platform with no recorded value is refused unless
# KOTO_ALLOW_UNPINNED_BINARY=1, in which case only install.sh's own check
# stands. To record a new version, take the values from that release's
# checksums.txt and confirm them by hashing the downloaded assets.
KOTO_UNPINNED_OVERRIDE_VAR="KOTO_ALLOW_UNPINNED_BINARY"

kf_err() {
    echo "check-koto-floor: $*" >&2
}

# sha256_tool: prints the command that computes a SHA-256, or fails naming the
# tools it looked for. install.sh itself only warns when neither is present and
# installs an unverified binary, so this check has to happen before it runs.
sha256_tool() {
    if command -v sha256sum >/dev/null 2>&1; then
        echo "sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
        echo "shasum -a 256"
    else
        kf_err "no checksum tool: neither sha256sum nor shasum is on PATH"
        return 1
    fi
}

# sha256_of <file>: prints the file's SHA-256.
sha256_of() {
    local tool sum
    tool=$(sha256_tool) || return 1
    # $tool is word-split on purpose: "shasum -a 256" is three words.
    sum=$($tool "$1" | awk '{print $1}') || return 1
    [ -n "$sum" ] || { kf_err "could not compute the SHA-256 of $1"; return 1; }
    echo "$sum"
}

# verify_sha256 <file> <expected>
verify_sha256() {
    local actual
    actual=$(sha256_of "$1") || return 1
    if [ "$actual" != "$2" ]; then
        kf_err "SHA-256 mismatch for $1: expected $2, got $actual"
        return 1
    fi
}

# check_installer_output <file>: fails when install.sh said it installed a
# binary it could not verify.
check_installer_output() {
    if grep -q 'Could not verify checksum' "$1"; then
        kf_err "install.sh could not verify the release checksum:"
        cat "$1" >&2
        return 1
    fi
}

# assert_koto_version <bin> <version>: `<bin> version` must report exactly
# <version>, with or without a leading v. The output looks like
# `koto 0.12.2 (1ca8c98 2026-08-24T23:46:46Z)`.
assert_koto_version() {
    local bin="$1" want="${2#v}" out got
    out=$("$bin" version 2>/dev/null) || { kf_err "$bin version failed"; return 1; }
    got=$(printf '%s\n' "$out" | awk 'NR == 1 {print $2}')
    if [ "$got" != "$want" ]; then
        kf_err "$bin reports version [$out], want $want"
        return 1
    fi
}

# koto_platform: the `<os>-<arch>` suffix install.sh picks a release asset by,
# derived the same way install.sh derives it.
koto_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
    esac
    echo "$os-$arch"
}

# koto_binary_sha256 <version> <platform>: prints the recorded SHA-256 of the
# koto-<platform> asset of release <version>, or nothing when none is
# recorded. linux-amd64 is the CI runner; darwin-arm64 is a developer's Mac.
# v0.13.0 records all four platforms its release publishes.
koto_binary_sha256() {
    case "v${1#v}/$2" in
        v0.12.2/linux-amd64)  echo "a98bc2108dfd457bbfc79530ecc85f82b29801e2826682f4323c24b960e548c8" ;;
        v0.12.2/darwin-arm64) echo "73d163521733a2b8c8acfb59fb96e783f2f1314d928ab6c76371fbb9132f9739" ;;
        v0.13.0/linux-amd64)  echo "b888f75d5647b92a796f9fdc10db3300131ab2b3476cc027ce7eba937dc25b1e" ;;
        v0.13.0/linux-arm64)  echo "c0c2f5c2665acdab312b2f60a5bcfb3c377c2d52e09e3e5856d06e11cc288d97" ;;
        v0.13.0/darwin-amd64) echo "24691c3507a437d2d583ff1803d4112eb0972099e848d0eb5fe140b492d6a756" ;;
        v0.13.0/darwin-arm64) echo "e72601b8d81d349415c708c486eda676382d265ff1751117ce0f111c20bb831c" ;;
    esac
}

# expected_koto_sha256 <version> <platform>: prints the recorded SHA-256, or
# nothing when none is recorded and KOTO_ALLOW_UNPINNED_BINARY=1. Fails, naming
# the version, the platform, and the override, when none is recorded and the
# override is not set.
expected_koto_sha256() {
    local sum
    sum=$(koto_binary_sha256 "$1" "$2")
    if [ -n "$sum" ]; then
        echo "$sum"
        return 0
    fi
    if [ "${KOTO_ALLOW_UNPINNED_BINARY:-}" = 1 ]; then
        kf_err "warning: no recorded SHA-256 for the koto $1 binary on $2; $KOTO_UNPINNED_OVERRIDE_VAR=1 is set, so only install.sh's own checksums.txt check applies"
        return 0
    fi
    kf_err "no recorded SHA-256 for the koto $1 binary on $2; refusing to install an unpinned binary. Record it in koto_binary_sha256 in scripts/koto-floor/lib.sh, or set $KOTO_UNPINNED_OVERRIDE_VAR=1 to rely on install.sh's checksums.txt alone"
    return 1
}

# install_koto <version> <install-dir>: installs koto <version> into
# <install-dir>/bin/koto and sets INSTALLED_KOTO_BIN to that absolute path.
# Nothing outside <install-dir> is written: --no-modify-path leaves shell
# profiles alone, and KOTO_INSTALL_DIR keeps the binary out of ~/.koto.
INSTALLED_KOTO_BIN=""
install_koto() {
    local version="$1" dir="$2" installer log platform want_bin
    INSTALLED_KOTO_BIN=""

    sha256_tool >/dev/null || return 1
    # Settled before anything is downloaded, so an unpinned platform or
    # version fails without touching the network.
    platform=$(koto_platform)
    want_bin=$(expected_koto_sha256 "$version" "$platform") || return 1
    command -v curl >/dev/null 2>&1 || { kf_err "curl is required to fetch install.sh"; return 1; }

    mkdir -p "$dir" || { kf_err "could not create $dir"; return 1; }
    dir=$(cd "$dir" && pwd)
    installer="$dir/install.sh"
    log="$dir/install.log"

    if ! curl -fsSL -o "$installer" "$KOTO_INSTALLER_URL"; then
        kf_err "could not fetch $KOTO_INSTALLER_URL"
        return 1
    fi
    verify_sha256 "$installer" "$KOTO_INSTALLER_SHA256" || return 1

    if ! KOTO_INSTALL_DIR="$dir" bash "$installer" --no-modify-path "--version=$version" >"$log" 2>&1; then
        kf_err "install.sh failed for koto $version:"
        cat "$log" >&2
        return 1
    fi
    check_installer_output "$log" || return 1

    [ -x "$dir/bin/koto" ] || { kf_err "install.sh left no binary at $dir/bin/koto"; return 1; }
    if [ -n "$want_bin" ] && ! verify_sha256 "$dir/bin/koto" "$want_bin"; then
        kf_err "the koto $version binary for $platform does not match the SHA-256 recorded in scripts/koto-floor/lib.sh; removed it"
        rm -f "$dir/bin/koto"
        return 1
    fi
    assert_koto_version "$dir/bin/koto" "$version" || return 1
    INSTALLED_KOTO_BIN="$dir/bin/koto"
}

# check_yq: mikefarah yq, major version 4. The python yq wrapper and yq v3
# take different syntax, and both would misread the strip expression.
check_yq() {
    local out
    command -v yq >/dev/null 2>&1 || { kf_err "yq is required (mikefarah yq v4) and is not on PATH"; return 1; }
    out=$(yq --version 2>&1) || { kf_err "yq --version failed: $out"; return 1; }
    case "$out" in
        *mikefarah/yq*' version v4.'* | *mikefarah/yq*' version 4.'*) return 0 ;;
    esac
    kf_err "yq must be mikefarah yq v4; yq --version says [$out]"
    return 1
}

check_jq() {
    command -v jq >/dev/null 2>&1 || { kf_err "jq is required and is not on PATH"; return 1; }
}

# -- templates ----------------------------------------------------------------

# list_templates <root>: every template the floor check covers, as paths
# relative to <root>, one per line. The shipped templates plus this check's own
# fixtures; the mermaid companions are diagrams, not templates.
list_templates() {
    local root="$1" f rel
    for f in "$root"/skills/*/koto-templates/*.md "$root"/scripts/koto-floor/fixtures/*.md; do
        [ -f "$f" ] || continue
        case "$f" in *.mermaid.md) continue ;; esac
        rel=${f#"$root"/}
        echo "$rel"
    done
}

# copy_tree <root> <dest>: copies what a scenario reads -- skills/ and this
# check's fixtures -- with relative paths preserved, so execute.md's
# `default_template: ../../work-on/koto-templates/work-on.md` resolves in the
# copy exactly as it does in the checkout.
copy_tree() {
    local root="$1" dest="$2"
    mkdir -p "$dest/scripts/koto-floor" || return 1
    cp -R "$root/skills" "$dest/skills" || return 1
    cp -R "$root/scripts/koto-floor/fixtures" "$dest/scripts/koto-floor/fixtures" || return 1
}

# strip_decider <file>: deletes every accepts field's decider block in place.
strip_decider() {
    yq --front-matter=process -i 'del(.states[].accepts[]?.decider)' "$1"
}

# decider_count <file>: how many maps in the front matter carry a decider key,
# wherever they sit. Counting everywhere rather than under accepts is what lets
# a decider in the wrong place survive the strip and be reported.
decider_count() {
    yq --front-matter=extract '[.. | select(tag == "!!map" and has("decider"))] | length' "$1"
}

# collect_escapes <file>: prints each escape value a template declares, one
# per line.
collect_escapes() {
    yq --front-matter=extract '.states[].accepts[]? | select(tag == "!!map") | .decider.escape.value | select(. != null)' "$1"
}

# compiled_path <koto-bin> <file>: prints the compiled cache path koto reports.
# The path is keyed by the compiled form's hash, so two sources that print the
# same path compiled to the same template_hash. Warnings go to stderr and are
# not compared.
compiled_path() {
    local out
    out=$("$1" template compile "$2" 2>/dev/null) || return 1
    printf '%s\n' "$out" | awk 'NF {last = $0} END {print last}'
}

# -- transcripts --------------------------------------------------------------

# transcript_line: reads one `koto next` JSON response on stdin and prints
# `state<TAB>action<TAB>advanced`. An error response has no state; its action
# is recorded as error:<code> so two runs that fail differently still differ.
# `advanced` is tested with has() rather than `//`, which treats false as
# missing.
transcript_line() {
    jq -r '[(.state // "-"), (.action // ("error:" + ((.error.code // "unknown") | tostring))), (if has("advanced") then (.advanced | tostring) else "-" end)] | @tsv' 2>/dev/null \
        || printf '%s\t%s\t%s\n' "-" "unparseable" "-"
}

# compare_transcripts <a> <b> <label>: byte-identical or a diff and a failure.
compare_transcripts() {
    if cmp -s "$1" "$2"; then
        return 0
    fi
    kf_err "$3: the transcripts differ (original, then stripped):"
    diff "$1" "$2" >&2
    return 1
}

# expects_values <responses.jsonl>: every value a recorded `koto next` response
# offered, one per line: the enum values of each expected field, and the
# evidence values each option routes on.
expects_values() {
    jq -r '(.expects.fields // {})[]? | (.values // [])[]? | tostring' "$1" 2>/dev/null
    jq -r '(.expects.options // [])[]? | (.when // {}) | to_entries[] | select(.key | startswith("gates.") | not) | .value | tostring' "$1" 2>/dev/null
}

# escape_leaks <escapes-file> <responses.jsonl>...: prints each escape value
# that appears among the values any response offered. Empty output is a pass.
escape_leaks() {
    local escapes="$1" f
    shift
    [ -s "$escapes" ] || return 0
    for f in "$@"; do
        [ -f "$f" ] && expects_values "$f"
    done | sort -u | grep -Fxf "$escapes" || true
}

# -- scenarios ----------------------------------------------------------------
#
# A scenario runs with these in its environment, set by check-koto-floor.sh:
#
#   KOTO_BIN     the koto under test, by absolute path
#   TREE         the plugin root this run uses: the checkout, or the stripped
#                copy. Holds skills/ and scripts/koto-floor/fixtures/.
#   RUN_DIR      an empty directory for this run's fixture
#   TRANSCRIPT   where tick lines and the final state go
#   RESPONSES    where each raw `koto next` response goes, one per line
#   HOME         a fresh home under RUN_DIR
#
# Its working repository is $RUN_DIR/repo, a clone of the bare $RUN_DIR/origin.git.

REPO=""
LAST_STATE=""

# setup_home: a git identity in the run's own HOME, nothing inherited.
setup_home() {
    mkdir -p "$HOME"
    git config --global user.email floor@example.com
    git config --global user.name floor
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false
}

# fixture_repo <branch>: a bare origin with a seeded main, a `seed` clone that
# plays upstream, and a `repo` clone checked out on <branch>. main carries
# src/a.go, src/b.go, and README.md.
fixture_repo() {
    setup_home
    REPO="$RUN_DIR/repo"
    (
        cd "$RUN_DIR" || exit 1
        git init -q --bare origin.git
        git clone -q origin.git seed
        cd seed || exit 1
        mkdir -p src
        printf 'a1\na2\n' > src/a.go
        printf 'b1\n' > src/b.go
        printf 'readme\n' > README.md
        git add -A && git commit -q -m init && git push -q origin main
        cd .. && git clone -q origin.git repo
        cd repo && git checkout -q -b "$1"
    ) >/dev/null 2>&1 || { kf_err "could not build the git fixture in $RUN_DIR"; return 1; }
}

# upstream <shell> <subject>: a change made in the seed clone and pushed to
# origin's main, which is what "main moved" means to drift_facts.
upstream() {
    (cd "$RUN_DIR/seed" && eval "$1" && git add -A && git commit -q -m "$2" && git push -q origin main) >/dev/null 2>&1 \
        || { kf_err "upstream change [$2] failed"; return 1; }
}

# commit_in_repo <path> <content> <subject>: a commit on the run's branch.
commit_in_repo() {
    (cd "$REPO" && mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" > "$1" && git add -A && git commit -q -m "$3") >/dev/null 2>&1 \
        || { kf_err "commit [$3] failed"; return 1; }
}

# koto_init <session> <template> [--var K=V]...
koto_init() {
    local s="$1" t="$2"
    shift 2
    if ! (cd "$REPO" && "$KOTO_BIN" init "$s" --template "$t" "$@" >/dev/null 2>&1); then
        kf_err "koto init $s failed"
        return 1
    fi
}

# record_response <json>: one transcript line and one raw response line.
record_response() {
    printf '%s\n' "$1" | jq -c . >> "$RESPONSES" 2>/dev/null || printf '%s\n' '{}' >> "$RESPONSES"
    printf '%s\n' "$1" | transcript_line >> "$TRANSCRIPT"
    LAST_STATE=$(printf '%s\n' "$1" | jq -r '.state // empty' 2>/dev/null)
}

# tick <session> [evidence-json]: one `koto next`.
tick() {
    local resp
    if [ -n "${2:-}" ]; then
        resp=$(cd "$REPO" && "$KOTO_BIN" next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        resp=$(cd "$REPO" && "$KOTO_BIN" next "$1" --no-cleanup 2>/dev/null)
    fi
    record_response "$resp"
}

# tick_to <session> <state> <rationale>: a directed transition, for crossing a
# state that needs GitHub or the network. Both runs of a scenario cross it the
# same way, so it cannot affect the comparison.
tick_to() {
    local resp
    resp=$(cd "$REPO" && "$KOTO_BIN" next "$1" --to "$2" --rationale "$3" --no-cleanup 2>/dev/null)
    record_response "$resp"
}

# expect_state <want> <label>: the last tick stopped at <want>.
expect_state() {
    if [ "$LAST_STATE" != "$1" ]; then
        kf_err "$2: expected the tick to stop at $1, it stopped at [${LAST_STATE:-none}]"
        return 1
    fi
}

# visited <session> <state>: the session's own log records a transition into
# <state>. For a state a tick passes through without stopping, which no tick
# line can show.
visited() {
    local dir
    dir=$(cd "$REPO" && "$KOTO_BIN" session dir "$1" 2>/dev/null) || return 1
    cat "$dir"/*.state.jsonl 2>/dev/null \
        | jq -e --arg s "$2" -s 'map(select((.type == "transitioned" or .type == "directed_transition") and .payload.to == $s)) | length > 0' >/dev/null 2>&1
}

expect_visited() {
    if ! visited "$1" "$2"; then
        kf_err "$1: expected the run to pass through $2"
        return 1
    fi
}

# expect_final <session> <state>: appends the final `koto status` state to the
# transcript and fails unless it is <state>. Transcript equality alone would
# pass two runs that both stopped early at the same wrong place.
expect_final() {
    local st
    st=$(cd "$REPO" && "$KOTO_BIN" status "$1" 2>/dev/null | jq -r '.current_state // empty' 2>/dev/null)
    printf 'final\t%s\n' "${st:--}" >> "$TRANSCRIPT"
    if [ "$st" != "$2" ]; then
        kf_err "$1: expected to end at $2, ended at [${st:-none}]"
        return 1
    fi
}

# -- shared scenario openings -------------------------------------------------

EXECUTE_PLAN='---
schema: plan/v1
---
# PLAN: floor

## Scope Summary

Touches `src/a.go`.

## Issue Outlines

### Issue 1: feat: change a

**Goal**: Change a.

**Files**: `src/a.go`'

# execute_start <upstream-shell> <subject>: a /execute run on impl/floor whose
# PLAN references src/a.go and whose origin/main has moved by <upstream-shell>,
# ticked to wherever drift_facts and worktree_sync leave it. orchestrator_setup
# creates the draft PR, which needs GitHub, so it is crossed with --to.
EXECUTE_SESSION="execute-floor"
execute_start() {
    fixture_repo impl/floor || return 1
    commit_in_repo docs/plans/PLAN-floor.md "$EXECUTE_PLAN" "docs: plan" || return 1
    upstream "$1" "$2" || return 1
    koto_init "$EXECUTE_SESSION" "$TREE/skills/execute/koto-templates/execute.md" \
        --var PLAN_DOC=docs/plans/PLAN-floor.md --var PLAN_SLUG=floor \
        --var PLUGIN_ROOT="$TREE" --var PAUSE_BEFORE_FINALIZE=false || return 1
    tick "$EXECUTE_SESSION"
    expect_state orchestrator_setup "execute opening" || return 1
    tick_to "$EXECUTE_SESSION" settled_branch_record "the draft PR needs GitHub"
    expect_state settled_branch_record "execute opening" || return 1
    tick "$EXECUTE_SESSION"
}

# child_task <name> <fixture>: one task entry overriding the child template
# with one of this check's fixtures.
child_task() {
    printf '{"name":"%s","template":"%s/scripts/koto-floor/fixtures/%s"}' "$1" "$TREE" "$2"
}

# workon_init <session>: a /work-on session, plan-backed by its variables, in
# a fresh fixture on impl/<session>.
WORKON_TEMPLATE_REL="skills/work-on/koto-templates/work-on.md"
workon_init() {
    fixture_repo "impl/$1" || return 1
    koto_init "$1" "$TREE/$WORKON_TEMPLATE_REL" \
        --var ARTIFACT_PREFIX="task_$1" --var PLUGIN_ROOT="$TREE" \
        --var PLAN_DOC=docs/plans/PLAN-floor.md --var ISSUE_SOURCE=plan_outline
}

context_add() {
    (cd "$REPO" && printf '%s\n' "$3" | "$KOTO_BIN" context add "$1" "$2" >/dev/null 2>&1) \
        || { kf_err "koto context add $1 $2 failed"; return 1; }
}

# workon_plan_backed <session>: entry through plan_validation, which it leaves
# waiting for a verdict.
workon_plan_backed() {
    workon_init "$1" || return 1
    tick "$1"
    expect_state entry "$1" || return 1
    tick "$1" '{"mode":"plan_backed"}'
    expect_state plan_context_injection "$1" || return 1
    context_add "$1" context.md "Issue 1: change a. Goal: change a." || return 1
    tick "$1" '{"status":"completed","issue_source":"plan_outline"}'
    expect_state plan_validation "$1"
}

# workon_to_routing <session> <commit>: from plan_validation's `proceed` to
# issue_type_routing. With <commit> = yes, implementation lands a commit over
# main, which the docs route's gate needs.
workon_to_routing() {
    tick "$1" '{"verdict":"proceed"}'
    expect_state setup_plan_backed "$1" || return 1
    tick "$1" '{"status":"override"}'
    expect_state analysis "$1" || return 1
    context_add "$1" plan.md "Change src/a.go." || return 1
    tick "$1" '{"plan_outcome":"plan_ready"}'
    expect_state implementation "$1" || return 1
    if [ "$2" = yes ]; then
        commit_in_repo docs/guide.md "guide" "docs: add a guide" || return 1
    fi
    tick "$1" '{"implementation_status":"complete"}'
    expect_state issue_type_routing "$1" || return 1
    expect_visited "$1" changed_paths_record
}

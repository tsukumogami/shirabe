#!/usr/bin/env bash
# verification-map-schema_test.sh -- does shirabe's committed verification map
# match the shirabe-verification-map/v1 schema, and does the schema reference
# document it?
#
# The map at .claude/shirabe-extensions/verification-map.json replaced the
# Markdown list in .claude/shirabe-extensions/work-on.md. This holds the map to
# what that list said (the same default commands, check-skill once per changed
# skill) and to the schema's one cross-field rule: a command marked
# network: true sets unattended explicitly. It also holds the schema reference
# to naming every field and the merge-base read, and work-on.md to pointing at
# the map without listing commands itself.
#
# Each jq check is a named query run against a file, so the negative cases run
# the same query on altered copies of the map and require it to fail; a check
# that passed everything would be caught.
#
# Usage: verification-map-schema_test.sh
# Exit codes: 0 all pass, 1 any failed, 2 the harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
command -v git >/dev/null 2>&1 || { echo "git is required to run this suite" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) \
    || { echo "not inside a git working tree" >&2; exit 2; }

MAP="$ROOT/.claude/shirabe-extensions/verification-map.json"
EXT="$ROOT/.claude/shirabe-extensions/work-on.md"
REF="$ROOT/skills/work-on/references/verification-map.md"
for f in "$MAP" "$EXT" "$REF"; do
    [ -r "$f" ] || { echo "$f is not readable" >&2; exit 2; }
done

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/verification-map-schema-test.XXXXXX")
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# The queries. Each is true exactly when the map satisfies the rule.
Q_SCHEMA='.schema == "shirabe-verification-map/v1"'
# The default list, resolved to argv strings, is the three commands the
# Markdown default named, in that order.
Q_DEFAULT='. as $m | [$m.default[] | $m.commands[.].run | join(" ")]
    == ["cargo test --workspace",
        "skills/plan/scripts/plan-to-tasks_test.sh",
        "skills/work-on/scripts/run-cascade_test.sh"]'
# A skills/** entry exists, and one of its commands runs
# scripts/check-skill.sh once per changed skill.
Q_SKILLS='. as $m | [$m.entries[] | select(.paths | index("skills/**"))
    | .commands[] | $m.commands[.]]
    | any(.run == ["scripts/check-skill.sh"] and .each == "skills/*")'
# Every command that reaches the network says whether it may run unattended.
Q_NETWORK='[.commands[] | select(.network == true) | has("unattended")] | all'
# Every id an entry or the default names is defined.
Q_IDS='. as $m | [($m.entries[].commands[]), ($m.default // [])[]]
    | all(. as $id | $m.commands | has($id))'

# holds <file> <query>: exit 0 when the query is true on the file.
holds() { jq -e "$2" "$1" >/dev/null 2>&1; }

check() { # check <label> <query>
    if holds "$MAP" "$2"; then pass "$1"; else fail "$1"; fi
}

check "the map declares schema shirabe-verification-map/v1" "$Q_SCHEMA"
check "the default list names the three Markdown default commands" "$Q_DEFAULT"
check "the skills/** entry runs scripts/check-skill.sh with each: skills/*" "$Q_SKILLS"
check "every network: true command sets unattended explicitly" "$Q_NETWORK"
check "every command id an entry or the default names is defined" "$Q_IDS"

# Negative cases: altered copies of the map must fail the same queries.
neg() { # neg <label> <query> <jq edit>
    local copy="$WORKDIR/neg.json"
    if ! jq "$3" "$MAP" > "$copy" 2>/dev/null; then
        fail "$1 (could not build the altered map)"; return
    fi
    if holds "$copy" "$2"; then fail "$1"; else pass "$1"; fi
}

neg "a different schema string is refused" "$Q_SCHEMA" \
    '.schema = "shirabe-verification-map/v2"'
neg "a default list missing run-cascade is refused" "$Q_DEFAULT" \
    '.default |= map(select(. != "run-cascade"))'
neg "a check-skill without each is refused" "$Q_SKILLS" \
    '.commands["check-skill"] |= del(.each)'
neg "a networked command without unattended is refused" "$Q_NETWORK" \
    '.commands["net"] = {"run": ["true"], "network": true}'
neg "an entry naming an undefined id is refused" "$Q_IDS" \
    '.entries += [{"paths": ["x/**"], "commands": ["nope"]}]'

# The positive twin of the network case: setting unattended either way passes.
copy="$WORKDIR/net.json"
if jq '.commands["net"] = {"run": ["true"], "network": true, "unattended": false}' \
        "$MAP" > "$copy" 2>/dev/null && holds "$copy" "$Q_NETWORK"; then
    pass "a networked command with unattended set explicitly is accepted"
else
    fail "a networked command with unattended set explicitly is accepted"
fi

# The schema reference names every field the design lists, and the merge-base
# read.
for field in run each timeout_secs network unattended max_procs entries default; do
    if grep -Fq "\`$field\`" "$REF"; then
        pass "verification-map.md documents \`$field\`"
    else
        fail "verification-map.md documents \`$field\`"
    fi
done
if grep -Fq 'git show <merge-base>:.claude/shirabe-extensions/verification-map.json' "$REF" \
        && grep -Fq 'merge-base' "$REF"; then
    pass "verification-map.md documents the read at the merge-base"
else
    fail "verification-map.md documents the read at the merge-base"
fi

# work-on.md points at the map and lists no commands of its own.
n=$(grep -c 'verification-map.json' "$EXT")
if [ "$n" -ge 1 ]; then
    pass "work-on.md names verification-map.json"
else
    fail "work-on.md names verification-map.json (count $n)"
fi
n=$(grep -c 'cargo test' "$EXT")
if [ "$n" -eq 0 ]; then
    pass "work-on.md lists no commands (no cargo test)"
else
    fail "work-on.md lists no commands (cargo test appears $n times)"
fi

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]

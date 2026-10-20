#!/usr/bin/env bash
# jev-withhold.sh -- which copy of a rule file a state loads, for a rule a
# trusted Jev criterion checks.
#
# A rule whose Jev criterion has earned pass trust may be left out of what a
# run reads, but only where the decider will actually check the result: a user
# whose decider runs in auto with a key, in a project that sets no decider
# configuration of its own, in a session where the check hasn't fallen back to
# the agent. Everywhere else the rule stays loaded. DESIGN-jev-pass-trust.md is
# the design; references/jev-criteria.md the contract.
#
# Usage:
#   jev-withhold.sh <rule-id> <rule-file> <session-name> <session-dir> <plugin-root>
#
# <rule-file> is the plugin-relative path of the file the state loads, the
# rule's text.path. A template runs this as a default action with
# capture_stdout_as, the way work-on.md runs offload-canary.sh, and names the
# captured path in its directive. No template calls it yet:
# jev_criteria.py check refuses a call for a rule that isn't trusted, and none
# is.
#
# It prints exactly one line and always exits 0. Called with anything but five
# arguments it knows no file to fall back on and prints an empty line; with
# five, the line is a path. The answer is <plugin-root>/<rule-file>, the full
# file, unless every check below passes, in order; then it is a copy of that
# file without the rule's lines, rendered into <session-dir>/jev-rules/:
#   0. the arguments have safe shapes and the session directory exists and is
#      not a symlink;
#   1. the registry entry's jev.state is trusted, its withhold is eligible and
#      its text.path is <rule-file>;
#   2. `koto config get decider.mode` prints auto;
#   3. `koto config get decider.api_key` exits 0;
#   4. ./.koto/config.toml, where koto reads the project's configuration, is
#      absent or mentions `decider` on no line outside a comment;
#   5. the session log, <session-dir>/koto-<session-name>.state.jsonl, holds
#      for the entry's gate and criterion no decider_checked whose mode isn't
#      veto or whose outcome isn't pass or fail (unanswered, escape,
#      not_graded or none), no decider_fallback and no decider_check_answered.
#      A missing or malformed log fails this.
# Because 5 reads the log on every call, a fallback, an agent answer or a
# check the decider left unanswered makes every later call in the session
# print the full file.

set -u

FULL=""
ANSWER=""
# Whatever happens below, one path is printed: the full file unless a
# rendering was completed and checked.
trap 'printf "%s\n" "${ANSWER:-$FULL}"' EXIT

# The registry's two id forms, as rule-registry.sh and jev_criteria.py accept
# them. The session name only builds a log path, so its shape is kept narrow;
# a name outside it falls back to the full file.
ID_SHAPE='^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3})$'
NAME_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
PATH_SHAPE='^[A-Za-z0-9._][A-Za-z0-9._/-]*$'

[ $# -eq 5 ] || exit 0
RULE=$1 REL=$2 NAME=$3 SDIR=$4 ROOT=$5
FULL="$ROOT/$REL"

[[ $RULE =~ $ID_SHAPE ]] || exit 0
[[ $NAME =~ $NAME_SHAPE ]] || exit 0
[[ $REL =~ $PATH_SHAPE ]] || exit 0
case "/$REL/" in */../*|*/./*) exit 0 ;; esac
[ -d "$SDIR" ] && [ ! -L "$SDIR" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

REG="$ROOT/references/rule-registry.json"
HELPER="$ROOT/scripts/rule-registry.sh"

# 1. The entry.
entry=$(jq -ce --arg id "$RULE" '.rules[] | select(.id == $id)' "$REG" 2>/dev/null) || exit 0
[ "$(jq -r '.jev.state // ""' <<<"$entry")" = trusted ] || exit 0
[ "$(jq -r '.withhold // ""' <<<"$entry")" = eligible ] || exit 0
[ "$(jq -r '.text.path // ""' <<<"$entry")" = "$REL" ] || exit 0
GATE=$(jq -r '.check.gate // ""' <<<"$entry")
CRIT=$(jq -r '.check.criterion // ""' <<<"$entry")
[ -n "$GATE" ] && [ -n "$CRIT" ] || exit 0

# 2 and 3. The user's decider, as koto resolves it (the KOTO_DECIDER variable
# over the user's own koto configuration file).
command -v koto >/dev/null 2>&1 || exit 0
[ "$(koto config get decider.mode 2>/dev/null)" = auto ] || exit 0
koto config get decider.api_key >/dev/null 2>&1 || exit 0

# 4. A project setting can only lower the mode; any mention counts.
if [ -e .koto/config.toml ]; then
    [ -f .koto/config.toml ] && [ ! -L .koto/config.toml ] || exit 0
    if sed 's/#.*//' .koto/config.toml 2>/dev/null | grep -qi decider; then
        exit 0
    fi
fi

# 5. The session's own decider events for this check.
LOG="$SDIR/koto-$NAME.state.jsonl"
[ -f "$LOG" ] && [ ! -L "$LOG" ] || exit 0
seen=$(tail -n +2 "$LOG" | jq -c --arg g "$GATE" --arg c "$CRIT" '
  select(.payload.gate? == $g and .payload.rule_id? == $c)
  | select((.type == "decider_checked"
            and (.payload.mode != "veto"
                 or (.payload.outcome != "pass" and .payload.outcome != "fail")))
           or .type == "decider_fallback" or .type == "decider_check_answered")' 2>/dev/null) || exit 0
[ -z "$seen" ] || exit 0

# The withheld copy: the file without the rule's range, the range checked to
# be the rule's own lines in this file.
range=$("$HELPER" --root "$ROOT" range "$RULE" 2>/dev/null) || exit 0
a=${range% *}
b=${range#* }
case "$a$b" in *[!0-9]*|'') exit 0 ;; esac
[ "$(LC_ALL=C sed -n "${a}p" "$FULL")" = "$("$HELPER" --root "$ROOT" text "$RULE" 2>/dev/null | head -n 1)" ] || exit 0
DIR="$SDIR/jev-rules"
[ -L "$DIR" ] && exit 0
mkdir -p "$DIR" 2>/dev/null || exit 0
[ -d "$DIR" ] && [ ! -L "$DIR" ] || exit 0
OUT="$DIR/${RULE//\//-}-${REL##*/}"
[ ! -L "$OUT" ] && [ ! -d "$OUT" ] || exit 0
tmp=$(mktemp "$DIR/.withheld.XXXXXX" 2>/dev/null) || exit 0
if LC_ALL=C awk -v a="$a" -v b="$b" 'NR < a || NR > b' "$FULL" > "$tmp" 2>/dev/null && mv -f "$tmp" "$OUT"; then
    ANSWER=$OUT
else
    rm -f "$tmp"
fi
exit 0

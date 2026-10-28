#!/usr/bin/env bash
# work-on-requires_test.sh -- /work-on's koto floor, with and without
# --koto-leg, as preflight reports it.
# Part of the work-on skill
#
# skills/work-on/requires.tsv declares one koto init entry flag for every run,
# --attach-live (review-level.sh set rebinds REVIEW_LEVEL with it), and declares
# the entry flags --koto-leg needs (--vars-file, --attach-live, --koto-leg) in a
# `mode:koto-leg` record. Against a stand-in koto whose `init --help` predates
# --vars-file and --koto-leg, this asserts:
#
#   - the load-time preflight (`skill-preflight.sh work-on`) prints nothing
#     when that koto reports shirabe's koto minimum: a run without the flag is
#     not refused for lacking the entry flags
#   - the same koto reporting a version below the minimum gets the upgrade
#     block at load, from scripts/lib/preflight-minimum.sh
#   - `skill-preflight.sh work-on --mode koto-leg`, which SKILL.md runs before
#     the --koto-leg open, names the missing flags
#   - the mode record's flags are the ones /scope, /execute and /deliver
#     declare for the same call, --replace-terminal aside, which /work-on
#     never passes
#
# and, when a real koto with --koto-leg is installed, that the mode run prints
# nothing.
#
# Usage: work-on-requires_test.sh
# Exit codes: 0 all pass; 1 a failure.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
REQ="$REPO/skills/work-on/requires.tsv"
PREFLIGHT="$REPO/scripts/skill-preflight.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }

T=$(mktemp -d "${TMPDIR:-/tmp}/work-on-requires-test.XXXXXX") || exit 1
ktg_on_exit 'rm -rf "$T"'

MODE_FLAGS=$(awk -F'\t' '$1 == "koto" && $2 == "init" && $4 == "mode:koto-leg" { print $3 }' "$REQ")
for f in --vars-file --attach-live --koto-leg; do
    case ",$MODE_FLAGS," in
        *",$f,"*) ok "the mode:koto-leg init record declares $f" ;;
        *) bad "the mode:koto-leg init record declares $f" "[$MODE_FLAGS]" ;;
    esac
done
ALWAYS_FLAGS=$(awk -F'\t' '$1 == "koto" && $2 == "init" && $4 == "always" { print $3 }' "$REQ")
# --attach-live is the one entry flag every run needs: review-level.sh set
# rebinds REVIEW_LEVEL with it. The other two stay --koto-leg's alone.
case "$ALWAYS_FLAGS" in
    *--koto-leg*|*--vars-file*) bad "the always init record declares no --koto-leg-only entry flag" "[$ALWAYS_FLAGS]" ;;
    *) ok "the always init record declares no --koto-leg-only entry flag" ;;
esac
case ",$ALWAYS_FLAGS," in
    *,--attach-live,*) ok "the always init record declares --attach-live, which review-level.sh set needs" ;;
    *) bad "the always init record declares --attach-live, which review-level.sh set needs" "[$ALWAYS_FLAGS]" ;;
esac
DELIVER_FLAGS=$(awk -F'\t' '$1 == "koto" && $2 == "init" { print $3 }' "$REPO/skills/deliver/requires.tsv")
for f in $(printf '%s' "$MODE_FLAGS" | tr ',' ' '); do
    case ",$DELIVER_FLAGS," in
        *",$f,"*) ok "/deliver's init record also names $f" ;;
        *) bad "/deliver's init record also names $f" "[$DELIVER_FLAGS]" ;;
    esac
done

# A koto without the --koto-leg entry flags: `init --help` knows --template,
# --var and --attach-live (which every run needs, and which predates the
# floor); every other subcommand answers with the flags /work-on always needs,
# `decider answer` and its flags included, and lists `session dir` among the
# commands, so the only gap it shows is the entry flags.
# Its `version` prints $KOTO_STUB_VERSION, so one stand-in covers the surface
# cases at the minimum and the minimum case below it.
MINIMUM=$(bash "$REPO/scripts/assert-koto-floor.sh" --print-floor)
mkdir -p "$T/bin" "$T/cwd"
cat >"$T/bin/koto" <<'OLD'
#!/usr/bin/env bash
case "$*" in
    "init --help") printf 'Usage: koto init <NAME> --template <T>\n\nOptions:\n      --template <T>\n      --var <K=V>\n      --attach-live\n  -h, --help\n' ;;
    *"--help"|"help") printf 'Usage: koto %s\n\nCommands:\n  init\n  next\n  workflows\n  status\n  session\n  rewind\n  context\n  decisions\n  overrides\n  decider\n  list\n  cleanup\n  dir\n  add\n  get\n  exists\n  remove\n  record\n  answer\n\nOptions:\n      --with-data <D>\n      --no-cleanup\n      --from-file <F>\n      --children <NAME>\n      --gate <G>\n      --rationale <R>\n      --criterion <C>\n      --answer <A>\n  -h, --help\n' "$1" ;;
    "version"|"--version") printf 'koto %s\n' "$KOTO_STUB_VERSION" ;;
    *) printf "error: unrecognized subcommand '%s'\n" "$1" >&2; exit 2 ;;
esac
OLD
chmod +x "$T/bin/koto"

OUT=$(cd "$T/cwd" && KOTO_STUB_VERSION="$MINIMUM" PATH="$T/bin:$PATH" bash "$PREFLIGHT" work-on 2>&1)
case "$OUT" in
    *koto*) bad "load-time preflight on a koto without the entry flags is silent about koto" "$OUT" ;;
    *) ok "load-time preflight on a koto without the entry flags is silent about koto" ;;
esac
OUT=$(cd "$T/cwd" && KOTO_STUB_VERSION=0.0.1 PATH="$T/bin:$PATH" bash "$PREFLIGHT" work-on 2>&1)
case "$OUT" in
    *"koto 0.0.1 is installed. shirabe's skills are tested on koto $MINIMUM and"*) ok "load-time preflight on a koto below the minimum names both versions" ;;
    *) bad "load-time preflight on a koto below the minimum names both versions" "$OUT" ;;
esac
OUT=$(cd "$T/cwd" && KOTO_STUB_VERSION="$MINIMUM" PATH="$T/bin:$PATH" bash "$PREFLIGHT" work-on --mode koto-leg 2>&1)
case "$OUT" in
    *--koto-leg*) ok "--mode koto-leg on an older koto names --koto-leg" ;;
    *) bad "--mode koto-leg on an older koto names --koto-leg" "$OUT" ;;
esac

# The case needs a koto at or above the floor: one below it is named by the
# load-time minimum check, which is the case above, not this one.
if command -v koto >/dev/null 2>&1 && bash "$REPO/scripts/assert-koto-floor.sh" >/dev/null 2>&1; then
    OUT=$(cd "$T/cwd" && bash "$PREFLIGHT" work-on --mode koto-leg 2>&1)
    if [ -z "$OUT" ]; then ok "--mode koto-leg on a koto at the floor prints nothing"; else bad "--mode koto-leg at the floor prints nothing" "$OUT"; fi
else
    echo "SKIP: no koto at or above the floor ($MINIMUM) on PATH -- the at-floor case did not run"
fi

# The PR gate's validator flag. Both /work-on (pr_creation) and /execute
# (pr_finalization) run check-pr-output.sh, which passes --writing-style, so
# both skills' always records declare it, and a shirabe whose `validate
# --help` predates it is named at load.
for skill in work-on execute; do
    FLAGS=$(awk -F'\t' '$1 == "shirabe" && $2 == "validate" && $4 == "always" { print $3 }' \
        "$REPO/skills/$skill/requires.tsv")
    for f in --pr-body --pr-title --writing-style; do
        case ",$FLAGS," in
            *",$f,"*) ok "$skill's always shirabe validate record declares $f" ;;
            *) bad "$skill's always shirabe validate record declares $f" "[$FLAGS]" ;;
        esac
    done
done
mkdir -p "$T/shbin"
cat >"$T/shbin/shirabe" <<'OLDSHIRABE'
#!/usr/bin/env bash
case "$*" in
    "validate --help") printf 'Usage: shirabe validate [OPTIONS] [FILES]...\n\nOptions:\n      --format <FORMAT>\n      --check <CHECK>\n      --visibility <V>\n      --lifecycle <ROOT>\n      --mode <MODE>\n      --lifecycle-chain <DOC>\n      --allow-untracked-acs\n      --merge-gate\n      --pr <PR>\n      --upstream <U>\n      --coordination-body <FILE>\n      --pr-body <FILE>\n      --pr-title <STRING>\n  -h, --help\n' ;;
    *"--help") printf 'Usage: shirabe %s\n\nCommands:\n  validate\n  transition\n  finalize-chain\n\nOptions:\n  -h, --help\n' "$1" ;;
    "--version"|"-V") printf 'shirabe 0.26.0\n' ;;
    *) exit 2 ;;
esac
OLDSHIRABE
chmod +x "$T/shbin/shirabe"
for skill in work-on execute; do
    OUT=$(cd "$T/cwd" && PATH="$T/shbin:$PATH" bash "$PREFLIGHT" "$skill" 2>&1)
    case "$OUT" in
        *--writing-style*) ok "load-time preflight for $skill on a shirabe without --writing-style names it" ;;
        *) bad "load-time preflight for $skill on a shirabe without --writing-style names it" "$OUT" ;;
    esac
done

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

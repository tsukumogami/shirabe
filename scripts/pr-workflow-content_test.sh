#!/usr/bin/env bash
# pr-workflow-content_test.sh -- pr-workflow-content.sh prints include only
# for a repository that declares it, omit otherwise, reading CLAUDE.local.md
# before CLAUDE.md.
#
# Covers: no file, no header (omit); include and omit in CLAUDE.md; case and
# spacing; CLAUDE.local.md before CLAUDE.md, both ways; an unknown value
# passed over; the first well-formed header in a file; CRLF line ends; the
# work tree's root as the default directory; a missing directory; usage.
# The recorded switch: --record stores the value read once as pr_content;
# --session prints it, keeps it when the files change, falls back to the files
# only with the key absent, and reads anything but include as omit; the
# failure exits; usage. Those cases run against the record stub koto.
#
# Usage: bash scripts/pr-workflow-content_test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/pr-workflow-content.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/pr-workflow-content-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

N=0
repo() { N=$((N + 1)); R="$T/r$N"; mkdir -p "$R"; }

repo
eq "no CLAUDE.md: omit" omit "$(bash "$S" "$R")"
repo; printf '# Repo\n\n## Repo Visibility: Public\n' > "$R/CLAUDE.md"
eq "no header: omit" omit "$(bash "$S" "$R")"
repo; printf '# Repo\n\n## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "include in CLAUDE.md: include" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.md"
eq "omit in CLAUDE.md: omit" omit "$(bash "$S" "$R")"
repo; printf '  ## pr workflow content:   INCLUDE  \n' > "$R/CLAUDE.md"
eq "case and spacing don't matter" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: include\r\n' > "$R/CLAUDE.md"
eq "a CRLF line end is read" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.local.md"; printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.md"
eq "CLAUDE.local.md is read before CLAUDE.md (include)" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.local.md"; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "CLAUDE.local.md is read before CLAUDE.md (omit)" omit "$(bash "$S" "$R")"
repo; printf '# Local\n' > "$R/CLAUDE.local.md"; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "a CLAUDE.local.md with no header falls through to CLAUDE.md" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: yes\n## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "an unknown value is passed over for the next well-formed header" include "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: always\n' > "$R/CLAUDE.md"
eq "only an unknown value: omit" omit "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: include please\n' > "$R/CLAUDE.md"
eq "trailing words make it not well-formed: omit" omit "$(bash "$S" "$R")"
repo; printf '## PR Workflow Content: omit\n## PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "the first well-formed header wins" omit "$(bash "$S" "$R")"
repo; printf '### PR Workflow Content: include\n' > "$R/CLAUDE.md"
eq "a deeper heading is not the header" omit "$(bash "$S" "$R")"

if command -v git >/dev/null 2>&1; then
    repo; git init -q "$R" && printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md" && mkdir -p "$R/a/b"
    eq "no argument: the work tree's root" include "$(cd "$R/a/b" && bash "$S")"
else
    ok "no argument: the work tree's root (skipped: no git)"
fi

bash "$S" "$T/missing" >/dev/null 2>&1; eq "a directory that doesn't exist: exit 2" 2 $?
bash "$S" a b >/dev/null 2>&1; eq "two arguments: exit 64" 64 $?
bash "$S" --help >/dev/null 2>&1; eq "an option: exit 64" 64 $?

# --- the switch, recorded once per invocation ----------------------------------
# --record and --session run against the record stub koto, never a real one:
# the stub is asserted to be the koto on PATH before the first case.
STUB_DIR="$HERE/testdata/record-koto"
export RECORD_KOTO_STORE="$T/koto-store"
mkdir -p "$RECORD_KOTO_STORE"
KPATH="$STUB_DIR:$PATH"
case "$(PATH="$KPATH" command -v koto)" in
    "$STUB_DIR/koto") ok "the koto on PATH is the record stub" ;;
    *) bad "the koto on PATH is not the record stub" "$(PATH="$KPATH" command -v koto)"; echo "pr-workflow-content: refusing to run the session cases"; exit 1 ;;
esac
kv() { # kv <dir> <session>: the session's pr_content as the stub holds it
    (cd "$1" && PATH="$KPATH" koto context get "$2" pr_content 2>/dev/null)
}

repo; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.local.md"
for s in execute-t execute-odd execute-w; do
    (cd "$R" && PATH="$KPATH" koto init "$s" --template t >/dev/null)
done
OUT=$(cd "$R" && PATH="$KPATH" bash "$S" --record execute-t "$R"); RC=$?
eq "--record prints the value it read" "include/0" "$OUT/$RC"
eq "--record stores include as pr_content" include "$(kv "$R" execute-t)"
eq "--session prints the recorded include" include "$(cd "$R" && PATH="$KPATH" bash "$S" --session execute-t)"
# The header turned off after the open: the recorded value stands until the
# next opener records again.
printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.local.md"
eq "--session keeps the recorded value when the files change" include "$(cd "$R" && PATH="$KPATH" bash "$S" --session execute-t)"
OUT=$(cd "$R" && PATH="$KPATH" bash "$S" --record execute-t)
eq "a later --record (no directory: the work tree's root, else here) records omit" "omit/omit" "$OUT/$(kv "$R" execute-t)"
eq "--session then prints omit" omit "$(cd "$R" && PATH="$KPATH" bash "$S" --session execute-t)"

R1=$R
repo; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.md"
(cd "$R" && PATH="$KPATH" koto init execute-none --template t >/dev/null)
eq "--session with the key absent falls back to the files" include "$(cd "$R" && PATH="$KPATH" bash "$S" --session execute-none)"
(cd "$R1" && printf 'yes' | PATH="$KPATH" koto context add execute-odd pr_content >/dev/null)
eq "--session with a key holding neither word prints omit" omit "$(cd "$R1" && PATH="$KPATH" bash "$S" --session execute-odd)"

OUT=$(cd "$R1" && RECORD_KOTO_FAIL_WRITES=1 PATH="$KPATH" bash "$S" --record execute-w "$R1" 2>/dev/null); RC=$?
eq "--record whose write fails: exit 66, the value still printed" "omit/66" "$OUT/$RC"
# A koto whose exists answers neither 0 (held) nor 1 (absent) is a failed
# read, never an absent key: the files are not consulted.
mkdir -p "$T/failing-koto"
printf '#!/usr/bin/env bash\nexit 3\n' > "$T/failing-koto/koto"
chmod +x "$T/failing-koto/koto"
OUT=$(cd "$R" && PATH="$T/failing-koto:$PATH" bash "$S" --session execute-t 2>/dev/null); RC=$?
eq "--session whose read fails: omit, exit 66, the files not read" "omit/66" "$OUT/$RC"

# --reference: the one Part 2 line under include, nothing under omit.
RID=0123456789abcdef0123456789abcdef
repo; printf '## PR Workflow Content: include\n' > "$R/CLAUDE.local.md"
(cd "$R" && PATH="$KPATH" koto init execute-ref --template t >/dev/null \
    && printf '%s' "$RID" | PATH="$KPATH" koto context add execute-ref run_id >/dev/null \
    && PATH="$KPATH" bash "$S" --record execute-ref >/dev/null)
eq "--reference under include prints the one Run record line" \
    "Run record: execute-ref (run $RID)" "$(cd "$R" && PATH="$KPATH" bash "$S" --reference execute-ref)"
printf '## PR Workflow Content: omit\n' > "$R/CLAUDE.local.md"
(cd "$R" && PATH="$KPATH" bash "$S" --record execute-ref >/dev/null)
OUT=$(cd "$R" && PATH="$KPATH" bash "$S" --reference execute-ref); RC=$?
eq "--reference under omit prints nothing" "/0" "$OUT/$RC"
printf '## PR Workflow Content: include\n' > "$R/CLAUDE.local.md"
(cd "$R" && PATH="$KPATH" koto init execute-norid --template t >/dev/null \
    && PATH="$KPATH" bash "$S" --record execute-norid >/dev/null)
OUT=$(cd "$R" && PATH="$KPATH" bash "$S" --reference execute-norid 2>/dev/null); RC=$?
eq "--reference with no run_id under include prints nothing, exit 66" "/66" "$OUT/$RC"

# A multi-pr item's session names its plan root (record_root); the line names
# the plan root and the run_id it holds at the shared address.
export SHIRABE_RUN_RECORD_TEST_ROOT="$T/shared-record"
PROOT=plan.o.r.topic.0123456789ab
PRID=fedcba9876543210fedcba9876543210
mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/o"
(cd "$SHIRABE_RUN_RECORD_TEST_ROOT/o" && PATH="$KPATH" koto init "$PROOT" --template t >/dev/null \
    && printf '%s' "$PRID" | PATH="$KPATH" koto context add "$PROOT" run_id >/dev/null)
(cd "$R" && PATH="$KPATH" koto init item-7 --template t >/dev/null \
    && printf '%s' "$PROOT" | PATH="$KPATH" koto context add item-7 record_root >/dev/null \
    && PATH="$KPATH" bash "$S" --record item-7 >/dev/null)
eq "--reference for a multi-pr item names its plan root and the root's run_id" \
    "Run record: $PROOT (run $PRID)" "$(cd "$R" && PATH="$KPATH" bash "$S" --reference item-7)"

bash "$S" --record >/dev/null 2>&1; eq "--record without a session: exit 64" 64 $?
bash "$S" --session 'a b' >/dev/null 2>&1; eq "--session with a bad name: exit 64" 64 $?
bash "$S" --session execute-t "$R" >/dev/null 2>&1; eq "--session with a directory: exit 64" 64 $?
bash "$S" --record execute-t a b >/dev/null 2>&1; eq "--record with two directories: exit 64" 64 $?

echo
echo "pr-workflow-content: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

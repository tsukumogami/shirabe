#!/usr/bin/env bash
#
# release-eval-check.sh - shirabe's eval check for /shirabe:release
#
# Runs every skill's script cases, labels each failing case against the newest
# earlier release whose eval-pass-rates.json asset measured the skill, and
# leaves a record for the release to attach. Any failing case stops the
# release until a person confirms it. Declared as the release check in the
# repository's release extension; see
# docs/designs/current/DESIGN-skill-regression-detection.md (Decision 3).
#
# Usage:
#   scripts/release-eval-check.sh
#   scripts/release-eval-check.sh --finalize
#
# The check (first form):
#   1. Validates RELEASE_LAST_TAG (empty, or vX.Y.Z), RELEASE_VERSION (X.Y.Z)
#      and the names in RELEASE_CONFIRMED_DROPS.
#   2. With a last tag, reads the GitHub repository from the origin remote, so
#      an origin it can't read fails before any case runs.
#   3. With RELEASE_CONFIRMED_DROPS non-empty and a state marker naming this
#      HEAD and last tag, skips to step 6: a confirmation compares the saved
#      summary again and runs no case.
#   4. Otherwise exits 1 when koto isn't on PATH (the hand-off cases attach
#      koto sessions), empties the state directory, prints the host it runs
#      on, and selects every skills/<name>/ holding evals/evals.json, in name
#      order: the set scripts/lib/script-cases.py --all runs.
#   5. Runs python3 scripts/lib/script-cases.py --all --summary-out
#      <state>/summary.json once, from the repository root, with its output
#      passing through. A runner exit of 0, or 1 (a case failed), goes on and
#      writes the marker naming HEAD, the last tag and the selected skills;
#      any other exit is an infrastructure failure and writes no record.
#   6. Prints "script cases: <P> of <N> passed", the totals over the saved
#      summary, and "model-graded cases: not run": the two lines the release
#      notes copy.
#   7. With a non-empty last tag, downloads eval-pass-rates.json with gh into a
#      mktemp -d directory from that release and from the older v* releases
#      merged into HEAD, newest first, ten releases at most. A release or asset
#      gh reports as not found is skipped, and none found anywhere means no
#      baseline; any other download failure exits 1 with gh's reason.
#   8. Runs scripts/lib/eval-pass-rates.py merge with the saved summary, the
#      selected skills and every record found, newest first. The merge labels
#      each failing case against the skill's baseline (regressed, still
#      failing, or failing with no baseline), writes <state>/eval-pass-rates.json
#      and decides the exit code: the baseline picks the label and never the
#      exit. A record over the merge's size cap is skipped there, unread.
#
# --finalize (the release-assets half, after the draft release exists):
#   Refuses unless the marker names the current HEAD and RELEASE_LAST_TAG and a
#   record exists. Then stamps the record with RELEASE_VERSION (its version, and
#   measured_at of the skills the marker names) and prints
#   "asset: <record path>" as its last line. It uploads nothing.
#
# State directory: $(git rev-parse --git-dir)/shirabe-release/, per worktree
# and never committed.
#
# Environment:
#   RELEASE_VERSION          the version being released (X.Y.Z), required
#   RELEASE_LAST_TAG         the previous release's tag (vX.Y.Z), or empty
#   RELEASE_CONFIRMED_DROPS  comma-separated skills whose failing cases a
#                            person confirmed; set only on the re-run after a yes
#
# Exit codes:
#   check:    0 every case passed, or every skill with a failing case is in
#             RELEASE_CONFIRMED_DROPS; 1 an infrastructure failure (no koto, a
#             runner exit other than 0 or 1, a skill directory off the name
#             pattern, a failed download, a missing summary entry); 5 a failing
#             case not confirmed, the output ending with a
#             "confirm: RELEASE_CONFIRMED_DROPS=<a,b>" line; 2 usage
#   finalize: 0 with an "asset:" line; 1 the marker or record doesn't match
#             this release; 2 usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SCRIPT_DIR/lib/script-cases.py"
RECORD_TOOL="$SCRIPT_DIR/lib/eval-pass-rates.py"
ASSET_NAME="eval-pass-rates.json"
RETRY="run the check again"

SKILL_RE='^[a-z0-9][a-z0-9-]*$'
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

usage() {
  echo "Usage: $0" >&2
  echo "       $0 --finalize" >&2
  exit 2
}

die_usage() {
  echo "release-eval-check: $*" >&2
  exit 2
}

fail() {
  echo "release-eval-check: $*" >&2
  exit 1
}

valid_skill() {
  grep -Eq "$SKILL_RE" <<<"$1"
}

# --- arguments ----------------------------------------------------------------

# No argument runs the check and --finalize alone finalizes. Anything else,
# the options the graded check took included, is a usage error that runs
# nothing.
MODE=check
case $# in
  0) ;;
  1)
    [ "$1" = --finalize ] || usage
    MODE=finalize
    ;;
  *) usage ;;
esac

# --- environment ----------------------------------------------------------------

LAST_TAG="${RELEASE_LAST_TAG:-}"
VERSION="${RELEASE_VERSION:-}"
CONFIRMED="${RELEASE_CONFIRMED_DROPS:-}"

if [ -n "$LAST_TAG" ] && ! grep -Eq "$TAG_RE" <<<"$LAST_TAG"; then
  die_usage "RELEASE_LAST_TAG must be empty or v<major>.<minor>.<patch>"
fi
grep -Eq "$SEMVER_RE" <<<"$VERSION" ||
  die_usage "RELEASE_VERSION must be <major>.<minor>.<patch>"
if [ -n "$CONFIRMED" ]; then
  OLD_IFS=$IFS
  IFS=,
  for name in $CONFIRMED; do
    [ -z "$name" ] || valid_skill "$name" ||
      die_usage "RELEASE_CONFIRMED_DROPS has an invalid skill name"
  done
  IFS=$OLD_IFS
fi

cd "$REPO_ROOT"
GIT_DIR_PATH=$(git rev-parse --absolute-git-dir) || fail "not in a git repository"
HEAD_SHA=$(git rev-parse HEAD) || fail "cannot resolve HEAD"
STATE="$GIT_DIR_PATH/shirabe-release"
MARKER="$STATE/marker"
RECORD="$STATE/$ASSET_NAME"
SUMMARY="$STATE/summary.json"

# The marker's lines: "head <sha>", "last_tag <tag or empty>", then
# "skill <name>" per skill this run selected.
marker_matches() {
  [ -f "$MARKER" ] || return 1
  [ "$(sed -n 's/^head //p' "$MARKER")" = "$HEAD_SHA" ] || return 1
  grep -qx "last_tag $LAST_TAG" "$MARKER" || return 1
  [ "$(grep -c '^last_tag' "$MARKER")" -eq 1 ] || return 1
}

# Sets SKILLS (space-separated) from the marker.
SKILLS=""
read_marker_skills() {
  local tag name
  SKILLS=""
  while read -r tag name; do
    [ "$tag" = skill ] || continue
    valid_skill "$name" || fail "the state marker is malformed"
    SKILLS="$SKILLS $name"
  done <"$MARKER"
}

# --- finalize -------------------------------------------------------------------

if [ "$MODE" = finalize ]; then
  marker_matches ||
    fail "no eval check ran for HEAD $HEAD_SHA and last tag '${LAST_TAG}'; run the check first"
  [ -f "$RECORD" ] || fail "no record at $RECORD; run the check first"
  read_marker_skills
  set -- --record "$RECORD" --version "$VERSION"
  for name in $SKILLS; do
    set -- "$@" --measured "$name"
  done
  python3 "$RECORD_TOOL" stamp "$@" || fail "could not stamp the record"
  echo "asset: $RECORD"
  exit 0
fi

# --- check ----------------------------------------------------------------------

# The repository the previous record is downloaded from, settled before any
# case runs so an origin it can't read fails fast rather than after the cases.
REPO=""
if [ -n "$LAST_TAG" ]; then
  ORIGIN=$(git remote get-url origin || true)
  REPO=$(printf '%s\n' "$ORIGIN" |
    sed -n -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' |
    sed 's/\.git$//')
  grep -Eq "$REPO_RE" <<<"$REPO" ||
    fail "cannot tell the GitHub repository from the origin remote"
fi

if [ -n "$CONFIRMED" ] && marker_matches; then
  echo "Confirmation re-run: comparing the saved summary, running no case."
  read_marker_skills
else
  # The hand-off cases attach koto sessions, so a run without koto would fail
  # them for a reason that says nothing about the skills.
  command -v koto >/dev/null 2>&1 ||
    fail "koto is not on PATH; the hand-off cases need it. Put koto on PATH and $RETRY"

  rm -rf "$STATE"
  mkdir -p "$STATE"

  HOST=$(hostname || uname -n)
  echo "Eval check host: $HOST"

  # The runner's own rule for --all: every directory under skills/ holding
  # evals/evals.json, in Python's sorted order, so the marker names exactly
  # the skills the runner measures.
  SELECTION=$(python3 -c '
import os, sys
root = sys.argv[1]
for name in sorted(os.listdir(root)):
    if os.path.isfile(os.path.join(root, name, "evals", "evals.json")):
        print(name)
' "$REPO_ROOT/skills") || fail "could not list the skills under $REPO_ROOT/skills"
  # Checked line by line before any word splitting, so a directory name with
  # a space or a glob character is refused rather than split into others.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    valid_skill "$name" ||
      fail "the skill directory skills/$name does not match $SKILL_RE; no case was run"
  done <<<"$SELECTION"

  rc=0
  python3 "$RUNNER" --all --summary-out "$SUMMARY" || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
    fail "scripts/lib/script-cases.py exited $rc; no record was written; $RETRY"
  fi

  # Written only once the runner has saved a summary, so a marker always has
  # one beside it and a confirmation re-run always has a summary to compare.
  {
    echo "head $HEAD_SHA"
    echo "last_tag $LAST_TAG"
    for name in $SELECTION; do
      echo "skill $name"
    done
  } >"$MARKER.tmp"
  mv "$MARKER.tmp" "$MARKER"
  read_marker_skills
fi

TOTALS=$(python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    skills = json.load(fh)["skills"].values()
print("%d of %d" % (sum(e["cases_passed"] for e in skills), sum(e["cases_run"] for e in skills)))
' "$SUMMARY" 2>/dev/null) || fail "could not read the saved summary $SUMMARY; $RETRY"
echo "script cases: $TOTALS passed"
echo "model-graded cases: not run"

# --- baseline -------------------------------------------------------------------

# The baseline is composed per skill from the records of the last tag and the
# releases before it (eval-pass-rates.py merge takes them newest first), so a
# release that measured only some skills, or measured a skill with graded
# cases, leaves the skill labelled against the newest older release that
# measured it with script cases. The walk takes the last tag, then the older
# v* tags merged into HEAD, newest first, BASELINE_DEPTH releases in all; the
# cap keeps a long history from costing a download per release. Tags have to
# be fetched for the walk to see them: in a clone without them it shrinks to
# the last tag.
BASELINE_DEPTH=10

# Reads vX.Y.Z tags, one per line, and prints "<key> <tag>". The key is
# fixed-width and zero-padded, so string order is version order. Compare keys
# as strings: as numbers an 18-digit key loses precision in awk.
version_keys() {
  awk -F'[v.]' '{ printf "%06d%06d%06d %s\n", $2, $3, $4, $0 }'
}

FOUND=""
REASON=""
DOWNLOAD_DIR=""
cleanup() {
  [ -z "$DOWNLOAD_DIR" ] || rm -rf "$DOWNLOAD_DIR"
}
trap cleanup EXIT

if [ -z "$LAST_TAG" ]; then
  REASON="no last tag, so no previous release"
else
  LAST_KEY=$(printf '%s\n' "$LAST_TAG" | version_keys | cut -d' ' -f1)
  OLDER=$(git tag --merged HEAD --list 'v*' |
    { grep -E "$TAG_RE" || true; } |
    version_keys |
    sort -r |
    awk -v k="$LAST_KEY" -v n=$((BASELINE_DEPTH - 1)) \
      'c < n && ($1 "") < (k "") { print $2; c++ }')
  DOWNLOAD_DIR=$(mktemp -d) || fail "could not create a temporary directory"
  DOWNLOAD_ERR="$DOWNLOAD_DIR/gh-stderr"
  TRIED=0
  # Each release downloads into a directory named for its tag, and FOUND lists
  # the tags that had a record, newest first: the merge below passes records
  # in FOUND's order, which is the order the baseline is composed in.
  for tag in $LAST_TAG $OLDER; do
    TRIED=$((TRIED + 1))
    dir="$DOWNLOAD_DIR/$tag"
    mkdir "$dir" || fail "could not create a temporary directory"
    # Only "there is nothing to download" skips a release: it doesn't exist,
    # or it has no such asset. gh says those two in fixed words. Any other
    # failure (network, auth, a wrong repository) is not evidence that no
    # baseline exists, and labelling against nothing would hide a regression,
    # so it stops the check.
    if gh release download "$tag" --repo "$REPO" --pattern "$ASSET_NAME" \
      --dir "$dir" >/dev/null 2>"$DOWNLOAD_ERR"; then
      FOUND="$FOUND $tag"
    elif ! grep -qxE 'no assets match the file pattern|release not found' "$DOWNLOAD_ERR"; then
      GH_REASON=$(head -n 3 "$DOWNLOAD_ERR" | tr -d '\r' | tr '\n' ' ' | sed 's/ *$//')
      fail "could not download $ASSET_NAME from the $tag release: $GH_REASON; $RETRY"
    fi
  done
  if [ -z "$FOUND" ]; then
    if [ "$TRIED" -eq 1 ]; then
      REASON="no $ASSET_NAME on the $LAST_TAG release"
    else
      REASON="no $ASSET_NAME on the $LAST_TAG release or the $((TRIED - 1)) before it"
    fi
  else
    # Numbered, because the merge's warnings name a skipped record by its
    # position among the records passed to it.
    i=0
    LISTED=""
    for tag in $FOUND; do
      i=$((i + 1))
      LISTED="$LISTED $i=$tag"
    done
    echo "Baseline records, newest first:$LISTED"
  fi
fi

# --- merge ----------------------------------------------------------------------

set -- merge --no-baseline-reason "$REASON" \
  --version "$VERSION" --last-tag "$LAST_TAG" --confirmed "$CONFIRMED" \
  --out "$RECORD" --summary "$SUMMARY"
if [ -z "$FOUND" ]; then
  set -- "$@" --previous -
fi
for tag in $FOUND; do
  set -- "$@" --previous "$DOWNLOAD_DIR/$tag/$ASSET_NAME"
done
for name in $SKILLS; do
  set -- "$@" --selected "$name"
done

rc=0
python3 "$RECORD_TOOL" "$@" || rc=$?
exit "$rc"

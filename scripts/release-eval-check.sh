#!/usr/bin/env bash
#
# release-eval-check.sh - shirabe's eval check for /shirabe:release
#
# Runs the evals of the skills changed since the last release, compares their
# pass rates with the previous release's eval-pass-rates.json asset, and leaves
# a record for the release to attach. Declared in
# .claude/shirabe-extensions/release.md; see
# docs/designs/current/DESIGN-evals-at-release.md (Decision 3).
#
# Usage:
#   scripts/release-eval-check.sh --critical <a,b> --critical-runs <N>
#   scripts/release-eval-check.sh --finalize
#
# The check (first form):
#   1. Validates RELEASE_LAST_TAG (empty, or vX.Y.Z) and RELEASE_VERSION (X.Y.Z).
#   2. With RELEASE_CONFIRMED_DROPS non-empty and a state marker naming this
#      HEAD and last tag, skips to step 6: a confirmation re-compares the saved
#      numbers and never calls the harness.
#   3. Otherwise empties the state directory, prints the host it runs on and
#      what the nested eval sessions can reach, and asks the harness for the
#      skills changed since the last tag (scripts/run-evals.sh --list-changed).
#   4. Writes a marker naming HEAD, the last tag and the skills it measures.
#   5. Runs scripts/run-evals.sh --runs <N> --summary-out <state>/<i>.json
#      <skill> per selected skill: N is --critical-runs for a skill in
#      --critical and 1 otherwise. A failing skill doesn't stop the others.
#   6. With a non-empty last tag, downloads that release's eval-pass-rates.json
#      with gh into a mktemp -d directory; a failed download means no baseline.
#   7. Runs scripts/lib/eval-pass-rates.py merge, which writes
#      <state>/eval-pass-rates.json, prints the comparison, and decides the
#      exit code.
#
# --finalize (the release-assets half, after the draft release exists):
#   Refuses unless the marker names the current HEAD and RELEASE_LAST_TAG and a
#   record exists. Then stamps the record with RELEASE_VERSION (its version, and
#   measured_at of the skills this run measured) and prints
#   "asset: <record path>" as its last line. It uploads nothing.
#
# State directory: $(git rev-parse --git-dir)/shirabe-release/, per worktree
# and never committed.
#
# Environment:
#   RELEASE_VERSION          the version being released (X.Y.Z), required
#   RELEASE_LAST_TAG         the previous release's tag (vX.Y.Z), or empty
#   RELEASE_CONFIRMED_DROPS  comma-separated skills whose drop a person
#                            confirmed; set only on the re-run after a yes
#
# Exit codes:
#   check:    0 clean; 1 an infrastructure failure (a harness exit 2, 3 or 4,
#             a missing summary, or the selection failing); 5 drops not in
#             RELEASE_CONFIRMED_DROPS, the output ending with a
#             "confirm: RELEASE_CONFIRMED_DROPS=<a,b>" line; 2 usage
#   finalize: 0 with an "asset:" line; 1 the marker or record doesn't match
#             this release; 2 usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$SCRIPT_DIR/run-evals.sh"
RECORD_TOOL="$SCRIPT_DIR/lib/eval-pass-rates.py"
ASSET_NAME="eval-pass-rates.json"

SKILL_RE='^[a-z0-9][a-z0-9-]*$'
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

usage() {
  echo "Usage: $0 --critical <a,b> --critical-runs <N>" >&2
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
  printf '%s\n' "$1" | grep -Eq "$SKILL_RE"
}

# --- arguments ----------------------------------------------------------------

MODE=""
CRITICAL=""
CRITICAL_RUNS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --finalize)
      MODE=finalize
      shift
      ;;
    --critical)
      [ $# -ge 2 ] || usage
      CRITICAL="$2"
      MODE=${MODE:-check}
      shift 2
      ;;
    --critical-runs)
      [ $# -ge 2 ] || usage
      CRITICAL_RUNS="$2"
      MODE=${MODE:-check}
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done
[ -n "$MODE" ] || usage
if [ "$MODE" = finalize ] && { [ -n "$CRITICAL" ] || [ -n "$CRITICAL_RUNS" ]; }; then
  usage
fi
if [ "$MODE" = check ]; then
  [ -n "$CRITICAL_RUNS" ] || die_usage "--critical-runs is required"
  printf '%s\n' "$CRITICAL_RUNS" | grep -Eq '^[1-9][0-9]?$' ||
    die_usage "--critical-runs must be a number from 1 to 99"
  OLD_IFS=$IFS
  IFS=,
  for name in $CRITICAL; do
    [ -z "$name" ] || valid_skill "$name" || die_usage "--critical has an invalid skill name"
  done
  IFS=$OLD_IFS
fi

# --- environment ----------------------------------------------------------------

LAST_TAG="${RELEASE_LAST_TAG:-}"
VERSION="${RELEASE_VERSION:-}"
CONFIRMED="${RELEASE_CONFIRMED_DROPS:-}"

if [ -n "$LAST_TAG" ] && ! printf '%s\n' "$LAST_TAG" | grep -Eq "$TAG_RE"; then
  die_usage "RELEASE_LAST_TAG must be empty or v<major>.<minor>.<patch>"
fi
printf '%s\n' "$VERSION" | grep -Eq "$SEMVER_RE" ||
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

# The marker's lines: "head <sha>", "last_tag <tag or empty>", then
# "skill <i> <name>" per skill this run measures, <i> naming <state>/<i>.json.
marker_matches() {
  [ -f "$MARKER" ] || return 1
  [ "$(sed -n 's/^head //p' "$MARKER")" = "$HEAD_SHA" ] || return 1
  grep -qx "last_tag $LAST_TAG" "$MARKER" || return 1
  [ "$(grep -c '^last_tag' "$MARKER")" -eq 1 ] || return 1
}

# Sets SKILLS and INDEXES (space-separated, parallel) from the marker.
SKILLS=""
INDEXES=""
read_marker_skills() {
  local tag index name
  SKILLS=""
  INDEXES=""
  while read -r tag index name; do
    [ "$tag" = skill ] || continue
    printf '%s\n' "$index" | grep -Eq '^[0-9]+$' || fail "the state marker is malformed"
    valid_skill "$name" || fail "the state marker is malformed"
    SKILLS="$SKILLS $name"
    INDEXES="$INDEXES $index"
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

is_critical() {
  case ",$CRITICAL," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# The repository the previous record is downloaded from, settled before any
# eval runs so an origin it can't read fails fast rather than after the evals.
REPO=""
if [ -n "$LAST_TAG" ]; then
  ORIGIN=$(git remote get-url origin || true)
  REPO=$(printf '%s\n' "$ORIGIN" |
    sed -n -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' |
    sed 's/\.git$//')
  printf '%s\n' "$REPO" | grep -Eq "$REPO_RE" ||
    fail "cannot tell the GitHub repository from the origin remote"
fi

if [ -n "$CONFIRMED" ] && marker_matches; then
  echo "Confirmation re-run: comparing the saved summaries, running no eval."
  read_marker_skills
else
  rm -rf "$STATE"
  mkdir -p "$STATE"

  HOST=$(hostname || uname -n)
  echo "Eval check host: $HOST"
  echo "The nested eval sessions run shell on this host with access to its stored credentials (gh logins, git credential helpers, SSH keys on disk); only GH_TOKEN, GITHUB_TOKEN and SSH_AUTH_SOCK are unset."

  SELECTION_FILE="$STATE/selection"
  if ! "$HARNESS" --list-changed >"$SELECTION_FILE"; then
    fail "scripts/run-evals.sh --list-changed failed; no skill was measured"
  fi

  {
    echo "head $HEAD_SHA"
    echo "last_tag $LAST_TAG"
  } >"$MARKER.tmp"
  i=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    valid_skill "$name" || fail "the harness selected an invalid skill name"
    i=$((i + 1))
    echo "skill $i $name" >>"$MARKER.tmp"
  done <"$SELECTION_FILE"
  mv "$MARKER.tmp" "$MARKER"
  read_marker_skills

  if [ -z "$SKILLS" ]; then
    echo "No skill with evals changed since ${LAST_TAG:-the start of history}; no eval runs."
  fi
  set -- $INDEXES
  for name in $SKILLS; do
    index=$1
    shift
    runs=1
    if is_critical "$name"; then
      runs=$CRITICAL_RUNS
    fi
    echo ""
    echo "== $name ($runs run(s)) =="
    rc=0
    "$HARNESS" --runs "$runs" --summary-out "$STATE/$index.json" "$name" || rc=$?
    echo "== $name: harness exit $rc =="
  done
fi

# --- baseline -------------------------------------------------------------------

PREVIOUS="-"
REASON=""
DOWNLOAD_DIR=""
cleanup() {
  [ -z "$DOWNLOAD_DIR" ] || rm -rf "$DOWNLOAD_DIR"
}
trap cleanup EXIT

if [ -z "$LAST_TAG" ]; then
  REASON="no last tag, so no previous release"
else
  DOWNLOAD_DIR=$(mktemp -d) || fail "could not create a temporary directory"
  if gh release download "$LAST_TAG" --repo "$REPO" --pattern "$ASSET_NAME" \
    --dir "$DOWNLOAD_DIR" >/dev/null; then
    PREVIOUS="$DOWNLOAD_DIR/$ASSET_NAME"
  else
    REASON="no $ASSET_NAME could be downloaded from $LAST_TAG"
  fi
fi

# --- merge ----------------------------------------------------------------------

set -- merge --previous "$PREVIOUS" --no-baseline-reason "$REASON" \
  --version "$VERSION" --last-tag "$LAST_TAG" --confirmed "$CONFIRMED" --out "$RECORD"
for name in $SKILLS; do
  set -- "$@" --selected "$name"
done
for index in $INDEXES; do
  if [ -f "$STATE/$index.json" ]; then
    set -- "$@" --summary "$STATE/$index.json"
  fi
done

rc=0
python3 "$RECORD_TOOL" "$@" || rc=$?
exit "$rc"

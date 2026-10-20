#!/usr/bin/env bash
#
# Capture the roadmap byte-identity baseline.
#
# roadmap/v3 was added to the roadmap readers with a promise: every
# roadmap/v1 and roadmap/v2 document reads exactly as it did before. This
# script records what a shirabe built before that change prints for each
# roadmap under roadmap-identity/corpus/, and roadmap_identity.rs asserts the
# current binary prints the same bytes:
#
#   expected/<path>.validate.{stdout,stderr,exit}
#       `shirabe validate --format json <path>`, run in the corpus directory
#   expected/<path>.populate.{doc,stdout,stderr,exit}
#       `shirabe roadmap populate --no-issues <path>` on a scratch copy, and
#       the document it left behind
#
# The corpus is a frozen copy of every roadmap in shirabe's test, golden and
# eval fixtures (SOURCES.tsv says where each came from), plus fixtures that
# exist only here. Copies rather than the originals, so a later change to a
# fixture can't move the baseline under the test.
#
# CI never builds the old commit: building a second shirabe on every run
# costs minutes for a check whose answer only changes when this script runs.
# The outputs are checked in instead, and this script regenerates them.
#
# Usage:
#   crates/shirabe/tests/fixtures/capture_roadmap_identity.sh [<base-binary>]
#
# With no argument it checks BASELINE_REF out into a scratch worktree and
# builds it there. Run it from anywhere; paths resolve relative to this
# script. Add a corpus file and its SOURCES.tsv line before running, and
# `git add` the corpus first: `validate` reports on whether a file is
# tracked, so an untracked corpus captures findings CI won't see.

set -euo pipefail

# The commit before roadmap/v3 existed. Override with
# SHIRABE_IDENTITY_BASELINE_REF=<ref> to capture against another ref.
BASELINE_REF="${SHIRABE_IDENTITY_BASELINE_REF:-05d3a505e997b6ed146a8889395f9dbeff2bd9a3}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
identity_dir="${script_dir}/roadmap-identity"
corpus_dir="${identity_dir}/corpus"
expected_dir="${identity_dir}/expected"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"

if [[ ! -d "${corpus_dir}" ]]; then
  echo "error: corpus dir not found: ${corpus_dir}" >&2
  exit 1
fi

scratch="$(mktemp -d -t shirabe-identity.XXXXXX)"
build_dir=""
cleanup() {
  if [[ -n "${build_dir}" ]]; then
    git -C "${repo_root}" worktree remove --force "${build_dir}" >/dev/null 2>&1 || true
  fi
  rm -rf "${scratch}"
}
trap cleanup EXIT

if [[ $# -ge 1 ]]; then
  base_bin="$1"
else
  build_dir="${scratch}/src"
  git -C "${repo_root}" worktree add --detach "${build_dir}" "${BASELINE_REF}" >&2
  ( cd "${build_dir}" && cargo build --release --bin shirabe >&2 )
  base_bin="${build_dir}/target/release/shirabe"
fi
echo "baseline binary: ${base_bin} (${BASELINE_REF})" >&2

# FC09 reads these; unset, it emits its fixed no-PR-context notice.
unset SHIRABE_PR_NUMBER GITHUB_REF GITHUB_REPOSITORY GITHUB_TOKEN

rm -rf "${expected_dir}"
count=0
while IFS= read -r -d '' corpus_file; do
  rel="${corpus_file#"${corpus_dir}/"}"
  out="${expected_dir}/${rel}"
  mkdir -p "$(dirname "${out}")"

  set +e
  ( cd "${corpus_dir}" && "${base_bin}" validate --format json "${rel}" ) \
    >"${out}.validate.stdout" 2>"${out}.validate.stderr"
  printf '%s\n' "$?" >"${out}.validate.exit"
  set -e

  work="${scratch}/populate"
  rm -rf "${work}"
  mkdir -p "${work}/$(dirname "${rel}")"
  cp "${corpus_file}" "${work}/${rel}"
  set +e
  ( cd "${work}" && "${base_bin}" roadmap populate --no-issues "${rel}" ) \
    >"${out}.populate.stdout" 2>"${out}.populate.stderr"
  printf '%s\n' "$?" >"${out}.populate.exit"
  set -e
  cp "${work}/${rel}" "${out}.populate.doc"

  count=$((count + 1))
done < <(find "${corpus_dir}" -type f -name 'ROADMAP-*.md' -print0 | sort -z)

echo "captured ${count} roadmaps into ${expected_dir}" >&2

#!/usr/bin/env bash
#
# Capture the Go baseline outputs for the parity corpus.
#
# Builds the reference Go `shirabe` binary at the pinned baseline commit
# and records its stdout, stderr, and exit code for every file under
# golden/corpus/ into golden/expected/<path>.{stdout,stderr,exit}.
#
# The parity test (crates/shirabe/tests/parity.rs) then asserts the Rust
# binary reproduces these bytes exactly. The Go binary is the immutable
# reference (DESIGN Decision 3 + Decision 7): once captured, the fixture
# asserts against these files rather than rebuilding Go on every run.
#
# Baseline commit: the merge-base of the rewrite branch with main -- the
# exact Go tree the O5 cut deletes. The validate/annotation source at this
# SHA equals the worktree's Go tree, so building from the current checkout
# produces an identical binary; the SHA is recorded here for provenance and
# so the capture stays reproducible after the Go tree is deleted.
#
# Usage:
#   crates/shirabe/tests/fixtures/capture_go_baseline.sh
#
# Run from anywhere; paths resolve relative to this script.

set -euo pipefail

# The pinned baseline commit (current origin/main HEAD at rebaseline time).
# Override with SHIRABE_GO_BASELINE_REF=<ref> to capture against another ref.
BASELINE_REF="${SHIRABE_GO_BASELINE_REF:-20fb8ed}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
golden_dir="${script_dir}/golden"
corpus_dir="${golden_dir}/corpus"
expected_dir="${golden_dir}/expected"

# Locate the repo root (two levels up from crates/shirabe/tests/fixtures is
# crates/shirabe/tests; walk up to the dir containing go.mod / cmd/shirabe).
repo_root="$(cd "${script_dir}/../../../.." && pwd)"

if [[ ! -d "${corpus_dir}" ]]; then
  echo "error: corpus dir not found: ${corpus_dir}" >&2
  exit 1
fi

# Build the Go reference binary. Prefer building from the current worktree
# (its validate/annotation/cmd tree equals BASELINE_REF); fall back to a
# detached checkout of BASELINE_REF in a temp clone if the Go tree is gone
# (post-cut reproduction).
go_bin="$(mktemp -t shirabe-go-baseline.XXXXXX)"
build_dir="${repo_root}"

if [[ -d "${repo_root}/cmd/shirabe" ]]; then
  echo "building Go baseline from current worktree (== ${BASELINE_REF})" >&2
else
  echo "Go tree absent; checking out ${BASELINE_REF} into a temp clone" >&2
  build_dir="$(mktemp -d -t shirabe-go-src.XXXXXX)"
  git -C "${repo_root}" worktree add --detach "${build_dir}" "${BASELINE_REF}" >&2
fi

( cd "${build_dir}" && go build -o "${go_bin}" ./cmd/shirabe )

echo "captured baseline from: ${BASELINE_REF}" >&2

# Walk every corpus file and capture the three outputs. We invoke the
# binary with the corpus directory as the working directory and pass the
# corpus-relative path as the argument, so the emitted `file=<path>`
# annotation is the relative path -- host-independent by construction, with
# no post-hoc path rewriting. The parity test invokes the Rust binary the
# same way (cwd = corpus dir, relative path arg).
while IFS= read -r -d '' corpus_file; do
  rel="${corpus_file#"${corpus_dir}/"}"
  out_base="${expected_dir}/${rel}"
  mkdir -p "$(dirname "${out_base}")"

  set +e
  ( cd "${corpus_dir}" && "${go_bin}" validate "${rel}" ) \
    >"${out_base}.stdout" \
    2>"${out_base}.stderr"
  code=$?
  set -e
  printf '%s\n' "${code}" >"${out_base}.exit"
done < <(find "${corpus_dir}" -type f -print0 | sort -z)

echo "wrote expected/ for $(find "${corpus_dir}" -type f | wc -l | tr -d ' ') corpus files" >&2

# Clean up the temp binary and any temp worktree.
rm -f "${go_bin}"
if [[ "${build_dir}" != "${repo_root}" ]]; then
  git -C "${repo_root}" worktree remove --force "${build_dir}" 2>/dev/null || rm -rf "${build_dir}"
fi

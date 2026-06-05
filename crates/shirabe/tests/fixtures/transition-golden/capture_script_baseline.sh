#!/usr/bin/env bash
#
# Capture the script baseline outputs for the transition parity corpus.
#
# For every case in cases.tsv, this runs the matching per-skill
# transition-status.sh (the parity oracle) and records, under
# expected/<case_id>/:
#
#   result.json    The JSON result the oracle emits, normalized through
#                  `jq -S .` (sorted keys) so the parity test can assert
#                  structural equality (same keys + values) without a JSON
#                  dependency in Rust. On success this is the oracle's stdout;
#                  on a 1/2/3 failure it is the oracle's stderr (json_error
#                  writes there).
#   exit           The oracle's exact exit code.
#   final_path     The repo-relative path of the resulting document after the
#                  oracle ran -- the (possibly git-mv'd) `new_path` on a move,
#                  or the original path otherwise. For an error case the doc is
#                  unchanged, so this is the input path.
#   final_content  The full contents of the document at final_path after the
#                  oracle ran (frontmatter + body). The parity test asserts the
#                  subcommand produces byte-identical content.
#
# Each case runs in a FRESH temp git repo: the corpus tree (docs/...) is copied
# in, committed, then the oracle is invoked from the repo root with the
# repo-relative doc path. This represents the three moving types' `git mv`
# result and staged state -- the moved file's new path and contents are what we
# record. The parity test (transition_parity.rs) reproduces the same setup and
# asserts the subcommand matches these baselines.
#
# The oracle scripts (the original six plus comp's, retired when the
# consolidation was extended to the comp artifact type) were the immutable
# reference and have now been DELETED, so this capture is no longer runnable on
# the current tree. It is
# retained only as frozen provenance: it documents exactly how the committed
# baselines under expected/<case_id>/ were generated (from the corpus + the
# scripts at the pre-cut commits). The parity test (transition_parity.rs)
# asserts against those committed baseline files, never a live oracle run, so
# deleting the scripts does not affect the test. To regenerate, check out a
# commit before the Issue 5 cut.
#
# Usage:
#   crates/shirabe/tests/fixtures/transition-golden/capture_script_baseline.sh
#
# Run from anywhere; paths resolve relative to this script.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
corpus_dir="${script_dir}/corpus"
expected_dir="${script_dir}/expected"
manifest="${script_dir}/cases.tsv"

# The repo root holds skills/<skill>/scripts/transition-status.sh. Walk up from
# crates/shirabe/tests/fixtures/transition-golden to the repo root.
repo_root="$(cd "${script_dir}/../../../../.." && pwd)"

if [[ ! -f "${manifest}" ]]; then
  echo "error: manifest not found: ${manifest}" >&2
  exit 1
fi

# A fresh, isolated git identity for the temp repos so commits succeed in CI
# without a configured user.
export GIT_AUTHOR_NAME="parity"
export GIT_AUTHOR_EMAIL="parity@example.invalid"
export GIT_COMMITTER_NAME="parity"
export GIT_COMMITTER_EMAIL="parity@example.invalid"

count=0
while IFS=$'\t' read -r case_id script doc_relpath target flag arg3; do
  # Skip comments and blank lines.
  [[ -z "${case_id}" || "${case_id}" == \#* ]] && continue

  oracle="${repo_root}/skills/${script}/scripts/transition-status.sh"
  if [[ ! -x "${oracle}" ]]; then
    echo "error: oracle script not found/executable: ${oracle}" >&2
    exit 1
  fi

  case_corpus="${corpus_dir}/${case_id}"
  if [[ ! -d "${case_corpus}" ]]; then
    echo "error: corpus tree missing for case ${case_id}: ${case_corpus}" >&2
    exit 1
  fi

  # Build a fresh temp git repo with the case's corpus tree committed, so the
  # oracle (and later the subcommand) sees a tracked file in a real work tree.
  work="$(mktemp -d -t shirabe-transition-baseline.XXXXXX)"
  cp -R "${case_corpus}/." "${work}/"
  git -C "${work}" init -q
  git -C "${work}" add -A
  git -C "${work}" commit -q -m "corpus"

  # Assemble the oracle argument vector. The 3rd positional is arg3 when set;
  # the flag column only tells the parity test which named flag to use, the
  # oracle always takes it positionally.
  args=("${doc_relpath}" "${target}")
  if [[ "${arg3}" != "-" ]]; then
    args+=("${arg3}")
  fi

  out_dir="${expected_dir}/${case_id}"
  mkdir -p "${out_dir}"

  set +e
  stdout="$( cd "${work}" && "${oracle}" "${args[@]}" 2>"${out_dir}/.stderr.raw" )"
  code=$?
  set -e

  printf '%s\n' "${code}" >"${out_dir}/exit"

  # The result JSON is on stdout for success (code 0) and on stderr for the
  # 1/2/3 json_error path. Normalize whichever carries it through `jq -S .`.
  if [[ "${code}" -eq 0 ]]; then
    printf '%s' "${stdout}" | jq -S . >"${out_dir}/result.json"
  else
    jq -S . <"${out_dir}/.stderr.raw" >"${out_dir}/result.json"
  fi
  rm -f "${out_dir}/.stderr.raw"

  # Resolve the resulting document path. On a successful move the oracle reports
  # the new repo-relative path in `new_path`; otherwise (no move, or an error)
  # the document stays at its input path.
  final_path="${doc_relpath}"
  if [[ "${code}" -eq 0 ]]; then
    np="$(printf '%s' "${stdout}" | jq -r '.new_path // empty')"
    if [[ -n "${np}" ]]; then
      final_path="${np}"
    fi
  fi
  printf '%s\n' "${final_path}" >"${out_dir}/final_path"

  # Record the resulting document contents (byte-exact).
  cp "${work}/${final_path}" "${out_dir}/final_content"

  rm -rf "${work}"
  count=$((count + 1))
done <"${manifest}"

echo "captured baselines for ${count} cases into ${expected_dir}" >&2

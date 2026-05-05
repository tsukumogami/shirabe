---
status: Proposed
upstream: docs/prds/PRD-gha-doc-validation.md
problem: |
  shirabe's doc format rules exist only as prose. There is no executable
  representation: no CLI that encodes the rules, no reusable workflow that
  downstream repos can call, and no distribution path for local use. The one
  existing validator (validate-plan.sh) is a non-portable bash script hardcoded
  to shirabe's own path layout.
decision: |
  TBD — to be filled in after Phase 3 cross-validation.
rationale: |
  TBD — to be filled in after Phase 3 cross-validation.
---

# DESIGN: GHA Doc Validation

## Status

Proposed

## Context and Problem Statement

shirabe defines five doc formats (Design, PRD, VISION, Roadmap, Plan), each with
required frontmatter fields, a closed set of valid status values, a required set of
section headings, and format-specific structural rules. These rules are specified in
prose. There is no executable artifact that encodes them.

The technical problem has three parts:

**1. No portable validation binary.** The only existing validator is
`skills/plan/scripts/validate-plan.sh` — a bash script that calls other scripts by
relative path. It cannot be invoked from outside shirabe's repo. Any downstream repo
that wants validation must copy the script tree and keep it in sync manually.

**2. No reusable GHA workflow.** A reusable workflow (`on: workflow_call:`) runs in
the caller's repo context. To use Go validation logic, the workflow must obtain the
binary at runtime — either by building it from shirabe's source (a second checkout
step) or downloading a pre-built release artifact. Neither mechanism exists today.

**3. No distribution path for local use.** Plugin skills need the same validation
binary available locally. The Claude Code plugin system has no binary distribution
mechanism. A separate distribution path (tsuku recipe + curl install script) must
be established and the binary must be published via a release pipeline.

The solution requires three integrated components: a `shirabe` Go CLI that encodes
all validation rules, a reusable GHA workflow that builds and invokes it, and a
release pipeline that distributes pre-built binaries for local use.

## Decision Drivers

- **Go, not bash** (R13a): typed frontmatter parsing, `go test`, cross-platform
  binary compilation, no bash portability issues
- **Shared binary for CI and local use** (R13a): identical validation behavior in
  both contexts; no duplicate rule implementations
- **Two-layer scope control** (R2, R8): changed-files-only scan narrows to PR-touched
  files; schema version gate further narrows to opted-in docs
- **Collect-all before exit** (R12): errors must be buffered per file; a fail-fast
  pattern is explicitly rejected
- **Exact annotation format** (R11): `::error file=<path>,line=<N>::[CODE] message` —
  GHA annotation rendering is format-sensitive; any deviation produces plain text
- **60-second total budget including binary build** (R15): the checkout + build step
  must not consume the bulk of the budget; the validator itself must be fast
- **Zero files to copy** (R13): the entire validator lives in shirabe; downstream
  repos add one ~12-line caller file
- **CLI distributable via tsuku + curl** (R13a): pre-built binaries required for
  tsuku recipe and install script; requires cross-platform release pipeline
- **Schema version replaces canonical enum, not extends** (R9): `custom-statuses`
  override is full replacement; partial addition is not supported
- **Plan upstream uses `git ls-files HEAD`** (R6): the upstream file must be
  disk-present and git-tracked on the PR branch at the time validation runs
- **VISION visibility check fails closed** (R7): unknown or unset
  `github.repository_visibility` → apply the public-repo restriction


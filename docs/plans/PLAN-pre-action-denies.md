---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-pre-action-denies.md
milestone: "Pre-action denies from shirabe"
issue_count: 6
---

# PLAN: Pre-action denies from shirabe

## Status

Active

## Scope Summary

The shirabe plugin ships its own Bash PreToolUse hook that denies a `gh
pr create` or `gh pr edit` breaking a PR-body rule and a `git push` that
would send a commit with an AI-attribution trailer, with reasons read
from the rule registry, and that fails closed on every guarded command it
can't check. `shirabe pr-body-hook` becomes the same evaluator, and the
registry links each guarded rule to the hook.

## Decomposition Strategy

**Horizontal.** The pieces have stable interfaces and each is a
prerequisite of the next, in the order the design's Implementation
Approach gives: the validator's finding codes, the shared evaluator with
the legacy entry point, the plugin subcommand and its settings probe, the
push check, the plugin hook and its end-to-end suite, and the registry
links with the checker. Issues 5 and 6 can't land apart (the checker
reads the script's `RULE_IDS` line against the registry's `deny`
fields), and all six land in one pull request. Docs coverage (the plugin
README, the canary guide, `references/rule-registry.md`) rides on Issue
6.

## Issue Outlines

### Issue 1: refactor(validate): give each PR-body finding its PB code and share the attribution predicate

**Goal**: Add `code: &'static str` to `shirabe_validate::PrBodyFinding`,
set to `PB1` to `PB4` where each finding is built (empty for a finding
outside them), and make `is_attribution_line` public, so the hook maps
findings to registry ids through their aliases and checks commit
messages with PB3's own predicate.

**Acceptance Criteria**:
- [ ] Every `PrBodyFinding` built in `crates/shirabe-validate/src/pr_body.rs`
      carries a code; a unit test asserts `PB1` for a bad title, `PB2` for
      a missing separator, an empty Part 1 and two separators, `PB3` for an
      attribution footer and `PB4` for a heading in Part 1.
- [ ] `is_attribution_line` is `pub` and re-exported from the crate root,
      with its existing tests passing.
- [ ] `cargo test --workspace` passes, and `shirabe validate --pr-body`
      output is byte-for-byte unchanged on its existing fixtures.

**Dependencies**: None

### Issue 2: feat(shirabe): build the pre-action evaluator and route pr-body-hook through it

**Goal**: Create `crates/shirabe/src/pre_action/` with the tokenizer
(moved from `pr_body_hook.rs` and extended), the classifier, the body
reader, the registry reader, the reason renderer and `run_legacy`, and
make `shirabe pr-body-hook` a thin call into it with the PR-body rules
and the compiled-in registry (PRD R3, R5 to R7, R10, R11).

**Acceptance Criteria**:
- [ ] The tokenizer splits segments at unquoted `;`, `&`, `|`, newline,
      `(` and `)`, removes backslash-newline, records parenthesis depth,
      command substitutions with their spans and here-documents as data,
      and refuses an unterminated quote; unit tests cover each.
- [ ] The classifier skips `NAME=value`, redirection and reserved words,
      compares heads by basename, recognizes `gh [-R x] pr create|edit`
      and `git [-C p] [-c k=v] push`, fails closed on any other global
      option or a leading `GIT_...=` on a push, on wrapped guarded
      commands (the PRD's wrapper list, `$` heads, substitutions holding
      a guarded segment) and on the earlier-segment cases of PRD R7 case
      11, and tracks the directory through `cd`, `pushd`, `popd` and
      parenthesized groups; every row of the PRD's example table that
      concerns classification has a unit test.
- [ ] The body reader handles `--body`, `--body=`, `-b`, `--body-file`,
      `--body-file=`, `-F` and the here-document forms, refuses every
      form PRD R7 case 4 lists by name, and reads a body file only after
      `lstat`, an `O_NONBLOCK | O_NOFOLLOW` open, `fstat` and a 1 MiB cap.
- [ ] The registry reader resolves an id and an alias to an active entry
      and its anchor range as `scripts/rule-registry.sh range` does, from
      a plugin root or the compiled-in copy, refuses unsafe paths, and
      ignores unknown fields; a test compares its ranges with the shell
      script's for every PR-body and commit entry.
- [ ] Deny reasons follow PRD R5 and R7: one block per broken rule in
      registry order, details joined by `; `, the `full text:` line,
      fail-closed reasons naming the case word and `ask the user`, and
      never `SHIRABE_PRE_ACTION_HOOK`.
- [ ] `shirabe pr-body-hook` makes the same decision as at the base branch
      on the inputs of `pr_body_hook.rs`'s existing unit tests, except the
      five fail-open cases the PRD names, which now deny; it honors
      `PR_BODY_HOOK_DISABLE`, `SHIRABE_PRE_ACTION_HOOK=off` and the canary
      opt-in file (PRD R10 cases, symlink and `on\r` included).
- [ ] `cargo test --workspace` and `cargo fmt --check` pass.

**Dependencies**: Issue 1

### Issue 3: feat(shirabe): add the pre-action-hook subcommand with its settings probe and deadlines

**Goal**: Add `shirabe pre-action-hook --plugin-root <dir> --rules
"<ids>"`, which reads the plugin's registry, runs the evaluator on a
worker thread under the 25-second deadline, turns a panic into a
fail-closed deny, refuses a `--rules` list naming a rule it doesn't
check, and yields the PR-body rules when the host's settings wire `shirabe
pr-body-hook` (PRD R7, R9, R12).

**Acceptance Criteria**:
- [ ] `--rules` naming a rule outside the binary's table exits 3, and
      `--rules` equal to the table runs the evaluator.
- [ ] A test evaluator that panics, and one that sleeps past the deadline
      (shortened through the test seam), each give the fail-closed deny on
      a guarded command and no decision on an unguarded one, exit 0.
- [ ] The settings probe reads the user file and, with
      `CLAUDE_PROJECT_DIR` set, the project's two files; it counts only a
      Bash-matched (or matcher-less) command hook whose segment is
      `shirabe pr-body-hook` alone or with `2>/dev/null`, in a file without
      `disableAllHooks`, and only when `shirabe` resolves on an absolute
      `PATH` entry; each not-wired case in the PRD's R12 criterion has a
      test.
- [ ] When wired, the plugin entry point gives no decision on a bad-body
      create or a `--fill` create and still reports the push cases the
      classifier decides (a wrapped push, a same-command change, an
      unknown option), and after Issue 4 the trailer push; run on the
      same input, the two entry points report a broken rule once between
      them.
- [ ] `SHIRABE_PRE_ACTION_HOOK=off` gives no decision on every input;
      `OFF`, `off ` and `0` leave the hook on.

**Dependencies**: Issue 2

### Issue 4: feat(shirabe): deny a push that would send a commit with an AI-attribution trailer

**Goal**: Add `pre_action/push.rs`: parse the push argv against PRD R4's
option list, resolve the remote and the sources, find the outgoing
non-merge commits with `rev-list` and `cat-file --batch` in the hardened
git environment, and deny `commit/no-ai-trailer` naming each offending
commit (PRD R4, R5, R7 cases 7 and 8, R14, R15).

**Acceptance Criteria**:
- [ ] Each push in the PRD's push criteria (no refspec, a `src:dst`
      refspec, `--all`, `--tags` with an annotated tag, `--mirror`,
      `--repo=fork`, a branch not pushed, a merge-only trailer, the four
      remote-resolution steps, a URL remote, a remote with no tracking
      refs) gives the outcome the PRD states, in a scratch-repository
      test.
- [ ] A detached HEAD with no refspec, an unresolved source, a source
      word starting with `-`, an unknown option, 1,001 commits (1,000
      decides), a remote name outside `^[A-Za-z0-9._-]+$`, a directory
      outside a work tree, and a partial clone under git older than 2.44
      each fail closed with the PRD's case word.
- [ ] Every git child runs with the fixed environment and `-c` settings the
      design lists; a test with a repository whose config sets
      `core.fsmonitor`, `core.hooksPath`, `log.showSignature` with a
      `gpg.program`, and `core.pager` to a marker-writing script leaves no
      marker; a stub `git` on `PATH` records no `fetch`, `ls-remote` or
      `remote` call; a stub that sleeps past the shortened budget gives
      the `git` deny within the bound.
- [ ] Offending commits are listed as a 12-character hash and `subject:`
      with control characters removed and cut to 72 characters, at most
      10, then `and <n> more`; 12 offending commits list 10.

**Dependencies**: Issue 3

### Issue 5: feat(plugin): declare the pre-action hook and test it end to end

**Goal**: Add `hooks/hooks.json`, `hooks/pre-action-deny.sh`,
`hooks/testdata/coarse-cases.tsv` and `hooks/pre-action-deny_test.sh`, and
run the suite in CI after the release build (PRD R1, R7 case 1, R8, R16,
R17).

**Acceptance Criteria**:
- [ ] `hooks/hooks.json` declares one PreToolUse entry, matcher `Bash`,
      `timeout` 30, command `bash "${CLAUDE_PLUGIN_ROOT}/hooks/pre-action-deny.sh"`;
      the script has mode 100755 in git and a test checks both.
- [ ] The script handles the off switch, finds the binary on absolute
      `PATH` entries then `~/.shirabe/bin`, pipes the input to it with
      `--plugin-root` and `--rules` from its `RULE_IDS` line, kills it
      after 26 seconds, passes through only a line with the exact deny
      prefix, and otherwise applies the coarse test (JSON escapes
      decoded, backslash-newline as a space, `LC_ALL=C`) and prints its
      constant deny or nothing; it never interpolates the input.
- [ ] `coarse-cases.tsv` lists command strings with the coarse test's
      answer, and both the shell suite and a Rust test run it.
- [ ] The suite runs every row of the PRD's example table through the
      command read from `hooks/hooks.json`, plus the missing-binary,
      stub-exit-2, short-`--rules`, panicking and sleeping binary cases,
      the line-2 `git push` case, the canary, off-switch and double-wiring
      cases, a run from a plugin copy whose path holds a space, and a run
      with `jq` removed from `PATH`.
- [ ] `scripts/check-bash-floor.sh` passes on the script and the suite.
- [ ] `.github/workflows/build-and-test.yml`, which runs on every pull
      request and so on every path PRD R17 names, runs the suite with
      `target/release` first on `PATH`.

**Dependencies**: Issue 3, Issue 4

### Issue 6: feat(registry): link each guarded rule to the hook and document it

**Goal**: Add the `deny` field to the six rules the hook denies, teach
`scripts/check-rule-registry.sh` to check the field and scan `hooks/` for
`RULE_IDS` lines, tie the evaluator's rule table to the script's line, and
document the hook (PRD R13; docs coverage).

**Acceptance Criteria**:
- [ ] `pr-body/conventional-title`, `pr-body/one-separator`,
      `pr-body/no-ai-trailer`, `pr-body/no-heading-in-part1` and
      `pr-body/conformance` carry `"deny": {"hook":
      "hooks/pre-action-deny.sh", "before": ["pr-create"]}` and
      `commit/no-ai-trailer` carries the same with `["push"]`; no
      `withhold` value differs from the base branch.
- [ ] `check-rule-registry.sh` fails on a malformed `deny`, a `deny.hook`
      naming a missing file, a hook-script `RULE_IDS` id without a `deny`
      naming that script, and a `deny` whose script doesn't list the id;
      its test suite has a fixture for each, and the shipped registry
      passes.
- [ ] A Rust test asserts the evaluator's `RULES` table equals the script's
      `RULE_IDS` line.
- [ ] `.github/workflows/check-rule-registry.yml` lists `hooks/**` and
      `crates/**` among its paths.
- [ ] `references/rule-registry.md` documents the `deny` field;
      `docs/guides/offload-live-canary.md` says the PB4 exception holds in
      the plugin hook too; the README says the plugin ships a pre-action
      hook, what it denies, that it needs the shirabe binary, and how the
      person running a host turns it off with `SHIRABE_PRE_ACTION_HOOK=off`.

**Dependencies**: Issue 5

## Implementation Sequence

The critical path is the whole chain, 1, 2, 3, 4, 5, 6: each issue
builds on the one before it, and Issue 6's checker reads what Issue 5
ships. Issue 4 (the push check) is the largest single piece and the most
self-contained; it can be written beside Issue 3 once Issue 2's
classifier exists, since both only extend the evaluator. The docs in
Issue 6 can be drafted at any point and land with it.

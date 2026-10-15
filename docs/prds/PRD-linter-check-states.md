---
schema: prd/v1
status: Accepted
problem: |
  A /work-on or /execute run publishes a pull request whose title and body
  become the commit message on main and the record reviewers read, and no
  writing-style rule is checked against that text. The pull request gate
  already runs `shirabe validate --pr-body`, but only for structure (PB1 to
  PB4), so a banned word there is caught by a reviewer or not at all, and the
  writing-style guidance can never be moved behind a check that doesn't exist.
goals: |
  The pull request gate in /work-on and /execute holds a run whose title or
  body uses a banned word from the writing-style rules, and tells the agent
  the word, where it is, the registry rule id and where the rule's text is.
  Each hold is countable by rule id in koto's exported check events, adopters'
  CI is unchanged, and the choice between external linters and
  `shirabe validate` is settled on the record.
absorbed:
  - docs/briefs/BRIEF-linter-check-states.md
---

# PRD: linter check states

## Status

Accepted

Absorbed [BRIEF-linter-check-states](docs/briefs/BRIEF-linter-check-states.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists because the pull request title and body a /work-on or
/execute run publishes, which become the commit message on main and the
record reviewers read, pass no writing-style check, while the documents the
same run writes do. The pull request gate already runs the validator and
returns findings by rule id, but only for structure, so a banned word there
reaches main whenever the agent and the reviewer both miss it, and the
guidance can't be considered for removal from default context without a
check behind it. Where that check should live, external linters or
`shirabe validate`, was also open. This document's Problem Statement states
that in full.

The outcome it asked for is an agent held at the pull request gate when the
title or body uses a banned word, told the word, the rule id and where the
rule's text is, so it fixes the pull request itself; and a maintainer who can
count those holds per rule. Those are this document's Goals. Its four
journeys (a /work-on agent's body, /execute's plan pull request held on its
title, a maintainer counting breaks by rule id, an adopting repository's
declared term of art and unchanged CI) are the User Stories, with the
older-binary case added.

Its boundary held the feature to settling where the check lives, the banned
words checked in the title and body at the existing gate with the declared
vocabulary honored, findings carrying the rule id and the rule's reference,
and a registry entry not eligible to withhold: no rule withheld, no em-dash
density, no judgment-only rules, no branch commit messages, no change to the
reusable CI workflow, no escalation ladder or check lifecycle, and no
evasion matching. Those are this document's Requirements and Out of Scope.

## Problem Statement

A /work-on or /execute run publishes two kinds of prose. Documents under
`docs/` are checked against the writing-style rules in
`skills/writing-style/rules.yaml`: `shirabe validate` reports banned words as
FC10, and /scope holds every hop on them. The pull request is the other kind,
and nothing checks its prose. shirabe squash-merges, so the title and Part 1
of the body become the commit message on main, and Part 2 stays on the pull
request as the record reviewers read.

Both workflows already hold the run at a pull request gate
(`work-on:pr_creation`, `execute:pr_finalization`) until
`skills/work-on/scripts/check-pr-output.sh --pr-body` passes. That script runs
`shirabe validate --pr-body` and returns each finding to the agent under a
registry rule id, but the checks are structural only: a Conventional Commits
title, one separator, no AI attribution, no heading in Part 1. The banned
words reach pull request prose only as guidance preloaded into the agent's
context. An earlier requirements document,
`docs/prds/PRD-writing-style-enforcement.md`, put pull request descriptions
out of scope because their text is not a file on disk; the pull request gate
now reads that text, so the reason no longer holds.

Two costs follow. A banned word in a title or body reaches main whenever both
the agent and the reviewer miss it. And with no check holding the run on the
rule, the guidance can't be considered for removal from default context,
which is where shirabe's workflows are taking every rule that has a
deterministic check.

Where such a check should live is also unsettled. The obvious tools are
external linters, Vale for prose and commitlint for commit messages. shirabe's
`CLAUDE.md` says new correctness checks belong in `shirabe validate`, and
shirabe ships into the tsuku ecosystem, whose package manager exists so that
users need no system dependencies beyond it.

## Goals

- An agent running /work-on or /execute is held at the pull request gate when
  the title or body uses a banned word, and the finding tells it the word,
  where it is, what to prefer, the registry rule id and where the rule's text
  is, so it fixes the pull request and moves on without a person reading it.
- A maintainer counts those holds per rule id from koto's exported check
  events, beside the structural pull request rules.
- The rule has a registry entry linked to its check, so a later feature can
  weigh withholding its guidance; this feature withholds nothing.
- Adopting repositories see no change in their own CI, and their declared
  terms of art are honored in their agents' pull requests.
- Where the check lives is decided once, with its alternatives and reasons.

## User Stories

- As a /work-on agent that has just opened a pull request whose Part 1 uses
  `leverage`, I want the `pr_creation` gate to hold with a finding that names
  the word, its line, the plain verb the rules suggest and where the rule's
  text is, so that I fix the body with `gh pr edit` and continue to CI.
- As /execute finalizing a plan's pull request, found through the ownership
  filter rather than the checked-out branch, I want a banned word in the title
  alone to hold `pr_finalization` with a finding that says it is the title,
  so that the commit subject on main is checked the way an issue's is.
- As a maintainer measuring how often agents break the writing-style rules in
  pull requests, I want each hold exported under its own registry rule id, so
  that I can count it per run and per template version without parsing logs.
- As the maintainer of an adopting repository that declares `tier` as a term
  of art, I want my agents' pull requests to use `tier` without a hold, and my
  CI's pull-request-body job to report exactly what it reported before, so
  that adopting the new shirabe changes nothing I didn't ask for.
- As a developer whose installed `shirabe` is older than the plugin's
  scripts, I want the skill's preflight to tell me the validator lacks the
  new check when the skill loads, so that I upgrade before a run reaches the
  pull request gate and holds there.

## Requirements

Terms used below. The **gate** is `skills/work-on/scripts/check-pr-output.sh
--pr-body`, run by `work-on:pr_creation` (on the checked-out branch's pull
request) and by `execute:pr_finalization` (with `--owned`, on the one pull
request the ownership filter `skills/execute/scripts/owned-pr.sh` resolves).
The **body** is the `body` field `gh pr view --json title,body` returns, and a
**body line** is a 1-based line number over that whole text, Part 1, the `---`
separator and Part 2 alike. A **banned term** is an entry under a `terms:` list
in the `words:` block of `skills/writing-style/rules.yaml`; inflected forms
match only when listed (`tier` and `tiered` are separate entries).

### Functional

- **R1. The home of the check is decided and recorded.** The design records
  whether the check is built on external linters (Vale and commitlint) or in
  `shirabe validate`, with each alternative, what it would add, and the
  reasons for the choice, weighing shirabe's rule that correctness checks
  belong in `shirabe validate` and the preference for no extra system
  dependencies.
- **R2. Banned terms in the body.** Every occurrence of a banned term in the
  body's prose produces one finding, two occurrences on one line included.
  Matching is FC10's for documents: case-insensitive and whole-word, and only
  in prose, so inline code, fenced and indented code, link destinations, bare
  URLs, HTML comments and table cells are never matched, in either part.
- **R3. Banned terms in the title.** Every occurrence of a banned term in the
  title produces one finding whose message says it is in the title. The
  title's inline code is not matched, and neither is a Conventional Commits
  prefix (the `type(scope)!:` before the first `: `), which is an identifier,
  not prose. A title finding is never reported as
  `pr-body/conventional-title`, and a title that also breaks PB1 produces both
  findings.
- **R4. What a finding carries.** Each finding is a `::koto-finding::` line
  at `level` `error` with:
  - `rule_id` `pr-body/banned-word`, a new registry rule;
  - `rule_ref` in the registry's computed form
    (`<path>#L<first>-L<last>@<revision>`, `references/rule-registry.md`)
    naming the banned-words range of `skills/writing-style/rules.yaml`;
  - a `message` that starts with the registry entry's `summary` and `: `, then
    names the banned term, its body line (or "the title"), and the `guidance`
    text of the term's category in `rules.yaml`, which says what to prefer.
    A category with empty guidance gives a message without it.
- **R5. A bound on output.** The validator reports at most 50 banned-term
  findings for one pull request, title and body together. When there are
  more, it reports the first 50 and one more finding saying the list was
  truncated, under the same rule id.
- **R6. Declared vocabulary.** A banned term the repository declares under
  `## Prose Vocabulary:` produces no finding. The repository is found from
  the gate's working directory, which koto sets to the session's anchor:
  walking up from it to the first directory holding `.git`, the first
  `CLAUDE.local.md` or `CLAUDE.md` (in that order, per directory) that carries
  the header supplies the terms. Suppression is term-scoped, as for documents.
- **R7. The rules are the plugin's own.** The gate passes the validator the
  `skills/writing-style/rules.yaml` of the plugin it was installed with (the
  same plugin root as the script itself), and nothing else: neither
  `SHIRABE_RULES` nor a `rules.yaml` in the repository under review changes
  what is checked.
- **R8. No silent pass.** The gate exits 2 with no `::koto-finding::` line
  when the rules file is missing, unreadable, malformed, or lists no banned
  term; when `shirabe` is missing or rejects the opt-in; or when the
  validator exits with anything but 0 or 2.
- **R9. The gate's existing contract holds.** PB1 to PB4 findings keep their
  rule ids and messages and appear alongside banned-term findings; the gate
  exits 0 only when both kinds are clean, and 1 when either has a finding.
  The order of findings is not part of the contract.
- **R10. Opt-in validator flag.** `shirabe validate --pr-body <file>` gains a
  flag, `--writing-style <rules-file>`, that is valid only with `--pr-body`.
  With it, the validator loads the named rules file (failing as a tool error,
  exit 1, when it can't) and adds the banned-term findings, as code `PB5`, to
  the same `shirabe-pr-body/v1` output. Without it, output and exit codes are
  byte-identical to before for every input.
- **R11. The hook and adopter CI are unchanged.** `shirabe pr-body-hook`
  makes the same allow and deny decisions as before, and the reusable
  pull-request-body workflow passes no new flag.
- **R12. Registry.** `references/rule-registry.json` gains
  `pr-body/banned-word` with every field the registry requires: `check`
  `{"kind": "script", "path": "skills/work-on/scripts/check-pr-output.sh",
  "mode": "--pr-body"}`, `timing` `work-on:pr_creation` and
  `execute:pr_finalization`, `level` `gate`, `guards` `pr-create` and
  `publish`, `withhold` `never`, and alias `PB5`. No entry's `withhold`
  changes. `scripts/check-rule-registry.sh` passes.
- **R13. Skew is caught at preflight.** The `shirabe validate` records in
  `skills/work-on/requires.tsv` and `skills/execute/requires.tsv` that apply
  whenever the gate runs name `--pr-body`, `--pr-title` and
  `--writing-style`, so `skill-preflight.sh` reports an installed `shirabe`
  whose `validate` lacks the flag when the skill loads.
- **R14. The workflows say what the gate checks.** These name the
  banned-word check or `pr-body/banned-word` beside PB1 to PB4: the
  `pr_creation` gate comment and directive in
  `skills/work-on/koto-templates/work-on.md`, the `pr_finalization` gate
  comment and its rule-id list in `skills/execute/koto-templates/execute.md`,
  `references/pr-body-conformance.md`, and the header of
  `check-pr-output.sh`. The two directives point the agent at
  `skills/writing-style` when it writes the title and body, and no sentence
  claims CI enforces the banned-word check.

### Non-functional

- **R15. Time.** The gate adds one validator process and one rule id to
  resolve, and no `gh` or network call, so it stays inside koto's 30-second
  command-gate limit with the `--owned` lookup's 20-second allowance.
- **R16. No new dependency.** No tool is added to either skill's
  `requires.tsv` beyond `shirabe`, which both already declare.
- **R17. Tests.** The gate's suite covers the mapping, shape, rules pinning
  and failure exits with a stand-in validator, and one case runs a built
  `shirabe` to pin the `PB5` message prefixes the gate maps on. The
  validator's unit tests cover every behaviour in R2 to R6 and R10.

## Acceptance Criteria

Gate cases run `check-pr-output.sh --pr-body` with its suite's stand-in `gh`;
"the real validator" is a `shirabe` built from the same commit.

- [ ] `docs/designs/DESIGN-linter-check-states.md` (or its `current/` path) has a decision naming Vale and commitlint as
      one alternative and `shirabe validate` as another, stating what each
      would add and the reasons for the choice.
- [ ] Body line 3 (in Part 1) contains `leverage`; with the real validator the
      gate exits 1 and prints exactly one `::koto-finding::` line, with
      `rule_id` `pr-body/banned-word`, `level` `error`, a `message` starting
      with the entry's `summary` and `: ` and containing `leverage`, `line 3`
      and the verbs category's guidance text, and a `rule_ref` equal to what
      `scripts/rule-registry.sh ref pr-body/banned-word` prints.
- [ ] A banned term on a Part 2 line produces a finding naming that line's
      number counted over the whole body.
- [ ] `Leverage` and `LEVERAGE` each produce a finding; `leveraged` and
      `releverage` produce none.
- [ ] Two occurrences of `leverage` on one line produce two findings.
- [ ] The same term in inline code, a fenced block, an indented block, a
      table cell, a link destination, a bare URL and an HTML comment
      produces no finding.
- [ ] Title `feat: a seamless migration` with a clean body produces one
      finding naming the title, under `pr-body/banned-word`, and no
      `pr-body/conventional-title` finding; title `feat(tier): add levels`
      produces no finding; title `a seamless migration` produces both a
      `pr-body/conventional-title` and a `pr-body/banned-word` finding.
- [ ] Through `--pr-body --owned` (the /execute path), a title-only banned
      term read from the owned pull request produces the same finding.
- [ ] A clean title and body exit 0 with no finding line.
- [ ] In a scratch repository whose `CLAUDE.md` declares
      `## Prose Vocabulary: tier`, a body using `tier` passes and the same body
      using `tiered` produces one finding; the same holds with the header in
      `CLAUDE.local.md` instead.
- [ ] A body with 60 occurrences produces exactly 50 term findings and one
      truncation finding, all under `pr-body/banned-word`.
- [ ] The gate exits 2 with no finding line when the plugin's `rules.yaml` is
      deleted, when it is replaced with invalid YAML, when its `words:` block
      is emptied, when `shirabe` is not on PATH, and when the stand-in
      `shirabe` exits 1 on `--writing-style`.
- [ ] With `SHIRABE_RULES=/dev/null`, the gate still reports `leverage`.
- [ ] With a `skills/writing-style/rules.yaml` listing no banned term in the
      working directory, the gate still reports `leverage`.
- [ ] The stand-in `shirabe` records `--writing-style` followed by the path
      of the plugin's own `skills/writing-style/rules.yaml`.
- [ ] A body that breaks PB2 and uses `leverage` produces a
      `pr-body/one-separator` finding and a `pr-body/banned-word` finding, and
      the gate exits 1.
- [ ] On the PB1 to PB4 fixtures of the validator's unit tests and on a body
      and title containing banned terms, `shirabe validate --pr-body` without
      `--writing-style` produces the same stdout, stderr and exit code as the
      merge base's build, in all three `--format` values.
- [ ] `--writing-style` without `--pr-body` exits 1; with a missing or
      malformed rules file it exits 1 with no `shirabe-pr-body/v1` envelope.
- [ ] `shirabe pr-body-hook`'s unit tests pass unchanged, and a new hook test
      shows a body and title with banned terms are allowed.
- [ ] `.github/workflows/pr-body.yml` is unchanged.
- [ ] `scripts/check-rule-registry.sh` passes; `pr-body/banned-word` has
      `withhold` `never`, and no other entry's `withhold` changed.
- [ ] `rule-registry.sh verify-findings` passes on the findings log the gate
      suite writes, which includes a `pr-body/banned-word` finding.
- [ ] `skill-preflight.sh` for work-on and for execute, run against a stand-in
      `shirabe` whose `validate --help` lacks `--writing-style`, reports the
      missing flag.
- [ ] Each file R14 names contains `pr-body/banned-word` or the words
      "banned word", and neither template says CI enforces it.
- [ ] Neither `requires.tsv` gains a record for a tool other than those it
      declares today.
- [ ] The gate runs the validator once and `gh pr view` once per evaluation,
      as recorded by the stand-ins.
- [ ] The success edges of `work-on:pr_creation` and
      `execute:pr_finalization` still require the gate that runs
      `check-pr-output.sh --pr-body` to exit 0.
- [ ] `scripts/check-skill.sh --changed <skill>` passes for every skill whose
      files change.

## Out of Scope

- **Withholding any rule from default context.** This feature only adds the
  check a later decision would rely on.
- **Em-dash density on pull request bodies.** It is a per-document rate with
  a 300-word floor, and most bodies are shorter.
- **The judgment-only writing-style rules.** No matcher decides them.
- **Commit messages on the feature branch.** Squash merge discards them, and
  their subjects already pass `commit/conventional-subject`.
- **Turning the check on in shirabe's reusable pull-request-body CI
  workflow** for shirabe or its adopters. That needs a rules path in CI and is
  a separate change.
- **Returning the rule's text in steps as attempts accumulate, and the
  shadow-warn-block lifecycle of a check.** Both are later features.
- **The validator's general fail-open behaviour on a missing rules file** for
  document checks (FC10). This feature makes its own check fail loudly and
  leaves FC10 as it is.
- **Matching evasions** such as homoglyphs or zero-width characters.

## Decisions and Trade-offs

- **A new rule id rather than widening `prose/banned-word`.** The registry's
  own rule is that changing what a rule means takes a new id, each entry names
  one checking script, and the pull request rules already follow this split
  (`commit/no-ai-trailer` beside `pr-body/no-ai-trailer`). Both ids point at
  the same text in `rules.yaml`. Alternative: add the pull request timings to
  `prose/banned-word`; rejected because its `check` names the /scope script
  and a count per output would be lost.
- **Both parts of the body are checked.** Part 1 lands on main and Part 2 is
  the public record on the pull request; the rules apply to both. Tables,
  where the review panel lives, are not prose and aren't matched.
  Alternative: Part 1 only; rejected because Part 2 is still prose shirabe
  publishes.
- **The check fails closed.** A gate that can't load its rules or run the
  validator holds the run (exit 2), as every other gate script does,
  and preflight names the capability so skew shows up early. Alternative: run
  only the structural checks when the binary is too old; rejected because a
  check that silently does nothing is the failure the rules file exists to
  end.
- **Opt-in, not default.** Turning the check on for every
  `shirabe validate --pr-body` caller would change adopters' CI and the
  pull-request-body hook without their asking. The gate opts in; nothing else
  does.

## Known Limitations

- The declared vocabulary comes from the repository the gate runs in. When
  /execute finalizes a pull request in another repository than the one its
  session is anchored in, that repository's declaration is not the one read.
- Banned words are matched as ASCII literals, as for documents; a writer who
  wants to evade the check can.
- The check runs after `gh pr create`, so a banned word is briefly public
  until the agent edits the pull request.

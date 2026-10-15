---
schema: prd/v1
status: Draft
problem: |
  /scope credits a hop's document after the validator's schema gate and three
  structural checks (FC01, FC03, FC04). Every other error-level check
  `shirabe validate` runs for a BRIEF, PRD, DESIGN or PLAN is held only by a
  prose step telling the agent to run the validator and stop on violations,
  and the banned-words rule, checked only at notice level, is held by nothing.
  A hop that skips the step carries a broken document forward, and no failure
  carries a rule id anyone can count.
goals: |
  Every /scope hop, and the fold that can rewrite the run's documents, holds
  until its documents pass every error-level validator check for their type
  plus the banned-words check raised to blocking there. Each failure is a koto
  finding with a registered rule id, the rule's reference and the line, so the
  validator becomes the enforcement for document-format rules at /scope's hops
  and failures can be counted per rule from koto's gate results.
upstream: docs/briefs/BRIEF-scope-document-gates.md
---

# PRD: scope document gates

## Status

Draft

## Problem Statement

A /scope run writes up to four documents for a topic, one per hop: a BRIEF, a
PRD, a DESIGN and a PLAN. Each hop is credited by `hop-complete.sh`, which asks
the validator four things: does the document carry a supported schema
(`SCHEMA`), are its required frontmatter fields present (`FC01`), does its
frontmatter status match its body (`FC03`), and are its required sections
there (`FC04`). That narrowness is deliberate, because the script answers "did
this hop land?". It leaves the rest of the format to a prose step in Phase 2,
the validator pass-through, which tells the agent to run `shirabe validate` on
the new document and stop the chain on a violation. The fold, which can absorb
one document into the next, rewrites the surviving document and re-validates it
the same way, in prose.

Nothing checks that the agent ran either step or read the result right. The
error-level checks left to the prose include a valid status value (`FC02`),
upstream links that resolve (`R6`) and point in a legal direction and lifetime
(`R10`, `R11`), stale prose references (`FC20`), absorb declarations and
orphaned requirement citations (`FC18`, `FC19`), and a PLAN's issue table and
outline dependencies (`FC05`, `FC06`, `FC17`). A document that breaks one of
them is credited as landed and the next hop builds on it; CI finds the breach
on the pull request after the chain is finished.

The banned-words rule from `skills/writing-style/rules.yaml` is worse off. The
validator reports it (`FC10`) only as a notice, so even a faithful agent is told
nothing it must act on, and the only thing holding the rule is the prose that
states it. That prose can't leave the instructions an agent loads, because
nothing would catch a breach once it did. And because none of these failures
carries a registered rule id, nobody can tell which rules agents break often.

/work-on and /execute already gate their outputs on the checks shirabe ships,
with findings that carry a rule id from `references/rule-registry.json` (the
output-gates work, `docs/designs/current/DESIGN-output-gates.md`). /scope is
the workflow that writes the most documents and has the thinnest gate.

In this PRD, codes in backticks such as `R6` or `FC10` are the validator's check
codes; this PRD's own requirements are numbered R1 to R16 without backticks.

## Goals

- An author, or a worker a coordinator dispatched, can't advance a /scope hop
  past a document that fails an error-level validator check for its type or
  uses a banned word, and the hold names the rule and the line.
- Every rule the gate can hold has a registry entry whose timing names the
  /scope states it holds in, so a maintainer can see from the registry which
  document-format rules a gate enforces at /scope's hops.
- Each failure at the gate reaches koto's gate result as a finding carrying the
  registered rule id, so failures can be counted per rule from koto's events.

## User Stories

- As an author running `/scope` on a feature, I want a PRD whose `upstream:`
  names a BRIEF path that doesn't exist to hold the PRD hop with a finding
  naming the upstream rule, the file and the line, so that I fix the path
  before the DESIGN and PLAN are written on top of it. (R1, R3, R5)
- As a worker running `/scope --auto` for a coordinator, I want a DESIGN that
  uses a banned word to hold its hop with a finding naming the banned-words
  rule and the line, so that I rewrite the sentence instead of reading a
  notice I'm free to ignore. (R1, R4, R5)
- As an author whose fold just absorbed the BRIEF into the PRD, I want the
  rewritten PRD checked before the run moves on, so that a malformed
  `absorbed:` declaration can't survive the fold. (R2)
- As an author whose held hop I've since fixed, I want submitting `landed`
  again to re-run the gate and advance, so that a fix needs no other step.
  (R1)
- As an author whose machine lacks `jq`, I want the gate to say it couldn't
  decide rather than report my document as broken, so that I fix the
  environment, not the document. (R7, R10)
- As a maintainer weighing whether the banned-words instruction can leave what
  an agent loads during a hop, I want the registry entry for that rule to name
  the /scope states as gate timings, so that I can see a gate holds it there.
  (R6)
- As a maintainer reviewing live /scope runs, I want each gate finding to
  carry the registered rule id in koto's gate result, so that I can count
  failures per rule without reading transcripts. (R5, R12)

## Requirements

### Functional

- **R1. A document gate at each hop.** `hop_brief`, `hop_prd`, `hop_design`
  and `hop_plan` each carry a command gate that checks the hop's own document:
  `docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`,
  `docs/plans/PLAN-<topic>.md`, or, for the design hop, each of
  `docs/designs/DESIGN-<topic>.md` and `docs/designs/current/DESIGN-<topic>.md`
  that exists. The `landed` transition requires both this gate and the existing
  completion gate to exit 0. The `skipped`, `rejected` and `bail` transitions
  don't name the gate. koto re-runs the gate on every `koto next`, so a fixed
  document passes on the next `landed`.
- **R2. A document gate at the fold.** The `fold` state carries a gate that
  checks every one of the topic's documents present on disk at the paths in
  R1. Every transition out of `fold` requires it to exit 0, so a document the
  absorb rewrote is checked before the run moves on.
- **R3. Every error-level check, at the declared visibility.** For each
  document the gate runs `shirabe validate --format json` once, without
  `--check`, and passes `--visibility=<v>` where `<v>` is the first
  `## Repo Visibility:` header (public or private) in the repository root's
  `CLAUDE.local.md`, else its `CLAUDE.md`; with neither, the flag is omitted.
  Every finding the envelope reports with `"severity": "error"` is a violation.
  Because the gate reads severity rather than a code list, a check the
  validator adds or promotes to error later is held without a change here.
- **R4. The banned-words check raised to blocking.** An `FC10` finding whose
  message starts with `[FC10] writing-style banned word ` or
  `[FC10] writing-style findings truncated at ` is a violation at this gate,
  though the validator reports it as a notice. Every other notice, including
  `FC10`'s em-dash-density finding and the plan-structure notices, is not a
  violation and prints nothing.
- **R5. One finding per violation.** For every violation, in the validator's
  order and without a cap of its own, the gate prints one line
  `::koto-finding::<json>` built by `scripts/lib/rule-findings.sh`'s
  `rf_finding`: `rule_id` is the registry id whose `aliases` hold the
  validator's code (for `FC10`, the banned-words entry), `level` is `error`,
  `rule_ref` is the reference the library resolves, `path` is the validator's
  `file`, `line` is the validator's `line` when it isn't null, and `message`
  is `<entry summary>: <validator message>`. A finding with a null line
  carries no `line` key.
- **R6. A registry entry per reportable rule.** Every rule the gate can print
  has an active entry in `references/rule-registry.json` with all of the
  registry's fields: the validator code in `aliases`, `level` `gate`,
  `timing` naming `scope:hop_brief`, `scope:hop_prd`, `scope:hop_design`,
  `scope:hop_plan` and `scope:fold` (the plan-only rules name `scope:hop_plan`
  and `scope:fold`), `check` naming the gate script and its mode, the gate's
  test suite in `fixtures`, and `withhold` `never`. The entries that already
  exist for the validator's `R7`, `R8` and `R9` (from the output-gates work)
  keep their ids and gain the /scope timings.
- **R7. Three exit statuses.** The gate exits 0 when every checked document
  passes, 1 when at least one violation was found (with at least one finding
  printed), and 2, printing no finding and a one-line reason on stderr, when
  it can't decide: `shirabe`, `jq` or `git` missing; the validator exiting
  anything but 0, 2 or 4; no parseable `shirabe-validate/v1` envelope; an
  envelope outcome of `incomplete` (the validator skipped a schema-less
  document and checked nothing); an error-level code with no registry entry
  whose `aliases` hold it; or a registry entry that doesn't resolve. No
  transition names exit 1 or 2, so koto holds the state and reports the gate
  in its blocking conditions.
- **R8. Absent documents pass.** A path in R1 that doesn't exist is not
  checked. When none of a gate's paths exist the gate exits 0 and says so on
  stderr; whether a hop landed stays the completion gate's question.
- **R9. Not overridable.** Every new gate is declared `overridable: false`.
- **R10. Directives say what a hold means.** The `hop_brief`, `hop_prd`,
  `hop_design`, `hop_plan` and `fold` directives each gain text naming the
  gate, telling the agent that a hold lists one finding per violation to fix
  in the document before submitting again, and that an exit 2 means the
  environment couldn't decide, to be diagnosed by running the gate script by
  hand, and that `bail` is the way out when it can't be fixed. No directive or
  details text is removed or reworded, including the Phase 2 validator
  pass-through and the fold's re-validation step.
- **R11. Untracked upstreams are findings.** The gate makes no exception for
  validator check `R6`: an upstream that isn't tracked by git is a violation
  like any other. Each hop's commit lands after its gate passes and before the
  next hop starts, so an untracked upstream at a later hop means that commit
  didn't happen.
- **R12. Findings reach koto.** In a real koto session on the shipped
  template, a hop held by the gate shows the gate in the response's blocking
  conditions with the printed findings, each carrying its registered
  `rule_id`.

### Non-functional

- **R13. Fast.** Each gate runs the validator once per document. On the
  largest PLAN fixture in the test suite the gate finishes in under 10 seconds,
  a third of koto's 30-second command limit.
- **R14. Run from the repository root.** The gate changes to `git rev-parse
  --show-toplevel` before validating, because validator check `R6` asks git
  whether an upstream is tracked and resolves paths from the working
  directory. Run from a subdirectory, it gives the same result as from the
  root.
- **R15. Tested.** The gate script has a test suite (`_test.sh`) whose cases
  run against the real validator and fail rather than skip when `shirabe`
  isn't on `PATH` in CI. It covers every case in the acceptance criteria that
  doesn't need koto, records every printed finding in `SHIRABE_FINDINGS_LOG`,
  and checks the log with `scripts/rule-registry.sh verify-findings`.
- **R16. Wired into CI.** The suite runs in `.github/workflows/check-scope-scripts.yml`
  in a job that builds `shirabe` from source, and is listed in the `scope`
  suite of `scripts/check-bash-floor.sh`. `scripts/check-skill.sh scope` and
  `scripts/check-rule-registry.sh` pass.

## Acceptance Criteria

Unless a criterion says otherwise, "the gate" is the new gate script run
directly by the test suite, and a finding is a `::koto-finding::` line on its
standard output.

Hops and transitions:

- [ ] For each hop (brief, prd, design, plan), a fixture document that
      `shirabe validate` reports with no error and no banned word makes the
      gate exit 0 with no finding printed.
- [ ] For each hop, a fixture document with one error-level violation makes
      the gate exit 1 with exactly one finding.
- [ ] A design-hop fixture placed at `docs/designs/current/DESIGN-<topic>.md`
      instead of `docs/designs/` is checked the same way.
- [ ] In `skills/scope/koto-templates/scope.md`, compiled with `koto template
      compile`, each hop state's `landed` transition requires the new gate's
      exit code 0 alongside the completion gate's, and its `skipped`,
      `rejected` and `bail` transitions name no new gate.
- [ ] In the compiled template, every transition out of `fold` requires the
      fold's new gate to exit 0.
- [ ] In the compiled template, every new gate has `overridable: false`.
- [ ] In a real koto session on the shipped template, a PRD hop whose PRD
      names a nonexistent `upstream:` stays in `hop_prd` after `landed`, and
      the response's blocking conditions list the new gate with a finding whose
      `rule_id` is the entry aliased `R6`. After the upstream is fixed, the
      next `landed` advances.

Rules and findings:

- [ ] A PRD whose `upstream:` names a nonexistent file yields a finding with
      `rule_id` equal to the entry aliased `R6`, `path` the PRD, and `line` the
      `upstream:` line.
- [ ] A DESIGN containing the banned word `leverage` in a sentence yields a
      finding with `rule_id` equal to the entry aliased `FC10`, at that line.
- [ ] A DESIGN with more than 50 banned words yields 51 findings, the last
      the truncation finding, all under the `FC10` entry.
- [ ] A DESIGN whose only finding is `FC10` em-dash density exits 0.
- [ ] A PLAN whose only findings are plan-structure notices exits 0.
- [ ] A document with two banned words and one error-level violation exits 1
      with three findings.
- [ ] A finding's `message` equals the entry's `summary`, `: `, and the
      validator's message, and its `level` is `error`.
- [ ] A fold run over a PRD with a malformed `absorbed:` entry yields a
      finding under the entry aliased `FC18`.
- [ ] A test fails when the built validator's banned-word message no longer
      starts with `[FC10] writing-style banned word `.
- [ ] Every finding printed by the suite passes `rule-registry.sh
      verify-findings`.

Cannot-decide and absence:

- [ ] With no document at any of a gate's paths, the gate exits 0 and its
      stderr says no document was found.
- [ ] Each of these makes the gate exit 2 with no finding and a reason on
      stderr: `shirabe` missing, `jq` missing, a stub validator exiting 1, a
      stub printing no JSON, a schema-less document (outcome `incomplete`),
      and a stub reporting an error-level code no registry entry aliases.
- [ ] Run from `skills/` inside the fixture repository, the gate gives the
      same exit and findings as from the root.

Registry and repository:

- [ ] For every error-level code the validator's per-file pass can emit for
      `brief/v1`, `prd/v1`, `design/v1` and `plan/v1` (`FC01` to `FC06`,
      `FC17` to `FC20`, `R6` to `R11`), an active registry entry aliases it,
      and the gate script's `RULE_IDS` line lists that entry.
- [ ] The `FC10` banned-words entry's `timing` contains all five /scope
      states in R6, and its `withhold` is `never`.
- [ ] The entries with ids for validator codes `R7`, `R8` and `R9` keep the ids
      they have on the default branch.
- [ ] No registry entry has `withhold: eligible`.
- [ ] `scripts/check-rule-registry.sh` exits 0.
- [ ] `git diff` of `skills/scope/koto-templates/scope.md` against the
      default branch removes no line from any `## <state>` section.
- [ ] Each of the five directives contains the gate's name.
- [ ] The suite appears in `check-scope-scripts.yml` in a job that runs
      `cargo build --release --bin shirabe`, and in the `scope` list of
      `scripts/check-bash-floor.sh`.
- [ ] `scripts/check-skill.sh scope` exits 0.
- [ ] The gate over the suite's largest PLAN fixture finishes in under 10
      seconds and invokes the validator once.

## Out of Scope

- **Withholding.** No prose leaves the hop directives and no rule is marked
  eligible to withhold; that is the withholding features' work, gated on a
  backstop check after the gate.
- **Validator severities.** The validator's own notice and error levels don't
  change. `FC10` stays a notice in CI and in every other caller.
- **The check lifecycle.** Shadow, warn, block and retirement for checks, and
  a dispute path for a check that fails wrongly, are separate work.
- **Documents outside /scope.** A `/prd`, `/design` or `/plan` run on its own
  gets no new gate, nor does any document outside the four topic paths.
- **Writes after the last fold.** `finalize` and the exit states write no
  topic document on a full run, and the status changes a child makes go
  through `shirabe transition`, which keeps a document valid. The drafts an
  abandoned run force-materializes aren't gated.
- **Cross-repository upstreams.** The validator resolves nothing for an
  `owner/repo:path` upstream, so the gate holds nothing for one.
- **Offline measurement.** No ablation or long eval run; the effect is
  measured live from koto's gate results.
- **Other notice-level checks.** Plan-structure notices (`FC07`, `FC08`,
  `FC11`, `FC12`, `FC14`), section order (`FC15`), GitHub reconciliation
  (`FC09`) and the em-dash density rule stay notices; the Decisions section
  says why.

## Decisions and Trade-offs

**Which notice-level checks are raised (the BRIEF's open question).** Only
`FC10`'s banned-word findings and its truncation finding. A notice is raised
when the rule it checks is prohibitive (an author can write a conforming
document without ever reading the rule, so its prose is a real candidate to
withhold), the check is local and deterministic, and each finding names a line
the author fixes in place. The banned words meet all three. The plan-structure
checks (`FC07`, `FC08`, `FC11`, `FC14`) and section order (`FC15`) are
generative: the author needs the format's text to write the document at all,
so that prose isn't going anywhere and a blocking check buys little. `FC12`,
the PLAN/DESIGN field consistency check, is closer to prohibitive, but it
skips silently when the PLAN names no DESIGN, so it stays a notice until a
withholding feature names it. `FC09` reads GitHub, so it isn't local.
Em-dash density is prohibitive and local, but it's a rate over the whole
document reported at its first occurrence, and 55 of the 221 BRIEF, PRD,
DESIGN and PLAN documents in this repository were over its threshold when this
was written; blocking on it would hold many hops on a style rate nobody has
decided must hold. Alternative considered: raise every notice that can fire on
these four types. Rejected because it holds hops on generative rules whose
prose stays loaded anyway.

**A separate gate rather than a wider completion check.** `hop-complete.sh`
answers whether a hop landed, and its own comments explain why it validates
structure only. The new gate sits beside it, and only the `landed` edge needs
both. Alternative: widen the completion check's `--check` list. Rejected
because the fold's routing gates read the same predicate to decide which hop is
next, and a style finding would then change routing.

**The fold checks every topic document present.** The absorb rewrites the
surviving document after its own hop gate passed, and its re-validation is
prose. Checking every topic document at the fold avoids choosing a survivor,
which is ambiguous when a settled document sits downstream of the hop that just
landed. Alternative: check only the most downstream document. Rejected because
in that case it can miss the document the absorb rewrote.

**Error severity read from the envelope, not a code list.** The gate counts
what the validator itself calls an error, so a check added or promoted later is
held without editing the gate, and a code with no registry entry stops the run
(exit 2) rather than passing silently.

**No exception for an untracked upstream.** `hop-complete.sh` avoids validator
check `R6` because completion shouldn't depend on another document. The new
gate isn't a completion check, and by the time a hop's gate runs every earlier
hop has committed its document, so an untracked upstream is a real defect.

## Known Limitations

- A settled topic document that predates this run, held back by re-entry
  protection, is checked at the fold too. If it now breaks an error-level rule
  or uses a banned word, the fold holds until it's fixed, though this run
  didn't write it.
- A PLAN's validation runs `FC09`'s `gh auth status` probe. Without a pull
  request context the reconciliation does nothing, and its findings are
  notices the gate ignores, so the probe can cost time but can't hold a hop.
- Banned-word findings are told apart from em-dash density by the validator's
  message text, since both carry `FC10`. The prefix test in the acceptance
  criteria makes a reworded message fail CI rather than silently change what
  the gate holds.

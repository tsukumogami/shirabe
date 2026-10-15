---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-scope-document-gates.md
problem: |
  /scope's hop gates ask the validator four structural questions and leave every
  other error-level check, and the banned-words rule, to prose the agent may
  skip. The fold rewrites documents after their hop gate with only a prose
  re-validation, and no failure carries a registered rule id.
decision: |
  One gate script, `check-hop-document.sh`, runs `shirabe validate --format
  json` once per document and prints a `::koto-finding::` per error-level
  finding and per banned-word finding, under registry ids keyed by validator
  code. Each hop's `landed` edge and every edge out of `fold` require it, not
  overridable. It loads the plugin's own writing-style rules and reads the
  declared visibility through a library it shares with work-on's gate.
rationale: |
  Reading severity from the validator's envelope holds every error-level check
  the validator has, now and later, without a code list to keep in step. A gate
  beside the completion check leaves the fold's routing gates alone. Keying
  findings by validator code reuses the output-gates conventions, so the
  findings count per rule the way work-on's already do.
decision_provenance: inline-resolved
---

# DESIGN: scope document gates

## Status

Proposed

## Context and Problem Statement

The upstream PRD, `docs/prds/PRD-scope-document-gates.md`, asks /scope to hold
each hop until its document passes every error-level check the validator has
for its type, plus the banned-words check raised to blocking there, with each
failure reported as a koto finding under a registered rule id.

Today each hop state in `skills/scope/koto-templates/scope.md` carries one
gate, `<hop>_complete`, which runs `skills/scope/scripts/hop-complete.sh`. That
script calls `shirabe validate --check SCHEMA,FC01,FC03,FC04` and answers one
question, whether the hop landed. It skips whole-document validation on
purpose: the same predicate also drives the `fold` state's routing gates
(`plan_present`, `design_present`) and the exit states' `chain_complete`, so a
finding about style or an upstream link there would change where the run goes.
The rest of the format is enforced by the Phase 2 validator pass-through, a
prose step in `skills/scope/references/phases/phase-2-chain-orchestration.md`,
and the fold's own re-validation (Stage 3, step 7) is prose too.

The validator already has what the gate needs. `shirabe validate --format json`
without `--check` runs every per-file check for the document's type and
reports each finding with a `code`, a `severity` of `error` or `notice`
(computed by `effective_severity` in `crates/shirabe-validate/src/validate.rs`),
a `message`, a `file` and a `line`. For the four /scope types the error-level
codes are `FC01` to `FC04`, `FC18`, `FC19`, `FC20`, `R6`, `R10`, `R11`, and on a
PLAN also `FC05`, `FC06` and `FC17`; `R7`, `R8` and `R9` run but can't fire on
these types. The banned-words check is `FC10`, a notice, and it shares its code
with the em-dash-density finding; the two are told apart only by message
(`[FC10] writing-style banned word "<w>"`, `[FC10] em-dash-density: ...`, and,
past 50 banned-word findings, `[FC10] writing-style findings truncated at 50
...`).

Two facts found while scoping shape the design. First, the validator finds the
banned words by walking up from the working directory to
`skills/writing-style/rules.yaml`; in a repository without that file it checks
no banned word and reports nothing, without an error. Since /scope runs in any
repository, the gate has to point the validator at the plugin's copy through
`SHIRABE_RULES`. Second, validator check `R6` asks git whether an upstream is
tracked and resolves paths from the working directory, so the gate has to run
from the repository root.

The findings format, the registry and the exit convention already exist from
the output-gates work (`docs/designs/current/DESIGN-output-gates.md`): gate
scripts source `scripts/lib/rule-findings.sh`, list their ids on a `RULE_IDS`
line, print `::koto-finding::` lines through `rf_finding`, and exit 0 (pass),
1 (violations) or 2 (couldn't decide). work-on's
`skills/work-on/scripts/check-branch-output.sh --docs-visibility` is the
closest precedent: it runs the validator over changed documents and maps
`R7`, `R8` and `R9` to registry ids.

## Decision Drivers

- **Every error-level check, now and later** (PRD R3): the gate must hold what
  the validator calls an error, without a list of codes that drifts as checks
  are added or promoted.
- **Only the banned words raised** (PRD R4): `FC10`'s banned-word and
  truncation findings block; its em-dash-density finding and every other
  notice don't.
- **Findings countable per rule** (PRD R5, R6, R12): each violation is one
  `::koto-finding::` line with a registered `rule_id`, `rule_ref`, `path` and
  `line`, and every reportable rule has a registry entry.
- **Routing untouched**: `hop-complete.sh` and the gates that route on it
  keep their behaviour; the new check only adds a condition to edges that
  already advance.
- **Fold covered** (PRD R2): the absorb rewrites a document after its hop
  gate; the gate must see the result.
- **Decides or says it can't** (PRD R7, R13, R15): a missing tool, an unparseable
  envelope, a schema-less document, an unmapped code or an unreadable rules
  file is exit 2 with no finding, never a pass and never a violation.
- **Not overridable** (PRD R9), and **no prose removed** (PRD R10).
- **Bash 3.2 floor, no `set -e`, no flaky pipes**: the scope scripts run on
  macOS's system bash in CI; `hop-complete.sh` shows how a
  `printf | grep -q` under `pipefail` can fail at random when grep exits early,
  so the new script reads files, not pipes, when it decides.
- **Fast** (PRD R14): one validator call per document, well inside koto's
  30-second command limit.

## Considered Options

### Decision 1: The gate script's shape and where it sits

Resolved inline.

The gate needs one entry point that the four hop states and the fold can each
call, a way to say which documents to check, and a place in each state's
transitions.

Key assumptions:
- koto re-evaluates every gate on each `koto next`, so a fixed document passes
  on the next submission without any extra state.
- No transition naming a gate's exit 1 or 2 means koto holds the state and
  reports the gate in its blocking conditions, as it does for
  `hop-complete.sh`'s exit 2 today.

#### Chosen: one script with a document-set argument, a gate per state

`skills/scope/scripts/check-hop-document.sh --topic <slug> --hop
<brief|prd|design|plan|all>`. `--hop all` is the fold's set: every topic path.
The paths, in this order, are `docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`,
`docs/designs/current/DESIGN-<topic>.md` and `docs/plans/PLAN-<topic>.md`; a
named hop takes its own entries (the design hop both DESIGN paths). Paths that
don't exist are skipped; none existing is exit 0 with a stderr note.

Each hop state gains a gate `<hop>_document` and the fold gains
`fold_documents`, all `overridable: false`, each running
`test -x "<script>" || exit 2; "<script>" --topic "{{TOPIC}}" --hop <h>`. The
condition `gates.<gate>.exit_code: 0` is added to every transition that
advances on `landed`: the one `landed` arm in `hop_brief`, `hop_prd` and
`hop_design`, and the two arms of `hop_plan` that target `fold` (its three
`bail` arms, which route on the mode and filing gates, are left as they are).
In `fold` it is added to all fourteen arms. Arms on `skipped`, `rejected` and
`bail` don't name it.

#### Alternatives Considered

- **Widen `hop-complete.sh`'s `--check` list.** One gate per state, no template
  edits. Rejected: the same predicate routes the fold and the exit states, so a
  banned word would change routing, and its comments document why it stays
  structural.
- **One script per hop.** Simpler arguments, four copies of the same logic.
  Rejected on maintenance.
- **Gate only the fold's survivor (the most downstream document).** Narrower at
  the fold. Rejected: when a settled document sits downstream of the hop that
  just landed, the most downstream document isn't the one the absorb rewrote.

### Decision 2: Registry entries, rule text and guards

Resolved inline.

Every finding needs a registered `rule_id` whose entry carries a summary, a
text anchor, a check, fixtures, timing and guards that
`scripts/check-rule-registry.sh` accepts.

Key assumptions:
- A rule can be printed by more than one script; the registry's `check` names
  one, and `notes` can name the other (no check enforces a one-script rule).
- The validator's codes are stable aliases: output-gates already uses `R7`,
  `R8`, `R9` and `PB1` to `PB4` that way.

#### Chosen: one entry per validator code, anchored in the documents that state the rule

| Code | id | Text anchored in |
|---|---|---|
| `FC01` | `docs/required-fields` | `docs/guides/doc-validation.md`, the FC01 to FC04 item |
| `FC02` | `docs/valid-status` | the same item |
| `FC03` | `docs/status-matches-body` | the same item |
| `FC04` | `docs/required-sections` | the same item |
| `FC05` | `plan/issues-table-shape` | `references/issues-table.md`, its FC05 item |
| `FC06` | `plan/issues-table-dependencies` | `references/issues-table.md`, its FC06 item |
| `FC17` | `plan/outline-dependency-resolves` | `skills/plan/references/plan-to-tasks-contract.md`, the FC17 passage |
| `FC18` | `docs/absorbed-declaration` | `docs/guides/doc-validation.md`, the FC18 to FC19 item |
| `FC19` | `docs/absorbed-requirement-citation` | the same item |
| `FC20` | `docs/no-stale-reference` | `docs/guides/doc-validation.md`, a new item |
| `R6` | `docs/upstream-resolves` | `docs/guides/doc-validation.md`, the format-specific rules item |
| `R10` | `docs/upstream-direction` | `references/pipeline-model.md`, the R10 and R11 paragraph |
| `R11` | `docs/upstream-lifetime` | the same paragraph |
| `FC10` | `prose/banned-word` | `skills/writing-style/rules.yaml`, the `words:` block |
| `R7`, `R8`, `R9` | the existing `docs/visibility-vision-sections`, `docs/visibility-strategy-sections`, `docs/private-only-type` | unchanged |

Every new entry has `level: gate`, `check` `{"kind": "script", "path":
"skills/scope/scripts/check-hop-document.sh", "mode": "--hop"}`, fixtures
`skills/scope/scripts/check-hop-document_test.sh`, guards `pr-create` and
`publish` (a /scope run's documents reach a pull request at its exit, the same
guards the existing `docs/*` entries carry), `withhold: never`, and the
validator code in `aliases`. The plan-only rules (`FC05`, `FC06`, `FC17`) take
timing `scope:hop_plan` and `scope:fold`; the rest take all five /scope states.
The three existing visibility entries add the five /scope timings and a note
that `check-hop-document.sh` also prints them. `baseline_keys` hold the pinned
commit's range where the anchor already occurs there, and are empty with the
registry's standard note where it doesn't. `docs/guides/doc-validation.md`
gains the missing FC20 item and its R6 sentence is corrected to say R6 runs for
every format that carries `upstream:`, which it has since R6 moved out of the
Plan arm.

A code the validator reports at error level with no entry aliasing it is exit
2: the gate never prints a finding it can't register.

#### Alternatives Considered

- **One shared id for every document rule** (`docs/validator`). One entry.
  Rejected: counting failures per rule is the point, and the output-gates
  design rejected a gate-name `rule_id` for the same reason.
- **A new reference file restating each rule for the anchors.** One place for
  all the text. Rejected: it would be a second statement of rules the format
  guides already state, and the registry exists to point at a rule's one home.
- **New ids for `R7` to `R9` under `scope/`.** Rejected: the same rule under two
  ids splits its counts.

### Decision 3: Raising the banned words, and loading them

Resolved inline.

The gate has to block on banned words, not on em-dash density, though both
are `FC10`, and has to make sure the validator has a word list at all.

Key assumptions:
- The validator's message text for these findings is stable enough to pin in
  a test, as `PROSE_FINDING_CAP` and the message formats are in
  `crates/shirabe-validate/src/checks.rs`.
- `SHIRABE_RULES` is honoured by the installed validator (verified with
  shirabe 0.25.0); the `--rules` flag is not in that release.

#### Chosen: match the message prefix, and set `SHIRABE_RULES` to the plugin's rules

A finding is a violation when its `severity` is `error`, or its `code` is
`FC10` and its `message` starts with `[FC10] writing-style banned word ` or
`[FC10] writing-style findings truncated at `. The two prefixes are constants
in the script beside a comment naming their source in `checks.rs`, and the
test suite runs the real validator on a banned word and a truncation fixture,
so a reworded message fails CI.

Before validating, the script sets `SHIRABE_RULES` to
`<plugin root>/skills/writing-style/rules.yaml`, found relative to the script
itself, unless the caller already set it, and exits 2 when that file isn't
readable. The repository's declared prose vocabulary still applies, because
the validator reads it per file from the document's own repository.

#### Alternatives Considered

- **Add a sub-rule field to the validator's JSON.** Cleaner matching. Rejected
  for this feature: it changes the validator, needs a release before /scope can
  use it, and the PRD keeps the validator unchanged. A later change can move
  the gate to it.
- **Rely on the ancestor walk.** Works in shirabe's own repository only.
  Rejected: everywhere else the banned words would silently go unchecked.

### Decision 4: Sharing the declared-visibility reading

Resolved inline.

The gate passes `--visibility=<v>` from the root `CLAUDE.local.md` or
`CLAUDE.md` header, exactly as work-on's `--docs-visibility` does.

Key assumptions:
- work-on's `check-branch-output_test.sh` covers the parsing it does today, so
  moving the function keeps its behaviour checked.

#### Chosen: move `declared_visibility` into `scripts/lib/declared-visibility.sh`

Both `check-branch-output.sh` and `check-hop-document.sh` source it. The
function moves unchanged: first well-formed `## Repo Visibility:` header,
`CLAUDE.local.md` before `CLAUDE.md`, lowercased, nothing when neither file
declares one.

#### Alternatives Considered

- **Copy the function.** No change to work-on. Rejected: two parsers of one
  header drift, and `hop-complete.sh`'s history shows what that costs.
- **Call `check-branch-output.sh` from the new script.** Rejected: it would
  make /scope depend on a work-on script's interface.

## Decision Outcome

The four choices fit together as one new gate script beside the existing
completion check. The script resolves the repository root, sets the plugin's
writing-style rules, reads the declared visibility through the shared library,
and runs the validator once per topic document in a fixed order, keeping every
envelope in a temporary directory. It decides only after every document has a
verdict: any document it can't decide makes the whole run exit 2 with no
finding; otherwise each error-level finding and each banned-word finding is
printed as a `::koto-finding::` under the registry entry that aliases its code,
and the exit is 1 if anything was printed, 0 if not.

The scope template wires the script into the five states that can change a
topic document, on exactly the edges that advance, and declares it not
overridable, so neither a hop nor the fold moves on past a document the
validator calls broken. The registry gains an entry for each rule the gate can
report, anchored in the guides that already state the rules, so a finding's
`rule_id` joins koto's gate results to one rule and its `rule_ref` opens that
rule's text.

## Solution Architecture

### Overview

```
hop_<x> / fold (koto)                     check-hop-document.sh
  gate <x>_document / fold_documents  -->   cd repo root
    overridable: false                      SHIRABE_RULES=<plugin>/skills/writing-style/rules.yaml
  landed / verdict edges require 0          visibility <- scripts/lib/declared-visibility.sh
                                            for each present topic document:
                                              shirabe validate --format json [--visibility=v] <doc>
                                            decide all, then print findings via rule-findings.sh
                                            exit 0 | 1 | 2
```

### Components

- **`skills/scope/scripts/check-hop-document.sh`** (new). Arguments `--topic`
  (validated against `^[a-z0-9][a-z0-9-]*$`, no trailing hyphen) and `--hop`
  (one of `brief`, `prd`, `design`, `plan`, `all`). A `RULE_IDS` line listing
  the seventeen ids; an `undecided` that prints `check-hop-document: <reason>`
  and exits 2; `rf_require` on every id before any check. A fixed map from
  validator code to id written as a `case` statement.
- **`skills/scope/scripts/check-hop-document_test.sh`** (new). Builds
  throwaway git repositories with fixture documents, runs the script against
  the real validator, and uses stub `shirabe` scripts on `PATH` for the
  null-line, argument-recording, call-counting, exit-code and no-JSON cases.
  Sets `SHIRABE_FINDINGS_LOG` and checks it with `rule-registry.sh
  verify-findings`. Fails, rather than skips, when `shirabe` is missing and
  `CI` is set.
- **`scripts/lib/declared-visibility.sh`** (new), and
  **`skills/work-on/scripts/check-branch-output.sh`** (sources it).
- **`skills/scope/koto-templates/scope.md`**: five gates, the added transition
  conditions, and a paragraph in each of the five states' details text.
- **`references/rule-registry.json`**: fourteen new entries, three updated.
- **`docs/guides/doc-validation.md`**: the FC20 item and the R6 correction.
- **CI**: the suite in `.github/workflows/check-scope-scripts.yml`, in the job
  that builds `shirabe` from source (`test-hop-complete`'s build steps), and in
  the `scope` list of `scripts/check-bash-floor.sh`; the workflow's path filter
  gains `scripts/lib/declared-visibility.sh`, `scripts/lib/rule-findings.sh`
  and `references/rule-registry.json`.
- **Tests that follow the template**: `skills/scope/scripts/scope-template_test.sh`
  asserts each new gate's command, `overridable: false`, and the edges that
  name it; `skills/scope/scripts/scope-substrate_test.sh` gains a session case
  that holds `hop_prd` on a PRD with a missing upstream, reads the finding from
  the blocking conditions, fixes it and advances. Its existing fixture
  documents must pass the new gate; any that don't are fixed.

### Key Interfaces

Gate command, per state (the fold's uses `--hop all`):

```
test -x "{{PLUGIN_ROOT}}/skills/scope/scripts/check-hop-document.sh" || exit 2; "{{PLUGIN_ROOT}}/skills/scope/scripts/check-hop-document.sh" --topic "{{TOPIC}}" --hop prd
```

Finding (one line on stdout):

```
::koto-finding::{"rule_id":"docs/upstream-resolves","level":"error","message":"<summary>: [R6] upstream \"docs/briefs/BRIEF-x.md\" does not exist on disk","rule_ref":"docs/guides/doc-validation.md#L<a>-L<b>@<rev>","path":"docs/prds/PRD-x.md","line":19}
```

Exit statuses: 0 every checked document passes, or none exists; 1 at least
one finding printed; 2 no finding printed, reason on stderr.

### Data Flow

1. Resolve the root with `git rev-parse --show-toplevel` and `cd` there.
2. Check `git`, `jq`, `shirabe`; set and check `SHIRABE_RULES`; `rf_require`
   every id.
3. Read the declared visibility.
4. For each present path in order: run the validator, store stdout and the
   exit status in the temporary directory. Exit status 0, 2 or 4 with a
   parseable `shirabe-validate/v1` envelope is a verdict; anything else is
   undecided. An envelope whose `summary.outcome` is `incomplete` is
   undecided.
5. With every document decided, select findings with `jq` (`severity ==
   "error"`, or the two `FC10` prefixes), map each code to its id (an unmapped
   code is undecided, checked before anything prints), then print each through
   `rf_finding <id> <message> <file> [<line>]`.
6. Exit 1 if anything printed, else 0.

## Implementation Approach

### Phase 1: Registry and shared pieces

Add `scripts/lib/declared-visibility.sh` and switch `check-branch-output.sh`
to it. Add the FC20 item and the R6 correction to `docs/guides/doc-validation.md`.
Add the fourteen registry entries and update the three visibility entries.
`check-rule-registry.sh` and `check-branch-output_test.sh` pass.

### Phase 2: The gate script and its tests

Write `check-hop-document.sh` and `check-hop-document_test.sh` covering every
acceptance criterion that doesn't need koto, and wire the suite into
`check-scope-scripts.yml` and `check-bash-floor.sh`.

### Phase 3: Template wiring

Add the five gates and their edge conditions to `scope.md`, the paragraph in
each state's details, and the template and substrate test cases; make the
existing substrate fixtures pass the gate. `scripts/check-skill.sh scope`
passes.

## Security Considerations

The gate reads documents an agent wrote and passes paths built from the topic
slug, which koto already constrains and the script re-validates before
composing any path. The documents reach the validator as file arguments, never
as shell text, and the validator's JSON reaches findings through `jq`, so a
document can't inject a command or a `::koto-finding::` line of its own: every
printed line is built by `rf_finding`, which replaces control characters.
`SHIRABE_RULES` is set only to a path computed from the script's own location
and is checked readable, so a document can't redirect it; a caller that set it
already is the caller's choice. The gate runs the validator, `git` and `jq`
and nothing else, writes only to its own `mktemp -d` directory, removed on
exit, and makes no network call itself; the validator's `FC09` probe on a
PLAN runs `gh auth status`, whose result is a notice the gate ignores. The
gate is `overridable: false`, so an agent can't record its way past it; its
only way out is fixing the document or `bail`.

## Consequences

### Positive

- A /scope hop can't advance past a document the validator calls broken or
  that uses a banned word, and the hold names the rule and the line.
- Each failure carries a registered id, so failures count per rule from koto's
  gate results, alongside work-on's.
- The banned-words rule has a gate that holds it at every /scope hop, which is
  what a later withholding feature needs before taking its prose out.
- `docs/guides/doc-validation.md` describes FC20 and R6 correctly.

### Negative

- Hops that passed before can now hold, on any error-level finding or banned
  word, including a settled topic document checked at the fold.
- The banned-word selection depends on the validator's message text.
- `scope.md` grows by five gates and about twenty transition conditions.

### Mitigations

- The finding names the rule and line, and the details text tells the agent
  how to read a hold, so a held hop costs one edit.
- A test against the built validator pins both message prefixes.
- `scope-template_test.sh` asserts every new condition, so a later edit that
  drops one fails CI.

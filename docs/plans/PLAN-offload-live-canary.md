---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-offload-live-canary.md
milestone: "Live Offload Canary"
issue_count: 4
---

# PLAN: Live Offload Canary

## Status

Active

Authored under `/scope --auto` at tracking level `none`: the work items are
outlines below, and no GitHub issue or milestone is filed.

## Scope Summary

Withhold PB4 (`pr-body/no-heading-in-part1`) from a random half of standalone
`/work-on` runs on hosts that opt in, show each run's group as a marker state
in koto's exported `state_entered` events, release PB4's text when its gate
fails, and give a Datadog query that splits PB4's broken rate by group, as
`docs/designs/DESIGN-offload-live-canary.md` describes.

## Decomposition Strategy

**Horizontal**, following the design's four implementation steps. Each layer
has a stable interface for the next: the conformance file's single home for
PB4 and the gate's release come first, because the canary renders from that
file and relies on that release. The canary itself is next, then the guide
that documents its attributes and switch. The registry admission is last,
because it waits on the owner's ruling. The draw asks the registry before it
withholds anything, so the first three items are inert until it lands.

## Issue Outlines

### Issue 1: refactor(pr-body): give PB4 one home and release it on failure

**Complexity**: testable

**Goal**: Every statement of PB4 lives inside its anchored paragraph in
`references/pr-body-conformance.md`, and the PR-body gate prints PB4's text
when it fails on PB4.

**Acceptance Criteria**:
- [ ] Outside the lines `scripts/rule-registry.sh` resolves for
      `pr-body/no-heading-in-part1`, `references/pr-body-conformance.md`
      contains neither `PB4` nor the word `heading` (case-insensitive), and
      the PB4 paragraph is at most 60 lines.
- [ ] `scripts/rule-registry.sh ref pr-body/no-heading-in-part1` resolves, and
      `scripts/check-rule-registry.sh` passes.
- [ ] `check-pr-output.sh --pr-body`, given a stubbed `gh` returning a body
      with a heading in Part 1, exits 1 and prints the
      `pr-body/no-heading-in-part1` finding and the PB4 text between
      `::shirabe-rule::` and `::shirabe-rule-end::`.
- [ ] A body breaking PB4 and PB3 prints both findings and the PB4 text once;
      a body breaking only PB2 exits 1 with no `::shirabe-rule::` line; a
      conformant body exits 0 with none.
- [ ] `skills/work-on/scripts/check-pr-output_test.sh` covers the four cases
      and passes.

**Dependencies**: None

### Issue 2: feat(work-on): draw a canary group at run start and withhold PB4

**Complexity**: critical

**Goal**: A standalone `/work-on` run on an opted-in host is assigned to the
withheld or preloaded group once its plan is ready, passes through a marker
state named for its group, and reads a conformance text without PB4 when
withheld, with every other run's instructions unchanged.

**Acceptance Criteria**:
- [ ] `scripts/rule-registry.sh withhold <id>` prints the entry's `withhold`
      value and `range <id>` prints its first and last line numbers, with
      tests in `scripts/rule-registry_test.sh`.
- [ ] `skills/work-on/scripts/offload-canary.sh` exists with `draw` and `arm`;
      `draw` prints exactly one line and exits 0 in every case its test
      covers, including a missing registry and an unwritable session
      directory.
- [ ] Against a fixture plugin root whose registry marks PB4 eligible and an
      opt-in file reading `on`, 200 draws in fresh session directories pick
      each group between 70 and 130 times.
- [ ] A draw picks neither group, prints the real conformance path, and
      writes no `sample` file, for each of: `OFFLOAD_CANARY=off`,
      `SHARED_BRANCH` non-empty, no opt-in file, an opt-in file reading
      `off`, and PB4 marked `withhold: never`.
- [ ] A second draw in a session directory that already holds a group returns
      the same group 20 times out of 20.
- [ ] The withheld rendering equals `references/pr-body-conformance.md` with
      the `range` lines removed, and contains neither `PB4` nor `heading`.
- [ ] When the first line `range` reports doesn't hold PB4's `text.first`
      anchor, or the session directory, `pr-rules/` or a file in it is a
      symlink, a draw picks neither group and writes no `sample` file.
- [ ] `work-on.md` declares `OFFLOAD_CANARY` (`values: ["on", "off"]`,
      default `"on"`, no `rebind`), routes `analysis`'s `plan_ready` edge to
      `offload_canary`, keeps `initial_state: entry`, and
      adds exactly the states `offload_canary`, `offload_arm_withheld` and
      `offload_arm_preloaded`, none with `accepts`; `koto template compile`
      passes and `work-on.mermaid.md` matches.
- [ ] The `pr_creation` directive names `{{PR_BODY_RULES}}` and no longer
      lists the PR-body rule ids; `phase-6-pr.md` no longer names
      `references/pr-body-conformance.md`; `{{PR_BODY_RULES}}` appears in no
      other directive.
- [ ] A koto-level test with `gh` stubbed drives sessions to `pr_creation`:
      a withheld session's journal has one `state_entered` for
      `offload_arm_withheld` and none for `offload_arm_preloaded`, the
      reverse for a preloaded session, and neither for off, shared-branch and
      failed-assignment sessions (the script missing, not executable, and
      exiting non-zero, each a case); the preloaded, shared, off and failed
      sessions render byte-identical `pr_creation` directives.
- [ ] In a withheld session at `pr_creation`, the rendered directive,
      `skills/work-on/references/phases/phase-6-pr.md` and the conformance
      text the directive names contain neither PB4's `text.first` anchor nor
      `pr-body/no-heading-in-part1`.
- [ ] `koto init` with `OFFLOAD_CANARY=maybe` is refused, attaching to a live
      session with a different `OFFLOAD_CANARY` is refused, and a rewound
      withheld session re-enters `offload_arm_withheld`.
- [ ] No template under `skills/` other than `work-on.md` defines a state
      named `offload_canary`, `offload_arm_withheld` or
      `offload_arm_preloaded`.
- [ ] `scripts/check-skill.sh work-on` passes, and the new suites are listed
      in `.github/workflows/check-work-on-scripts.yml`.

**Dependencies**: <<ISSUE:1>>

### Issue 3: docs(work-on): add the live offload canary guide

**Complexity**: simple

**Goal**: A maintainer can read the canary's state, turn it on for a host or
off everywhere, and run the readout query from a session using one guide.

**Acceptance Criteria**:
- [ ] `docs/guides/offload-live-canary.md` names the attributes
      (`koto.session.id`, `koto.state`, `koto.rule.id`), the marker states,
      the opt-in file, the off switch's file, line and value, and gives the
      DDSQL query from the design with its filter and columns.
- [ ] The guide states that the canary withholds nothing until PB4 is
      eligible and the host opts in, that the denominator is runs that
      entered `pr_creation`, that the readout counts first failures, and that
      runs from one plan are correlated.
- [ ] A test fails when the template's `OFFLOAD_CANARY` default line differs
      from the line the guide quotes.
- [ ] The query, run in Datadog over the week before the pull request with
      `pr_precheck` standing in for a marker state, returns a row with a run
      count above 0, recorded in the pull request.

**Dependencies**: <<ISSUE:2>>

### Issue 4: feat(registry): admit PB4 as the one withholdable gate rule

**Complexity**: critical

**Goal**: The registry marks PB4 `withhold: eligible` with its reason, and
its check admits that one gate rule by name and no other.

**Acceptance Criteria**:
- [ ] `scripts/check-rule-registry.sh` carries
      `WITHHOLD_GATE_RULES="pr-body/no-heading-in-part1"`; an entry on it may
      be `level: gate` with `guards: ["none"]` and must be
      `withhold: eligible` with non-empty `notes`.
- [ ] `references/rule-registry.json` gives PB4 `guards: ["none"]`,
      `withhold: eligible` and `notes` giving the reason, and the check
      passes on it.
- [ ] `scripts/check-rule-registry_test.sh` fails for: another gate entry
      marked `eligible`, an eligible entry guarding `push`, `merge` or
      `pr-create`, and an eligible gate entry with empty `notes`.
- [ ] `references/rule-registry.md` and
      `docs/designs/current/DESIGN-rule-registry.md` say that one gate rule is
      withholdable and where the list lives.
- [ ] Against the real plugin root, with an opt-in file reading `on` under a
      scratch `XDG_CONFIG_HOME`, `offload-canary.sh draw` picks a group.
- [ ] The commit lands only after the owner's ruling on narrowing the
      withhold safety, and the pull request names that ruling.
- [ ] Across the pull request, no file under `.github/workflows/` gains a
      `schedule:` trigger and no eval workflow runs.

**Dependencies**: <<ISSUE:2>>

## Implementation Sequence

The critical path is Issue 1, then Issue 2, then Issue 4. Issue 3 can run
beside Issue 4 once Issue 2 has landed, since both depend only on the canary
being in place. Issue 4 also waits on the owner's ruling on narrowing the
withhold safety. Until it lands, the canary is inert, because the draw asks
the registry first, so Issues 1 to 3 can be finished and reviewed without it.

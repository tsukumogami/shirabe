# Check lifecycle

Every deterministic check shirabe runs from a koto gate (a registry entry whose
`check.kind` is `script`) has a lifecycle stage. The stage decides how the gate
treats the rule's finding, the figures say when the stage should change, and a
reviewed change to `references/rule-registry.json` is the only way it changes.
The registry fields are described in `references/rule-registry.md`; the design
behind all of this is `docs/designs/current/DESIGN-check-lifecycle.md`.

Entries checked any other way (the `rs-*` review-shadow criteria, which a model
grades, and prose rules nothing checks) have no stage. A stage never changes
whether a rule may be withheld from an agent's default context.

## Stages

| Stage | Finding level | What the gate does |
|---|---|---|
| `shadow` | `info` | Prints the finding. The gate doesn't fail on it, and koto never lists it in `advisories`. |
| `warn` | `warning` | Prints the finding. The gate doesn't fail on it; a koto that carries the advisories change puts it on the agent's response as `advisories` (see "On an older koto"). |
| `block` | `error` | Fails the gate, as every gate rule did before stages existed. |
| `retired` | none | The check doesn't report the rule at all. |

The level carries the stage one to one, so a finding in koto's events says
which stage its rule was at. `stage` is separate from `status`: `status:
retired` means the rule no longer applies and its id leaves every `RULE_IDS`
line, while an active entry at stage `retired` still applies, keeps its id on
`RULE_IDS`, and only its gate check stops reporting it. `level: shadow`, on
review-shadow entries, is unrelated.

The five gate scripts (`check-pr-output.sh`, `check-branch-output.sh`,
`check-verification.sh` and `panel-scope.sh` under `skills/work-on/scripts/`,
`check-hop-document.sh` under `skills/scope/scripts/`) decide their exit from
block-stage findings alone; their could-not-decide exit (2) is unchanged.
Three details:

- `check-verification.sh --verdict` picks its route (1, 3 or 4) from the
  causes that printed at `block` only, and exits 0 when none did.
- `check-pr-output.sh --pr-body` adds its `pr-body/conformance` fallback only
  when the validator listed no finding, and releases the text of
  `pr-body/no-heading-in-part1` only at `warn` or `block`.
- `panel-scope.sh --verdict` prints every finding at the stage of
  `panel/open-finding`, whichever rule the finding cites: the stage governs a
  deterministic check, and a reviewer's finding isn't one.

A gate script reads a rule's stage through `scripts/rule-registry.sh stage`
(or `resolve`, which prints the reference, summary and stage on one line). The
plugin's pre-action hook (`hooks/pre-action-deny.sh`) ignores stage: a rule's
`deny` keeps denying at every stage.

## Changing a stage

A stage changes only through a pull request to the registry that a person or
a coordinator session reviews, and the pull request carries the rule's figures
(below) and the criterion they meet. Nothing changes a stage automatically. The
change sets `stage` and raises `stage_since` to the date it lands.

`scripts/check-rule-registry.sh --base <merge base>`, which CI runs on every
pull request that touches the registry, allows only these changes:

- no change;
- a new entry starting at `shadow`, `warn` or `block`;
- a base entry with no stage taking `block`, or `retired` when its status is
  `retired`;
- one step up: `shadow` to `warn`, `warn` to `block`;
- down any number of steps among `block`, `warn` and `shadow`;
- any stage to `retired`;
- `retired` to `shadow`, on an active entry.

Every change of stage must set a `stage_since` later than the base's. A status
change to `retired` moves the stage to `retired` in the same change, and a
`status: retired` entry never changes status or stage again. An active entry
that drops a protected guard must be at `block` in that change, so dropping a
guard and softening the stage take two reviewed changes. A base the check
can't read exits 2 rather than passing.

### Guarded rules

A rule whose `guards` include a protected action (`pr-create`, `push`,
`force-push`, `merge`, `close-issue`, `release`, `delete-branch`, `publish`,
`destroy-record`) stays at `block`, unless it carries `stage_backstops`: one
entry per protected action it guards, each naming the action (`before`) and a
deterministic check (`check`, a repository path other than the rule's own
check) that still blocks that action when the rule is broken, with `notes`
saying why. This holds for every other stage, `retired` included. The registry
check refuses the entry otherwise, and `scripts/rule-registry.sh stage` repeats
the rule when a gate runs: a guarded rule below `block` without full backstops
is read as `block`, so a registry edited without passing CI can't soften it.
Whether a named check really blocks the action is the reviewer's call; the
checks confirm only that the file exists and isn't the rule's own.

## Figures

Every figure comes from koto's run journal, the record koto writes on each
host and that is exported to a log backend. The figures a stage-change pull
request quotes come from log queries over that exported journal across every
host; one host's journal sees only that host's runs.

Each figure is for one rule, over its window, summed across the rule's `gates`
(`<skill>:<state>:<gate>`; the journal carries the state and gate, not the
skill). Names are given in koto's flat line format. A log backend nests a name
that has children: on `check_evaluated`, where `koto.check` sits beside
`koto.check.outcome` and the rest, the gate arrives as `koto.check.name`;
`check_finding` and `check_disputed` write the gate as `koto.check.name`
themselves, so in a backend the gate has one path on all three kinds.

| Figure | Definition |
|---|---|
| Window | From the rule's `stage_since` (inclusive) to the newest `at` among the records read, of any kind and any rule. Its length is the calendar days between the two dates. |
| Evaluations | `check_evaluated` records in the window that carry `koto.check.finding_count` (a koto that journals findings; older evaluations would read as quiet and aren't counted), whose `koto.state` and `koto.check` (`koto.check.name` in a backend) are the state and gate of one of the rule's gates. One per `koto.session.id` and `koto.seq`. |
| Fires | Evaluations with a `check_finding` for the rule (`koto.rule.id`) at the same `koto.session.id` and `koto.seq`, whose `koto.state` and `koto.check.name` are one of the rule's gates. Counted once per evaluation, and once per evaluation per `koto.finding.level`. Fires are evaluations minus passes, not the sum of the level columns. |
| Passes | Evaluations minus fires. |
| Disputes | `check_disputed` records for the rule at one of its gates (`koto.state`, `koto.check.name`), at most one per `koto.session.id` (the earliest by `at`), split by `koto.dispute.source` (`agent` or `person`; no other source counts). A record with no session id isn't counted. |
| Unconverged visits | `koto.session.id` and `koto.visit.seq` pairs with an `error` fire for the rule and no evaluation of the same gate with `koto.check.outcome` `passed` in that visit. Informational. |

A finding joins its evaluation on the session id and `koto.seq`; a dispute
joins the evaluation it disputes on the session id, `koto.state`,
`koto.check.name` and `koto.attempt`. A review panel's finding that cites a
rule counts for `panel/open-finding`, whose gates the panel gates are, never
for the cited rule. A rate is per evaluation of the rule's gates, not per case
the rule applies to.

## Criteria

Rates are fires over evaluations and disputes over fires, counting agent and
person disputes alike; a rate with a zero denominator meets no criterion that
reads it. "At least" and "at most" are inclusive. The first criterion a rule
meets, in this order, is the one it meets; a rule meeting none holds its stage.

| Criterion | At stage | Evidence over the window |
|---|---|---|
| demote | warn or block | at least 7 days; at least 3 disputes; disputes more than 20% of fires |
| retire | shadow, warn or block | at least 300 evaluations and 56 days; no fires (evaluations whose findings were cut at koto's 50-finding cap, `koto.check.findings_truncated`, are left out of the evaluation count) |
| promote to warn | shadow | at least 100 evaluations and 14 days; at least 1 fire; fires at most 25% of evaluations |
| promote to block | warn | at least 100 evaluations and 14 days; at least 5 fires; disputes at most 5% of fires |

A guarded rule still needs its backstops for any stage other than `block`. The
figures are evidence for a reviewer, never a trigger: the journal sits where an
agent's process can write, disputes report their own source, and a cut finding
list can hide a finding.

### The reference reader

`scripts/rule-lifecycle.sh figures [--json] [<journal-file>...]` implements the
definitions above over koto's line format (files, or standard input), with each
rule's `stage`, `stage_since` and `gates` read from the registry beside it, and
prints one tab-separated line per script-checked rule: `id stage days
evaluations fires_error fires_warning fires_info passes disputes_agent
disputes_person unconverged criterion`, or one JSON object per rule with
`--json`. Its fixtures pin every threshold boundary, which is how the
definitions are tested. It is for tests and spot checks on one host; it never
decides a stage change. It writes no file and makes no network call, and exits
2 when the registry or an input can't be read.

## Disputing a finding

A gate script that fails on a block-stage finding prints one standard-error
line naming the dispute path. An agent or a person who believes a finding is
wrong runs:

```
scripts/rule-dispute.sh --session <name> --gate <gate> --rule <rule-id> --reason <why> [--state <state>] [--by agent|person]
```

with the session and gate from the koto response. A dispute is recorded, not
obeyed: it changes no gate outcome, route or state, so the run stays held
until the output is fixed or a person overrides the gate through koto's
existing override path.

- On a koto with `koto disputes record`, the dispute is a `finding_disputed`
  session event and a `check_disputed` journal record (no reason text), and the
  script prints `dispute=journaled`.
- On an older koto, it is a koto decision with choice `dispute:<rule-id>` and
  the gate, state, source and reason in its rationale, and the script prints
  `dispute=session-only`. That stays in the session and reaches no figure.

The script refuses (exit 2) a missing or empty required argument, `--by` other
than `agent` or `person`, and a rule id that isn't an active registry entry,
all before calling koto; when koto fails, its exit status passes through and
nothing is printed on standard output.

## On an older koto

On a koto without the journal and response changes (koto 0.20.0, shirabe's
floor today), block-stage checks behave exactly as before. A warn or shadow
finding never fails a gate; koto keeps a passing check's findings only in the
session log, so it reaches neither the journal nor the agent, and warn behaves
as shadow. Evaluations from such a koto carry no `koto.check.finding_count`, so
they don't count toward any figure.

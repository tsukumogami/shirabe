# Rule registry

`references/rule-registry.json` is the one place a shirabe rule is defined. Every rule a gate
script reports, every review-shadow criterion, and every rule a script releases on a trigger
has exactly one entry there, under an id that never changes. `scripts/rule-registry.sh` is the
only reader scripts use. The design behind both is the rule-registry DESIGN document under
`docs/designs/`.

No skill loads this file or the registry into an agent's context. They are for scripts, CI and
the people who read gate events and trial records.

## A registered rule

A **registered rule** is an id with an entry in `references/rule-registry.json`. That is the
set the interim routing-gate rule in `DESIGN-output-gates.md` (Decision 9) refers to: a koto
fallback finding carries the gate's name as its `rule_id`, gate names have no entry, so such a
finding is not a violation. A reader counting violations from an event log counts a finding
only when its `rule_id` is a registered rule, until koto's routing-gate declaration
(tsukumogami/koto#306) lets routing gates write no fallback at all.

## Fields

Every entry has every field below except `backstop`, which only an eligible gate rule carries,
`deny`, which only a rule the plugin's pre-action hook denies carries, `stage`, `stage_since`
and `gates`, which every script-checked entry carries and no other entry does,
`stage_backstops`, which only a script-checked entry may carry, `jev`, which only a rule
Jev grades carries, and `held_by`, which only a jury or review-shadow item a document check
also decides carries; `fixtures`, `baseline_keys` and `aliases` may be empty lists.

| Field | Meaning |
|---|---|
| `id` | `<area>/<rule>` for a named rule, `rs-NNN` for a review-shadow criterion. Never changed, never reused, never a location. |
| `status` | `active`, or `retired` for a rule that no longer applies. A retired entry keeps its id so old records still join; its text needn't resolve and no script may print it. Entries are never deleted. |
| `summary` | The short text an agent sees when the rule is broken. Gate scripts print it at the start of a finding's `message`, then `: ` and their own detail. One line, no control characters, no `::`. |
| `text` | Where the rule's full text is: `path` (a repository-relative file), `first` (a substring of the rule's first line, found on exactly one line of the file) and, for a rule longer than one line, `last` (a substring of its last line, the first line at or after `first` that contains it). A review-shadow entry's `path` is its criterion's `rule_ref`; where that file states no sentence for the rule, the anchors frame the nearest passage and `notes` says so, and the criterion's question is the precise statement. |
| `check` | What enforces it: `{"kind": "script", "path": ..., "mode": ...}`, `{"kind": "review-shadow", "criterion": "rs-NNN"}`, `{"kind": "decider", "template": ..., "state": ..., "gate": ..., "criterion": ...}` (a koto `decider-check` gate's criterion, which Jev grades), or `{"kind": "none"}`. A `decider` entry guards no protected action, so it needs no backstop to sit at `level: gate`. A document criterion's `template` is the first of its formats' templates; the rest are in its `jev.pairs`. |
| `fixtures` | Tests and fixture files that exercise the check. |
| `level` | `gate` (a koto gate holds or reroutes the run on it), `shadow` (graded and recorded beside a panel, never blocking) or `prose` (stated in a skill or template, checked by nothing). |
| `timing` | Where it applies: `<skill>:<state>` naming a `## <state>` section of that skill's koto template, or `pre-merge` (the review-shadow trial's point, before a pull request's panel). Never empty. |
| `guards` | What the rule keeps from doing harm that can't be taken back once it happens: `pr-create`, `push`, `force-push`, `merge`, `close-issue`, `release`, `delete-branch`, `publish`, `destroy-record`, or `none` alone. |
| `withhold` | `never` or `eligible`, with no default. Any guard other than `none` forces `never`, and so does `check.kind: none`: a rule nothing checks can't be withheld on trust. A gate rule can be `eligible` only through `backstop`. |
| `backstop` | Only on a gate rule eligible to withhold: `{"before": <protected action>, "check": <path>}`, the deterministic check that still blocks `before` after the rule's gate, for a rule whose gate runs after the action it would otherwise guard and whose harm a later edit undoes. A gate rule may carry `guards: ["none"]` only with a backstop, or as a script-checked rule at `shadow` or `warn`, which never fails its gate and so guards nothing in fact; a change that steps such a rule up to `block` gives it a protected guard in the same change, and a new entry can't take an alias another entry already holds at the base. A backstop needs `withhold: eligible` and notes saying why. `pr-body/no-heading-in-part1` is the one such rule: its gate reads the pull request GitHub already has, `gh pr edit` fixes it, and `.github/workflows/validate-pr-body.yml`, a required status check on `main`, keeps the pull request from merging while it fails. |
| `deny` | Only on a rule a plugin hook denies before a command runs: `{"hook": <path>, "before": [<protected action>, ...]}`, the hook script and the actions it stops when the rule is broken, with no other field. `hook` is a repository-relative path to an existing file, and `before` is a non-empty list from the `guards` vocabulary less `none`. The script lists the rule on its `RULE_IDS` line, and `check-rule-registry.sh` holds the two to each other both ways. A `deny` changes nothing about `withhold`: `pr-body/no-heading-in-part1` carries one and stays `eligible`. |
| `stage` | A script-checked entry's lifecycle stage: `shadow`, `warn`, `block` or `retired`. Its gate scripts print the rule's finding at `info`, `warning` or `error`, or not at all at `retired`, and only a `block` finding fails the gate. A `status: retired` entry is at `retired`. `rule-registry.sh stage <id>` prints the effective stage, which is `block` for a missing or unknown stage and for a guarded rule below `block` whose `stage_backstops` don't cover every protected guard. |
| `stage_since` | `YYYY-MM-DD`, the date the current stage was set; a new entry's is the date it was added. A change of stage must set it later than the merge base's value. It opens the window the lifecycle figures read. |
| `gates` | `<skill>:<state>:<gate>` values naming the koto command gates whose evaluations count as the rule's evaluations. Non-empty on an active script entry, except one checked by `scripts/doc-check.sh`, which runs from a skill's phase step rather than a koto gate and so has no gate to name (its evaluations are its `doc_rule_checked` telemetry records). `check-rule-registry.sh` refuses a value whose state isn't in that skill's koto templates, whose gate isn't a command gate of that state, or, on an active entry, whose command runs no script listing the id on its `RULE_IDS` line (`panel-scope.sh` may report any active rule). |
| `stage_backstops` | Only on a script entry, and required on an active one whose `guards` include a protected action at any stage other than `block`: `[{"before": <protected action>, "check": <path>}, ...]`, one per protected action it guards, each naming an existing deterministic check, other than the entry's own `check.path`, that still blocks `before` when the rule is broken, with `notes` saying why. No entry carries it yet. |
| `baseline_keys` | The offload baseline's source-location keys (`<path>#L<start>-L<end>` at the pinned commit in `docs/measurement/offload-baseline/template-pin.json`) where the rule's text was at that commit. Entries whose texts shared a range there share the key and say so in `notes`. An empty list says why in `notes`. |
| `aliases` | Other codes the rule is known by, such as the validator's `PB3` or `R7`. Unique across the registry, never an id, never printed as a `rule_id`. |
| `held_by` | Only on an `rs-` entry: the id of the active script-checked rule that decides the same item, such as `docs/required-sections` for a jury seat's required-sections item. `scripts/doc-events.sh fix --answers jury_fail` writes it as a fix's `check_rule`, so a fix answering the item's FAIL joins the check that verifies it; an item with none gets `none`. |
| `notes` | Why a key list is empty, which entries share a key, and anything else a reviewer needs. |
| `jev` | Only on a rule Jev grades: a `decider` entry, or a review-shadow criterion whose observer is Jev. Its slice contract and trust record: the sources the slice is built from, the script that builds it, its budget, its completeness case, its measured size on real runs, its fixture file, its state (`rejected`, `blocked`, `untrusted` or `trusted`) and any promotion or false-pass record. A document criterion, which runs on one or more formats, holds one such contract per format under `pairs` beside its `state` and `false_passes`. `check-rule-registry.sh` checks only that it is an object; `scripts/jev-criteria/jev_criteria.py check` holds its contents to the contract `references/jev-criteria.md` describes. |

`stage`, `status` and `level` answer different questions. `status` says whether the rule
applies at all: a `status: retired` entry leaves every `RULE_IDS` line and no script prints it.
`stage` says how a script-checked rule's gate check treats its finding while the rule applies,
so an active entry at stage `retired` keeps its id on its `RULE_IDS` lines and only its gate
check stops reporting it. `level` says what kind of rule it is (a gate, a review-shadow
criterion graded beside a panel, or prose), and `level: shadow` has nothing to do with stage
`shadow`. How a stage changes, the figures a change quotes and the way to dispute a finding are
in [`references/check-lifecycle.md`](check-lifecycle.md).

## The reference a finding carries

A gate finding's `rule_ref` is computed when the finding is printed, never stored:
`<path>#L<first>-L<last>@<revision>`, the entry's text in the copy of the file the script runs
from. The revision names that copy:

| Revision | When |
|---|---|
| a 12-character commit | a git checkout whose file matches its blob at `HEAD` |
| `worktree` | a git checkout whose file has uncommitted changes |
| `vX.Y.Z` | an installed release; the tag is on `main` |
| `<version>+<12-character blob>` | any other installed version, such as `X.Y.Z-dev`; `git log --all --find-object=<blob>` finds the commits holding that text |
| `<version>` | the same, with no `git` installed |
| `unknown` | the plugin's version doesn't have the expected shape |

Join records on `rule_id`; `rule_ref` is for opening the text.

## Checking what the gate scripts print

Gate scripts source `scripts/lib/rule-findings.sh`, which resolves every id in their mode
before any check runs and builds each finding. One exception is declared rather than ambient:
a script that prints a finding under the finding's own rule (`panel-scope.sh --verdict`,
where a finding raised by a rule's check, or citing an active id, prints under that id)
resolves the id at run time with `rf_require_any`, which refuses any id that isn't an active
entry. Such a script carries a `RULE_IDS_ANY_ACTIVE=1` line beside its `RULE_IDS` line, and
`check-rule-registry.sh` allows that line only in `panel-scope.sh`, only beside an
`rf_require_any` call. When `SHIRABE_FINDINGS_LOG` names a file,
`rule-registry.sh log-finding <line>` appends a printed `::koto-finding::` line to it; the
library calls it for every finding, and the gate scripts' test suites set the variable. Because an agent can also run a gate script from its own shell,
the log is honored only for a regular file under `$TMPDIR` (or `/tmp`) that isn't a symlink;
anything else is ignored. `rule-registry.sh verify-findings <log>` then fails unless the log
holds at least one finding and every finding's `rule_id` is an active entry whose `rule_ref` is
the one `ref` computes, whose `message` starts with the entry's summary and `: `, and whose
`level` is the one the rule's stage prints at (with `--stage-source <id>`, that rule's stage
instead, as for `panel-scope.sh`). Log only
what the scripts print: a koto fallback finding carries a gate name, which is not a registered
rule.

## Denying a command before it runs

The plugin's `hooks/pre-action-deny.sh` is a Claude Code PreToolUse hook on Bash. It denies a
`gh pr create` or `gh pr edit` whose title or body breaks a PR-body rule, and a `git push` that
would send a commit with an AI-attribution trailer; the rules it checks are the ones whose
`deny` names it. The script hands the command to `shirabe pre-action-hook`, which reads this
registry from the plugin's own root at run time. A validator code such as `PB2` finds its entry
through `aliases`, and the deny reason names each broken rule by its id and `summary` and points
at its `text` range, so a reworded summary or a moved rule reaches the next deny with no binary
change. A registry or rule text the binary can't read denies the guarded command rather than
letting it through. `shirabe pr-body-hook`, the older entry point some hosts wire themselves,
runs the same evaluator on a copy of the registry compiled into the binary.

## Adding, changing or retiring a rule

- **A new rule** gets a new entry with every field, in the same pull request as the check or
  trigger that uses it. A gate script lists the id in its `RULE_IDS="..."` line; a script that
  isn't listed there can't print it.
- **Editing a rule's text** needs no registry change unless the edit rewrites the rule's first
  or last line, in which case the anchor changes in the same pull request.
- **Changing what a rule means** is a new id; retire the old one.
- **Retiring** sets `status: retired`, removes the id from every `RULE_IDS` line and drops the
  entry's `deny`. A script-checked entry moves to stage `retired` in the same change, with a
  later `stage_since`.

## Delivering a rule when it applies

`rule-registry.sh release <id>` prints a rule's text on standard error between two marker
lines, and always exits 0:

```text
::shirabe-rule::{"rule_id":"<id>","rule_ref":"<rule_ref>"}
<the rule's lines, byte for byte>
::shirabe-rule-end::
```

A script calls it at the moment it detects that the rule applies, so the agent that ran the
script reads the rule in the same tool result. `release` prints only from files under
`references/`, `skills/*/references/`, `skills/*/koto-templates/` or a `skills/*/SKILL.md`, at
most 60 lines, and refuses text holding a marker line or a control character. When it can't
print, it prints one `rule-registry: could not release <id>: <reason>` line instead and the
caller's result is unchanged. Releasing copies a rule; it never moves one out of the prose that
loads by default.

The first trigger is `/execute`'s owned-PR lookup: when `adopt-or-create-pr.sh` finds another
run's pull request on the plan's shared branch (its exit 6), it releases
`execute/pr-takeover-needs-signal`.

The second is `/work-on`'s PR-body gate, through the escalation ladder below: in a run
whose template supplies the ladder's context, `pr-body/no-heading-in-part1` is released like
every other rule, from its second failure. `check-pr-output.sh` run without that context
(by `/execute`'s `pr_finalization`, by hand, or by a test) still releases it on every
failure.

**Delivery markers.** So telemetry can count what a gate handed the agent, the rule library
(`scripts/lib/rule-findings.sh`) prints one line on standard output for every delivery of a
rule this run resolved, which koto records as a rule delivery:

```text
::koto-rule-delivered::{"rule_id":"<id>","extent":"<summary|full>","delivery":"<printed|refused>"}
```

Extent `summary` with delivery `printed` follows each finding the library prints; extent
`full` follows each full-text release a gate script makes through `rf_release` (the ladder's
and the PR-body gate's own), with delivery `printed` when the text printed and `refused` when
`release` refused it. A retired finding prints no marker, and neither does an id the run
didn't resolve. A koto without marker support ignores the line. koto reads a marker only at
the start of a line, and every line the library prints on standard output starts with its own
marker, so a finding's detail, which may quote a pull request body, can't forge one.

## Escalating a rule's text

A gate script prints each violation as a finding whose message starts with the rule's
`summary`. When a fix doesn't land, the same rule fails again, and the gate hands over more of
it each time. koto records, on every failed check event, how many times that check has failed
on each rule in the state (`rule_counts[<id>].session`), and the gate reads that count rather
than any number the agent supplies. `scripts/lib/rule-findings.sh` holds the ladder; a gate
script that prints through it gets it from one call, `rf_deliver`, made just before the script
exits non-zero. The design is `DESIGN-validate-and-return.md`.

**The count.** For a rule the failing gate reports, the count is 1 plus the highest
`rule_counts[<id>].session` on the `gate_evaluated` events already in the session's log whose
`state` and `gate` are this gate's, which is the number koto then records for this failure. It
counts failed evaluations, so a `koto next` that re-runs a failing gate without a change raises
it like a failed fix does. The state is read from the log (the last `transitioned`,
`directed_transition` or `rewound` event's `to`), never from the gate's command.

**The rungs.**

| Count | What the gate adds to its findings, on standard error |
|---|---|
| 1 | Nothing: the finding's summary is the first rung. |
| 2 or more (`RF_FULL_TEXT_AT`) | `release <id>`, the rule's full text between its marker lines. For a rule `release` refuses, its refusal line and then `rule-findings: <id>'s full text is at <rule_ref>`, the file and line range to read. |
| 3 or more (`RF_EXIT_AT`) | In a state with a named exit, one `::shirabe-check-exit::{json}` line naming the rule with the highest count (the first printed, on a tie), its count, the state and the exact evidence that takes the exit. |

Both thresholds are defined once, at the top of `rule-findings.sh`.

**The context.** The ladder runs only when the gate's command supplies it, as environment
assignments written the same in every state that shares the command:

```text
SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"
SHIRABE_GATE_NAME=<the gate's name>
SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status"
```

`/work-on`'s template supplies it on its ten output gates. Without the log and the name,
`rf_deliver` does nothing and the script prints what it always printed: a script run from an
agent's shell, a test or `/execute` gets no ladder. With them, a log the ladder can't read
(missing, not a schema-version-1 koto log, or no transition in it) releases every reported
rule, prints one line naming the log, and offers no exit, since opening the exit needs a real
count. `rf_deliver` writes the rule text and its notices only to standard error and returns 0,
so a gate's exit status and the findings koto records never change; on standard output it
adds only the delivery markers below.

**Rules `release` refuses.** Five rules a `/work-on` gate script can report have text `release`
won't print, so their second rung is the refusal and the reference: `pr-body/banned-word` (its
text is in `skills/writing-style/rules.yaml`), `pr-body/conformance` (over 60 lines), and
`docs/private-only-type`, `docs/visibility-vision-sections` and
`docs/visibility-strategy-sections` (in `docs/guides/doc-validation.md`). A test in
`scripts/rule-registry_test.sh` pins that set.

**The named exit.** `/work-on`'s `pr_creation`, `finalization` and `pr_precheck` hold the run
on a violation. Each accepts `check_unsatisfiable` on its status field with a
`check_exit_reason`, but only while its registry gate (`pr_body_conformant`,
`commit_convention`, `branch_docs_visibility`) exits 1. The run goes through the marker state
`check_exit` to `done_blocked`, its `failure_reason` reading `check_exit at <state>: <gate>
could not be satisfied: <reason>`. The exit never moves a run past the gate it failed, so
every rule that guards pull request creation, a push or a merge blocks as before. The count-3
notice is when the gate offers it; the template doesn't refuse it earlier, since taking it
gains nothing but a stopped run.

**Counting it.** koto's run journal exports state names and rule counts but no evidence
values. Runs that took the exit are its `state_entered` records with `koto.state` =
`check_exit`; each is credited to the rules on the `check_rule` records of the same session at
the exit's state with the highest `koto.seq` below it. Failures by rung are `check_rule`
records split on `koto.rule.session_count`: 1 the summary, 2 or more the full text. Because
submitting the exit re-runs the failing gate, the check just before `check_exit` carries one
more than the count the notice showed.

## Leaving a rule out of a run

The live offload canary (`DESIGN-offload-live-canary.md`) leaves one rule's
text out of the conformance text half of `/work-on` runs read. It reads the registry through
two more commands: `rule-registry.sh withhold <id>` prints the entry's `withhold` value, and
the canary draws a group only when it prints `eligible`; `rule-registry.sh range <id>` prints
the rule's first and last line numbers, which the canary removes from its copy of the file.

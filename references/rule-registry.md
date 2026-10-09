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

Every entry has every field below; `fixtures`, `baseline_keys` and `aliases` may be empty lists.

| Field | Meaning |
|---|---|
| `id` | `<area>/<rule>` for a named rule, `rs-NNN` for a review-shadow criterion. Never changed, never reused, never a location. |
| `status` | `active`, or `retired` for a rule that no longer applies. A retired entry keeps its id so old records still join; its text needn't resolve and no script may print it. Entries are never deleted. |
| `summary` | The short text an agent sees when the rule is broken. Gate scripts print it at the start of a finding's `message`, then `: ` and their own detail. One line, no control characters, no `::`. |
| `text` | Where the rule's full text is: `path` (a repository-relative file), `first` (a substring of the rule's first line, found on exactly one line of the file) and, for a rule longer than one line, `last` (a substring of its last line, the first line at or after `first` that contains it). A review-shadow entry's `path` is its criterion's `rule_ref`; where that file states no sentence for the rule, the anchors frame the nearest passage and `notes` says so, and the criterion's question is the precise statement. |
| `check` | What enforces it: `{"kind": "script", "path": ..., "mode": ...}`, `{"kind": "review-shadow", "criterion": "rs-NNN"}`, or `{"kind": "none"}`. |
| `fixtures` | Tests and fixture files that exercise the check. |
| `level` | `gate` (a koto gate holds or reroutes the run on it), `shadow` (graded and recorded beside a panel, never blocking) or `prose` (stated in a skill or template, checked by nothing). |
| `timing` | Where it applies: `<skill>:<state>` naming a `## <state>` section of that skill's koto template, or `pre-merge` (the review-shadow trial's point, before a pull request's panel). Never empty. |
| `guards` | What the rule keeps from doing harm that can't be taken back once it happens: `pr-create`, `push`, `force-push`, `merge`, `close-issue`, `release`, `delete-branch`, `publish`, `destroy-record`, or `none` alone. |
| `withhold` | `never` or `eligible`, with no default. Any guard other than `none` forces `never`, and so does `check.kind: none`: a rule nothing checks can't be withheld on trust. This feature withholds nothing; the field is for later work. |
| `baseline_keys` | The offload baseline's source-location keys (`<path>#L<start>-L<end>` at the pinned commit in `docs/measurement/offload-baseline/template-pin.json`) where the rule's text was at that commit. Entries whose texts shared a range there share the key and say so in `notes`. An empty list says why in `notes`. |
| `aliases` | Other codes the rule is known by, such as the validator's `PB3` or `R7`. Unique across the registry, never an id, never printed as a `rule_id`. |
| `notes` | Why a key list is empty, which entries share a key, and anything else a reviewer needs. |

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
before any check runs and builds each finding. When `SHIRABE_FINDINGS_LOG` names a file,
`rule-registry.sh log-finding <line>` appends a printed `::koto-finding::` line to it; the
library calls it for every finding, and the gate scripts' test suites set the variable. Because an agent can also run a gate script from its own shell,
the log is honored only for a regular file under `$TMPDIR` (or `/tmp`) that isn't a symlink;
anything else is ignored. `rule-registry.sh verify-findings <log>` then fails unless the log
holds at least one finding and every finding's `rule_id` is an active entry whose `rule_ref` is
the one `ref` computes and whose `message` starts with the entry's summary and `: `. Log only
what the scripts print: a koto fallback finding carries a gate name, which is not a registered
rule.

## Adding, changing or retiring a rule

- **A new rule** gets a new entry with every field, in the same pull request as the check or
  trigger that uses it. A gate script lists the id in its `RULE_IDS="..."` line; a script that
  isn't listed there can't print it.
- **Editing a rule's text** needs no registry change unless the edit rewrites the rule's first
  or last line, in which case the anchor changes in the same pull request.
- **Changing what a rule means** is a new id; retire the old one.
- **Retiring** sets `status: retired` and removes the id from every `RULE_IDS` line.

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

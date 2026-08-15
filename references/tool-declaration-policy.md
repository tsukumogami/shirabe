# Tool Declaration Policy

The rule that decides how much of a host tool a skill declares in its
`skills/<name>/requires.tsv` sidecar, and why the line falls where it does.
Normative prose, like [`wip-hygiene.md`](wip-hygiene.md) and
[`worktree-discipline.md`](worktree-discipline.md): no skill loads this file,
and it's reviewed as part of a PR. The load-time check and the CI conformance
scan both cite it by name, so an author who trips the split is sent here rather
than left to infer the rule from someone else's sidecar.

## The rule

A tool whose release cadence is coupled to shirabe's own gets
subcommand-and-flag records: one record per subcommand the skill calls, naming
the flags that subcommand's call actually depends on.

A tool with an independent release cadence gets a tool-only record, with `-` in
field two and `-` in field three. It's verified for presence and nothing else.

Current membership:

| Cadence | Tools | What a record names |
|---|---|---|
| Coupled to shirabe | `shirabe`, `koto` | Tool, subcommand path, depended-on flags |
| Independent | `gh`, `jq`, `git`, `python3` | Tool alone |

There's no third depth and no per-declaration depth verb. A tool declared with
no subcommands yields presence verification by construction, because there's
nothing left to enumerate.

## Why the split falls there

shirabe declares what it can track and what actually skews against it.

The plugin and the binary ship separately, and they're skewed right now: the
version `plugin.json` declares in this worktree is a dev build ahead of the
`shirabe` binary installed on the host. That's not an accident to be fixed once.
A skill body ships inside the plugin and the binary it calls installs on its
own schedule, so the two drift by construction. `koto` sits in the same
position. Both surfaces are ours, both move under our own PRs, and the record
shows them moving: `validate` and `roadmap populate` each accreted flags well
after the subcommand shipped. When one of those surfaces changes, the change and
the declaration that names it are visible to the same reviewer.

`gh` is the opposite case on both counts. Its surface is stable and shirabe
neither controls nor tracks its releases, so a subcommand record for `gh` would
verify something no shirabe author watches. A stale entry there would be
indistinguishable from a real finding, and the reader who has to decide which
one it is loses more than the check ever gave them. Volume makes it worse: `gh`
has roughly ninety call sites across the corpus, and without a stated rule that
volume pulls an author toward declaring the surface simply because there's so
much of it.

The cost runs the same direction. `gh --help` measures around 20 ms against 2.5
to 3 ms for `koto --help`, so a `gh` subcommand declaration is also the most
expensive one available, paid on every skill load, for the surface least likely
to move. `jq`, `git`, and `python3` are the same argument with smaller numbers,
and not one of the four carries a surface incident anywhere in the record.

## A declaration describes, it doesn't predict

PR #278 chose a CI matrix over a runtime guard, reasoning that "a pattern list
only catches what its author remembered." That reasoning is sound, and this
policy has to answer it rather than talk past it.

The answer is that a declaration is a description of a call that exists, not a
prediction about a call someone will write. A pattern list, a version floor, and
a curated list of flags-that-look-risky are all guesses about the future. Each
can go wrong while the code around it stays perfectly correct, which is how they
rot without anyone noticing. A declaration entry is written by the same author,
in the same change, as the call it describes. It can't go stale while the call
stays correct, because getting the description wrong means getting the call
wrong too.

This repo's own history is the evidence. The one flag anybody labelled
skew-prone in advance, `--superseded-by`, arrived in the same commit as its
subcommand and never skewed. The flags that actually accreted after their
subcommand shipped were labelled as a risk nowhere. Prediction has a losing
record here.

The defence has one limit, and it's worth stating rather than smoothing over: a
description can still be **omitted**. An author who adds a call and forgets the
entry gets no finding. That failure is the conformance scan's job, not the
declaration's, and it's why the scan extracts flags from a skill's own command
lines instead of trusting the sidecar to be complete. The moment declarations
stop describing actual calls and become a curated risk list, #278 applies in
full.

## Defaulted flags: name the mode at the call site

A skill that calls a subcommand whose behaviour is governed by a defaulted flag
passes that flag explicitly. It does not rely on the default.

The case that forced the rule is `shirabe roadmap populate`. Its
`--issues` / `--no-issues` pair flipped which side is the default in #264 while
the flag names and their presence in `--help` stayed exactly as they were. A
probe compares surfaces, and that surface did not move, so no probe at any depth
sees the flip. Every call site in the skills now names its mode: the automatic
population in `/roadmap` Phase 4 and on the activate path passes `--no-issues`,
and the post-approval issue-filing action passes `--issues`. The prose that
documents the flagless form — the `## Roadmap Issues:` header's resolution
stack — says so in the same breath, so a reader can't mistake documentation of
the default for a call site that depends on it.

Peer subcommands with the same shape, from a sweep of the clap definitions in
`crates/shirabe/src/`:

- **`shirabe validate --format`** (default `annotation`) and
  **`shirabe validate --mode`** (default `draft`). Both are value enums where
  every side is nameable, so both are governable at the call site. Skills that
  need the non-default side already name it (`--format json` for envelope
  parsing, `--mode=ready` for the merge gate and the ready-posture lifecycle
  runs). Sites that want the default side mostly leave it off today. That is the
  same exposure `roadmap populate` had, at lower stakes: an `annotation` or
  `draft` default that flipped would change what a caller gets without changing
  the surface.
- **`--dry-run`** on `shirabe finalize-chain` and on `shirabe roadmap populate`
  is a presence boolean with no counterpart flag. There is nothing to pass for
  the apply side, so the mitigation is unavailable rather than skipped; it would
  take a `--dry-run` / `--apply` pair to make these governable.
- **`shirabe validate --visibility`** (default `""`, meaning auto-detect) is a
  free-string default, not a mode selector. Skills that care about the value
  pass it explicitly already.

No other subcommand pairs a defaulted flag with a nameable opposite.

The rule's limit is worth stating rather than implying. A compliant call site is
greppable — `grep -rn 'roadmap populate' skills/` and eyeballing the hits is the
whole verification — but nothing detects a default flip at a **non**-compliant
one, at any probe depth. Passing the flag is a mitigation applied by the caller.
There is no check behind it, and there cannot be one: the surface a check would
read is identical on both sides of the flip.

## No version, ever

The check never parses a version string and never compares one. No declaration
carries a version number or a version floor, and neither does this file.

That's settled, not open. The authority is
[`DECISION-skill-preflight-verification-depth-2026-08-14.md`](../docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md),
which records the argument and the evidence behind it. Don't re-derive it in a
review thread.

## The record format

Four tab-separated fields per record, with a mandatory schema line first:

```
#schema	skill-requires/v1
<tool>	<subcommand>	<flags>	<when>
```

Field one is the tool name, which must also appear as a tool in
`scripts/lib/tool-routes.tsv`. Field two is the full subcommand path including
its spaces (`roadmap populate`, `context add`), because that's the string the
probe hands to `--help`, or a literal `-` for an independent-cadence tool. Field
three is a comma-separated flag list with no spaces, or `-` for none. Field four
is `always` or `mode:<name>`.

Every field is mandatory, and `-` is the explicit empty value rather than an
empty field. Two reasons. A trailing empty field is invisible in a diff and
vulnerable to an editor that trims trailing whitespace. And an entry that forgets
its mode marker has to fail the scan rather than quietly become
always-required.

The rest of the format:

- **Line kinds.** Exactly three: a line whose first character is `#` is a
  comment and is skipped, a line that's empty or whitespace-only is skipped, and
  every other line is a record carrying exactly three tabs. The comment rule is
  what makes the `#schema` line legal.
- **The schema line.** Required, and it must be the first line. The reader
  compares the token literally against `skill-requires/v1`. Any other value, or
  no schema line at all, is a hard error naming the skill rather than a
  best-effort parse.
- **Whitespace.** Leading and trailing whitespace on a record is stripped before
  the tab count. Whitespace inside a field is significant only in field two,
  where it separates path elements and runs of spaces collapse to one. No other
  field may contain a space.
- **Commas in flags.** Comma is field three's intra-field separator, there's no
  escaping mechanism, and a flag whose own name contains a comma can't be
  declared. The character allowlist turns that into a rejected, reported record
  rather than a silent mis-split. Nothing in either binary's help output has one
  today; if one ever appears, the schema gets a new version rather than an
  escape.
- **Field order.** Not significant. Records are read in file order only so the
  output is stable, and the report re-sorts by posture anyway.

A file containing only the schema line is an explicit empty declaration. An
absent file is undeclared and fails the scan. The difference is decidable by
`ls`.

## Adding an entry

Add the entry in the same change as the call, in the same PR. Never as a
follow-up.

1. You add or change a `shirabe` or `koto` command line in a skill's phases. Open
   that skill's `skills/<name>/requires.tsv`.
2. Write one record per subcommand path the call uses. `koto context add` is one
   record with `context add` in field two, not two records.
3. In field three, name only the flags the call's behaviour depends on. If the
   call works the same without a flag, leave it out. You aren't predicting which
   flags will drift.
4. In field four, write `always` if the call happens on every run of the skill,
   or `mode:<name>` if it only happens in a named execution mode. The mode name
   is an interface: it has to match a mode string the skill's own phases use.
5. For a `gh`, `jq`, `git`, or `python3` call, one record with the tool name and
   `-` in fields two and three is the complete and correct entry.

A worked sidecar:

```
#schema	skill-requires/v1
# Split rule: references/tool-declaration-policy.md
koto	context add	-	always
shirabe	roadmap populate	--no-issues	always
gh	-	-	mode:issues
```

## What the conformance scan checks

`scripts/check-skill-requires.sh` runs in CI and checks six things: that every
skill directory has a sidecar, that every record carries exactly four fields,
that every field matches its character allowlist, that every tool name appears in
`scripts/lib/tool-routes.tsv`, that declared flags match the flags extracted from
the skill's own command lines, and that declared mode names match the mode
strings in the skill's own phases.

Flag extraction is the check that catches omission, which is the one failure
mode a description can still have. When a record trips the cadence split, the
scan's failure text names this file.

The load-time reader enforces the same field rules independently, and it's the
load-bearing copy. CI runs after the fact, while a reviewer with the plugin root
pointed at a PR checkout loads that branch's declarations before CI has seen
them.

## Moving a tool between the lists

Editing this file is how a tool moves. There's no configuration key and no
per-skill override.

The edit lands in the same PR as the declaration changes it forces. Promoting a
tool to the coupled list means every sidecar naming it grows subcommand records
in that PR; demoting one means those records collapse to a tool-only form in that PR. A
membership change that ships ahead of its declarations leaves the corpus in a
state where the scan's failure text points at a rule the sidecars don't follow
yet, which is exactly the confusion the stated policy exists to prevent.

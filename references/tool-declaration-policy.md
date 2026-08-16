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

## Verifying a mode-scoped record

A `mode:<name>` record is not checked when the skill loads. It can't be: the
skill hasn't chosen a mode yet, and a check that reported the record satisfied
or unsatisfied at that point would be reporting an evaluation it never made. The
load-time report is therefore silent about mode records entirely -- not
"deferred", not "skipped", nothing. The deferral is visible in field four, which
a reader inspects without running anything.

The record still gets verified. The skill runs the check itself, at the step
that selects the mode:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> --mode <name> 2>&1 || true
```

That run evaluates the `mode:<name>` records and only those. The `always`
records were checked at load and are not re-reported; a second copy of a block
the model has already read is exactly what the zero-byte rule exists to prevent.
Everything else matches the load-time report: the same block shapes, the same
four unsatisfied cases, zero bytes when every matching record is satisfied, and
exit 0 on every path. A mode name that matches no record is silent too, so
adding the call to a skill that turns out to need no mode record costs nothing
and says nothing.

**This is not an injected line, and it must never be written as one.** The
load-time check is a `!`-prefixed command at column 0 in SKILL.md, resolved by
the harness before the model sees the body, covered by an `allowed-tools` entry
in the same file, and checked by `scripts/check-skill-injection.sh`. The
mode call is none of those things: it is an instruction in the skill's prose
that the agent follows mid-run, like every other command a phase tells it to
run. `scripts/check-skill-injection.sh` reads only lines beginning with `` !` ``
at column 0, so it never sees this one, and the `allowed-tools` frontmatter
governs the injected line rather than this call.

The `2>&1 || true` guard is carried anyway, and it is not optional. A missing
script or an unexpanded `${CLAUDE_PLUGIN_ROOT}` still exits 127, and every
argument for swallowing that at load applies with more force at a phase
boundary, where a run that dies has already written state.

Where a skill has no mode-scoped record, it makes no mode call, and the reason
is written down at the step that selects the mode rather than left as an
absence. `/plan`'s step 3.6 is the worked example.

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

The check runs one way. An extracted flag that no record names is a finding; a
declared flag the extractor never sees is not, because a call can live in prose
the extractor doesn't read and because over-declaring costs a probe rather than
a missed prerequisite.

Extraction is scoped so that a fixture or an eval scenario is never read as a
call: `evals/` and `*_test.sh` are out, a skill's files are searched only inside
its own directory, a shell comment isn't a command line, and in Markdown a
command has to sit inside an inline-code span or a fenced block.

## Turning the check off

`SHIRABE_PREFLIGHT_DISABLE` is the kill switch. Set it to anything other than
empty, `0`, or `false` and `scripts/skill-preflight.sh` short-circuits to
silence and exit 0 before it resolves the plugin root or sources anything. It
is the same shape as `PR_BODY_HOOK_DISABLE` in
`crates/shirabe/src/pr_body_hook.rs`, so the plugin has one spelling for
"operator turned this off" rather than one per subsystem.

Setting it means the check does not run. No declaration is read, no tool is
resolved, no report is produced — and since a satisfied host is silent too, a
session with the variable set looks exactly like a session where every
prerequisite was met. It is for a host where the check itself is the problem,
and for a harness that needs a skill body to arrive byte-identical to how it
arrived before this subsystem existed. It is not a way to make a report go
away: the report is the finding.

It doesn't weaken anything. There is no path where a declaration is read less
strictly, a resolution refusal is relaxed, or a block is suppressed after being
rendered — either the whole check runs or none of it does.

`scripts/run-evals.sh` sets it, and the reason is worth knowing because it will
recur. Tier-2 eval fixtures put shim binaries under the working directory and
prepend that directory to PATH; the resolver refuses to execute a binary that
resolves under `$PWD`, correctly, and emits a "was not probed" block. Those
evals are transcript-graded, so the block silently changes the input to every
scenario in the corpus. The fix is to not run the check inside the harness, not
to teach the resolver to trust a working directory.

The exception is the liveness eval in `skills/inflight/evals/evals.json`, which
runs with the variable cleared. Its whole subject is whether the injected line
still executes; disabling the check there would make it assert nothing.

## When the text is a citation, not a call

A skill's files carry two kinds of `shirabe validate --x` text and nothing
mechanical separates them. `skills/plan/SKILL.md` documents the validator's
whole-tree mode, which CI runs and `/plan` never invokes; `skills/design/`
names `shirabe validate --lifecycle-chain <prd-path>` as the authority for a
posture check it does make. Same shape, opposite answer.

So the judgment is written down, in the declaration, next to the records it
qualifies:

```
#not-a-call-site	skills/plan/SKILL.md	shirabe	--lifecycle	Documents the validator's whole-tree mode, which CI runs; /plan does not.
```

Five fields. It's a comment line, so the load-time reader skips it as it skips
any other. The path is repo-relative and has to sit inside the declaring
skill's own directory, so an exemption can't reach across a skill boundary. The
reason is mandatory. An exemption that stops matching an extracted flag fails as
stale, in both directions like the discard enumeration, so the list can't rot
into a permanent allowlist: edit the line it exempts and the judgment comes back
through review.

Reach for it only when the text really is a citation. The default answer to the
finding is to add the flag to the record.

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

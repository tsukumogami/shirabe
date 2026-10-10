# The skill-session convention: a skill's state in its own koto session

The normative rule for where a shirabe skill keeps its working state, how a
chain parent and its children find each other's state, and when that state can
be reclaimed. Normative prose like
[`koto-session-retention.md`](koto-session-retention.md): no skill loads this
file at runtime, and it is reviewed as part of a PR. A skill that follows the
convention cites it at the point it opens, reads or closes a session, in one or
two sentences, and calls `scripts/skill-session.sh` for the operation instead
of restating it.

The convention replaces the files skills kept in the staging folder, where the
folder was also the interface between them: a parent signalled a child through
a block in a state file, detected a mid-flight child from that child's files,
and skills run inline read each other's files. The decisions behind it, and
the alternatives they rejected, are in
`docs/designs/current/DESIGN-resume-convention.md`.

It describes koto 0.15.0 and later, shirabe's koto minimum
(`scripts/assert-koto-floor.sh`).

## The pieces

- **`koto-templates/skill-session.md`**, at the plugin root: the store
  template. One non-terminal state, `open`, which accepts `close: done |
  abandoned` and moves to the terminal state of that name. A first tick stops
  at `open` and the session stays there until it's closed. A skill with no
  koto template of its own opens its session from this file. The file name is
  part of the contract: `koto init --attach-live` compares a live session's
  template by file name, so renaming it makes every live session refuse to
  attach.
- **`scripts/skill-session.sh`**: every operation the convention repeats, one
  subcommand each. Its header documents arguments, output lines and exit
  codes. Every subcommand checks its arguments before any koto call.
- **`scripts/skill-session_test.sh`**: runs every subcommand against real koto
  in a store isolated by `KOTO_SESSIONS_BASE`, including a parent and a child
  run end to end.

## The convention, rule by rule

### Session naming

A skill's session is `<skill>-<topic>`: the skill's directory name, a hyphen,
and a topic that has passed `^[a-z0-9][a-z0-9-]*$`. The skill name matches
`^[a-z][a-z-]*$`. `skill-session.sh name <skill> <topic>` composes it.

The name is recomputed at every use and never read back from a key. Every
session is a root: no skill passes `koto init --parent`, and nothing a chain
needs rests on parent-child lineage, the request store or a request leg. A
skill opens its own session at its first phase, from its own koto template if
it has one and from the store template otherwise
(`skill-session.sh open <skill> <topic>`).

### Key naming

A staging-folder file `<skill>_<topic>_<rest>` becomes key `work/<rest>` in
`<skill>-<topic>`, and one in the folder's research directory becomes
`research/<rest>`, with `<rest>` kept byte for byte. A resume table's "file
exists" row becomes a "key exists" row, one for one.

The areas are fixed:

| Area | Holds | Written by |
|------|-------|------------|
| `work/` | the skill's own working files | the session's own skill |
| `research/` | agent outputs, reviewer verdicts | the session's own skill (through `ingest`) |
| `chain/` | what passes between a parent and a child: `chain/dispatch`, `chain/roadmap-scope`, `chain/parent` | the parent writes `dispatch` and `roadmap-scope` in its own session; the child writes `parent` in its own |
| `handoff/` | what one skill leaves for another's entry (`handoff/scope.md`, `handoff/charter.md`) | the leaving skill |
| `session/` | the convention's bookkeeping: `session/branch` | `skill-session.sh` |
| `record/`, `legs/` | reserved for coordinator state | no skill under this convention |

A skill run inside another skill's session writes under a sub-area there:
`/decision` run by `/design` writes `work/decision-<N>/<rest>` in
`design-<topic>`.

koto's key grammar takes `/`-separated components, each starting with a letter
or digit followed by letters, digits, `.`, `_` or `-`, at most 255 bytes in
all. A `<rest>` the grammar refuses has each character outside
`[A-Za-z0-9._-]` replaced by `-`, and an `x` prefixed to any component that
doesn't start with a letter or digit. No current file needs it.

**Sub-agents never write keys.** The orchestrator allocates a private
directory with `skill-session.sh scratch` (mode 0700, outside the work tree),
the agent writes its file there under the pinned name, and the orchestrator
runs `skill-session.sh ingest <session> research <dir>`, which adds each plain
file as `research/<name>` and removes the directory. A key-held document an
agent edits in place is materialized with `skill-session.sh get <session>
<key> <dir>` into such a directory, edited, and written back with `put`.

### Per-skill keys

Each moved skill's files and the keys they become. `<t>` is the topic; `<N>`,
`<role>`, `<k>` and `<id>` are the placeholders the skills use today. Files
named with a leading `_` carry the skill's own `<skill>_<t>` prefix.

| Skill | Files today (in the staging folder) | Keys, in `<skill>-<topic>` |
|-------|--------------------------------------|----------------------------|
| `/scope` | `scope_<t>_state.md` | `work/state.md`; `work/prior-run.md` after a replace |
| `/charter` | `charter_<t>_state.md`; `roadmap_<t>_scope.md` it pre-populates | `work/state.md`; `chain/roadmap-scope` |
| `/brief` | `_context.md`, `_discover.md`; research `_phase4_<role>.md` | `work/context.md`, `work/discover.md`; `research/phase4_<role>.md` |
| `/prd` | `_scope.md`, `_decisions.md`; research `_phase2_<role>.md`, `_phase4_<role>.md` | `work/scope.md`, `work/decisions.md`; `research/phase2_<role>.md`, `research/phase4_<role>.md` |
| `/design` | `_summary.md`, `_decisions.md`, `_coordination.json`, `_decision_<N>_report.md`; research `_phase5_*`, `_phase6_*` | `work/summary.md`, `work/decisions.md`, `work/coordination.json`, `work/decision_<N>_report.md`; `research/phase5_*`, `research/phase6_*` |
| `/decision` (run by `/design`) | `design_<t>_decision_<N>_{context,research,alternatives,bakeoff_<k>,examination}.md` | `work/decision-<N>/{context,research,alternatives,bakeoff_<k>,examination}.md` in `design-<topic>` |
| `/decision` (direct) | `<prefix>_{context,…,report}.md` | `work/<file>` in `decision-<topic>` |
| `/plan` | `_analysis.md`, `_milestones.md`, `_decomposition.md`, `_dependencies.md`, `_decisions.md`, `_manifest.json`, `_mapping.json`, `_issue_<id>_body.md` | `work/` plus the same name each |
| `/review-plan` | `plan_<t>_review.md`, `plan_<t>_review_loopback.md` | `work/review.md`, `work/review_loopback.md` in `plan-<topic>` |
| `/vision` | `_scope.md`, `_decisions.md`; research `_phase2_*`, `_phase4_*` | `work/scope.md`, `work/decisions.md`; `research/phase2_*`, `research/phase4_*` |
| `/strategy` | `_context.md`, `_discover.md`; research `_phase4_*` | `work/context.md`, `work/discover.md`; `research/phase4_*` |
| `/roadmap` | `_scope.md`; research `_phase2_*`, `_phase4_*` | `work/scope.md`; `research/phase2_*`, `research/phase4_*` |
| `/explore` (handoff only) | `scope_<t>_handoff.md`, `charter_<t>_handoff.md` | `handoff/scope.md`, `handoff/charter.md` in `explore-<topic>` |

`/review-plan` names its files with `/plan`'s prefix, so by the mapping it
reads and writes `/plan`'s session, `plan-<topic>`. Run directly on a topic
with no `plan-<topic>` session, it reviews the PLAN document alone, opens
`plan-<topic>` to write its verdict, and closes it when it finishes, since it
opened it.

### Finding a session by name, on one host

A reader recomputes the name and runs `skill-session.sh status <session>`,
which prints `absent`, `live` or `finished` from `koto status` without
advancing anything. A reader may read a finished session's keys but never
resumes it; the next `open` of that name replaces it, and the old keys go with
it.

Session names are machine-wide, so two worktrees of one clone can compute the
same name. `open` writes `session/branch`, the current git branch, which git
allows in only one worktree of a clone, and refuses a detached HEAD. Every
cross-session read that acts on what it finds compares that key with the
reader's own branch and treats a mismatch as absent: `dispatch read`,
`close-children`, and `has-work` from a parent. `open` refuses to attach to a
live session whose `session/branch` names another branch, and koto's own
`--attach-live` already refuses a session opened from another worktree.

`skill-session.sh has-work <skill> <topic>` is how a parent tells that a child
was mid-flight: it exits 0 when the child's session is live, belongs to the
current branch, and holds a key under `work/`.

### Finding a session after an import

An import keeps the session name (unless `--as` is given) and carries every
key byte for byte, and the branch name means the same on the new host.
Importing every session in a chain's set (the table under Session sets) under
its own name therefore gives the second host a resumable chain with no
rewrite. An import under another name breaks the lookup and is outside the
convention.

### The dispatch key

A parent tells a child it runs under a chain through key `chain/dispatch` in
the parent's own session. The parent writes it immediately before invoking a
child (`skill-session.sh dispatch write <parent> <topic> <child>
<fresh-chain|revise> [--no-suppress]`), removes it immediately after the child
returns (`dispatch clear <parent> <topic>`), and removes any it finds at its
own start, which is how a key a crashed run left behind stops misleading the
next one.

The value is exactly three YAML lines:

```yaml
child: design
suppress_status_aware_prompt: true
rationale: fresh-chain
```

`child` is one of the parent's fixed children, `suppress_status_aware_prompt`
is `true` or `false` (`false` under `--no-suppress`), and `rationale` is
`fresh-chain` or `revise`: the fields the `parent_orchestration:` block
carried. What changes in a child's behaviour under the signal stays as
[`fixes/sub-agent-dispatch.md`](fixes/sub-agent-dispatch.md) states it; only
the carrier moved.

The parents and their children are a fixed, closed set:

| Parent | Children |
|--------|----------|
| `scope` | `brief`, `prd`, `design`, `plan` |
| `charter` | `vision`, `strategy`, `roadmap` |

`dispatch write` refuses a child that isn't in the parent's list. When the
parent's session has no `session/branch` (a parent opened from its own
template rather than through `open`), `dispatch write` records the current
branch there; when it names another branch, the write is refused.

A child reads the signal with `skill-session.sh dispatch read <child>
<topic>`, which checks `scope-<topic>` and `charter-<topic>` by name. A parent
session is no match when it is absent or finished, when its `session/branch`
is missing or names another branch, when it holds no `chain/dispatch`, or
when the value fails re-validation: anything but the three lines, a `child`
outside the closed set of children, the other two fields outside their sets,
or a `child` naming another skill. One match prints `parent=`, `child=`,
`suppress_status_aware_prompt=` and `rationale=` lines; no match prints
nothing and exits 0; two matches print nothing, name both sessions on stderr,
and exit 3, so a forged or stale key in the other parent stops the child
rather than choosing for it.

A child records what it matched as its first act:
`skill-session.sh adopt <child> <topic>` writes `chain/parent`, the matched
parent's session name, into the child's own session, or removes a
`chain/parent` an earlier chained run left when nothing matched. A child that
runs directly therefore never carries a stale parent.

### Closing

Every `koto next` a skill or the script issues carries `--no-cleanup`, so a
close keeps the session and its keys stay readable;
[`koto-session-retention.md`](koto-session-retention.md) carries the
argument. `skill-session.sh close <session> <done|abandoned>` submits the
close evidence to a live store-template session, prints koto's `retention`
object, and leaves a finished or absent session alone.

- A chain child never closes its own session.
- At its exit the parent writes `exit` to its own state, then runs
  `skill-session.sh close-children <parent> <topic> <done|abandoned>`, then
  closes itself last. `close-children` closes each child in the parent's fixed
  list whose session is live, whose `chain/parent` equals the parent's
  recomputed name, and whose `session/branch` is the current branch,
  re-reading all three immediately before the close. Closing is idempotent, so
  a parent that crashes between writing `exit` and the closes finishes them on
  its next run, and a closed parent never leaves live children behind.
- A direct run closes its own session when it finishes.
- A consumer of a handoff closes the `explore-<topic>` session once it has
  removed the handoff key and the session holds no other key.

### The reclaimable rule

A session is reclaimable when it is finished and either has no `chain/parent`,
or its `chain/parent` string-equals `scope-<topic>` or `charter-<topic>` for
its own topic and that session is absent or finished. A live session is not
reclaimable, nor is an absent one. A malformed `chain/parent` (another topic,
another shape, a trailing newline) makes a session non-reclaimable: the value
is compared, never interpolated. `skill-session.sh reclaimable <session>`
prints `yes` or `no`; it derives the topic by removing the skill prefix,
matched longest first against the skills the convention knows, and answers
`no` for a name whose skill it doesn't know.

The rule never frees a session a live parent may still read. This convention
only evaluates it; deleting is later prune work, which should also keep a
finished `scope-` or `charter-` session until its next run has consumed the
replaced result.

### Content assembly and koto's absence

Content for a key is assembled only in a private per-run directory outside the
work tree (`scratch`), and `ingest` removes that directory on every exit path,
a failed key write and a signal included. `ingest` takes only regular,
non-symlink files directly in the directory, with names matching
`^[A-Za-z0-9][A-Za-z0-9._-]*$` and under 1 MiB, and reports each entry it
skips, so an agent that writes a link to a host file can't get that file's
content into a key. `get` and `put` refuse a key outside the session's own
`work/` and `research/` areas, a key or path containing `..`, and a path
outside a scratch directory.

A skill under the convention stops when koto is missing or below the floor; it
never falls back to the staging folder. `open` checks the floor through
`scripts/assert-koto-floor.sh` and stops with a message naming koto: exit 127
when koto is not on `PATH`, exit 69 when it is too old.

### Session sets

The session names a chain uses, which are also the set an import moves:

| Chain | Parent | Children (and inline skills) | Handoff |
|-------|--------|------------------------------|---------|
| tactical | `scope-<topic>` | `brief-`, `prd-`, `design-`, `plan-<topic>`; `/decision` inside `design-<topic>`, `/review-plan` inside `plan-<topic>` | `explore-<topic>` |
| strategic | `charter-<topic>` | `vision-`, `strategy-`, `roadmap-<topic>` | `explore-<topic>` |

### The reserved coordinator areas

For later coordinator work, written by no skill this convention moves: a
coordinator's own session keeps its stored set under `record/` and each
worker's result under `legs/<request-id>/<leg>`, so an import carries both.
Session names beginning `coordinate-` belong to the coordinate skill.

### Limits

A skill's state is local to its host until session import is applied to skill
sessions; until then a replacement on another host reaches none of it, as it
reaches none of it through koto today. No chain may rest on koto parent-child
lineage, since an import neither carries children nor accepts a child as its
source.

## Security

- **Names reach koto commands.** Every session name is composed from a fixed
  skill name and a checked topic, or checked against
  `^[a-z][a-z-]*-[a-z0-9][a-z0-9-]*$`, before any koto call. A `chain/parent`
  or `chain/dispatch` value read from a session is compared against a closed
  set and never placed on a command line, so a tampered key can't redirect a
  close, a removal or a prune.
- **Forged keys.** A forged `chain/dispatch` can at most make a direct run of a
  child behave as a chain child (skip its push and routing prompt); a forged
  `chain/parent` can at most get a session closed early, and a closed session
  stays readable.
- **Key content is data.** Research outputs, handoffs and verdicts read back
  from keys are untrusted text, and agents reading them keep the
  fixed-preamble discipline the reviewer prompts use. Values from keys reach
  commands only through `jq --arg` or as compared strings.
- **Retention.** Sessions are kept until the later prune work exists. Nothing
  secret belongs in a key; with koto's cloud backend configured, keys sync to
  the configured bucket, which needs the same access control as the
  repositories whose work it holds.

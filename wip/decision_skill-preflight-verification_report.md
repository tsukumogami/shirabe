<!-- decision:start id="skill-preflight-verification" status="assumed" -->
### Decision: What a skill-load prerequisite check verifies about a host tool

**Context**

shirabe's twenty skills reach for six host tools and almost none of those calls
says what it needs or checks that it is there. The accepted BRIEF
(`docs/briefs/BRIEF-skill-preflight-checks.md`) carries the question forward as
its first Open Question, noting that two committed artifacts already disagree:
`references/fixes/cli-version-preflight.md` argues for probing `--help` per
subcommand, while `.tsuku-recipes/shirabe.toml` verifies against `shirabe
--version`. All five filed incidents are skew or a never-shipped file, not
absence. The highest-severity one, shirabe#279, succeeded silently: `/execute`
called `koto context set`, a subcommand koto does not have, the error was
filtered by `2>/dev/null`, the step reported success, and twelve children would
have dispatched against a branch nobody created.

Two prior positions cut against the obvious shapes. PR #278 chose a CI matrix
over a runtime version guard, arguing "a pattern list only catches what its
author remembered." `DESIGN-shirabe-pattern-v1-ergonomics` Decision 6 rejected
per-skill inline probes in favour of lazy-loaded prose — which became
`cli-version-preflight.md`, which no skill cites, so it never loads.

The check must run on every skill load, stay silent when satisfied (identical
rendered content is deduplicated on re-invocation; differing content re-appends
the whole skill body), never hard-block, and print a host-appropriate
instruction when unsatisfied.

**Assumptions**

- Counting granularity for (tool, subcommand) pairs is first-level. If wrong,
  per-skill counts roughly double; the declaration-bound conclusion is
  unaffected.
- `build.rs` as read reflects shipped release binaries, so
  `cli-version-preflight.md`'s `shirabe-unknown` claim is stale documentation.
- One-call-per-tool `--help` enumeration generalizes across shirabe and koto
  versions; verified against installed versions, not every historical tag.
- Made in `--auto` mode without user confirmation, hence status `assumed`.

**Chosen: Presence plus declared surface, including declared flags — and no version comparison**

The check verifies three things about a host tool, and nothing else:

1. **The tool resolves** to an executable on this host.
2. **Every subcommand the declaration names** appears in the tool's advertised
   command surface.
3. **Every flag the declaration names** appears on its subcommand's surface.

A declaration names a flag only where the call's behaviour depends on it — not
every flag passed, and explicitly not flags an author guesses might be
skew-prone. A tool declared with no subcommands is verified for presence alone,
by the same rule rather than a separate verb; this is how `gh`, `jq`, `git`,
`python3`, and `curl` are covered, and it is the complete and correct answer for
them, since not one carries a surface incident anywhere in the record.

The check never parses a version string and never compares one.

The result is three states: **satisfied**; **missing** (the tool does not
resolve); and **present-but-incomplete** (the tool resolves but a declared
subcommand or flag is absent). The third state is the prior art's
"present-but-insufficient" grounded on a directly observed fact rather than a
semver inference, so flutter's three-state model survives intact without a
floor. "Install it," "upgrade it," and "source your env file" stay distinct
instructions.

**Rationale**

Every filed incident is skew rather than absence, so presence alone would have
caught one of five; and shirabe#279 is reachable only by asking whether the
surface the skill calls actually exists, since `koto context set` has never
existed in any koto commit and no version floor could ever have caught it. The
cost objection that made surface probing look expensive turned out to be
mistaken: `shirabe --help` and `koto --help` enumerate their entire command list
in one invocation, so verification costs one call per tool plus one per nested
group reached plus one per flag-bearing subcommand — 6-9 calls at roughly 2ms
each in the worst case (`/work-on`), under 100ms, with six of twenty skills
declaring nothing and paying zero. Flags are included because the skill bundle
and the binary are versioned and shipped independently and are skewed in
practice — the bundle that ran this decision is 0.16.1-dev against a v0.16.0
binary — so a skill calling `validate --pr-body` on an older host is a routine
reachable state, and `validate` accreted exactly those flags after it shipped.
Version floors are excluded because no floor is derivable from the working tree,
the only floor the repo ever declared has already drifted five minor versions
between its skill-facing copies and its design doc, the `-dev` prerelease
comparator is a trap with no existing code to model on, and the one tool that is
floor-natural was already carved out by the maintainer in PR #278.

What it costs: a declaration that must name subcommands and the flags a call
depends on, which is more to write than a tool name, and a bound ("the flags the
call actually depends on") that is descriptive rather than mechanical and that
nothing enforces.

What it fails to catch: semantic drift behind a stable surface — `roadmap
populate --no-issues` kept its name and flipped its default in #264, so every
probe passes and behaviour still differs. Interpreter syntax floors like
shirabe#270, which PR #278 already routed to CI and whose fix removed the
dependency outright. And any runtime failure after the surface check passes: a
bad positional value, an auth failure, a network error.

**On PR #278's objection — the line this decision has to argue past**

C's claim that the objection now cuts against D rather than against C is
**upheld**, and it is upheld on this repo's own data. The one flag shirabe
pre-labeled as skew-risky, `--superseded-by`, was added in the same commit that
created `transition` and never skewed. The flags that actually accreted after
their subcommand shipped — `--coordination-body`, `--merge-gate`, `--pr-body`,
the `--format` lifecycle modes, `--no-issues` — were named as a risk nowhere. A
scoped compromise that asks authors to flag skew-prone flags in advance is
therefore precisely the pattern list #278 discredited, and the repo's own
authors have not performed that prediction correctly even once.

But the objection does not reach the declaration this decision adopts, and the
distinction is **prediction versus description**. #278's pattern list, B's
version floor, and D's scoped-flag compromise are all predictions: which
constructs will recur, which version will carry a feature, which flags will
skew. Each can be wrong while the code around it stays correct, which is how
they rot silently. A declaration of what a call depends on is a description of
the present call, written by the same author in the same change. It cannot go
stale while the call stays correct, because the author cannot get the
description wrong without also getting the call wrong.

That defence has a real limit and it should be recorded rather than smoothed
over: `run-cascade.sh` calls `jq` nineteen times with zero guards, and
`/inflight` invokes `shirabe work-summary render` with no declaration at all, so
authors in this repo demonstrably do forget. The claim is not that description
is immune to omission — it is that description does not silently *drift* the way
a prediction does, which is the specific failure #278 named.

**Alternatives Considered**

- **A, presence only** (`command -v`). Not rejected so much as **absorbed**: it
  is what the chosen rule does for a tool declared without subcommands, and it
  remains the necessary first step of every richer check. Insufficient as the
  whole answer because it catches one of five filed incidents and misses
  shirabe#279 entirely. Its advocate conceded this in revision.
- **B, presence plus version floor.** Rejected as a gating verb. Structurally
  incapable of catching shirabe#279 (`koto context set` never existed at any
  version); no floor derivable from the working tree; the repo's one declared
  floor already drifted (koto >= 0.3.3 in README and SKILL.md versus >= 0.8.0 in
  the design doc); the `-dev` prerelease comparator has no existing
  implementation to model on; and PR #278 already declined a runtime floor for
  the one floor-natural tool. Its advocate retreated to advisory-only.
  Its genuine contribution survives elsewhere: GitHub Release bodies *are*
  structured and issue-linked, which means a detected gap can point somewhere
  concrete — a remediation improvement, not a change to what is verified.
- **C, presence plus per-subcommand-and-flag probe.** **Adopted for its scope
  question.** Its rule as revised — probe whatever flag a call actually depends
  on, rather than flags anyone predicts are risky — is the chosen bound.
- **D, presence plus declared-surface enumeration.** **Adopted for its
  mechanism.** One enumeration call per tool rather than one probe per
  subcommand is what makes the chosen answer affordable at every skill load. Its
  scoped-flag compromise was rejected on C's evidence.
- **E, author-declared verification depth.** Withdrawn by its own advocate. A
  tool declared with no subcommands yields presence by construction, so the
  depth verb never varies from what the tool dictates and adds vocabulary
  without adding expressiveness. Its corpus-partition finding survives as
  independent corroboration of the chosen rule.

**Consequences**

shirabe#279 becomes detectable at load, cheaply and silently, which is the
incident that motivated the feature. Six of twenty skills declare nothing and
pay nothing. The version-parsing surface — seven incompatible `--version`
formats, the `-dev` precedence trap, the `0.0.0` local-build fallback — is
removed from the problem entirely rather than solved.

`references/fixes/cli-version-preflight.md` is superseded on its central
argument, which it wins: surface probing over version comparison. Its documented
per-subcommand sed-edit fallback remains the answer to a detected gap, since no
version→feature map exists to name an upgrade target.

Declarations become the place a reviewer reads to see what a skill requires, and
maintaining them is real ongoing work. The flag bound is a judgment call that
nothing enforces; if it drifts toward "every flag passed," cost rises without
benefit, and if it drifts toward nothing, the #279 class reopens one level down.

Two requirements fall out that this decision does not itself answer and that the
PRD must carry separately. **Neither the check's own probes nor any skill call
site may discard stderr or ignore an exit code** — validators A and D
independently established that shirabe#279 was silent purely because of
`2>/dev/null` plus an unchecked exit status, and that clap reports an unknown
flag and an unknown subcommand identically (exit 2, clear message). This stands
regardless of the verdict, and it has a sharper form: a preflight whose own
probe redirects stderr to `/dev/null` reproduces the exact defect it exists to
prevent. And **the exit-code contract needs a bucket for surface failure**:
`/charter` (`references/phases/phase-finalization.md:165-198`) and `/scope`
(`SKILL.md:615-637`) both branch on 0 clean, 2 violations, 1 tool-error, and
both were confirmed in cross-examination to collide — a clap usage error exits
2 with no `shirabe-validate/v1` envelope on stdout, so it is read as a content
violation and sends the author to fix a document that is not wrong, while exit
1, the code explicitly reserved as "DISTINCT from a content violation," is not
the code a surface failure returns. Any tool carrying an application-level
exit-code contract needs its CLI-surface-failure signal kept structurally
distinct from that contract. This is the misdiagnosis the prior art warns is
worse than no check at all.

**PATH-invisibility remains orthogonal and unaddressed**: distinguishing "not
installed" from "installed under `~/.tsuku/tools/current/` but not on this
shell's PATH" cannot be done by any of the five alternatives, and the BRIEF's
"Installed, invisible" journey requires it. It must be built regardless.

Two further items surfaced in cross-examination and belong downstream rather
than here. **Multi-version binding ambiguity is the precondition for flag
skew and needs its own resolution**: shirabe#217 reports three shirabe copies
on disk with the reporter unable to say which one an invocation binds to, and
which binary a workspace-managed tool call resolves to should not be ambiguous.
Fixing that shrinks the problem this decision addresses; leaving it makes flag
skew routine rather than rare. And **the default-flip shape needs authoring
discipline, not verification**: since no probe can see a changed default, the
mitigation is to always pass the mode flag explicitly — `--issues` or
`--no-issues` — and never rely on a default. Both validators named this
independently and both placed it outside any alternative's reach.
<!-- decision:end -->

---
schema: design/v1
status: Planned
problem: |
  Upstream-link legality is written in prose across format references and skill
  files, and nothing carries it to the moment a link is created. The validator
  has no representation of an artifact type's lifetime or of which types may sit
  above it, so a brief naming a design validates clean and a durable document
  naming a document scheduled for deletion validates clean too.
decision: |
  Two declarations move onto FormatSpec — a lifetime class and a legal-parent
  set, both keyed by a new FormatId enum — and one check function reads them
  inside validate_file after the schema gate, emitting a direction code and a
  lifetime code with the lifetime taking precedence. The roadmap link moves off
  the brief and onto the plan through a --upstream flag /plan gains, and
  /brief keeps both roadmap input routes as grounding that records nothing.
rationale: |
  Declaring both facts beside the type's other structural facts makes the
  maintainer journey work and lets a plain unit test enforce that no durable
  type declares a working parent. One check function rather than two is chosen
  because a shared classifier feeding two emitters is that one function with an
  extra indirection, while suppression downstream of the finding boundary is not
  expressible at all: a finding carries no entry index. Placing the check after
  the schema gate is what keeps the golden corpus byte-identical.
upstream: docs/prds/PRD-upstream-link-legality.md
---

# DESIGN: Upstream Link Legality

## Status

Planned

## Context and Problem Statement

The `upstream:` field is the only durable record of a document's lineage, and
the system has no representation of what makes one legal. Two properties are at
stake and neither is enforced: the direction of the link, and whether its target
survives long enough to be followed.

The validator's `FormatSpec` carries a type's required fields, valid statuses,
required sections, issues-table columns, a private-only flag, and a per-execution
mode section override. It carries nothing about lifetime and nothing about which
types may sit above it. The lifetime classes exist only as prose in eight
`SKILL.md` files — `grep -rn "Working" --include=*.rs crates/` returns nothing —
and the legal parents exist only in the format references. A hand-authored
document with either property violated passes `shirabe validate` today.

Three facts about the existing code shape the solution more than the problem
statement does.

**There is already one front door for the field.** `crates/shirabe-validate/src/upstream.rs`
normalizes `upstream:` into entries for all three of its readers, deciding four
semantics: placeholders are skipped, cross-repo values are marked rather than
removed, entries are trimmed and blanks dropped, and entries come back as
written rather than resolved. A new reader has a front door to use rather than a
normalizer to write.

**The type of a target is derivable without reading it.** `detect_format` is
longest-prefix matching over a basename. Legality is therefore a pure function
of two strings, which is what keeps the check out of the document index and,
with it, keeps `docs/visions/` and `docs/strategies/` out of the orphan rule
they were never written for.

**One golden fixture is protected only by the schema gate.**
`crates/shirabe/tests/fixtures/golden/corpus/real/PRD-roadmap-skill.md` carries
`upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md` — a durable document
naming a working one, and an illegal edge on both properties. Its frozen
expected output is a single `schema field missing, skipping` notice and exit 0,
because the file has no `schema:` field and `validate_file` returns at its first
statement. The independent proof that the gate is what protects it: that
upstream path does not resolve relative to the corpus directory, so the existing
resolution check would already be reporting a dangling link if anything ran past
the gate. It does not. Byte parity with that fixture is a real constraint on
where the new check may be called, not a theoretical one.

## Decision Drivers

**The maintainer journey is the requirement that shapes the data model.** A
maintainer adding an artifact type must declare its lifetime and its legal
parents once, beside the type's other structural facts, and get both enforced
from that declaration. That rules out any design where the declaration is
optional, lives away from `FormatSpec`, or is derived from something that only
covers part of the type set.

**No existing test may be modified and no golden fixture's frozen output may
change.** This is a hard constraint from the requirements, and it is what
decides check placement.

**A finding carries no entry index.** `ValidationError` is a file, a line, a
code, and a message. Every per-entry finding on a multi-valued `upstream:` sits
at the field's single line, because the parser records one line for the field.
Any design that needs to correlate two findings about the same entry has no key
to correlate them by.

**Existing contracts are reused rather than reinvented.** The `--upstream <path>`
flag is owned by five skills with the same parse-before-positional discipline,
the same bare-flag rejection, and the same three ordered validation checks. A
sixth skill adopting it should adopt the contract, not a variant of it — and
where it must extend the contract, the extension applies to every skill that
validates a supplied path rather than to the new one alone.

**The change is authored in each skill's own contract.** A skill records the
same value invoked standalone as it does under a parent, so no parent may
post-edit a child's frontmatter to get the outcome.

## Considered Options

### Decision 1 — where the two declarations live

**Option A: two new fields on `FormatSpec`, keyed by a new `FormatId` enum.**
`lifetime: Lifetime` with `Durable` and `Working` variants, `legal_upstream:
Vec<FormatId>`, and an `id: FormatId` field so the parent set names type
identities rather than strings.

**Option B: a separate legality module** holding a table keyed by format name,
leaving `FormatSpec` untouched. Rejected because it makes the declaration
optional where it has to be total. A maintainer adding a type gets a compiler
error for a missing `FormatSpec` field and silence for a missing table row, and
silence is the failure mode the maintainer journey exists to remove.

**Option C: derive legality from the existing chain model.** `lifecycle.rs` has
a `ChainRole` type and a terminal-status map. Rejected on inspection: between
them they cover five of the eight types, neither models VISION, STRATEGY or
COMP, and no altitude ordering exists to derive a parent set from. Deriving
would mean building the ordering first, which is Option A wearing a longer
route.

**Option D: read the `## Artifact Lifecycle` sections from the skill files at
validation time.** Rejected for two reasons that compound. It puts filesystem
I/O inside `validate_file`, which every other per-file check avoids; and the
declaration-level assertion would pass vacuously in any tree without a `skills/`
directory, which is every consumer repository.

**Why the parent set is typed rather than stringly.** `FormatSpec::name` mixes
casing deliberately — `VISION` and `PRD` are upper-case, `Design`, `Roadmap`,
`Plan`, `Strategy`, `Brief` and `Comp` are not — and `validate.rs` carries an
explicit warning against normalizing it, because the format dispatch matches on
those exact strings. A `Vec<String>` parent set would inherit that trap: an
entry spelled `"DESIGN"` instead of `"Design"` compiles, reads correctly to a
human, and silently never matches. A `FormatId` enum makes the lookup total and
gives the finding messages a display form independent of the dispatch strings.

**Why lifetime is an enum and not a `bool`.** `FormatSpec` already has
`private: bool`, so a `durable: bool` would not look out of place. The enum wins
on two counts: the finding message has to name the class ("Working"), and a
two-variant enum makes the declaration-level assertion read as a comparison
between two named classes rather than as a negation.

### Decision 2 — how the check is structured and dispatched

**Option A: two check functions**, one per property, both called from the shared
cross-format block. Rejected, and the reason is the precedence rule rather than
taste. Its strongest form is not two independent walks but a shared per-entry
classifier feeding two emitters, and that form is expressible: the normalizer
returns an ordered vector, so a position in it is a usable key *inside* a check.
What that buys, though, is Option B with an extra indirection and a second
function boundary to keep the branch order behind. Its weaker forms are worse:
recomputing the lifetime predicate inside the direction check makes the
direction check contain the whole lifetime check and leaves an unenforced
invariant that the two copies agree. What is genuinely inexpressible is
suppression *downstream of the finding boundary* — once both functions have
returned, a finding is a file, a line, a code and a message with no entry index,
and two findings about the same document sit at the same line, so a filter in
the caller would have to recover the offending entry by string-matching the
message.

**Option B (chosen): one check function emitting both codes**, called from the
shared block immediately after the resolution check. Precedence becomes branch
order inside one loop over one entry: at most one finding per entry, no
cross-function invariant, and nothing to keep in sync.

**Option C: fold the legality decision into the existing resolution check.**
Rejected because that function hardcodes its code in a closure, shells out to
`git ls-files` per entry, and has its output bytes pinned by golden fixtures.
Adding a second code to it means restructuring a check that currently mixes pure
logic with a subprocess, for no gain over Option B.

**Option D: a separate validation mode.** Rejected because it removes the
finding from the per-file pass an author already runs, and the requirements ask
for a failure at authoring time.

**What cross-validating Decisions 1 and 2 turned up.** Every lifetime violation
is also a direction violation, and this is a consequence of the declaration-level
assertion rather than a coincidence. A lifetime violation needs a Durable
document naming a Working target; the assertion forbids any Durable type from
listing a Working type among its legal parents; so the target is necessarily
absent from the naming type's parent set. The converse does not hold — a brief
naming a design violates direction alone. So the two findings have different
populations, one strictly inside the other, and the precedence rule fires on
every lifetime finding rather than on a rare overlap. That is not an argument
against the lifetime code: it is the more specific diagnosis of the same defect,
and it is the runtime half of a rule whose other half is enforced against the
declarations. But a reader comparing the two codes' corpus yields should know
the containment is structural.

### Decision 3 — how the roadmap path reaches the plan

**Option A (chosen): `/plan` gains `--upstream <path>`**, and `/scope` supplies
its recorded roadmap there.

**Option B: hand the roadmap to `/plan` positionally.** Rejected on five
independent counts, each fatal. The positional slot is the input classifier, so
a roadmap path changes what `/plan` is planning — decomposition becomes one
issue per roadmap feature and the chain's design is not decomposed at all. The
slot holds one value, so the roadmap displaces the design. The topic slug is
derived from the source filename, so the plan lands under the roadmap's slug and
the parent's structural file-existence check fails against the chain's own
artifact. Execution mode is forced to multi-PR. And the upstream status gate
expects a roadmap at Active rather than a design at Accepted. `/scope` already
wrote this argument down for `/brief` under "Why the slug and the upstream
travel separately"; every word of it transfers.

**Option C: `/plan` discovers the roadmap itself** by scanning for a feature
naming this chain's slug. Rejected because it rests on a per-feature downstream
field that the roadmap format does not specify — the cascade both reads and
writes it, and no format reference defines it — so choosing this option means
canonicalizing that field first.

**Option D: `/scope` writes the roadmap into the produced plan's frontmatter
after `/plan` returns.** Rejected on a decisive mechanical objection before any
argument about layering: the produced plan is outside `/scope`'s closed
write-target set, and a write outside that set fails the parent's own
hard-finalization check. The layering objection is real but weaker than it first
looks — the write happens after the child has recorded, so it does not violate
the letter of the same-behaviour-standalone rule; what it violates is the reason
behind it, since a plan produced standalone would then carry no roadmap while an
otherwise identical plan produced under a parent would. That is the divergence
the rule exists to prevent, and it is why the mechanical objection and the
layering one point the same way.

**The hand-off is duplicated, not moved.** `/brief` still receives the roadmap
for grounding; `/plan` receives it for the record. `/scope` validates the value
once at Phase 0 and passes it to the first child and the last one.

### Decision 4 — `/brief`'s roadmap input surface

**Option A (chosen): keep both input routes and rename what they do.** The flag
and the positional roadmap mode become grounding inputs, and the skill states
the read-versus-record distinction explicitly.

**Option B: remove the flag, keep the positional mode.** **Option C: remove the
positional mode, keep the flag.** Both rejected for the same reason: the two
routes exist because a roadmap sequences several features, so the roadmap's
filename and the feature's topic slug usually differ. Removing the flag forces
the brief to be named after the roadmap; removing the positional mode breaks the
one case where they legitimately coincide. Neither route's value changed when
the recording did.

**Option D: remove both** and have the author paste roadmap context into the
scoping conversation. Rejected because the input does real work — Phase 1 loads
the roadmap, finds the feature this brief frames, and derives the problem and
outcome candidates from the feature's line item and the sequencing rationale.
That work is the reason a chain run under a roadmap produces a better brief than
one run cold, and it is unaffected by whether a field is written.

**The precedent this follows.** `/strategy` reads a grounding PRD and
deliberately does not record it, and says why in a section called "Reading a
document vs. recording it as `upstream`". `/brief` gets the same section with
the same shape, and the reason it gives is what a brief *is* — a type whose legal
parent set is empty — rather than what it happened to be handed.

## Decision Outcome

Two declarations, one check, one flag, one renamed act.

`FormatSpec` gains `id: FormatId`, `lifetime: Lifetime`, and `legal_upstream:
Vec<FormatId>`, all defined in `formats.rs`. The declared table is the one the
requirements fix: a brief's parent set is empty, a plan's contains ROADMAP, and
no durable type's contains a working type. Two plain unit tests over `formats()`
enforce the table verbatim and the durable-names-working prohibition, with no
fixtures and no I/O.

One check function reads both declarations, walks the field's entries through
the shared normalizer, resolves each target's type from its basename, and emits
at most one finding per entry: the lifetime code when the naming type is durable
and the target working, the direction code when the target's type is absent from
the parent set, and nothing when the basename resolves to no known type. It is
called from `validate_file`'s cross-format block immediately after the resolution
check — after the schema gate, which is what preserves the golden fixture, and
after the private-only gate, which short-circuits before it.

`/plan` gains `--upstream <path>` with the contract its five sibling skills
already ship: parsed before the positional argument, never used to derive the
topic slug, rejected when bare or repeated, canonicalized and bounds-checked,
and run through the ordered validation checks. The contract is extended rather
than merely adopted, and the extension applies to every skill that validates a
supplied path rather than to `/plan` alone: cross-repo discrimination is
promoted to the first check, because running it later makes the visibility check
unreachable for exactly the values it governs; and the canonical path is
confined to the roadmaps directory, because dropping the tracked-by-git check
for a read-only input would otherwise widen what a grounding path may be. Both
are set out in the flag path below.

`/scope` passes its recorded roadmap to `/brief` for grounding and to `/plan`
for the record. The produced plan carries its design first and the roadmap
second.

`/brief` keeps both roadmap routes, writes no `upstream:` field, and announces
the omission with its reason. Its basename enforcement stays and gains weight:
with nothing reaching frontmatter, that check is now the only thing standing
between a wrong-type input and a silently mis-framed brief.

## Solution Architecture

### The declaration layer

`crates/shirabe-validate/src/formats.rs` gains two types and three fields. The
`FormatId` enum has one variant per format and a display form for messages, kept
separate from `FormatSpec::name` so the dispatch strings stay untouched. Each of
the eight `FormatSpec` literals gains its `id`, its `lifetime`, and its
`legal_upstream` list, with an empty vector for the two types that head their
own lineage.

The declarations are the only new source of truth. `lifecycle.rs`'s
terminal-status map is a second, partial spelling of the lifetime class for five
of the eight types; the two are not derived from each other, because that map
also encodes *which* status is terminal. A test asserts they agree on the five
they share, and a comment names the new field as authoritative.

### The check

One function taking the document and its spec, returning findings. It reads the
`upstream:` field, takes its entries from the shared normalizer, and for each
entry resolves the target's format from its basename. An entry whose basename
matches no known prefix contributes nothing, which is what leaves cross-repo
values and non-artifact paths alone. A cross-repo value whose file component
does name a known prefix is judged on that prefix.

Findings carry the field's line, matching the resolution check's existing
behaviour. The message names the document, the offending value, the resolved
type pair, and the property that failed.

The codes are `R10` for direction and `R11` for lifetime. Neither collides with
a code an existing test asserts is unrecognized, and both land error-level
without touching the intrinsic-notice set or the posture classifier, which
default every unlisted code to always-enforced. The validator's check-code
namespace is unrelated to the requirement numbering in the upstream PRD despite
sharing an `R` prefix; `R10` the check and `R10` the requirement name different
things, and the code registry is the authority for the former.

The predicate the lifetime branch actually implements is narrower than the
property the requirements state. The stated property is that the target outlives
the naming document or is retired with it; the implemented predicate is that a
durable document may not name a working one. The two agree on every pair the
declared table admits, because the only working-names-working pair in it is a
plan naming a roadmap, and the cascade that deletes the roadmap deletes the plan
first. A future artifact type with a shorter working life than another working
type would separate them, and the implemented predicate is the one to revisit
then.

### The call site

Inside `validate_file`, in the cross-format block, immediately after the
resolution check. Three placements break the golden corpus and are named here so
the constraint is not rediscovered: anything before the schema gate, anything in
the per-file driver loop outside `validate_file` — superficially attractive
because both arguments are already in scope there — and anything that makes the
private-only gate run after legality.

The whole-tree lifecycle traversal is undisturbed by any of this. It is a
separate mode that emits its own codes and never calls the per-file pass, so
`shirabe validate --lifecycle . --mode=draft` exits 0 after the change exactly
as it does before, with the same single orphan notice.

### The flag path

`/scope` Phase 0 validates the supplied roadmap once and records it. Phase 2's
child-argument table gains the flag on the `/plan` row and rewords the `/brief`
row to say the roadmap grounds the framing and is not recorded.

`/plan` parses the flag ahead of its positional argument and validates it
against the record-time set its five sibling skills run, extended as Decision
Outcome describes, in this order:

1. **Cross-repo discrimination first.** An `owner/repo:path` value names a file
   in another repository, is not a working-tree path, and is not resolved
   against the filesystem at all. It skips checks 2, 3 and 5, keeps the basename
   rule on its file component, and lands on the visibility check, which is the
   only one that can say anything about it. Putting this first is what keeps the
   flag able to express the case that motivates it — a tactical chain run in one
   repository underneath a roadmap that lives in another. Run in any other
   order, the checks below would reject every cross-repo roadmap and the
   visibility check would become unreachable, which is the check that matters
   most for exactly those values.
2. **Canonicalize with symlink resolution and bounds-check** against the working
   tree.
3. **Confine the canonical path to the roadmaps directory**, which is the
   constraint `/brief`'s positional input mode already carries.
4. **Enforce the `ROADMAP-` basename**, on the file component for a cross-repo
   value.
5. **Reject a path under `wip/`, and reject an untracked path.**
6. **Omit rather than record** when this repository is public and the roadmap is
   private, announcing the omission and its reason.

It then writes the value into the produced plan's `upstream:` as a second
sequence entry after the design.

The directory confinement applies to every skill that validates a supplied path
— `/scope`, `/brief` and `/plan` — and to none of the consumers that later read
a recorded field, which judge what is written rather than what was typed.
Confining only the two that do not record would leave standalone `/plan`
accepting what standalone `/brief` rejects, and `/plan` is the one that commits
the value.

"The roadmaps directory" means `<root>/docs/roadmaps/` for whichever repository
root the value was canonicalized against, not any path segment spelled
`docs/roadmaps/` anywhere beneath it. The distinction is not academic here: this
repository tracks eight `ROADMAP-*.md` files and has no `docs/roadmaps/` of its
own, so under this reading every one of them is outside the confinement, four
of them sitting in fixture corpora that have their own roots. A path-segment
reading would admit four of the eight and would let a fixture tree launder a
roadmap path into a real chain.

Two of these are changes to `/brief`'s flag validation, which R13 otherwise
describes as unchanged: check 5's tracked-by-git half is dropped there because a
read-only input has no durability to protect, and check 3 is added there because
dropping it opened a directory-scope residual that the confinement closes. Both
are named here rather than left inside "unchanged as inputs".

The plan's own pre-flight script reads `upstream:` as a scalar and silently
skips its entire upstream check when the value is a sequence. That is a
pre-existing hole rather than one this change creates, but this change is what
walks into it: a plan with two entries would pass a check that is not running.
The script enumerates sequence entries, applies its existing status gate to the
tactical entry, and accepts a roadmap entry at Active.

### What does not change

The finalization walk and the lifecycle chain walk keep their type-agnostic
behaviour. Both already handle multiple upstream entries in written order, and
the finalization walk already dispatches a roadmap node to the roadmap handoff
from whichever node names it. A chain authored before this change, in which a
brief names a roadmap, walks and cascades exactly as it does today; the cascade
fixtures that encode that shape are kept frozen as the evidence.

The orphan rule is untouched. Its exemption for a document whose upstream is an
Active roadmap keeps its behaviour and its tests, and simply becomes unreachable
for documents authored under the new rule, since no durable type may name a
roadmap. A brief that heads its own lineage with no downstream document takes
the ordinary orphan notice an upstream-less brief takes today — notice-level
under draft posture, and resolved the moment its PRD names it.

`FormatId` and `lifecycle.rs`'s `ChainRole` overlap without depending on each
other. `ChainRole` models the five roles the chain walk traverses;
`FormatId` names all eight types for the legality lookup. Unifying them means
changing `ChainRole::from_format`'s signature and its tests, which the
no-modified-tests constraint puts out of reach here. The dependency stays
one-directional — `lifecycle.rs` already depends on `formats.rs`, and nothing
new points the other way — so the overlap costs a comment naming `FormatId` as
the legality authority, not a refactor.

## Implementation Approach

**First, the declaration layer alone.** The two types, the three fields, the
eight literals, and the two unit tests. Nothing reads the declarations yet, so
this phase changes no validation result and is independently reviewable. The
terminal-status agreement test lands here too.

**Second, the check.** One function, its call site, the two codes registered in
the selectable-code set, and the valid-codes message updated. This is the phase
that changes the eight named documents' findings, so it is the phase whose diff
is measured against the named list. Its tests cover both properties, the
precedence rule, the unknown-prefix skip, per-entry reporting on a multi-valued
field, and the cross-repo file-component case.

**Third, the reference sweep.** Every format and pipeline reference that
documents a roadmap as a legal parent for a brief, a PRD, or a design is
corrected. This phase writes no code and is what makes the prose and the
declarations agree.

**Fourth, the skill contracts and the plan pre-flight script together.**
`/brief`'s read-versus-record section and its write site; `/plan`'s flag and the
script that validates what the flag records; `/scope`'s child-argument table and
its pre-authoring notice; `/explore`'s roadmap handoff. Each is authored in the
skill's own files.

`/explore` today reads a vision out of its crystallize artifact and passes it to
`/roadmap` as `--upstream`, and `/roadmap` records whatever it is handed without
enforcing a basename. A roadmap's only legal parent is a strategy, so that
handoff produces an illegal link on a live path — and `/roadmap`'s own contract
already forbids substituting a vision for a strategy, so the handoff contradicts
it today. After the change `/explore` passes no upstream to `/roadmap` unless it
is a strategy.

The script's sequence handling belongs in this phase rather than the next one.
It is a security fix, and it is a hard dependency of the flag: a plan with two
upstream entries would otherwise pass a check that has silently stopped running,
in the one continuous gate that validates a plan's upstream at all.

**Fifth, the evals and fixtures.** The five named eval expectations and the
new-shape cascade fixture chain beside the frozen old-shape one.

Phases one and two are independent of three through five and can land first.
Phase five depends on four; nothing inside phase four depends on phase five.

## Security Considerations

The change moves a committed frontmatter value from one skill to another and
relaxes one input check. Three areas need work, two are accepted with reasons.

**`/plan`'s new flag inherits the whole record-time validation set.** This is the
main finding. `/plan` has no `--upstream` today and therefore no validation for
one, and it is now the skill that turns the value into a committed field in a
public repository. The relaxation Decision 4 applies to `/brief` inverts here:
`/brief` reads, so it keeps the path-safety checks and drops the durability ones;
`/plan` records, so it takes all of them, in the order the flag path lays out.
Canonicalization with symlink resolution and a bounds check against the working
tree is the load-bearing one — without it, a roadmap path that is a symlink out
of the tree, or a `../`-shaped value, resolves outside the repository and lands
in a committed field.

Cross-repo discrimination has to run before any of them, and getting that order
wrong is a security failure rather than a functional one. A cross-repo value is
not a working-tree path: it does not canonicalize, it is not inside the tree,
and the index lookup returns nothing for it. A validation set that runs those
checks first therefore rejects every cross-repo roadmap and never reaches the
visibility check — which is the only check that has anything to say about a
cross-repo value, and the one that keeps a public plan from naming a private
roadmap.

`/plan`'s existing Phase 7 hygiene re-check does not substitute for Phase 0
validation. It runs after issues have been created, it does not canonicalize, it
has no visibility stop, and it cannot read a sequence-valued field at all — which
is the second half of this finding. The plan pre-flight script's blindness to a
sequence is a security fix, not a tidiness one: without it, every plan this
change produces silently stops being upstream-validated by the only continuous
check that validates it, and nothing reports that it stopped. The script is also
canonicalizing and rejecting an out-of-root or symlinked target while it is being
changed, rather than relying on git's index lookup to refuse one.

**Two interpolation sites take the value, and both get the argument boundary.**
One is new — the per-entry `git ls-files` in `/plan`'s Phase 7 hygiene step,
whose prose today specifies the invocation unquoted and without a terminator,
which is the exact shape the discipline forbids. The other is pre-existing, in
the pre-flight script this change is already rewriting: it quotes the value but
passes no `--`, so a value beginning with a dash parses as an option rather than
a pathspec. Both are quoted and passed after `--` when this change lands; the
script does not have that boundary today and gains it here. Validation is not
the guarantee; the argument boundary is. `/plan`'s contract states this in its
own words rather than inheriting it by assumption.

**The private-upstream omission rule is restated in `/plan`'s own contract.**
Without it, a `/plan` invoked standalone would skip a check the chain-driven path
performs, because `/scope` runs the check before handing the value over. That
asymmetry is precisely what the same-behaviour-standalone rule forbids, and the
consequence is a public plan naming a private roadmap — which the validator
cannot catch, since a cross-repo value resolves to nothing.

**Dropping the tracked-by-git check from `/brief`'s flag: accepted, with the
residual closed rather than warned about.** The content channel this appears to
open predates the change — `/brief`'s positional roadmap mode never ran the
check, and Phase 1 reads the file's contents either way — so what actually
widens is directory scope, from an untracked file under the roadmaps directory
to an untracked file anywhere outside `wip/`. Decision 4's own defence of the
`wip/` rejection is the argument against leaving that open: grounding a durable
brief in a scratch draft that will not exist at review time makes the framing's
provenance unreproducible, and that is as true of a build directory as of
`wip/`. So the flag's canonical path is confined to the roadmaps directory,
matching the constraint the positional input mode already carries. This is the
convergence Decision 4 wanted, completed rather than left halfway, and it
rejects nothing legitimate: every roadmap the roadmap skill produces lands
there, and cross-repo values skip path resolution entirely.

The confinement applies to every skill that validates a supplied path, and to
none of the consumers that read a recorded field. Confining `/scope` and
`/brief` alone would make the chain direction safe — the parent is then stricter
than the child, so nothing is rejected mid-flight — while leaving standalone
`/plan` accepting what standalone `/brief` refuses, and `/plan` is the one that
commits. What that halfway version leaves open is a tracked file carrying a
roadmap basename outside `<root>/docs/roadmaps/`, of which this repository
tracks eight, and a committed frontmatter pointer to one is strictly worse than
grounding prose in it.

**The check performs no I/O: N/A.** Legality is decided by matching two
basenames against a compiled table. There is no path to canonicalize, no file to
open, and no syscall an attacker could steer. This is the same property that
keeps the strategic directories out of the document index.

**Typing a target from its basename is a spoofing surface, and it is accepted.**
A file named with a roadmap prefix that is not a roadmap will be typed as one,
and a roadmap renamed without its prefix will not be. Both directions are
author-visible — a false positive is a validation error on a document the author
is editing, and evading the check by renaming means losing every other piece of
tooling that keys on the same prefix, including the format detection that gives
the document its required sections. This is the assumption format detection
already makes everywhere else in the validator; the new check does not extend
it.

## Consequences

**Positive.** A maintainer adding an artifact type declares two facts and gets
both enforced, with a compiler error for a missing declaration rather than
silence. The declaration-level assertion means the class of defect this work
exists to remove cannot be reintroduced by editing a table. The check needs no
index, so the strategic directories stay out of the orphan rule. And the
consolidation absorb's re-point, which today converts a stable link into a
doomed one, dissolves without a separate guard: a brief with no upstream leaves
the surviving PRD correctly headed under the absorb's existing rule.

**Negative.** Three documents that validate clean today will fail, and the
repository will carry eight illegal edges that this work names and does not
repair. The lifetime code's runtime yield is a strict subset of the direction
code's, so it earns its place on message quality and on being the runtime
statement of a declaration-level rule rather than on finding anything the other
code misses. And a chain that bails before its plan records no roadmap anywhere,
where today it would have recorded an illegal one on the brief.

**Mitigations.** The eight edges are named ahead of the diff so an intended
change is never read as a regression. The bail case is recorded in the parent's
durable artifact record so the roadmap a chain consumed is not lost with the
state file. The plan pre-flight script's sequence hole is fixed in the same
change that would otherwise walk into it.

**Accepted, with reasons.** The cascade's diagnostic for a missed roadmap
feature infers a parent path from report order and will now name the design
rather than the roadmap. Fixing it properly means the finalization walk emitting
a real per-node parent, which alters the report and risks the frozen-output
constraint; the inaccuracy is confined to one diagnostic message and is accepted
here. And `/scope`'s promise that its three ordered checks behave identically
whichever skill receives the flag narrows to "wherever the flag records", since
`/brief` no longer records; the rule stays stateable in one line rather than
becoming an exception list.

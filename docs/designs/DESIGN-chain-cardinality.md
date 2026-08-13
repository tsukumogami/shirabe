---
schema: design/v1
status: Accepted
upstream: docs/prds/PRD-chain-cardinality.md
problem: |
  Document lineage is one-to-many in the formats and in practice, but four
  places in the tooling assume one-to-one: YAML sequences never survive
  frontmatter parsing, the chain-targeted check evaluates whichever chain sorts
  first by filename, a document under two chains receives contradictory status
  requirements with no diagnostic, and the finalization walk retires shared
  parents while other consumers still depend on them.
decision: |
  Parse sequences into real entries and route every reader through one
  normalization helper. Replace the two chain-evaluation loops with a
  member-keyed obligation map consumed by a single emitter, making finding
  identity a map key rather than message text. Add a conflict finding that
  supersedes the contradictory pair, computed from effective postures and
  guarded by a root-versus-member fix applied first. Give the finalization walk
  a referrer map and a worklist, and make a block a reported skip. Give both
  parents and both head children an --upstream flag, recorded in parent state
  and surfaced by a non-blocking notice before the chain head is authored.
rationale: |
  Each half is chosen to make a guarantee structural rather than coincidental.
  One parser plus one normalization helper makes reader agreement impossible to
  drift from; a map key makes duplicate findings unconstructible rather than
  deduplicated after the fact; a referrer map read once makes the blocking
  decision a property of the walk rather than of an external gate; and a flag
  decoupled from the topic slug removes a dependence on two slugs coinciding
  that the reuse case is defined by breaking.
---

# DESIGN: Chain Cardinality

## Status

Accepted

Five decisions were researched independently and cross-validated. Three sequencing edges
and one inverted repair are recorded in Implementation Approach; they are the parts most
likely to be got wrong by reading one decision alone.

## Context and Problem Statement

`PRD-chain-cardinality` establishes that document lineage is one-to-many in the format
references and in practice, while the tooling assumes one-to-one in four places. This
design settles how each is repaired without changing what any document in the corpus
validates to.

Three properties of the existing code shape every decision below.

**The `upstream:` field has three readers that do not agree.** The resolution check and
the finalization walk each treat the whole value as one path; the chain walk splits on
newlines and strips list prefixes. The chain walk's list handling has never been
reachable, because the frontmatter parser collapses every YAML sequence to the empty
string before any reader sees it — block, flow, and single-entry alike. A `|` block
scalar survives as joined text and is the only multi-valued shape that half-works today.

**Posture belongs to a chain, and a chain is identified by its root.** A shared member is
cloned into every chain reaching it, and each imposes an independent requirement on one
mutable status field. Nothing groups by member, so a document under two chains receives
two instructions; and the post-hoc deduplication cannot collapse them because the message
interpolates the posture name, which makes message equality a false proxy for finding
identity.

**The finalization walk is a single-path traversal with no index.** It reads one upstream
per node and transitions every ancestor it reaches. It has no way to know whether anything
outside its branch still points at what it is retiring — which is how five documents in
this repository came to carry dangling references from one commit.

## Decision Drivers

- **No corpus document may change its validation result**, and the existing suite must
  pass with no test modified. This is the binding constraint on every option below and it
  eliminated otherwise-attractive choices in two decisions.
- **Guarantees should be structural, not coincidental.** Several defects here exist
  because a property held by accident until something shifted: reader agreement held while
  no document used a sequence, deduplication held while no message carried a posture name,
  and the parent hand-off holds while two slugs coincide.
- **A repair must not tell an author to fix something that is correct.** A diagnostic that
  fires on documented, intended lineage is worse than silence, because it trains readers to
  ignore it.
- **The mutation path deserves more caution than the check path**, because its failure mode
  is irreversible and its damage is discovered late.
- **Prose contracts are the implementation for the parent half.** The skills are documents;
  changing them means changing contract text, state schemas, and prompt wording, and their
  evals assert on literal strings.

## Considered Options

Each decision was researched independently against the running binary, and every claim
below was measured rather than reasoned about. The evidence is summarized here because the
research files that produced it are working artifacts and do not survive the merge.

### Decision 1 — Sequence representation and resolution reporting

**Chosen: parse sequences into real entries, with one shared normalization helper.** The
parser returns entries; every reader asks for them through the same helper, which owns
trimming, the placeholder rule, cross-repo handling, and self-reference suppression.

*Rejected — newline-joined text.* It would activate the chain walk's existing splitting for
free and cost almost nothing. It fails because a scalar reader then silently receives a
joined multi-path string, which is the exact failure the requirement on reader agreement
exists to prevent, and because splitting scalars would make every `problem: |` prose block
parse as a many-entry list.

*Rejected — a parallel accessor for declared multi-valued fields.* Keeps the scalar path
intact but leaves two ways to read one field, which is the condition that produced three
disagreeing readers in the first place.

Two consequences are accepted deliberately: a `upstream: |` two-line value stops
half-working, and sequence fixtures must stay out of the cross-implementation parity
corpus, because the frozen baseline collapses sequences and such a fixture could only be
made to pass by editing the gate.

**Resolution reporting.** The resolution check currently reads the whole field as one path
and emits at most one finding. It iterates entries instead, emitting one finding per entry
that does not resolve, so a two-entry value with one bad path names the bad path rather
than the pair. A field that is present but names nothing — null, an empty sequence, or a
scalar empty after trimming — reports exactly one finding stating that the field is present
and empty, at the field's line, under the existing code. It never reports a placeholder as
though it were a path, which is what the current empty-string and null messages do. A
sequence with at least one entry is never "the empty field" even when an entry is blank:
that is one per-entry finding, not a field-level one, which keeps "exactly one finding" true
in both directions. A value that is neither scalar nor sequence reports one finding saying
so, since discarding it silently is the behavior this decision exists to remove.

The empty-scalar case goes beyond the requirement's literal text, which names only the null
and empty-sequence spellings. It is included because `upstream: ""` is the same authoring
mistake and its current message is precisely the placeholder-reported-as-a-path the
requirement outlaws. No document in the validated set writes it, so corpus invariance is
unaffected either way.

**What the field's scalar value holds for a sequence** must be stated, because it feeds the
annotation bytes the cross-implementation parity gate compares. It stays the empty string,
unchanged from today. Entries are reached through the entries representation; nothing that
compares scalar text sees a new value, so the gate's baseline is untouched by this change.

### Decision 2 — Chain evaluation and finding identity

**Chosen: a member-keyed obligation map, built once, consumed by a single emitter.** A
document's obligations are the union over every chain containing it. The mode selects only
which documents are reported on, not what is said about them. Finding identity is the map
key — code, path, required set — so a duplicate cannot be constructed rather than being
removed afterwards.

*Rejected — keep both loops, drop the posture name, deduplicate textually.* Fifteen lines
against roughly a hundred and twenty, and it satisfies most requirements the day it lands.
It fails because identity becomes message equality, which is precisely the arrangement that
already failed here; the next person to add a hint or a line number to a message silently
reopens the defect with no test able to name what broke.

*Rejected — chain-targeted calls whole-tree and filters.* Strongest possible form of
mode agreement, but filtering by path drops corpus-integrity findings the mode reports
today, which is a regression on the one mode the cascade runs.

*Rejected — reachability instead of per-root walks.* Produces the same map by a different
traversal, rejected on regression risk rather than merit. The existing walk carries three
behaviors that are observable in tests and in the corpus and easy to lose in a rewrite: it
stops at a BRIEF or a ROADMAP while still recording the stopping node as a member; a cycle
produces a specific finding carrying the path in walk order and then drops the chain
entirely; and posture is inferred from the root rather than from any member. Naming them is
the point — a rejection resting on an unenumerated set asks to be taken on trust, and these
three are the reason the walk is reused rather than replaced.

**The walk does change in one respect.** The
requirement that every entry of a multi-valued upstream be a membership edge is a change to
the walk itself: it currently advances to the first upstream and discards the rest. Making
it fan out is not a one-line substitution, because two properties of the walk assume a
single path. Its cycle detection shares one visited set across the whole traversal, so a
diamond — two entries reconverging on a common ancestor — would be reported as a cycle and
the chain dropped, turning a legal shape into a spurious error. And chain root identity is
currently recoverable by position, since members are recorded root-first and then reversed;
that stops holding once the walk branches. The fan-out therefore needs per-branch cycle
tracking and an explicit root path on the chain rather than a positional convention.

### Decision 3 — Conflict detection and supersession

**Chosen: a distinct check code emitted from the obligation map, superseding the
status-lifecycle findings of the conflicting chains, with the root-versus-member fix
applied first.**

Conflict is disjointness of required sets, not inequality — treating "the chains want
different things" as conflict would fire on every shared DESIGN, which is the case the
intersection requirement exists to protect. The sets are computed from *effective*
postures, after the ready-mode re-target, because a conflict computed from raw postures
reports a ready-mode conflict that ready mode does not have.

Supersession is safe by construction rather than by care: if no status satisfies every
chain, the document's status satisfies at most one, so at least one superseded finding
always fired. The replacement is always one-for-N with N at least one, never one-for-zero.

**Disjointness needs the required sets expanded to concrete status sets, and one value
needs a rule of its own.** The requirement values are not sets today — two of them name a
single status, two name a disjunction, and one means the document must be absent. The first
four expand naturally. The absent value expands to the empty set, and the empty set is
disjoint from everything including itself, so a literal disjointness test would fire on two
chains that both require the same PLAN deleted — perfect agreement reported as conflict, on
correct and documented state. The rule is therefore stated rather than inferred: two
requirements conflict when both name statuses and their sets do not intersect, or when one
requires absence and the other requires a status. Two requirements of absence agree.

*Rejected — detect but do not supersede.* The honest option, and it was given a full
hearing: it satisfies the severity requirement vacuously, has provably zero regression
exposure, and is the smallest change. Two of the three arguments against it are weaker than
they look, and only the third carries the rejection.

The accepted requirements say otherwise in SHALL language, so choosing it is a PRD
amendment and would have to be proposed as one — an appeal to authority rather than merit,
and named as such.

The claim that the contradictory pair is itself the harm argues for *detection*, which this
option also provides, not for supersession. A proponent would say the conflict message alone
stops the cycling and the per-chain findings beside it are redundant rather than harmful,
and on that framing they would be right.

What actually carries the rejection is narrower and holds: each finding becomes an
independent annotation in the rendered CI output, one per file and line, so the reader who
sees the instruction to change a status does not reliably see the explanation attached to
it. Ordering within a text report keeps them adjacent; the annotation surface does not. The
rejection stands on that alone, and the design says so rather than resting on the broader
claim.

*Rejected — reuse the existing lifecycle code with a merged message.* Severity would be
pinned by identity and every existing consumer would keep working, but the code family
exists to name kinds, a lineage conflict is not a state-versus-posture mismatch, and a
merged code cannot be split later.

### Decision 4 — Consumer-aware, multi-branch finalization

**Chosen: build the referrer map once per walk from the validator's existing index through
a narrow graph-level API; the walker makes a per-node decision; a block is a reported skip,
not a walk-aborting failure.**

The walk becomes a worklist over every upstream with a visited set, so a shared ancestor
reached through two branches is visited once — otherwise it would be transitioned twice and
the exit code would depend on traversal order. Branches are ordered by written order, not
path order, because ordering by path would reintroduce the filename dependence forbidden
elsewhere.

The carve-out is *documents this walk retires*, not *documents it visits*. That distinction
earns a property for free: a blocked node stays non-terminal, so it remains a blocking
referrer for its own ancestors and the block propagates upward with no additional rule.

*Rejected — an index owned by the finalization module.* Rejected on reader agreement rather
than cost: it would duplicate the upstream parse at the exact moment that parse is being
unified, in a change whose stated problem is that three readers disagree.

*Rejected — a report-only walk plus an external gate.* Given a serious hearing, since a
refusal before any mutation has a smaller blast radius. Rejected on four counts: the
per-node verdict an acceptance criterion requires cannot come from an all-or-nothing gate;
a cross-process gate widens the window between check and mutation; a gate outside the
binary leaves the documented public subcommand willing to perform the unsafe transition;
and it saves no orchestration. Its reporting half is adopted.

### Decision 5 — The parent upstream contract

**Chosen: `--upstream <path>`, the same token on both parents and on both head children,
parsed before the positional slug, recorded in parent state under a conditional field, and
announced by a non-blocking notice inside the chain proposal.**

The flag never enters the positional slot, so the parents' rejection of artifact paths
there is untouched. Inbound validation enforces the basename, deliberately unlike the
outbound contract that does not — outbound, the parent is handing over an artifact whose
type it knows; inbound, it is routing on a string the author typed, and a wrong type
silently mis-frames the chain head.

A notice is not a prompt: no options, no default, no control-flow change. It rides inside
the chain-proposal output that already fires on every run, names no candidate so it needs
no directory scan, and blocks nothing so it has no non-interactive default to get wrong.

*Rejected — an upstream-path positional input mode.* Reopens the path-rejection rule and
still needs the topic slug from somewhere, making it two inputs in one input's costume.

*Rejected — a discovery scan that asks which upstream to attach to.* Adds a blocking prompt
to every run, and attaching a bet to the wrong upstream silently is worse than a visible
duplicate.

### The specification corrections

Two requirements — stating which written `upstream:` shapes the format references support,
and correcting the two accepted acceptance criteria that describe a positional path as
slug-derived when both parents reject it — carry no design choice. They are recorded here
rather than left silent, because a plan built from this document would otherwise not find
them. The first is settled by the parsing decision: the supported shapes are a scalar and a
sequence, and the format references say so. The second is a factual correction to two
documents whose content is already determined by the behavior those parents ship.

## Decision Outcome

The five decisions compose into one change with a clear spine: **make each guarantee a
property of structure rather than of circumstance.**

One parser produces entries; one helper normalizes them; three readers consume that helper.
Reader agreement stops being a thing to verify and becomes a thing that cannot vary.

One obligation map replaces two evaluation loops. Deduplication stops being a post-hoc
pass over message strings and becomes the impossibility of constructing a duplicate key.
Mode agreement stops being a coincidence of two loops staying in sync and becomes identity
of the code that produces both.

One referrer map, read once per walk, replaces the absence of any consumer knowledge.
Safe retirement stops being an external gate's responsibility and becomes a property of
the walk that performs the mutation.

One flag, decoupled from the topic slug, replaces a hand-off that works only while two
slugs coincide — a coincidence the reuse case is defined by breaking.

The conflict diagnostic sits on top of the obligation map and reports the one case the
model cannot represent: a document whose consumers demand states that no single status
satisfies. It supersedes rather than accompanies, because each finding becomes an
independent annotation in rendered output — so a reader who sees an instruction to change a
status does not reliably see the explanation that the instruction is contradicted.

## Solution Architecture

**Parsing layer.** The frontmatter parser gains an entries representation for sequence
values, preserving written order, covering block and flow syntax and the single-entry case.
Scalars yield exactly one entry containing their whole text; scalars are never split. A
shared normalization helper is the only path by which any reader obtains entries, and the
string surgery currently inside the chain walk is deleted, since the parser now returns what
it was reconstructing.

The helper's semantics have to be *chosen*, not merely centralized, because the three
readers disagree today on all four of its concerns. Placeholder-shaped values are skipped as
entries rather than being allowed to reach path resolution, which is the chain walk's
current behavior and which converts a present-day tool error in the finalization path into
a clean termination. Cross-repo references are recognized and marked as not resolvable
as a local path, rather than being joined onto the local root as literal paths, which is what
an unconditional join would do. **Marked, not removed** — the distinction is load-bearing on
the mutation path. The finalization walk stops at a cross-repo upstream and reports a node
saying so; that write wall is asserted by an existing test the requirements forbid modifying.
If the helper dropped cross-repo entries from the list instead of flagging them, the walk
would never see them and the wall would silently vanish. The validator skips them; the walk
stops at them; both need the entry present to do so. Trimming and self-reference suppression follow the chain walk.
The helper returns entries as written after normalization and does not resolve them against
a root; resolution stays with each caller, because the two callers that resolve today anchor
against different bases and unifying that is a behavior change this design does not need.

**Evaluation layer.** The chain walk is reused as a per-root walk rather than replaced,
which is what preserves the three behaviors named above. It changes in exactly two ways: it
follows every entry of a multi-valued upstream instead of only the first, and it carries its
own root path rather than leaving root identity to be recovered from member ordering. The
fan-out requires cycle detection to be tracked per branch, so that two entries reconverging
on one ancestor are recognized as a diamond rather than reported as a cycle.

From its output an obligation map is built once: document path, to required status set, to
the postures and chain roots imposing it. The ready-mode re-target is applied once, before the map is built, so every consumer
sees effective postures. Emission becomes a single function over a scope set of document
paths; whole-tree passes every indexed document, chain-targeted passes the members of every
chain containing the target. Corpus-integrity findings remain whole-corpus in both modes,
which is what both modes already do for index and chain errors.

Two checks need a stated home rather than being carried along implicitly. The file-location
check runs today only in whole-tree mode, so a document in the wrong directory is reported
by one mode and not the other — a mode-agreement violation that exists independently of
chain selection and that a restructure touching only the status check would leave standing.
It moves into the single emitter and runs over the scope set, which closes it. The
outline-criteria check is chain-scoped rather than member-scoped: it needs the chain to
locate its subject, not just a document path. It stays keyed to the chain, evaluated once
per chain in scope, and the emitter treats it as a chain-level output rather than folding it
into the per-document pass.

The chain-targeted scope is a shallow closure, not a transitive one: the members of chains
containing the target, not then the chains containing those members. A transitive closure
would make the targeted mode indistinguishable from whole-tree in a connected corpus,
defeating the mode's purpose.

**Conflict layer.** Before conflict detection, the root-versus-member fault is repaired at
source: a ROADMAP that is not the root of the chain being evaluated is required to be
Active, which is the requirement the one correct cell already states for exactly this
position. Only a ROADMAP's own chain can require its absence. The repair is stated as Active
rather than as the weaker "present" because the two differ on a real case — a retired
ROADMAP above a still-completing chain passes under "present" and is correctly flagged under
Active — and an implementer given both readings would pick one at random. The requirements table cannot currently
tell whether a posture came from a document's own chain or from a chain it merely sits
above, and that conflation produces a live false positive — one feature finishing beneath a
live ROADMAP makes the validator demand the ROADMAP be deleted.

With that repaired, conflict detection is disjointness across the required sets a document
carries. The finding names each conflicting chain and the full set each requires. The
status-lifecycle findings from those chains are withheld in its favour; findings of every
other kind on that document are unaffected.

**Mutation layer.** The finalization walk builds a referrer map once per invocation through
a narrow API over the validator's index, and reads upstreams through the shared helper
rather than its own scalar read. Traversal becomes a worklist with a visited set. Before
transitioning any ancestor, the walk consults the referrer map: a non-terminal document
outside the set this walk retires blocks the transition, which is reported as a skip
carrying the blocking documents and their statuses. The walk continues; the exit code is
unaffected.

**Parent layer.** Both parents accept `--upstream <path>` parsed at setup before slug
validation, canonicalized and bounds-checked, with basename enforcement against the chain
head's type. The value is recorded in the parent's state under a conditional field, absent
when no upstream was supplied, and re-validated on resume with a defined outcome when it no
longer resolves. Both head children gain the same flag, so the parent passes slug and
upstream separately and the child's own slug derivation stops being driven by the upstream's
name. The pre-authoring notice fires from the chain proposal when the head child will author
a new head-altitude artifact and no upstream was supplied.

## Implementation Approach

**Three sequencing edges are load-bearing.**

The parsing change must land before the finalization change. This edge is created by this
design rather than inherited: the finalization walk today has its own scalar read and
depends on nothing, but the design routes it through the shared helper, so landing it first
would mean writing a reader that is about to be replaced.

The multi-edge walk must land with or before the obligation map. The map's correctness rests
on membership following every upstream edge; built over a walk that still follows only the
first, it would be a union over an incomplete set of chains and would look right while being
wrong.

The evaluation restructure must land before the conflict diagnostic. The conflict check
consumes the obligation map and the root-versus-member repair is a branch inside its
builder; neither exists until the map does. The repair specifically must land before any
disjointness is ever computed — not merely as the conflict work's first commit — because
without it a ROADMAP member of a completing chain carries a requirement of absence against
its own chain's requirement of Active, and the conflict finding fires on correct lineage.
That is a hard edge, not a tidiness preference.

**One repair runs opposite to the obvious direction.** The requirements table has one cell
that disagrees with its neighbours, and the instinct is to normalize it to match. That is
backwards: the odd cell is the one encoding correct member semantics, and normalizing it
would spread a live false positive rather than remove it. The repair generalizes the odd
cell's semantics to the others, conditioned on position. Anyone reading the evaluation
decision without the conflict decision will get this wrong, which is why it is stated here
rather than left in a research artifact.

**Phasing.** Parsing and normalization first, since three consumers depend on it. Evaluation
restructure second, as the largest single change and the one the conflict work needs.
Conflict diagnostic third, with the root-versus-member repair as its first commit rather
than a follow-up. Finalization fourth. The parent and child contract changes are independent
of all four and can proceed in parallel, with one constraint carried from the requirements:
the conflict diagnostic must be in place before the upstream-recording work ships, because
recording consumed upstreams makes concurrent chains under one parent more common, and that
is the shape the diagnostic exists to catch. That constraint belongs in the plan's
dependency graph, not in a requirement — it constrains the work rather than the software.

**Testing.** Sequence coverage stays out of the cross-implementation parity corpus. The
parity baseline needs re-establishing rather than assuming, because the parsing change is
what makes a sequence-valued fixture possible in the first place. Corpus invariance is
verified against every repository the change is tested against, before and after, in both
modes.

**Corpus invariance has exactly one intended exception, and it must be named before the
diff is run.** The root-versus-member repair changes what a member ROADMAP is required to be,
which shows up as a diff in two shapes, both expected. A live ROADMAP beneath a completing
feature stops being told to delete itself — the finding disappears. A retired ROADMAP above
a still-running chain keeps its finding but with a changed expectation, since the requirement
moves from absence to Active. Both are deliberate breaches of the invariance requirement
rather than regressions, and an exception scoped only to findings that vanish would
misclassify the second. This repository has no roadmaps and cannot exhibit it; whether a
sibling repository does is a question the implementation must ask before it starts, because
an engineer running the before-and-after comparison will otherwise see a difference with no
way to tell the intended repair from a fault. Every other difference is a regression. Also
verify during that pass that no document carries a present-but-empty upstream whose message
the reporting change would alter — that assumption was recorded but never checked.

**The finalization tests are part of the invariance obligation, not just the validation
output.** Two behaviors this design adds touch that path: a canonicalization failure now
blocks a transition, and the walk reads every indexed document rather than only its own
chain. Both must be checked against the existing finalization suite before they are
considered settled, because the requirement that no test be modified covers those tests as
much as the validator's.

## Security Considerations

### The flag's value reaches a committed frontmatter field

This is the largest surface, and the least obvious, because nothing about a flag suggests
its value ends up in a committed file.
The supplied upstream is not merely read — a head child writes it into the produced
document's `upstream:` field, and that document is committed. On the strategic hop the
private-to-public direction is not a corner case but the ordinary one: the strategic corpus
lives outside this repository, so a run in a public repo is naturally pointed at a private
artifact. Public documents referencing private ones are forbidden, and that rule is enforced
by content governance rather than by tooling — the resolution check returns nothing for a
cross-repo value, so a public document carrying a private cross-repo upstream validates
clean and always will.

**Cross-repo values are accepted, and the visibility check is therefore mandatory rather
than advisory.** Rejecting them outright would be safe and would also make the flag unable
to express the one case that motivates it, which is a functional gap on the exact hop the
requirements name. Accepting them means the parent owns the check the validator cannot make.
The check already exists in a sibling skill and is reused rather than reinvented: reject a
path into the non-durable working-artifact directory, confirm the target is tracked by git,
and stop rather than record when this repo is public and the upstream is private — omitting
the field instead of writing it. The first of the three matters because such a path would
otherwise let a document be committed pointing at something deleted before merge. One of the
two children that already carries this flag has all three checks and the other has none; this
design closes that asymmetry rather than extending it to four more skills.

### Interpolation and the positional contract

The flag is the first author-supplied value either parent accepts that is not derived from a
validated slug, and the parents' security contract requires an addition of author-input
handling to re-state the interpolation discipline explicitly rather than silently broaden the
surface. Stated in the repository's own terms: the value is canonicalized to an absolute path
and rejected if it resolves outside the working tree, then quoted and passed after `--` in
any emitted command, so neither a leading dash nor a shell metacharacter in a filename can
change what runs. Validation alone is not the guarantee — the argument boundary is.

This must be re-stated in both parents' own Security Considerations. One of the two has no
such section today, so this design creates it rather than assuming a home exists.

The claim that the flag never enters the positional slot holds only once the residue rule is
stated, because the parents validate their positional argument as provided, byte for byte,
with no normalization. The rule: the flag and its value are removed from the argument string
before the positional slug is read, and what remains is validated unchanged. A bare flag with
no value is rejected at setup, naming the missing argument, before any state is written.

The re-validation that happens when a run resumes against a recorded upstream is a second
interpolation site, not a repeat of the first, and carries the same discipline.

### The write-target set

The supplied upstream is a read target only — recorded, handed to a child, never written to
— so no new path becomes a write destination. The claim is true in substance but is only
*checkable* for one of the two parents, since the other declares no write-target set at all.
This design adds that declaration so the property can be verified rather than asserted.

### The mutation path reads more than it did

The finalization change is a net reduction in risk: it prevents a mutation that strands
references. It does, however, widen what the mutation path reads, which the parser half does
not. The walk goes from parsing the documents on its own chain to parsing every
document the index covers. Each of those files was already an input to the validator; none
was previously an input to the mutation path, and that distinction is worth stating rather
than eliding. Node paths are canonicalized with the index's own primitive before any referrer
lookup, so the walk and the map agree on what names the same document; a canonicalization
failure blocks the transition rather than silently missing referrers.

The parser change genuinely adds nothing: it surfaces a YAML value the loader already parsed
and then discarded.

### The fail-open compromise, extended

When the corpus cannot be indexed the referrer map cannot be built and the retirement guard
cannot run. Failing closed would let one unparseable document block every finalization and
would break existing tests the requirements forbid changing, so the walk fails open — but
visibly, recording on each transition node that the guard did not run.

Two properties of that compromise decide whether "visibly" is true. The reachable failure is
not a total index failure but a *partial* one: a single document failing to parse during
index construction yields an incomplete referrer set, which is the silent version of the same
hazard and must produce the same note. And a note that lands only in the structured report is
visible only to whoever reads the report, while the automated caller reads a rendered field
and exits zero. The note must reach the surfaced output, and the test the plan carries must
assert it arrives there rather than merely existing in the report.

### Housekeeping this change owes

Two shared references carry "where this rule is enforced" tables with explicit
keep-in-sync instructions. This change adds four enforcement points — two parents and two
head children — and both tables need the rows.

## Consequences

**Positive.** Three guarantees become structural: reader agreement is enforced by there
being one reader, duplicate findings become unconstructible rather than removed afterwards,
and both validator modes agree because one function produces both. A live false positive is
removed — the validator stops demanding a live ROADMAP be deleted when one feature beneath
it finishes. The finalization walk stops producing the class of damage that left five
dangling references in this repository. Two head children lose a defect unique to them:
they are the only document-emitting children that conflate where an upstream is with what
the produced document is called.

**Negative.** The retirement guard's reach is bounded by the index's directory coverage: a
document outside those directories can still reference an ancestor and will not block its
retirement. That is the guard's scope, not a bug, and it is stated so nobody reads the
protection as total. The unbounded alias expansion the YAML loader permits is a pre-existing
property this change neither introduces nor closes, recorded because the parsing work is the
natural place someone would expect it to have been addressed.

The evaluation restructure is the largest change and touches the module every
lifecycle finding flows through, so its regression surface is the whole corpus rather than
one check. A `upstream: |` block-scalar value stops half-working, which is a behavior
removal even though no document uses it. The conflict diagnostic reports rather than
resolves — an author with genuinely conflicting consumers is told to fix the lineage, not
given a status that satisfies everyone. The parent half now changes four skills rather than
two, because the hand-off cannot work without the children accepting the flag.

**Mitigations.** Corpus invariance is verified before and after against every repository in
the test set, in both modes, which is what catches an evaluation regression — with the one
named exception above, since removing a live false positive necessarily changes a result and
would otherwise read as the very regression the check exists to find. All three
sequencing edges are encoded in the plan's dependency graph rather than left to memory,
including the multi-edge-walk-before-map edge, which is the least obvious of the three and
therefore the one most likely to be dropped. The root-versus-member repair ships as the
conflict work's first commit, so the false positive cannot be spread by a partial landing.
The un-indexable-corpus compromise is recorded on the node, surfaced on the rendered output
rather than only in the structured report, and asserted by a test that checks it arrives
there.

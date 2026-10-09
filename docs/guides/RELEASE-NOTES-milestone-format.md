# Milestone roadmaps

Roadmap items can now be milestones: an outcome someone can exercise end to
end, with a check someone other than the session that delivers it can
judge. `/roadmap` writes them by default and `shirabe validate` holds them
to their fields. An existing roadmap keeps validating as it did; what
changes is that populate now draws dependency edges it used to miss (see
Migrating a roadmap).

## What's new

**`schema: roadmap/v2` marks a milestone roadmap.** Each item carries an
`**Outcome:**`, one or more `**Evidence:**` clauses, a `**Left open:**`, a
one-line `**Dependencies:**` list and one of four Status values (`Not
started`, `In progress`, `Done`, `Dropped`), with optional `**Needs:**` and
`**Delivered:**` lines. The format, a worked example and the rule for when a
milestone is Done are in `skills/roadmap/references/roadmap-format.md`,
Milestones.

**FC21 checks milestone roadmaps.** On a `roadmap/v2` roadmap, `shirabe
validate` reports an error naming the milestone (`[FC21] milestone 'AB1:
Loader' has no Evidence`) for a missing or empty Outcome, Evidence with no
clause, a missing Left open, Dependencies or Status, a Dependencies line that wraps
or names something that isn't another milestone or `<owner>/<repo>#<n>`, a
Status outside the four values, a repeated tag, and a `###` heading in
Features that isn't a milestone heading. `roadmap/v1` roadmaps get exactly
the findings they got before.

**`/roadmap` drafts milestones and sharpens them in place.** New roadmaps
are `roadmap/v2`, and the jury sends back an Outcome that names mechanism,
Evidence only the author could judge, and a Left open that holds part of
the Outcome. Run on an Active `roadmap/v2` roadmap, `/roadmap` offers to
sharpen one milestone's Evidence or Left open in place.

**Prefixed tags resolve everywhere.** A dependency written as a heading tag
(`AB1`, or `AB10a` with a letter suffix) now resolves in populate and the
validator, not only `Feature N`, and so does an `F<N>` written in a
Dependencies line. Populate draws those edges on both schema versions, so a
`roadmap/v1` roadmap whose dependencies name prefixed tags or `F<N>` gains
diagram edges and `F<n>` dependency cells the next time it is populated.
A `Feature N` that names no feature no longer draws an edge to nothing,
and an item that mentions its own tag or number draws no edge to itself.

Populate and the coordinator's picker don't read a Dependencies line the
same way yet. Populate keeps a mention that is marked soft or sits in
parentheses and counts it as a dependency; the picker drops both. On a
`roadmap/v2` roadmap FC21 keeps Dependencies to a plain list of tags, so the
two agree there; on a `roadmap/v1` roadmap written in prose they can
differ.

**The coordinator reads older roadmaps the way a person would.** The
picker reads a Dependencies paragraph across its wrapped lines, ignores
mentions in parentheses or marked soft (`soft`, `optional`, `preferred`,
`paced by`, or a sentence opening `Soft`), treats a Status that opens with
`Done` or `Shipped` as finished whatever follows, and never reports a
finished item as blocked. Its done check widens with it, so the status
write-back refuses an item whose Status reads `Done -- shipped in #12`,
and close-out reads such a roadmap complete.

**The status write-back records `**Delivered:**`.** When the coordinator
records that a feature's work merged, it writes the pull requests on a
`**Delivered:**` line after the Status and no longer touches any
`**Outcome:**` line. In a public roadmap that line names only public pull
requests; a mechanical guard is tracked in #682.

## Migrating a roadmap

**Run populate once on an existing roadmap that uses prefixed tags.** On a
`roadmap/v1` roadmap whose Dependencies name prefixed tags, or whose
headings carry a letter suffix (`### AB10a:`), the next populate rewrites
the Implementation Issues table and the Dependency Graph: rows that read
`None` gain their real dependencies, and a suffixed heading now counts as a
feature, so the `F<n>` keys after it renumber. Give each such roadmap one
populate pass of its own, so the rewrite isn't folded into an unrelated
change, such as the coordinator's status write-back.

A roadmap already written with the milestone fields (`### Feature N:`
headings, `**Outcome:**`, `**Evidence:**`, `**Left open:**`,
`**Dependencies:**` naming `Feature N`, a bare Status word and a
`**Delivered:**` line) migrates by changing its `schema:` line to
`roadmap/v2`; run `shirabe validate` on it and fix what it names. A roadmap
that recorded merged pull requests on an `**Outcome:**` line renames that
line `**Delivered:**` and writes the item's real outcome in its place.

## Not in this release

The Done rule is documentation for now: the completion cascade and the
coordinator's status write-back still set Done when work merges, before
anyone has judged the Evidence. Enforcing the rule at the coordinator, so
that a milestone reaches Done only on a verification verdict, is later
work.

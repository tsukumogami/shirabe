<!-- decision:start id="compression-strategy" status="assumed" -->
### Decision: Compression Strategy for Completed Artifacts

**Context**

After a plan's implementation completes, DESIGN docs accumulate an
"Implementation Issues" section added by `/plan`. This section contains an
issues table (GitHub links, dependency columns, complexity labels) and a Mermaid
dependency diagram. For design-input mode it also includes a `Plan:` line
referencing the PLAN doc — which the cascade deletes. All of this content is
fully captured in git history and the GitHub issue tracker once work ships.
Leaving it in the DESIGN doc adds noise and contains a broken link.

PRDs may contain a Downstream Artifacts section linking to the design doc, PLAN
doc, and/or issues. After cascade, the PLAN doc link is broken, but the design
doc and issue links remain valid historical navigation. PRDs have no other
candidate for stripping: all seven required sections are durable records (problem,
goals, user stories, requirements, acceptance criteria, out-of-scope). The
optional sections that aren't durable (Open Questions) are already removed before
Accepted status, so they're never present when compression runs.

The constraint that compression must use a deterministic script rather than agent
inference narrows the implementation to `awk`/`sed` operations on known, stable
heading boundaries.

**Assumptions**

- The Implementation Issues section heading is exactly `## Implementation Issues`
  with no variation across all PLAN-produced DESIGN docs. Two real examples and the
  phase-7-creation.md template confirm this. If wrong: the strip script misses the
  section (no data loss, just no stripping).
- PRD acceptance criteria are checklist-format (`- [ ]` / `- [x]`), not large
  tables, so they don't constitute compression-worthy bulk. Verified against
  prd-format.md.
- By the time cascade runs, PRDs are already at "In Progress" or later status,
  meaning the Open Questions section is already absent (required before Accepted).

**Chosen: Strip Implementation Issues from DESIGN; leave PRD body untouched**

For DESIGN docs: remove the entire `## Implementation Issues` section. The section
starts at the `## Implementation Issues` heading and ends at the line before the
next `## ` heading. The script:

```sh
# Remove Implementation Issues section from a DESIGN doc
strip_implementation_issues() {
    local file="$1"
    awk '
        /^## Implementation Issues/ { skip=1; next }
        skip && /^## / { skip=0 }
        !skip { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}
```

This removes the issues table, Mermaid diagram, and the PLAN doc `Plan:` line.
All of these are covered by git history and GitHub issue state.

For PRDs: no content removal. The status transition to Done (triggered by the
cascade) is sufficient signal. The optional Downstream Artifacts section may
contain a broken PLAN doc link, but removing one line from an optional section
adds script surface without meaningful benefit — the link is navigational-only
and the broken destination doesn't corrupt any reference used by downstream
tooling.

**Rationale**

The Implementation Issues section in a DESIGN doc is the only part of any
artifact where all four disqualifying conditions converge: it's not present in
the original design (added by /plan), it duplicates information captured
elsewhere (GitHub issues + git history), it contains a stale reference (the PLAN
doc link), and it has a deterministic heading boundary. No other section in any
artifact meets all four conditions.

PRDs don't have an equivalent section. Their optional sections either carry
durable reasoning (Decisions and Trade-offs, Known Limitations) or are already
absent by the time cascade runs (Open Questions). Downstream Artifacts contains
mostly valid links; its one stale link doesn't justify section removal. Aggressive
compression of PRDs risks discarding the navigation from PRD to DESIGN, which
is the last readable link in the upward traceability chain.

Keeping the implementation to one script operation (DESIGN only) also reduces the
risk surface: a bug in a DESIGN doc stripper can corrupt at most one artifact per
cascade run; adding a PRD stripper doubles the failure modes without proportionate
benefit.

**Alternatives Considered**

- **Strip Implementation Issues + patch PLAN link in PRD**: Patches only the
  broken PLAN doc line from Downstream Artifacts. Rejected because the benefit
  (removing one stale navigational line from an optional section) doesn't justify
  the added script complexity and risk of incorrectly matching a `docs/plans/PLAN-`
  pattern in edge cases.

- **Strip Implementation Issues + remove full Downstream Artifacts section from PRD**:
  Removes the entire Downstream Artifacts section from PRDs. Rejected because it
  deletes valid links to the DESIGN doc and closed issues, losing the only
  reader-visible navigation from the PRD to its implementation artifacts.

- **No stripping; rely on status lifecycle only**: Leave all content intact.
  Rejected because it leaves a stale PLAN doc reference inside the DESIGN doc
  (broken link), and fails to deliver Feature 8's compression goal. The lifecycle
  status change alone doesn't help readers who are looking at the DESIGN doc and
  see a table of closed issues and a diagram with now-irrelevant color coding.

**Consequences**

After cascade, DESIGN docs with status "Current" are slimmer: the implementation
scaffolding is gone and no broken links remain. The durable content (decisions,
rationale, architecture, consequences) is fully preserved. PRDs transition to Done
with content intact; the Downstream Artifacts section may carry a broken PLAN doc
link, which is cosmetic.

The strip operation is one `awk` invocation per DESIGN doc. It's idempotent: if
the section is already absent (e.g., if /plan was never run, or the cascade ran
twice), the command is a no-op. The cascade script must check for section presence
before invoking the stripper to avoid spurious "section not found" errors or
empty-file bugs if the Implementation Issues section is the last section.
<!-- decision:end -->

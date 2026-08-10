# Populate defaults to issueless — Migration Guide

**This release contains a breaking change to `shirabe roadmap populate`.**
If you invoke that subcommand directly, read the next section.

`shirabe roadmap populate <path>` used to create one GitHub issue per feature
when you gave it no mode flag. It no longer does. The unflagged invocation now
renders the roadmap's reserved sections from the Features section and makes no
GitHub call at all. To create issues, pass `--issues`.

Alongside that, `/roadmap` now fills a roadmap's reserved Implementation Issues
and Dependency Graph sections during its normal run, so you no longer have to
remember a second command.

## Breaking change: what to do

If you have a script, alias, CI step, or saved command that looks like this:

```bash
shirabe roadmap populate docs/roadmaps/ROADMAP-thing.md \
    --milestone "Thing" --output-map map.json
```

add `--issues`:

```bash
shirabe roadmap populate docs/roadmaps/ROADMAP-thing.md --issues \
    --milestone "Thing" --output-map map.json
```

Without it the command still succeeds and still populates both sections — it
just does so issuelessly, and files nothing. **Nothing errors.** The signal
that you got the issueless path is an empty `mapping` object in the summary
JSON on stdout, and an Implementation Issues table keyed on feature labels
rather than issue links.

If you were already passing `--no-issues`, nothing changes. That flag is
retained, still means issueless, and is not deprecated.

New: passing both `--issues` and `--no-issues` is now an error rather than
silently resolving to one of them. The rejection happens during argument
parsing, so a conflicting invocation writes nothing and calls no `gh`.

## Why the default flipped

Blast radius, not ergonomics.

Getting it wrong toward issueless leaves you with a populated local file and
no issues — you notice, you add `--issues`, you re-run, and nothing outside
your working tree ever knew. Getting it wrong toward issue-creating files
issues on a repository other people share, and somebody has to go close them
by hand. Both mistakes are equally easy to make. Only one of them leaves a
mess you cannot clean up locally.

This reverses a documented decision. `DESIGN-roadmap-issueless-preference.md`
recorded decision driver D5, requiring the default to stay `required` for
backward compatibility. That was the right call when issueless mode was new
and unproven. It has since shipped, had its table rendering fixed, and become
the mode the `/roadmap` workflow itself uses on every automatic run — so the
compatibility argument no longer outweighs the asymmetry. The full reasoning
is in `docs/decisions/DECISION-populate-issueless-default-2026-08-10.md`.

## `/roadmap` now populates automatically

The reserved Implementation Issues and Dependency Graph sections used to be
filled only when someone typed `/roadmap populate <path>`. Because `shirabe
validate`'s FC16 check tests those sections' shape rather than their content,
an empty skeleton passed validation at every lifecycle state — so a roadmap
could be drafted, jury-reviewed, activated, merged, and worked to completion
with both sections blank, and nothing anywhere complained.

Now:

- **During Phase 4**, after the jury findings resolve and before you're asked
  to approve, the sections are populated issuelessly. What you review is what
  merges.
- **On the `Draft -> Active` transition**, they're populated again. Populate is
  idempotent, so this is a no-op unless the Features section changed during
  review. It also means `/roadmap activate <path>` on an older roadmap fills
  its sections on the way through.

Neither automatic run creates issues, and neither presents the issue-creation
approval gate — there is nothing to approve when nothing is created.

## Filing issues is now a separate step

If you want your roadmap's features tracked as GitHub issues, do it after the
roadmap is approved:

```
/roadmap populate docs/roadmaps/ROADMAP-thing.md --issues
```

This goes through the approval gate — you see the feature count, the names,
and the milestone before anything is filed — and it regenerates both sections
so the table carries issue links instead of `needs-*` labels.

## The `## Roadmap Issues:` header changed meaning

The CLAUDE.md header still takes `optional` or `required`, but two things about
it are different:

- **It defaults to `optional` when absent**, matching the CLI's new default.
  It used to default to `required`.
- **It only governs a human-invoked `/roadmap populate <path>` with no flag.**
  It has no effect on the automatic population, which is always issueless.

The resolution stack is `flag > ## Roadmap Issues: header > issueless default`.

If your repo relied on the absent-header default to get issue-creating
populate, add `## Roadmap Issues: required` to CLAUDE.md — or, better, pass
`--issues` at the point of use, which says what you mean regardless of what
any default happens to be.

## References

- `docs/decisions/DECISION-populate-issueless-default-2026-08-10.md` — the
  decision record, including what it supersedes.
- `docs/designs/current/DESIGN-populate-issueless-default.md` — the design.
- `skills/roadmap/SKILL.md` — the Populating the Issues Table section.

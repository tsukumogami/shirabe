# Finalization

Verify changes, create summary, record the pre-PR referents, clean up artifacts.

## What this state must write

Two koto context keys, both before you submit `ready_for_pr` (or before a
deferral is approved). They are
checked on the way out of this state and checked again at `pre_pr_evidence`:

| Key | Required | Gate |
|-----|----------|------|
| `summary.md` | a `## Changes Made` heading, spelled exactly that way | `summary_shape` |
| `pre_pr.md` | one line `cleanup_commit: <sha>`, 7 to 40 lowercase hex characters, naming a commit that is `HEAD` or an ancestor of it | `cleanup_referent` |
| `pre_pr.md` | one line `design_diagram: docs/<path>.md`, a file in `HEAD`'s tree, or `design_diagram: not-applicable: <reason>` | `diagram_referent` |

`## Changes Made` is required because it's the part of the summary a reviewer
and the PR body are built from; the rest of the template below is guidance.
The `pre_pr.md` lines are referents rather than claims, so a word such as `done`
or `yes` where a sha or a path belongs fails, and so does a sha that names no
commit in `HEAD`'s history or a path that isn't committed.
`scripts/check-pre-pr-referents.sh` makes both checks. koto keeps only the
gate's exit status, so when one fails, run the script yourself (the template's
finalization directive gives the command) and read the reason it prints. `not-applicable` is hyphenated and
needs a reason after it. Don't confuse it with the `not_applicable` evidence
value you submit later at `pre_pr_evidence`: that one is an enum, this one is a
line of text, and neither accepts the other's spelling.

Why here: at `pre_pr_evidence` the same check failing ends the run at
`done_blocked`, and the run has to be re-entered to fix one artifact. Here a
failure only holds. A `ready_for_pr` submission with either artifact malformed matches no edge, the
state stays `finalization`, and the response's `blocking_conditions` names the
failing gate. Fix that artifact and submit again:

- `summary_exists` or `summary_shape` failed: write `summary.md` with a
  `## Changes Made` section.
- `cleanup_referent` failed: write `cleanup_commit: <sha>` in `pre_pr.md`, from
  `git rev-parse HEAD` rather than typed by hand.
- `diagram_referent` failed: write `design_diagram: docs/<path>.md` for a file
  committed in `HEAD`'s tree, or `design_diagram: not-applicable: <reason>`, in
  `pre_pr.md`.

The same hold applies to an approved deferral at `deferral_approval`.

## Auto-Skip

Check CLAUDE.md label vocabulary for summary-skippable labels. Default: skip
for `docs`, `config`, `chore`, `validation:simple`; generate for `bug`,
`enhancement`, `refactor`, `security`.

Skipping means a short summary, not none: `summary.md` still needs its
`## Changes Made` section, because the gate doesn't read labels.

## Steps

### Code Cleanup

Remove: debug statements, commented-out code, addressed TODOs, unused imports.

### Final Verification

Run complete test suite, build, linting. All must pass.

### Create Summary

Pipe the summary into koto context under the key `summary.md`. See
[`../koto-context-conventions.md`](../koto-context-conventions.md)
for the canonical ingestion pattern (stdin pipe; ephemeral
`mktemp`+`rm` alternative).

Summary format. `## Changes Made` is required (see the table above); the other
sections are the recommended shape:

```markdown
# Summary

## What Was Implemented
<Brief description>

## Changes Made
- `path/to/file`: <what changed>

## Key Decisions
- <Decision>: <rationale>

## Test Coverage
- New tests added: <count>
- Coverage change: <before> -> <after>

## Known Limitations
- <Limitation>

## Requirements Mapping

| AC | Status | Evidence |
|----|--------|----------|
| <criterion> | Implemented | <file:function> |
| <criterion> | Deviated | <what and why> |
```

### Record the Pre-PR Referents

After the cleanup pass, write `pre_pr.md`:

```bash
cat <<EOF | koto context add <WF> pre_pr.md
cleanup_commit: $(git rev-parse HEAD)
design_diagram: not-applicable: no design document is touched
EOF
```

`cleanup_commit` is the commit whose diff you reviewed in the cleanup pass.
`design_diagram` is the path of the design diagram you updated, or
`not-applicable: <reason>` when the change touches no design document. When the
issue body carries a `Design:` reference, run the update in
`phase-6-design-diagram-update.md` now and record that path, so the line names
an update that has happened rather than one still to come. The path has to be
committed before you submit `ready_for_pr`: the gate looks for it in `HEAD`'s
tree, not in the working directory.

### Consider Manual Testing

Recommend `/try-it` if changes affect user-facing behavior, complex logic, or
integration between components. Skip for docs-only or config changes.

## Retry Loop: issues_found

Returning to implementation invalidates the summary and the pre-PR referents.
Clear them before submitting:

```bash
OUTCOME_FIELD=finalization_status
for KEY in scrutiny_results.json review_results.json qa_results.json summary.md pre_pr.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and its gate may accept it."
    echo "Do NOT submit finalization_status: ready_for_pr on the next pass."
    echo "To stop the run, submit finalization_status: deferral_requested."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"issues_found\"}" --no-cleanup
```

`pre_pr.md` is on the list because it's written in this state, so
after a return trip the previous round's line would still satisfy the referent
gates while naming a commit reviewed before the fixes.

The diagnostic names `deferral_requested` rather than an escalate outcome because `finalization` has no escalate edge. Its exits are `ready_for_pr`, `issues_found`, and `deferral_requested`, and the last is the one that still moves the run forward when the summary cannot be cleared. Why the block checks both signals is in `phase-4a-scrutiny.md`.

A caveat or hedge ("experimental", "not yet handled", "known limitation") in the
issue's shipped artifacts is legitimate only where it records a human-approved deferral.
If you find yourself writing one, the matching acceptance criterion is unmet: submit
`deferral_requested` and take it through the `deferral_approval` gate rather than
shipping the caveat unapproved.

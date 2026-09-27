# Pragmatic review: Issue 1 (reconcile-report.sh)

No blocking findings. The script is one jq program plus one renderer, sized to
the acceptance criteria. The leg and merge-state handling reach slightly into
Issue 3's criteria, but the report schema is meant to be fixed up front, so
that's in scope.

## Advisory

1. `.github/workflows/check-coordinate-reconcile-scripts.yml:7` -- the trigger
   path `skills/coordinate/scripts/testdata/reconcile/**` matches nothing, and
   the comment at lines 23-25 describes gh/git/niwa/koto stand-ins that don't
   exist yet. Drop both until the issue that adds them, or leave them if
   Issues 2 and 3 are landing in the same PR anyway (single-pr mode, so this
   is inert).

2. `reconcile-report.sh:233` vs `:280` -- the report carries
   `reasoning.key = "reconcile/reasoning.md"`, but the renderer hardcodes the
   same string instead of reading `.reasoning.key`. Use the field, or drop
   `key` if nothing downstream reads it.

3. `reconcile-report.sh:143` -- `grade_of` has one caller (`leg`). Small and
   named well, so inline or keep.

4. `reconcile-report_test.sh:66` -- `got=` is assigned and never read; only
   `rc` matters.

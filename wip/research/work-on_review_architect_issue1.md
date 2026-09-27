# Architect review: Issue 1 (reconcile-report.sh)

Scope: skills/coordinate/scripts/reconcile-report.sh, reconcile-report_test.sh,
.github/workflows/check-coordinate-reconcile-scripts.yml, against
DESIGN-coordinate-reconcile.md Decisions 2 and 3 and "The contract with the
record feature".

## Verdict

No blocking findings. The script matches Decision 2's split: it is the pure
report function, reads only stdin, calls nothing but jq, sources nothing (so no
dependency on coord-common.sh or reconcile-deps.sh, which is right -- those
belong to the read and check scripts), and documents both schemas in its
header. The output keys match Decision 3's list (header, changes, holdings,
waiting, nowhere_else, side_effects, deferrals, reasoning, not_verified), the
schema id is `coordinate-reconcile-report/v1` as the gate and the pick reader
expect, and the exit-code convention (0 / 64 usage / 65 bad input) matches
sibling pure scripts such as skills/execute/scripts/coordination-verdict.sh.
The facts schema's per-holding `facts[]` with `{kind, status, read_at, reason}`
gives Issues 2 and 3 a clear target for `reconcile-check.sh` subcommand output.

## Advisory

### 1. Report v1 freezes display prose as enum values

reconcile-report.sh:130-163, 227, 247. `holdings[].state` carries values like
`"no pull request; worker not found on this read"`, `holdings[].next` carries
the seven next-line sentences, and `side_effects[].verdict` is converted from
the facts token `not_confirmed` to the display string `not confirmed`. The
script itself already matches on these sentences to build `waiting[]`
(`.next == "ready to land"`), and `reconcile-report-get.sh` (Issue 5) and the
pick state will have to do the same. The PRD's reason for a JSON report is
that pick shouldn't parse prose; `phase` (a closed two-value set) satisfies the
stated "count holdings by phase" need, so this isn't blocking, but once Issue 5
ships a consumer against v1, rewording a next line becomes a schema change.
Cheapest fix before Issue 5: emit tokens in the JSON (`state: "no_pr"`,
`worker: "missed"`, `next: "ready_to_land"`, `verdict: "not_confirmed"`) and
map them to sentences only in the `md` renderer.

### 2. Facts schema has no per-row provenance for handoff rows

Header, lines 24-25; report header lines 193-195; renderer line 264. Source is
document-level (`record.source: record|handoff`). The design says the
handoff's tables "join the work queue labelled with the handoff's heading
date", and Issue 4's criteria say the same, i.e. at discipline scope record
rows and handoff rows coexist. With a document-level flag, the renderer labels
every row "as written by the previous rotation" or none. Issue 4 will need an
optional per-holding (and per-side-effect/deferral) `source`/`as_of` field in
facts v1 and a matching field in report v1. Both are additive, so this can wait
for Issue 4, but it should be noted there rather than rediscovered.

### 3. The markdown is rendered from facts, not from the sealed JSON

Lines 7-8, 251-259. `md` mode rebuilds the report from facts and renders it,
so the pass calls the script twice on the same input. That is deterministic
and agrees with Decision 3 in effect, but the design's phrasing is that the
rendering is derived from the JSON. Having `md` accept the report JSON
(`reconcile-report.sh md < report.json`) would make the rendered text a
function of the exact sealed bytes, let `reconcile-report-get.sh` or a future
directive re-render from the sealed key without facts, and remove the
second-call contract from the pass. Small change now; harder once Issue 5 wires
the double call.

### 4. `inventory.items[].clone` is not covered by the path rule

Line 223. `safe_path` is applied to `.path` but not `.clone`. Decision 3 says
file paths in the report are clone-relative and never name the instance; the
facts header doesn't say `clone` is an instance-relative name. Either state in
the facts schema that `clone` is relative to the instance (Issue 3's contract)
or run it through `safe_path` too.

### 5. The workflow's macOS leg does not run the bash 3.2 floor

check-coordinate-reconcile-scripts.yml:23-28. The comment says both platforms
"keep the bash 3.2 floor honest on macOS", but a bare `bash` on the macOS
runner resolves to the image's newer bash; check-execute-scripts.yml:208-222
explains exactly this hole and routes its macOS leg through
`scripts/check-bash-floor.sh --backend system <suite>`, with the suite
registered in scripts/check-bash-floor.sh (SUITES, suite_scripts,
suite_workflow). scope and deliver also call bare `bash`, so the convention
isn't uniform, but the comment here claims a guarantee the job doesn't give.
Either register a `coordinate-reconcile` suite and use the floor runner on
macOS, or drop the claim. Later issues will also need the paths filter to
include skills/execute/scripts/coord-common.sh once reconcile-deps.sh sources
it (Decision 2).

# Maintainer review: reconcile-report.sh and reconcile-report_test.sh

Scope: `skills/coordinate/scripts/reconcile-report.sh`,
`skills/coordinate/scripts/reconcile-report_test.sh`,
`.github/workflows/check-coordinate-reconcile-scripts.yml`.

The overall shape reads well: the header documents both schemas, the jq
program is split into small named `def`s whose names mostly match what they
compute, and the render step only formats the JSON. The findings below are
places where the header, a name, or a test name tells the next person
something the code doesn't do.

## Blocking

### 1. `$nopr` means "no successful PR read", but the report says "no pull request"

`reconcile-report.sh:214-219`. `(ok($pr) | not) as $nopr` is true in two
different situations: the row has no pull request (no `pr` fact), and the
row has one but the read failed (`status: not_verified`). The name `$nopr`
and the `why` text treat both as "no pull request". So a holding whose PR
exists (maybe already merged) but whose read timed out shows up under
"Exists nowhere else" as `no pull request`. That's a stated fact the pass
never observed. `state_of` handles the same input correctly ("not verified"),
so the two sections disagree about the same holding.

The next person will read `$nopr` as "this holding has no PR" and build on it.
Fix: separate "no pr fact" from "pr fact present but not ok". Only the first
should say "no pull request". The second should either be left out of this
section or say the PR read failed. Add a test with a `not_verified` pr fact.

### 2. The header promises failed reads never keep a success grade, but side effects do

The header (lines 88-89) says: "A claim whose read failed is graded 'not
verified', never with the grade a successful read would have earned." The
side-effects block (226-229) grades on `.fact.verdict` alone and never looks
at `.fact.status`. A side effect whose re-check failed (`status:
not_verified`) still goes into `side_effects[]` graded "verified by reading"
with whatever verdict it carries. It's also listed under `not_verified`
(243-244), so it appears in both places. If its verdict is `not_confirmed`, it
also lands in `waiting`. Deferrals get this right: line 230 drops rows that
aren't `ok`, and the input doc at 54-55 says so. Side effects have no such
note and no such filter.

Someone who trusts the header's invariant won't look for this. Either filter
or regrade side effects the way deferrals are handled (and add a test), or
document in the side-effects input schema that the pass never sends a failed
status with a verdict. As written, the header and the code disagree.

## Advisory

### 3. The "branch tip differs" change puts a live value in `recorded`

`reconcile-report.sh:179-180`. Everywhere else in `changes[]`, `recorded`
means what the record said. Here it holds `$pr.head`, which is a live read,
and the renderer prints it as `record said <pr head>, now <branch tip>`. A
reader of the report, or a developer adding a new change kind, will take
`recorded` to mean the record's value. Either compare against
`.row.verified_head`, or add a comment saying this entry compares two live
reads and pick rendered wording that doesn't claim the record said it.

### 4. The board's `at` sha is never read; a test name suggests it is

`next_of` (158-159) returns "ready to land" when the board holds and
`$pr.head == .row.verified_head`. The board fact's `at` field, which the
input doc lists, is never used. The test at line 108 is called "holding board
at verified head -> ready to land", and its twin at 109 changes both the board
`at` and the PR head together. So nothing shows whether `at` matters. The next
person will assume a board read at a stale sha blocks "ready to land". It
doesn't. If the pass guarantees the board is always read at the PR head, say
that in the `board` input doc. If it doesn't, this is a gap. In either case,
rename the test or add a case where `at` differs from the head.

### 5. The recognised phase values are listed twice

`phase_known` (119) and `phase_of` (120-127) each list
`scoping|scoping-ahead|executing` separately. If someone adds a value to
`phase_of` and misses `phase_known`, the holding is classified correctly but
still gets reported as "unrecognised phase value". Derive both from one list,
or add a comment tying them together.

### 6. A worker in "ambiguous" state reads differently in different sections

`state_of` (135-136) keeps "ambiguous" separate from "not found".
`nowhere_else.why` (218) reports any non-`found` host as "worker not found on
this read", so an ambiguous host is described as not found. If that's
intended, it needs a one-line comment. Otherwise, pull the wording into one
shared `def`.

### 7. Hard-coded `recorded` values in `changes_of` rely on unstated assumptions

`recorded: "open"` (169) assumes the record always said open whenever a pr fact
exists. `recorded: "ready (parked)"` (172) assumes a non-empty `verified_head`
means the row was parked ready. `recorded: "none yet"` (183/185) assumes an
`appeared` fact only comes with a PR-less row. These are pass-side contracts,
and nothing near the code states them. A short comment on each would tell the
next person which facts the pass guarantees.

### 8. `board_of` checks every board fact; `fact()` takes only the first

`fact($k)` (113) uses `.[0]`, but `board_of` (145-149) scans all `ok` board
facts and fails if any of them fails. The difference is probably deliberate
(more than one required check?), but nothing says so, and the input doc
describes `board` as one fact with one `at`. Add a line explaining why there
can be several.

### 9. Header and workflow comments point at files that don't exist yet

- `reconcile-report.sh:7` names `reconcile-pass.sh` as the caller that runs
  the script twice. That file isn't in the tree yet (the PLAN puts it in a
  later issue).
- The workflow comment (23-25) says the tests go through "test-local gh, git,
  niwa and koto stand-ins", and the trigger paths include
  `skills/coordinate/scripts/testdata/reconcile/**`. Neither exists yet: this
  test is pure jq with no stand-ins, and the workflow runs only
  `reconcile-report_test.sh`.

As it stands, the next reader will go looking for stand-ins that aren't
there. Word these as "will" or "the pass, added later", or update them when
the pass lands.

### 10. Test header claims more redaction than the script provides

The test header (8-9) and the case at 196 say "no raw read output, absolute
path, session id or instance name reaches the report". The script only hides
absolute paths in inventory items (`safe_path`, used at 223). The test passes
because its fixtures put identifiers only in fields the report drops, like
`host.instance`, `session_name` and `stdout`. A path or session id in
`reason`, `detail`, `result` or `target` is passed through unchanged. Someone
reading the test will think the script redacts in general. Either narrow the
wording to "inventory paths are withheld and unreported fields are dropped",
or add a comment on `safe_path` saying redaction relies on the pass not
putting identifiers in free-text fields.

### 11. Smaller test-helper points

- `facts()` (31-41): passing `discipline` as the sixth argument also switches
  `source` to `handoff` and sets `handoff_date`. The EMPTY case at 72 depends
  on this. Mention it in the helper's usage comment.
- `holding()` default `"${3:-{\}}"` (45) is hard to read. A `local o=${3:-}`
  plus `[ -n "$o" ] || o='{}'` would be clearer.
- Line 66: `got=` is assigned and never used.
- Line 212: the regex `\b(gone|dead|lost)\b[^:]` has no comment. The `[^:]`
  seems to be there to skip a `what:` label, but the only nearby "gone" is the
  "branch gone" change text, which doesn't come before a colon. Say what it's
  meant to exclude. Also, the failure branch greps `gone|dead` but leaves out
  `lost`.
- Line 76 names "R16's order". That's the PRD-coordinate-reconcile R16, but
  the repo has dozens of R16s. Name the PRD, or describe the order in plain
  words.
- Line 190's name gives the bound formula (40 + 6 per holding). The 220 bound
  at 194 is the same formula over 30 items but doesn't say so.

### 12. Exit 65 covers both bad input and a jq program failure

Line 15 documents 65 as "the input is not a facts document", and line 251
exits 65 for any jq failure while building the report. A runtime error in the
program itself, such as string + null from an unexpected field type, is
reported as bad input. That's usually true here, but say "65: the input is not
a facts document or could not be reported" so the next debugger doesn't rule
out the program too early.

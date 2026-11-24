# Review levels

A `/work-on` run's review level decides which review panels a code change
goes through. Nobody chooses it up front: after implementation, the level
check sets it from the facts of the change, within the bound a coordinator
gave the run. The agent can raise it when the change is riskier than its paths
show, facts can raise it but never lower it, and every change to it lands in
a per-run ledger.

`scripts/review-level.sh` is the only way a level is set, raised or lowered.
Its header documents each subcommand and its exit codes; this page says what
the levels mean and the rules the script applies.

## The three levels

In increasing order:

| Level | Panels | Seats per round |
|-------|--------|-----------------|
| `light` | `light`: one seat | 1 |
| `standard` | scrutiny (3 seats), then review (3 seats) | 6 |
| `full` | scrutiny (3), then review (3), then QA (1) | 7 |

- **`light`** runs one panel, `light`, of one seat. The seat gets the same
  `scripts/review-packet.sh code` packet the review seats get (the acceptance
  criteria, the design context, the changed paths and the diff from
  `impl_base`), judges the change against the acceptance criteria, and returns
  the same verdict shape and the same definition of a blocking finding as a
  review-panel seat. No scrutiny, review or QA panel runs.
- **`standard`** runs scrutiny, then review. No QA.
- **`full`** runs scrutiny, review, then QA.

A blocking result from any panel, the `light` panel included, retries through
implementation under the same retry cap, and its next round is planned from
the findings ledger like every panel's: only the findings the fix made due are
re-verified. A `docs` or `task` run skips the level check and the panels, so
it records a level only when the agent set one.

## How the level is set

The template variable `REVIEW_LEVEL` holds the level, and the ledger holds
every change to it. At `review_level_check`, on every lap, koto runs
`review-level.sh facts` and then `review-level.sh set-from-facts`, which sets
the level to the highest of:

- the facts floor (below);
- the ledger's last level, which carries every raise the agent made, so a
  raise is kept; and
- the bound's floor.

When that differs from the ledger's level it writes one `from_facts` line;
when it's the same it writes no level line. A facts floor above the bound's
ceiling wins: the level is the facts floor and a `breach` line follows. A
facts floor at or below the ceiling never writes a breach. The level never
drops on its own: a lap whose diff is smaller keeps the level an earlier lap
reached, and only a `set` lower moves it down. Then it rebinds `REVIEW_LEVEL`
as `set` does.

A rebind shows only from koto's next tick, so the state doesn't route on the
variable. Its `level_route` gate runs `review-level.sh level <session> --exit`,
which reads the ledger's level and exits 11 for `light`, 12 for `standard` and
13 for `full` (10 plus the level's rank), 4 when no level is recorded and 66
when the read fails. `light` goes to the light panel and the other two to
scrutiny, in the tick that entered the state, so the run doesn't stop at the
level check on the passing path.

## Raising and lowering

`review-level.sh set <session> <level> [--reason <text>] [--cause veto:<criterion>]`
rebinds the variable on the live session and appends to the ledger in the
same call. It exits 0 when the change is recorded, 1 with a `refused:` line
when a rule below refuses it (nothing changes), 64 on a usage error, and 66
when the rebind or a context read or write fails (neither changes).

`set` is refused until the bound is recorded (`refused: no bound recorded
yet`), which `analysis`'s action does as the run enters it: a raise is made
from `analysis` on, before anything is implemented.

- **Before the first check.** With no level in the ledger yet, `set` records
  a `choose`, which the check then keeps as a raise. It is refused below the
  bound's floor; above the ceiling it needs `--reason` and is recorded as a
  breach.
- **Raise.** A higher level is free inside the bound: no reason needed. A
  raise above the ceiling needs `--reason` and is recorded as a breach. The
  exception is a **floor raise**, a raise to exactly the current facts floor
  from below it: it needs no reason anywhere, and above the ceiling it is
  recorded as a breach too, because the facts win over the ceiling. A raise
  made because the decider check vetoed the level passes
  `--cause veto:<criterion>` and is recorded as a veto; a raise after the
  agent's own `fail` answer is a plain raise.
- **Lower.** A lower level needs a non-empty `--reason`, which the ledger
  keeps. A lower below the facts floor or below the bound floor is refused,
  with or without a reason.
- **Same level.** No ledger line. The variable is rebound to it, which clears
  a hand rebind (below).

A `--reason` has control characters replaced by spaces and is cut to 200
characters before it's stored.

## The bound

A coordinator can give a run a floor, a ceiling, or both, each one of the
three level names, through `--review-floor=<level>` and
`--review-ceiling=<level>`. The run holds them in the `REVIEW_FLOOR` and
`REVIEW_CEILING` template variables, and `review-level.sh init` records them
once, in `analysis`'s action, as a `bound` line and the
`review_level_bound.json` key. The level the check sets never sits below the
bound's floor; it goes above the ceiling only for a facts floor or a raise
with a reason, and either is logged as a breach. A bound whose floor is above
its ceiling refuses every `set` and `set-from-facts`, naming both values, and
the level check holds under it whatever the level.

`/execute` and `/deliver` take the same two flags. `/deliver` forwards them to
`/execute`, and `/execute` sets them on every child task it spawns, only when
they aren't empty, so a run without the flags starts its children exactly as
before. Inside a `/work-on` run the bound doesn't move: the two variables aren't
rebind there, so a resume that passes a different bound is refused.

## The facts floor

After implementation and before the first panel of a code change, on every
lap, `review-level.sh facts` records the change's facts in
`review_facts.json` and derives a floor from them. Each gather is also
appended, as one line, to `review_facts.jsonl`, so the size of the change at
every lap survives the run for whoever reads its numbers later; nothing in
the workflow reads that history back.

- the diff is taken from two bases, the stored `impl_base` and the
  merge-base of HEAD with the default branch (origin/HEAD's branch, else
  `origin/main`, else `main`), and the larger one counts: more changed
  lines, then more files, with a tie keeping `impl_base`. An `impl_base`
  recorded after some of the work would otherwise hide that work and lower
  the floor. With no merge-base (no shared history) `impl_base` is used
  alone. On a shared branch the merge-base candidate is skipped and
  `impl_base` is the only base (see "A step's level under the lead shape"
  below). A merge of the default branch after `impl_base` isn't the step's
  change: when the default branch's merge-base with HEAD isn't already in
  `impl_base` (and isn't HEAD itself), the `impl_base` diff is taken from
  the clean merge of `impl_base` and that merge-base, so the lines, files
  and path classes the merge brought in don't count. A step with no merge of
  the default branch is measured from `impl_base` as before, and so is one
  whose merge with `impl_base` would conflict, which then counts what the
  merge brought in. `review_facts.json` names the winner in `base_source`,
  the shared branch in `shared_branch` (an empty string off one), and keeps
  both candidates under `bases`, with `bases.merged_default` naming the
  default-branch commit folded into `impl_base`, or null. Uncommitted work
  isn't counted. A rename is
  one file plus its changed lines, and both of its paths are classified; a
  deletion counts its deleted lines.
- changed lines (added plus deleted) and changed files;
- which path classes the changed paths fall in, and whether any path falls in
  none (`unclassified`);
- whether a test file changed (a path in the `test` class);
- whether a test file was edited rather than only added to (`tests_edited`):
  its diff removes or changes a line, it was deleted, renamed with a change or
  is a binary file that changed, or, for a fix, a reproducing test changed
  after its red. `scripts/lib/test-classify.sh` decides it, the same
  classifier the hold at `pass_counting` and the review packet's
  `## Test changes` section use, over the same base the facts chose;
- whether the acceptance criteria changed: a path under `docs/plans/` or
  `docs/prds/` changed, or the acceptance-criteria section of `context.md`
  differs from the copy `init` stored.

The classes and thresholds live in
[`review-level-rules.tsv`](review-level-rules.tsv), and changing one is a
change to that file only. The floor is the highest level any rule yields,
`light` when none does. A path can be in several classes, and each one
counts. A fix round (`fix-round.sh`) has one more rule, outside the file: the
last floor of the run it fixes, named `fix_round_parent`, so a round on a
shared branch, whose diff is the fix alone, never reviews below the run. The
shipped classes:

| Class | Paths | Floor |
|-------|-------|-------|
| `ci` | `.github/workflows/**`, `.github/actions/**` | `full` |
| `security` | `install.sh`, the rules file, `**/hooks/**`, `.claude/**`, `**/settings*.json`, any path containing `credential`, `secret`, `token` or `password`, `.env`, `.env.*`, `*.pem` | `full` |
| `template` | `**/koto-templates/**`, which hold the gates and the routing | `full` |
| `engine` | every script a koto template names in a gate's or a `default_action`'s command, listed path by path, plus every `*-open.sh` | `full` |
| `instruction` | `SKILL.md`, any path under a `references` directory, `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` | `standard` |
| `executable` | `**/scripts/**`, `scripts/**`, `crates/**` | `standard` |
| `test` | `test/**`, `tests/**`, `spec/**` (at any depth), `*.spec.*`, `*_test.*`, `test_*.*`, `**/evals/**` | `standard` |
| `manifest` | `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.toml`, `Cargo.lock`, `go.mod`, `go.sum`, `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `Gemfile`, `Gemfile.lock` | `standard` |
| `docs` | `*.md`, `docs/**`, `*.txt`, `LICENSE` | none |

The rules:

- `full` when a path is in the `ci`, `security`, `template` or `engine`
  class, or changed lines exceed 400, or changed files exceed 12, or a test
  file was edited (`tests_edited`), so the QA seat reviews the edit as well;
- `standard` when a path is in the `instruction`, `executable`, `test` or
  `manifest` class, or a path is in no class at all (`unclassified`), or the
  acceptance criteria changed, or changed lines exceed 40. A change whose
  only test change is a new test file or lines added to one floors here;
- `light` otherwise.

So `light` is reachable only when every changed path is documentation or in a
class no rule names. `docs` exists to keep a path out of `unclassified`: a
`README.md` alone stays `light`, a `SKILL.md` is `instruction` too and floors
at `standard`, `requirements.txt` is `manifest` too and floors at `standard`,
and a `.sh`, `.py` or `.rs` file in no class floors at `standard`. A test in
`review-level_test.sh` fails when a template names a script the `engine` class
doesn't cover, so the list can't fall behind the templates.

`facts` classifies with the copy of the rules `init` stored before
implementation, never with a file the run's diff can change, and the rules
file is itself in the `security` class. A change to the rules applies to runs
that start after it lands.

The level check (`review-level.sh check <session> --ledger`, a command gate
every route needs) judges the level `set-from-facts` recorded: it passes when
that level is at or above the floor, sits inside the bound (or above the
ceiling with a breach recorded), and the facts were gathered at HEAD.
Otherwise it holds with a `hold:` line naming why, as it does when no level is
recorded, and the run reaches no panel until the next tick's action sets the
level again or the agent raises it. koto's override record is the only way
past the hold without a raise, and the ledger reader counts each override.
Given a variable's value instead of `--ledger`, as a template from before this
change passes it, the check also holds when the variable differs from the
ledger, and with the level unset and no level in the ledger (a session from
an earlier template) it exits 3 and the run takes the full path.

The level check also carries a veto-mode decider check whose command is
`review-level.sh slice`: the counts, class names, booleans, the floor, the
order of the three levels, the rules above as the facts that call for each
level, and the ledger's level, never a path, a glob, a reason or criteria text.
Every value is typed (counts are non-negative integers, at most 16 class
names), so a hand-edited facts key can't carry text to the decider, and the
rules are rendered from the copy `init` stored, the one the floor was derived
from. It asks whether the level is too light for these facts under those
definitions. A session with no facts recorded gets `{}` and no rules, and the
decider escapes on it. `review-level.sh project <facts-file> <level>
[<rules-file>]` prints the same slice for a facts file, so a slice built
outside a live session is the script's own output. The slice's contract (its
sources, completeness case, measured size and trust record) is the
`work-on/review-level-fits-facts` entry
in `references/rule-registry.json`, with its written case in
`references/jev-criteria.md`. The check can only hold the run, never route it
or lower the level.

When the decider gives no verdict, the criterion falls back to the agent
instead of passing (koto 0.20.0), for a user whose decider runs in shadow as
well as one in veto: the check holds the run until the agent judges the level
itself and answers with `koto decider answer`. `pass` and `unclear` let it
through. An agent `fail` is acted on with a plain raise, not
`--cause veto:<criterion>`, because a `veto` ledger line records only a raise
the decider asked for. koto keeps the answer as the agent's: it is never
written as a decider verdict, so nothing that measures the decider reads it.

## A step's level under the lead shape

When `/execute` runs a plan in the lead shape, every step's `/work-on` child
commits to one shared branch, and the run's `SHARED_BRANCH` names it. The
review-level check passes it to `facts` as `--shared-branch`. There,
`impl_base` is the only base: the merge-base with the default branch holds
every earlier step's commits, so measuring from it would floor a late step on
work it didn't do. An `impl_base` that is unset on a shared branch is no base
at all, and `facts` exits 64 rather than falling back to the merge-base.
`record-changed-paths.sh` also measures from `impl_base`, which keeps the
siblings' commits out of `changed_paths.txt`, but it does fall back to the
merge-base when `impl_base` is unset. Both leave out a merge of the default
branch into the shared branch made after `impl_base`, the same way: the base
becomes the clean merge of `impl_base` and the default branch's merge-base.

The step's own `/work-on` sets its level from its own commits, inside the
bound the run was given. A path in the `ci`, `security`,
`template` or `engine` class floors a step at `full`, as anywhere else. A step
that touches none of those classes and stays within 400 changed lines and 12
changed files floors no higher than `standard`, however much the steps before
it changed or a merge of the default branch brought in.

## Hand rebinds

`REVIEW_LEVEL` can also be changed by hand with `koto init <session>
--attach-live --var REVIEW_LEVEL=<level>`. The level check doesn't read the
variable, and its action rebinds it to the ledger's level on every lap, so a
hand rebind made before the check changes nothing.

The level check runs once per lap, and two later states route on the level
again: `review` (whether QA runs) and `light_review`. Each carries a
`level_unchanged` gate, `review-level.sh agree`, on every route that depends
on the level, its carried route included. It passes when the variable equals
the ledger's last level, and when the variable is empty, and holds otherwise,
so a hand rebind made while the run sits in one of those states can't skip
QA or leave the light panel with the ledger untouched. A `set` to the
ledger's level clears the hold. An empty variable passes because it can't
skip a panel (review sends it to QA, and light_review doesn't route on it),
and because the tick that records the run's first level enters the light
panel or scrutiny before the rebind shows.

An attach re-applies every rebind variable from its own arguments, so one that
doesn't pass `REVIEW_LEVEL` (a resume through `koto init --attach-live`, say)
empties it. The next level check rebinds it from the ledger. For the same
reason `set` and `set-from-facts` pass `PLUGIN_ROOT` along with the level.

## The ledger

The context key `review_level.jsonl` holds one JSON object per line, only
ever appended to. No retry clearing step removes it. Each line has `ts` (UTC,
ISO-8601) and `event`, plus the fields the event needs from `from`, `to`,
`reason`, `rule`, `floor`, `ceiling`, `level` and `head`.

| Event | Written by | Means |
|-------|------------|-------|
| `bound` | `init` | the bound in force (`floor`, `ceiling`, null when absent) |
| `from_facts` | `set-from-facts` | the level the check set, naming its `source` (`facts` or `bound`) and the facts `rule` |
| `choose` | `set` | the first level, set before any check |
| `raise` | `set` | a higher level |
| `lower` | `set` | a lower level, with its `reason` |
| `floor_raise` | `set` | a raise to the facts floor, naming the `rule` |
| `veto` | `set` | a raise the decider check asked for, naming the criterion in `rule` |
| `breach` | `set`, `set-from-facts` | the level change on the line before went above the ceiling |
| `check` | `set-from-facts`, `facts` | the level and the facts floor at the check, written when the head, level or floor differs from the ledger's last `check` or `unset` line |
| `unset` | `facts` | the check was reached with no level (a template from before `set-from-facts`) |

Each level change writes exactly one of `from_facts`, `choose`, `raise`,
`lower`, `floor_raise` or `veto`, plus `breach` when it goes above the
ceiling.

`review-level.sh report [<session>...]` reads the ledgers of retained
sessions: one tab-separated row per session with `session`, `chosen` (the
first `choose`, `-` for a run whose level came from the facts alone), `final`
(the level of the last `check` at or above its
floor, `-` when there is none), `floor` and `ceiling` (the bound, `-` when
absent), counts of `raise`, `lower`, `floor_raise`, `veto` and `breach`
lines, `overrides` (koto overrides on the level check's gates) and `seats`
(the summed spawn counts in the verdict ledger's history). A session with no
ledger reads `none` in `chosen` and one whose ledger can't be read reads
`unreadable`; a ledger line that isn't JSON makes the row read `corrupt`.
Either of the last two makes the script exit 2 after printing every row.

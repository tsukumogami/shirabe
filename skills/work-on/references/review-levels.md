# Review levels

A `/work-on` run commits to a review level before it implements anything. The
level decides which review panels a code change goes through. Facts about the
change can raise it but never lower it, a coordinator can bound it, and every
change to it lands in a per-run ledger.

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
implementation under the same retry cap, sticky verdicts and per-seat scoping
as before. A `docs` or `task` run records a level too; its route skips the
panels, so the level only appears in its ledger.

## Choosing, raising and lowering

The template variable `REVIEW_LEVEL` holds the level and koto routes on it.
`review-level.sh set <session> <level> [--reason <text>] [--cause veto:<criterion>]`
rebinds the variable on the live session and appends to the ledger in the
same call. It exits 0 when the change is recorded, 1 with a `refused:` line
when a rule below refuses it (nothing changes), 64 on a usage error, and 66
when the rebind or a context read or write fails (neither changes).

- **Choose.** The first `set` chooses the level from the issue and the
  analysis plan. It must fall inside the bound. It is refused before the
  level-choice state has recorded the bound (`refused: no bound recorded
  yet`).
- **Raise.** A higher level is free inside the bound: no reason needed. A
  raise above the ceiling needs `--reason` and is recorded as a breach. The
  exception is a **floor raise**, a raise to exactly the current facts floor
  from below it: it needs no reason anywhere, and above the ceiling it is
  recorded as a breach too, because the facts win over the ceiling. A raise
  made because the decider check vetoed the level passes
  `--cause veto:<criterion>` and is recorded as a veto.
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
once, at the level-choice state, as a `bound` line and the
`review_level_bound.json` key. The first choice must fall inside the bound.
A bound whose floor is above its ceiling refuses every `set`, naming both
values, and the level check holds under it whatever the level.

`/execute` and `/deliver` take the same two flags. `/deliver` forwards them to
`/execute`, and `/execute` sets them on every child task it spawns, only when
they aren't empty, so a run without the flags starts its children exactly as
before. Inside a `/work-on` run the bound doesn't move: the two variables aren't
rebind there, so a resume that passes a different bound is refused.

## The facts floor

After implementation and before the first panel of a code change, on every
lap, `review-level.sh facts` records the change's facts in
`review_facts.json` and derives a floor from them:

- the diff is taken from two bases, the stored `impl_base` and the
  merge-base of HEAD with the default branch (origin/HEAD's branch, else
  `origin/main`, else `main`), and the larger one counts: more changed
  lines, then more files, with a tie keeping `impl_base`. An `impl_base`
  recorded after some of the work would otherwise hide that work and lower
  the floor. With no merge-base (no shared history) `impl_base` is used
  alone. `review_facts.json` names the winner in `base_source` and keeps
  both candidates under `bases`. Uncommitted work isn't counted. A rename is
  one file plus its changed lines, and both of its paths are classified; a
  deletion counts its deleted lines.
- changed lines (added plus deleted) and changed files;
- which path classes the changed paths fall in, and whether any path falls in
  none (`unclassified`);
- whether a test file changed (a path in the `test` class);
- whether the acceptance criteria changed: a path under `docs/plans/` or
  `docs/prds/` changed, or the acceptance-criteria section of `context.md`
  differs from the copy `init` stored.

The classes and thresholds live in
[`review-level-rules.tsv`](review-level-rules.tsv), and changing one is a
change to that file only. The floor is the highest level any rule yields,
`light` when none does. A path can be in several classes, and each one
counts. The shipped classes:

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
  class, or changed lines exceed 400, or changed files exceed 12;
- `standard` when a path is in the `instruction`, `executable`, `test` or
  `manifest` class, or a path is in no class at all (`unclassified`), or the
  acceptance criteria changed, or changed lines exceed 40;
- `light` otherwise.

So `light` is reachable only when every changed path is documentation or in a
class no rule names. `docs` exists to keep a path out of `unclassified`: a
`README.md` alone stays `light`, a `SKILL.md` is `instruction` too and floors
at `standard`, `requirements.txt` is `manifest` too and floors at `standard`,
and a `.sh`, `.py` or `.rs` file in no class floors at `standard`. A test in
`review-level_test.sh` fails when a template names a script the `engine` class
doesn't cover, so the list can't fall behind the templates.

`facts` classifies with the copy of the rules `init` stored when the level
was first chosen, never with a file the run's diff can change, and the rules
file is itself in the `security` class. A change to the rules applies to runs
that start after it lands.

The level check (`review-level.sh check`, a command gate) passes when the
level is at or above the floor, matches the ledger's last level, sits inside
the bound (or above the ceiling with a breach recorded), and the facts were
gathered at HEAD. Otherwise it holds with a `hold:` line naming why, and the
run reaches no panel until the level is raised. koto's override record is the
only way past the hold without a raise, and the ledger reader counts each
override. With the level unset and no level in the ledger (a session from an
earlier template), the check exits 3 and the run takes the full path.

The level check also carries a veto-mode decider check whose command is
`review-level.sh slice`: the counts, class names, booleans, the floor and the
level, never a path, a reason or criteria text. It asks whether the level is
too light for these facts under the definitions on this page. It can only
hold the run, never route it or lower the level.

## Hand rebinds

`REVIEW_LEVEL` can also be changed by hand with `koto init <session>
--attach-live --var REVIEW_LEVEL=<level>`. The level check holds whenever the
variable differs from the ledger's last level, naming both; a `set` to the
level the run should be at clears it.

The level check runs once per lap, and two later states route on the level
again: `review` (whether QA runs) and `light_review`. Each carries a
`level_unchanged` gate, `review-level.sh agree`, on every route that depends
on the level, its carried route included. It passes when the variable equals
the ledger's last level (both empty is the unset route) and holds otherwise,
so a hand rebind made while the run sits in one of those states can't skip
QA or leave the light panel with the ledger untouched. A `set` to the
ledger's level clears the hold.

An attach re-applies every rebind variable from its own arguments, so one that
doesn't pass `REVIEW_LEVEL` (a resume through `koto init --attach-live`, say)
empties it. With a level in the ledger that is a reset, not the unset route:
the check holds, naming the ledger's level, until `set` rebinds it. For the
same reason `set` passes `PLUGIN_ROOT` along with the level.

## The ledger

The context key `review_level.jsonl` holds one JSON object per line, only
ever appended to. No retry clearing step removes it. Each line has `ts` (UTC,
ISO-8601) and `event`, plus the fields the event needs from `from`, `to`,
`reason`, `rule`, `floor`, `ceiling`, `level` and `head`.

| Event | Written by | Means |
|-------|------------|-------|
| `bound` | `init` | the bound in force (`floor`, `ceiling`, null when absent) |
| `choose` | `set` | the first level |
| `raise` | `set` | a higher level |
| `lower` | `set` | a lower level, with its `reason` |
| `floor_raise` | `set` | a raise to the facts floor, naming the `rule` |
| `veto` | `set` | a raise the decider check asked for, naming the criterion in `rule` |
| `breach` | `set` | the level change on the line before went above the ceiling |
| `check` | `facts` | the level and the facts floor at the check, written when the head, level or floor differs from the ledger's last `check` or `unset` line |
| `unset` | `facts` | the check was reached with no level |

Each level change writes exactly one of `choose`, `raise`, `lower`,
`floor_raise` or `veto`, plus `breach` when it goes above the ceiling.

`review-level.sh report [<session>...]` reads the ledgers of retained
sessions: one tab-separated row per session with `session`, `chosen` (the
first `choose`), `final` (the level of the last `check` at or above its
floor, `-` when there is none), `floor` and `ceiling` (the bound, `-` when
absent), counts of `raise`, `lower`, `floor_raise`, `veto` and `breach`
lines, `overrides` (koto overrides on the level check's gates) and `seats`
(the summed spawn counts in the verdict ledger's history). A session with no
ledger reads `none` in `chosen` and one whose ledger can't be read reads
`unreadable`; a ledger line that isn't JSON makes the row read `corrupt`.
Either of the last two makes the script exit 2 after printing every row.

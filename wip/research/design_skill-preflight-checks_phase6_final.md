# Verdict: PASS

All 13 jury items are genuinely resolved, not papered over. The shell change is
consistent everywhere and the two byte-critical strings match. Every construct
the revision prescribes runs clean under this host's bash 3.2.57. The output
filter, walked over real `koto context --help`, `shirabe roadmap --help`, and
`shirabe roadmap populate --help`, produces exactly the lists R7 and R8 need.
R1-R28 still hold. The validator is clean and no `wip/` path appears.

Three defects are named below. None blocks implementation — each is a one-line
or one-sentence fix that changes no decision, no schema, and no architecture, so
they belong in `/plan` rather than in another jury round.

## 13-item resolution

Architecture blockers:

| # | Blocker | Resolved at | Verdict |
|---|---|---|---|
| A1 | R14 not producible from the schema | 802-844 (the two-way choice, "Narrow the report" taken), 846-947 (all four cases rendered verbatim) | Resolved. The fifth field was rejected with a stated reason; both worked examples were rewritten to use only `<tool> <subcommand> <flags> <when>`; the loss is booked in Negative consequences (1854-1862). |
| A2 | R10 deferral vs R12 zero bytes | 1204-1238, restated 1864-1871 | Resolved. Deferral moved to field four of the declaration; the load-time report says nothing at all about `mode:` records; R12's zero bytes is untouched; the PRD gloss is stated explicitly and the cost of reopening it is named. |
| A3 | Shell never identified; IFS and memoization unspecified | 202-238 (option section), 463, 729-742 (IFS), 744-771 (memoization) | Resolved. `bash` with a bash-3.2 floor, chosen against `sh` with the dash-CI-mismatch argument spelled out. Both named constructs specified and both executed successfully below. |
| A4 | `tool-routes.tsv` had no schema | 1043-1103 | Resolved. Six fields, per-field table, closed probe grammar (`<driver>` or `<driver> <verb>`, `never` for exclusions), mandatory citation on exclusions, seed showing all four route kinds. |
| A5 | R4's committed policy dropped | 469 (Components row), 481-507 (section), 1432 (Phase 3, sequenced before the declarations) | Resolved. `references/tool-declaration-policy.md`, cited by name from the conformance scan's failure text. |

Security required changes:

| # | Change | Resolved at | Verdict |
|---|---|---|---|
| S1 | No bound on tool-derived text | 974-1026 | Resolved, and normative rather than argued: ANSI CSI + C0/C1/DEL strip on the source line first, per-token allowlist, drop-don't-sanitize citing `extract_pr_url`, 64-byte token cap, 24-item list cap with `and N more`, labelled interpolation region, and a stated tripwire that makes a nonce fence mandatory if the alphabet ever loosens. The no-nonce decision is argued from the closed alphabet rather than asserted. |
| S2 | Word-split claim contradicted the format | 1551-1584, allowlist table 584-602 | Resolved. The old claim is quoted and corrected outright ("field two is split on spaces into argv elements, deliberately"). Allowlist enforced by the script at read time, not only CI; leading-`-` rejection in fields one and two; malformed record skipped *and* reported with skill, line number, field, expectation. |
| S3 | No probe execution safety | 681-691 (provenance), 712-727 (execution), 1610-1633 (DoS qualification) | Resolved. Absolute-path-and-outside-`$PWD` requirement with a "resolution refused" outcome; 2 s watchdog without `timeout(1)`; `</dev/null`; 64 KiB cap; timeout and cap paths reported as **inconclusive**, explicitly not as findings. The availability claim is separated from the exit-code claim. |
| S4 | `SHIRABE_PREFLIGHT_ROOTS` not treated as input | 1635-1652 | Resolved. Who can set it, what it buys, and the bound promoted to an invariant ("roots are only ever tested with `-x`, and a root-resolved path is never executed"), plus the path allowlist applied to roots echoed into report text. |
| S5 | No adjudicator for the discard enumeration | 1343-1364, 1699-1712 | Resolved. Field five justification, field six mandatory non-`-` citation, `CODEOWNERS` entry, same-PR-but-own-commit rule. The free-text asymmetry against the rejected fifth `requires.tsv` field is defended on reader-and-timing grounds. |
| S6 | Self-resolution fallback cited unusable code | 1525-1545 | Resolved. `${BASH_SOURCE[0]}` is now accurate because the interpreter is bash; the wrong version's failure mode is recorded; the resolved root must be absolute and contain a readable `plugin.json` **before** anything under `scripts/lib/` is sourced, with a single explanatory line printed on failure. |
| S7 | Malicious-PR ordering hole | 1586-1608 | Resolved. Both halves stated: the script is the control for a declaration-only branch, and for a script-changing branch the design refuses to pretend and names the exposure a local reviewer accepts. |
| S8 | Failure-open hides self-compromise | 1732-1767, 1879-1883 | Resolved. Eight-item enumeration of what zero bytes covers, an exact statement of what Phase 2 and Phase 3 do *not* cover, and one cheap mechanism (the Phase 4 liveness eval on the real injection path) with the residual named and accepted. |

## Shell consistency (check 1)

Clean. `grep -nE '(^|[^a-z_.-])sh [^a-z]'` over the whole document returns
nothing. `POSIX` survives only at lines 203 and 208, both inside the rejected
option A where it belongs. Every one of the ten `skill-preflight.sh` mentions is
`bash <path>`.

The two byte-critical strings, extracted mechanically and compared:

```
PAT  (1110): allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
BODY (1116): !`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> 2>&1 || true`
MODE (1246): bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> --mode <name> 2>&1 || true

pattern-prefix: [bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh]
BODY MATCH: yes (byte-exact prefix + space)
MODE MATCH: yes
```

The mode-time line is covered by the same pattern, which the design does not
say but which is true and worth keeping true. `Bash(true)` is declared for the
`|| true` arm, and the design already books the operator-composition question as
the Phase 2 gate.

Supporting factual claims re-verified in the tree: `skills/execute/SKILL.md:129`
is `bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh` (the house
idiom is bash, as now claimed); `grep -rn allowed-tools skills/` returns exactly
one hit, so nineteen files gain the key, as now stated; `evals.json` carries
four `preflight.sh` references, as now stated; twenty skill directories exist.

## Bash 3.2 execution results

Host: `GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`. No
`mapfile`, `declare -A`, `readarray`, `${var,,}`, `${var^^}`, `[[ -v ]]`,
nameref, or associative-array syntax appears anywhere in prescribed code — the
four grep hits (136, 232, 747, 1439) are all prohibitions or rationale.

**TSV read and roots split — PASS.**

```
L2 tool=[shirabe] sub=[roadmap populate] flags=[--issues,--milestone] when=[mode:issues] IFS_after=[$' \t\n']
L3 tool=[gh] sub=[-] flags=[-] when=[always] IFS_after=[$' \t\n']
count=3  root=[~/.tsuku/tools/current] root=[~/.shirabe/bin] root=[~/.local/bin]
```

Field two survives intact, and the `IFS` assignment scoped to the `read`
builtin does not leak — verified by printing `IFS` after each read. `IFS=: read
-r -a` works in 3.2 as the design says.

**Memoization store — PASS.** Both newline-delimited accumulators, the
newline-bracketed `case` membership test, and the `while IFS=$'\t' read -r k v`
retrieval all behave exactly as specified, including the exact-line property the
design claims:

```
HIT  [koto] -> context decisions overrides init next rewind workflows version
HIT  [koto context] -> add get exists list
MISS [koto contex]          <- substring does not match, exact-line test holds
MISS [koto context add]
OK: 'koto*' did not match   <- glob metachar in a key does not widen the match
OK: empty store, no match, no error
```

**Self-resolution fallback — PASS.**
`ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"`
run from a foreign `$PWD` yields the absolute script-relative root, one level
up, and the `plugin.json` marker gate fires correctly.

**Probe execution (2 s watchdog, `</dev/null`, 64 KiB cap, separate capture, no
temp files) — PASS, with a trap.** The design's three constraints are jointly
satisfiable in bash 3.2:

```
flooding probe (`yes AAAA`):  65536 bytes, real 0m0.007s   <- cap enforced via SIGPIPE
hanging probe  (`sleep 30`):  RC=143,       real 0m2.013s   <- TERM at budget
fast probe (koto context):    422 bytes,    real 0m0.004s
```

so "the check writes no files" (1769-1774) and "stdout and stderr captured
separately" (720) do **not** contradict each other. The trap is Defect 2 below.

**One genuine 3.2 failure — Defect 1.**

```
--- empty roots array under set -u ---
count=0
t1.sh: line 32: EMPTY_ROOTS[@]: unbound variable
EXIT=1
```

## Output filter walkthrough (check 3)

The extractor plus the normative filter, implemented literally from lines
703-710 and 986-999 and run against the live binaries:

```
koto context           Commands -> add get exists list help
koto context           Options  -> -h
shirabe roadmap        Commands -> populate help
shirabe roadmap        Options  -> -h            <- NOT --issues/--no-issues
shirabe roadmap populate Options -> --milestone --milestone-description --mapping
                                    --output-map --repo --dry-run --issues --no-issues -h
koto                   Commands -> 16 tokens
shirabe                Commands -> 9 tokens
```

Four things confirmed. The design's headline extractor claim is exactly right:
`--issues` and `--no-issues` appear in `populate`'s description prose at the
`shirabe roadmap` level, and the section-scoped, position-anchored extractor
correctly reports only `--help` there, where a loose grep reports all three.
Both clap layouts parse — inline (`  -h, --help  Print help`) and wrapped-long-
flag (`      --milestone` with the description at 10 spaces). The advertised
subcommand list for `koto context` is `add, get, exists, list`, matching the
report block at line 858. And the 16/9 top-level counts hold, so the
one-call-buys-the-first-layer cost argument stands.

Reject-don't-sanitize does not break R7 or R8. Every legitimate token clears the
allowlist: the longest, `--milestone-description`, is 23 bytes against the
64-byte cap, and the longest list is 9 items against the 24-item cap. The
allowlist correctly drops the value placeholders (`<MILESTONE>`, `<OUTPUT_MAP>`)
and the description words (`Print`, `help`) that share the option-definition
line. Every flag declared anywhere in the corpus is long-form, so nothing
declared is lost. The one loss is Defect 3.

## Internal consistency after the 863-line growth (check 4)

- *Word-splitting.* The only occurrence of "word-split" is line 1552, which
  quotes the old claim in order to overturn it. No residual contradiction.
- *"Writes no files."* Line 1769 survives, and the probe mechanism at 712-727
  is compatible with it — demonstrated above at 65536 bytes with no temp file.
  Consistent. `mktemp -d` appears only in the test plan, which is the harness,
  not the script.
- *Probe count.* 5 `command -v` + 9 `--help` at 778-781, and again at 1811-1812.
  Line 786-788 explains 18.7 ms as a conservative upper bound measured over ten
  levels. I re-derived 9 from the printed `/work-on` declaration under the
  stated rule and got 9. Consistent, with one wrong causal gloss (Defect 3b).
- *`assert-child-template.sh`.* Used consistently. Every surviving mention of
  `skills/execute/scripts/preflight.sh` (211, 226, 1123, 1161, 1425) describes
  present-tense state or is the rename instruction itself. No post-rename text
  uses the old name.
- *`sh` residue.* None, per check 1.

## Requirement coverage (check 5)

R1-R28 all still hold. R14 is met at declaration granularity by an argument the
architecture jury explicitly offered as an acceptable resolution ("replace the
worked report examples with what the four-field schema can actually produce"),
and the design takes it with the loss recorded rather than glossed. R10 is met
on its own requirement text — "SHALL NOT be reported as satisfied or unsatisfied
at load" — which silence satisfies more exactly than a marker would, and R11 is
carried by Phase 6's `--mode` entry point with a full output contract. R4's
deliverable now exists. R12, R13, R17, R19, R20, R21b, R22, R27 and R28 are
unaffected by either narrowing. No requirement is now unmet.

One PRD acceptance criterion deserves the same explicit gloss R10's got, and
does not have it — see Defect 3a.

## Blocking defects

None. Three fixes for `/plan` to absorb:

**1. Empty `SHIRABE_PREFLIGHT_ROOTS` aborts the script under `set -u`.** The
design prescribes `set -u` throughout (1139-1141) and
`IFS=: read -r -a PREFLIGHT_ROOTS <<<"$SHIRABE_PREFLIGHT_ROOTS"` (739). In bash
3.2 — but not bash 4.4+ — expanding an empty array as `"${PREFLIGHT_ROOTS[@]}"`
under `set -u` is an unbound-variable error that exits the shell, reproduced
above. R28 makes the variable user-settable, so `SHIRABE_PREFLIGHT_ROOTS=""` is
reachable, and the failure is swallowed by the injected line's `|| true`,
landing it in the failure-open blind spot the design just finished enumerating.
Fix: guard the expansion as `${PREFLIGHT_ROOTS[@]+"${PREFLIGHT_ROOTS[@]}"}`, or
state that an empty value is normalized to the default. Add an empty-roots case
to the Phase 3 test list, which currently only covers `mktemp -d` and
`/nonexistent`. This is exactly the class of bash-3.2-only trap the macOS CI leg
exists to catch, so the leg will catch it — but only if a test constructs it.

**2. The naive watchdog costs every probe the full 2-second budget.** The
mechanism at 722-724 ("the probe is started in the background, a watchdog
subshell sleeps the budget and sends `TERM` then `KILL`, and the parent waits")
is correct only if the watchdog's inherited file descriptors are explicitly
released. My first literal implementation returned in 2.014 s on
`koto context --help` — a 3 ms call — because the watchdog held the capture pipe
open for its whole sleep, and separately failed to kill the hanging probe at
all (30.0 s). Redirecting the watchdog's stdout/stderr to `/dev/null` and
closing its stdin fixes both, giving the 0.004 s / 2.013 s / 65536-byte results
above. Unfixed, `/work-on`'s nine probes cost roughly 18 *seconds* per skill
load instead of 18.7 ms, and nothing in the test plan would notice, since a
timeout test that asserts "inconclusive" passes either way. Fix: add one
sentence requiring the watchdog release the capture descriptors, and add a
wall-clock upper-bound assertion to the Phase 3 satisfied-path test so the
regression is detectable.

**3. Two one-sentence gaps.**

*(a) The "affected capability" acceptance criterion is left unglossed.* The
design glosses R10's PRD wording explicitly and well ("the marker lives in the
declaration"), then narrows R14 without giving the parallel treatment to the
criterion at PRD line ~312: "the report names the tool **and the affected
capability**." The narrowed report deliberately names no capability. The
substantive argument is already in the document at 826-844; it just needs the
same one-sentence pointer R10 got, so the criterion is not read as failing at
plan time.

*(b) Flag tokenization inside an option-definition line is unspecified.* The
design states the Commands rule precisely — "the first whitespace-delimited
token on a line carrying 2 to 6 leading spaces" — and states no equivalent for
Options, giving only the 2-to-6-space anchor. Read literally as first-token-
only, clap's inline layout `  -h, --help  Print help` yields `-h,`, which the
flag allowlist rejects on the comma and drop-don't-sanitize discards, so
`--help` is never extracted — contradicting the design's own rendered block at
line 883, which prints `--help` in the advertised list. Taking every
whitespace-delimited token on the line and letting the allowlist filter works
correctly in both layouts, verified above. Fix: state that rule, and that a
trailing comma is shed as a delimiter before allowlisting (which is
tokenization, not sanitizing). No flag declared anywhere in the corpus is
short-form, so R7 and R8 are unaffected either way.

*(c) Minor.* Line 769 attributes the ten-levels-to-nine-calls difference to
memoization collapsing `koto context add/get/exists`, but three levels
collapsing to one is a difference of two, and lines 782-784 give the correct
reason — `koto context add` declares no flags, so the leaf rule skips it. The
number 9 is right everywhere; only the causal gloss at 769 is wrong.

## Validator

```
$ shirabe validate --format json --visibility=public docs/designs/DESIGN-skill-preflight-checks.md
{
  "schema_version": "shirabe-validate/v1",
  "summary": {
    "outcome": "clean",
    "errors": 0,
    "notices": 0
  },
  "findings": [],
  "advisory": {
    "summary": "Draft posture: no draft-tolerable findings to flag.",
    "notes": []
  }
}
EXIT=0
```

`grep -n 'wip/'` over the document returns no matches. No `wip/` path appears in
frontmatter, prose, or references.

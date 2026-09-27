# Panel review: Issue 5 (sealed reconcile pass and the reconcile state)

Head reviewed: d76ed2d on docs/coordinate-reconcile. Probe scripts live in
the job scratch directory (panel5/forge_test.sh, toctou_test.sh,
cutoff_test.sh, fn/run.sh, kotofd/run.sh); each reuses the harness of
reconcile-pass_test.sh through `--test-entry`.

Tests run:

- reconcile-pass_test.sh: 79 passed, 0 failed
- reconcile-pass_engine_test.sh: 24 passed, 0 failed
- coordinate-template-structure_engine_test.sh: 47 passed, 0 failed
- rule-coverage_test.sh: 198 passed, 0 failed

The agreed deviations hold up. They are the `reconcile_pass` state ahead of
F2's `reconcile`, the report-digest gate on both of reconcile's arms, the
`reconciled <digest> sealed:` line, keeping GH_TOKEN, and the merged F2
branch. The template side meets the outline: no accepts or polling on
reconcile_pass, every gate is `overridable: false`, no override edge, both
reconcile commands start with `env -u BASH_ENV -u ENV`, no gate names
reasoning.md, PLUGIN_ROOT has no rebind, and the directive never names
RECONCILE_SEAL. The capture-based seal is sound: an agent can't set a
capture, and report-get reads the capture from the log itself. The
blocking findings are all ways to get forged facts into a report that the
engine then legitimately seals.

## Blocking

### B1. Exported bash functions survive the scrub, so the engine-run pass can be fed forged tool output

`reconcile-env.sh:78-94` unsets every variable outside the allowlist, but
`compgen -e` doesn't list exported functions (`BASH_FUNC_name%%`). They
survive `exec "$BASH"` and every child `bash`, including reconcile-check.sh
and coord-log.sh. An agent that runs `koto next` with `gh`, `git`, `niwa`,
`koto`, `date` or `sleep` exported as functions controls what the pass
reads and what time it thinks it is. The capture is still real, so the
seal is real too.

Failing input (panel5/fn/run.sh, against the shipped reconcile-env.sh):

```
gh() { echo '{"state":"MERGED"} (forged ...)'; }; date() { echo 1; }; koto() { ...; }
export -f gh date koto; env -u BASH_ENV -u ENV bash ./probe.sh
-> after scrub: type gh -> function
   {"state":"MERGED"} (forged by an exported function)
   date -> 1
   koto -> function
```

This breaks the outline criteria that a shadowing `gh` never runs and that
nothing in the environment changes the clock or the sleep. Unsetting the
functions inside rd_scrub isn't enough on its own. The pre-scrub lines
(`HERE=$(cd "$(dirname "$0")" && pwd)`, then `. "$HERE/reconcile-env.sh"`)
already run the imported `cd`/`dirname`/`pwd`, and even `builtin` and
`declare` can be shadowed (confirmed). The fix has to strip `BASH_FUNC_*`
before bash starts: a launcher on the template's command line that isn't
bash, or refusing to run when the environment holds any `BASH_FUNC_` name,
checked by something other than a shadowable bash builtin. Add a test that
exports `gh` and `date` as functions.

### B2. Work state outside the anchored work file is trusted between passes

Only `visit.json` is hash-anchored (`reconcile-pass.sh:118-139`). Two other
files feed facts and are never checked.

(a) Deferral row files. They're written once per visit
(`reconcile-pass.sh:169-175`) and handed to the deferral check on whatever
pass reaches it (`:227`). Failing input (forge_test.sh case A): a
10-holding record plus one undisposed deferral. After pass 1 (pending, no
deferral read yet), change `d0.row.json` to `"disposition":"closed: done"`.
The work file's hash doesn't change and the pass resumes. The deferral
check gets the edited row, and the sealed report's `deferrals` goes from
`[flaky test ...]` (control run) to `[]`. `report-get --check` passes.

(b) The reads directory. `$R` isn't cleared on resume (`discard` is the
only thing that clears it), and `launch` doesn't remove a stale
`$R/<id>.rc` (`:282-292`), so `collect` takes any `.rc` it finds as done
and reads `.out` (`:242-243`). Failing input (forge_test.sh case B): after
pass 1, plant `reads/h9.pr.rc` and a read-only `reads/h9.pr.out` with
`"state":"MERGED"`. The mode makes the real re-check's `>` redirect fail,
so the planted bytes stay. The work file is unchanged, the real PR read of
#10 never runs (0 calls), and the sealed report says "w10: pull request:
record said open, now merged (measured)".

Fix: write each row file from the work file right before its launch (or
pass the row through `$T`), put per-pass read files in the per-pass `$T`
rather than the session directory, and `rm -f "$R/$id".*` before a launch.

### B3. The work file can be edited during a pass, and the pass seals the edit

`save` rewrites `$WORK` from whatever is on disk (`reconcile-pass.sh:251`,
`:116`), and the pending hash is taken from the file at the end of the pass
(`:333`). A write made during a pass is folded in and then anchored by the
engine-logged hash. An agent can do this by running `koto next` in the
background and editing `visit.json` a moment later, or by running
`--test-entry` (unscrubbed) at the same time. The design's promise that
facts are "only ever the ones earlier passes of this visit wrote" doesn't
hold.

Failing input (toctou_test.sh): the first branch read's stand-in plays the
concurrent writer and sets `facts["h9.pr"]` to MERGED. The passes run to
the seal, #10 is never read, the report says w10 is merged (measured), and
`report-get --check` passes. Fix: keep the facts in memory within a pass,
or check before each save that the file still hashes to the last value
this pass wrote, and discard it when it doesn't.

### B4. A re-read due exactly at the 20-second cutoff sleeps 20 s and then launches nothing

`reconcile-pass.sh:323` allows the wait when `wait_until - T0 <= CUTOFF`.
But `:315` launches only when `el < CUTOFF`, so a re-read due at +20 s
waits and is then refused. Failing input (cutoff_test.sh): a missed worker,
with the second pass started exactly 20 s before `host1.t + 30`. The clock
advances 20 s, no launch happens, and the pass prints `pending:` with the
host read count still 1. The outline says a re-read happens in the same
pass only "when the wait ends before the 20-second cutoff". Fix: use `-lt`
at `:323`. Low impact (one wasted 20 s tick), but it's a demonstrated
defect.

### B5. The record read's deadline watcher holds koto's stdout open for 12 s

`exec 3>&1 1>&2` (`:60`) leaves fd 3 open during `rd_deadline 12 bash
reconcile-read.sh` (`:144`). The watcher subshell in
`reconcile-deps.sh:rd_deadline` redirects only stdout and stderr. Its
`sleep 12` inherits fd 3 and outlives `kill "$watcher"`. So do the watchers
inside reconcile-read.sh, which runs with fd 3 too. koto waits for EOF on
the action's stdout (kotofd/run.sh: an action that exits at once but
leaves a 6 s child holding the pipe makes `koto next` take 6 s).

Failing input (forge_test.sh case C): a `blocked:none` pass prints at once,
but its stdout closes after 12 s. Every first pass of a visit takes at
least 12 s, and so does every blocked tick. a19afdb fixed the same thing
for the re-checks but not for the record read. Fix: `3>&-` on the record
read (inside the `$(...)`), and close fd 3 in rd_deadline's watcher.

## Advisory

1. The budget margin is at most 2 s. `RUN_END = now + budget + 2`
   (`:294`) lets a read end at T0+28. Assembly, two reconcile-report.sh
   runs, three `koto context add`, one get, the save and the seal then have
   2 s before koto's 30 s kill. Use `RUN_END = now + budget`, or
   READS_END=24.
2. The board read's natural deadline (26) equals READS_END. It's clipped
   whenever it launches at `el >= 1`, and with whole seconds that happens
   whenever the startup crosses a second boundary. A board read clipped
   and then timed out is thrown away (`:248`) and costs another pass.
3. The final line isn't checked against `$VISIT` (`:384`). If a new entry
   into reconcile_pass lands mid-pass, the old visit's facts get sealed to
   the new visit. Require `sealed:$VISIT:` in `$LINE`.
4. A failed `koto context add` while sealing leaves an unsealed
   `reconcile/report.json` in context, and the next pass discards the whole
   visit's reads (forge_test.sh case D: pr reads went from 1 to 2). It
   fails in the safe direction but costs a full re-read. Consider removing
   the report keys on `die` after `:374`.
5. Once the workflow is in `reconcile`, a removed or altered
   `reconcile/report.json` can't be put back. The reprint path only runs in
   reconcile_pass, so a rewind (and a full re-read) is the only way out.
   The directive should say so.
6. The `reconcile` directive sends the agent to read `reconcile/report.md`.
   No gate checks that key, and the reprint path restores it from the
   unanchored `$W/report.md` (`:129`). Point the directive at
   `reconcile-report-get.sh --session S --md`, which renders from the
   verified JSON.
7. `$W/reasoning.md` is unanchored between passes. That matches "no gate
   names reasoning.md", but it's worth a line in the script header.
8. `--clock-file` is accepted on the scrubbed path (`:74`). The template
   never passes it, but reject it unless `--test-entry` was given.
   `--test-entry` skips the scrub. That's fine on its own because its
   output never becomes a capture, but it's also a ready-made concurrent
   writer for B3.
9. Stopping a read at its budget sends `pkill -P` to the subshell's direct
   child only (`:257`). reconcile-check's `gh` and its rd_deadline watcher
   are orphaned, and the watcher later kills a PID that may have been
   reused. The subshells still hold koto's stderr pipe through fd 1 and 2,
   so a `die` mid-loop can leave them delaying the action's end.
10. There are vacuous tests. `reconcile-pass_test.sh:401` (`grep -q ... |
    grep -v` is always false) always passes. `:406` greps only `${NAME`
    forms and can't see a function override. `:363` is hard to read. The
    pass suite never checks its own stub log against the outline's command
    allowlist; it checks only the `reconcile/` key prefix. The pass's `git
    rev-parse --show-toplevel` falls outside the outline's git list,
    though the design allows rev-parse.
11. `blocked:` only ever prints `none` or `unreadable`. The outline's
    `ambiguous` and `undeclared` are now settled upstream by F2's
    record_find, which is fine but should be stated. Exit 5 (a transient
    failure or a timeout) also maps to `blocked:unreadable`, and the
    directive says "say it up and stop". A network blip then halts the
    coordinator. Consider "tick again once" for a failed read.
12. Close-kind inference (`:219`) uses `holding_repo($t.n)` and ignores
    `$t.r`. `other/repo#12` is read as a PR whenever a host-repo holding is
    #12.
13. Allowlist. Keeping KOTO_HOME and KOTO_SESSIONS_BASE is sound: the
    engine that ran the pass used the same values. HOME from passwd
    differs from an agent-set HOME, and when it does the pass can't find
    the log and fails closed. The fixed PATH includes user-writable
    directories (`~/bin`, `~/.local/bin`, `~/go/bin`, `~/.cargo/bin`,
    `/opt/*/bin`) after the system ones. That's the same class as editing
    the plugin, but worth saying in the header.
14. F2's `coord-verdict.sh` gate on reconcile_pass isn't scrubbed and
    honours `KOTO_BIN` (coord-log.sh:60). It can't forge `reconciled` on
    its own, because reconcile's scrubbed report gate re-checks. It's
    noted only because the pass's security story leans on the second gate.
15. No leaks found. Refusal reasons are fixed strings, the host path is
    dropped from the facts (`del(.path)`), and the suite checks for session
    ids, paths and job ids in the stored keys.
16. Portability looks fine. CI runs the unit suites under macOS
    `/bin/bash` 3.2 and in the bash-floor container, and run-tests.sh
    `--engine` picks up the engine suite. The jq features used (named
    `capture`, `def f($x)`, `ascii_downcase`) are in 1.5, and BSD `sleep`
    takes fractions.

## Round 2 (267f294)

Tests at 267f294:

- reconcile-pass_test.sh: 90 passed, 0 failed
- reconcile-pass_engine_test.sh: 24 passed, 0 failed
- coordinate-template-structure_engine_test.sh: 47 passed, 0 failed
- rule-coverage_test.sh: 198 passed, 0 failed

I re-ran the round 1 probes against 267f294. B3, B4 and B5 are closed.
toctou_test.sh now shows #10 read for real and reported open. cutoff_test.sh
shows the clock doesn't move and the pass leaves the read pending.
forge_test.sh case C shows stdout closing after 0 s. B2 is closed for the
between-pass layout: the old reads/ and d*.row.json files are no longer
read (forge_test.sh cases A and B). B1 and the B2/B3 class are still open
in the forms below. The rd_deadline done/watcher change is ordered
correctly. `done` is created before the watcher's sleep is killed, so the
watcher sees it and exits without marking late. A read that ends exactly
at its deadline still counts as 124, the same as before.

### Blocking

#### R2-B1. `-p` stops only the first bash; the exported functions stay in the environment and every shebang-started child imports them

`bash -p` doesn't import `BASH_FUNC_*`, but it doesn't remove them
either. `rd_scrub` can't see them (`compgen -e` doesn't list them), so they
pass through the re-exec. Any script started through its shebang or by a
plain `bash` imports them. The pass tree does both:

- reconcile-check.sh starts `$RD_BOARD_CHECK` and `$RD_DEFERRAL_CHECK`
  directly (reconcile-check.sh:558, :690).
- reconcile-read.sh starts `$RD_COORD_LOG` and `$RD_RECORD_PARSE`
  directly (reconcile-read.sh:99, :147).
- coord-log.sh, deferral-check.sh and record-parse.sh call `bash` without
  `-p`.

Failing input (panel5/fn/run2.sh): with `gh` exported as a function and
the template's exact command line, the scrubbed script shows 1
`BASH_FUNC_` entry still in its environment. A shebang child prints
`type gh -> function; gh says: FORGED`, while a `bash -p` child runs the
real gh.

End to end (panel5/fn/run3.sh, via chain.sh): a stand-in for the pass,
started as the template starts it, scrubbed by the shipped rd_scrub, runs
the real `reconcile-check.sh deferral` the way launch() does. The row has
an empty disposition. The control run gives `"disposed":false,"how":"empty"`.
With `jq` exported as a function that answers only the disposition read,
the same call gives `"disposed":true,"how":"closed"`. The same route
forges the board verdict (gh in board-verdict.sh), the record's parse
(record-parse.sh) and the run's facts (koto in coord-log.sh).

The suite's new test (reconcile-pass_test.sh, "an exported function never
stands in for a tool") checks only the scrubbed script itself, so it
passes. Fix: make rd_scrub refuse, exit 70, when the environment holds any
exported function. For example, `/usr/bin/env | grep -q
'^BASH_FUNC_\|^[A-Za-z_][A-Za-z0-9_]*=() *{'`, run under `-p` so `grep` and
`env` can't be shadowed. Refusing fits the existing BASH_ENV refusal and
needs no `env -i`, which would put the token on a command line. Add a test
that runs a shebang child under the scrub.

#### R2-B2. A result planted in the pass's own reads directory mid-pass is still taken

B2 and B3 moved the reads into `$T/reads` and the document into memory.
But `launch` still doesn't remove a stale `$R/$id.rc` before it starts
(reconcile-pass.sh:288-301), and `collect` still takes any `.rc` as done
(:249-250). The directory is `${TMPDIR:-/tmp}/reconcile-pass.XXXXXX`, mode
0700 but owned by the same user, and an agent finds it by glob.

Failing input (panel5/toctou2_test.sh): during each pass, the branch
read's stand-in plays the concurrent writer. It writes `h9.pr.rc` and a
read-only `h9.pr.out` saying MERGED into every
`/tmp/reconcile-pass.*/reads` that hasn't launched h9.pr yet. The real PR
read of #10 never runs (0 calls). The sealed report says "w10: pull
request: record said open, now merged (measured)", and `report-get
--check` passes.

This is the same class as round 1's B3, which the fix claims to close ("an
edit made while a pass runs is overwritten rather than trusted"). Minimal
fix: `rm -f "$R/$id".*` at the top of launch(), and in collect, accept
`.rc` only once `kill -0` on the subshell pid fails, meaning it has exited.
A same-user writer can still overwrite `.out` in the moment between the
read's exit and collect's read. If that stays open, the DESIGN's Security
Considerations should say plainly that same-user writes to the pass's
temporary files are out of scope, like session-directory edits.
Alternatively, have the subshell hand its result back over a pipe rather
than a file.

### Advisory

1. The `-p` side effects on the tools are fine. koto, gh, jq, git, niwa and
   pkill aren't bash, so privileged mode changes nothing for them. In bash,
   `-p` also ignores SHELLOPTS, BASHOPTS, CDPATH and GLOBIGNORE from the
   environment, which helps. The suites and the real-koto engine suite pass
   with it.
2. `/bin/bash` is now hard-coded in three template command lines. On
   macOS that pins the pass to bash 3.2, which is covered by the floor CI.
   On hosts without `/bin/bash`, such as NixOS, the action fails with
   koto's fallback. Name this in Known Limitations or in requires.
3. The report reader's own nested `bash "$0" check` inside coord-log.sh
   (coord-log.sh:172-174) runs without `-p`. Under R2-B1 a forged `koto`
   there could accept a stale visit's capture in `reconcile`. That's
   covered once R2-B1 refuses up front.
4. forge_test.sh case D is unchanged. A failed context add while sealing
   leaves an unsealed `reconcile/report.json`, and the next pass re-reads
   the whole visit. It fails in the safe direction.
5. `local ... done` and `done=...` in rd_deadline
   (reconcile-deps.sh:71,76) use a reserved word as a variable name. Bash
   accepts it, and the bash-floor CI job covers 3.2, but a different name
   such as `fin` avoids a reader's double take.
6. The directive's "tick again once" on a failed read is reasonable. The
   refusal file's reason text is what the agent decides on, so keep
   reconcile-read.sh's exit-5 reasons ("timed out", "could not be read")
   stable, or put the case in the refusal file as `case: failed`.

## Round 3 (c825621)

Tests at c825621:

- reconcile-pass_test.sh: 75 passed, 0 failed (the environment section was
  removed)
- reconcile-pass_engine_test.sh: 24 passed, 0 failed
- coordinate-template-structure_engine_test.sh: 47 passed, 0 failed
- rule-coverage_test.sh: 198 passed, 0 failed

R2-B2 is closed as filed. toctou2_test.sh, which plants `h9.pr.rc` and
`.out` before launch, now shows #10 read for real and reported open,
because launch() clears `$R/<id>.*` first. `kill -0` doesn't hold up
collection. bash reaps a finished background subshell on SIGCHLD, so
`kill -0` fails on the next poll (panel5/fn/reap.sh: after 1 poll with
`sleep 0.05` between, and after 16 builtin-only polls). No zombie is left
behind.

On the removal: nothing outside `wip/` names `reconcile-env.sh`,
`--scrubbed` or `rd_scrub` any more, including CI and check-bash-floor. The
koto#261 wording matches across SKILL.md, the DESIGN, the PLAN, and the
record feature's PRD and DESIGN. Its "(not dash)" qualifier is accurate:
panel5/fn/dash.sh shows an exported function dropped across a `/bin/sh`
= dash hop.

### Blocking

#### R3-B1. The template now runs reconcile-pass.sh and reconcile-report-get.sh directly, but both are committed without the execute bit

The prefix removal changed the three command lines from `/bin/bash -p
<script>` to `"{{PLUGIN_ROOT}}/.../<script>"`, so the scripts now need
their own execute bit. `git ls-tree HEAD` gives mode 100644 for
`skills/coordinate/scripts/reconcile-pass.sh` and
`skills/coordinate/scripts/reconcile-report-get.sh`. `coord-verdict.sh`,
`reconcile-check.sh` and `reconcile-read.sh` are 100755.

Failing input: running either script as the template's command does, from
this checkout, prints `Permission denied` with exit 126. On a real session
the reconcile_pass action fails on every tick, so the workflow can never
leave reconcile_pass. Once past it, reconcile's report gate would also
fail, and so would the directive's `reconcile-report-get.sh --md` call.

The engine suite doesn't catch this because it runs `chmod +x "$SC"/*.sh`
on its copied tree (reconcile-pass_engine_test.sh:78). Fix: `git
update-index --chmod=+x` on both files. Add a structure check that every
script a template command names is committed as 100755, or drop the
chmod from the engine test so it runs the modes as shipped.

### Advisory

1. A same-user writer can still swap a running read's `.out`. It deletes
   the file and writes a new one at the same name after launch. The real
   read keeps writing to the unlinked file, and collect reads the
   replacement once the read's pid has gone. panel5/toctou3_test.sh does
   one swap: #10 is really read, but the sealed report says "now merged
   (measured)" and `report-get --check` passes.

   This is the residual race named in Round 2, not something this fix
   introduced. The new koto#261 text ("don't hold against a coordinator
   that rewrites its own tools, or its files") arguably covers it. But the
   DESIGN's Security Considerations still names only the session directory
   as out of scope, and its line 124 says the temporary directory keeps
   pass files out of reach. Add the pass's temporary directory to that
   paragraph.
2. DESIGN-coordinate-reconcile.md:649 still lists "a refused environment"
   among the pass tests. That test is gone.
3. In reconcile-pass.sh, `BASHP=("$BASH")` keeps a name that meant
   privileged mode. `--test-entry` now only shifts, and `--clock-file` is
   accepted without it. That's harmless because the template's command
   line is fixed, but a plain `"$BASH"` and a `--clock-file` that requires
   `--test-entry` would read more honestly.
4. No unit test covers a stale `.rc` planted in the pass's own reads
   directory. The "planted" case covers only the old session-directory
   layout. Worth one case now that the check depends on launch() clearing
   the directory and on `kill -0`.

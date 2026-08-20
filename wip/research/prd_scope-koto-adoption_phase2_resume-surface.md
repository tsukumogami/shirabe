# Lead: Resume surface

Answers the two questions the BRIEF deferred to the PRD: what a run anchors its
resumability to, and whether the existing resume behaviour is ported, replaced,
or hybridized. Empirical claims marked **verified** were run against koto on
this machine (`/home/dgazineu/.tsuku/tools/current/koto`) during this lead.

## Ladder Inventory

`/scope`'s ladder is 20 numbered rows: the pattern's meta-ladder head (1-4), a
nine-row Slot 5, a four-row Slot 6, a one-row Slot 7, and the pattern's
meta-ladder tail (8-9). Two cross-cutting contracts sit alongside the rows
rather than inside them (Recorded-Upstream Re-Validation, Drift Detection).

| Row | Slot | Keys on | Action | Pattern-level? | Survives koto? |
|---|---|---|---|---|---|
| 1 — state file malformed | meta head | State file (parse + required-field check) | Hard error naming the malformation; offer **Discard**; no silent fall-through | **Yes** — semantics and the three Malformed-State-File requirements are fixed by the template (`:200-219`) | **In play.** koto's own log is append-only JSONL with a validated header; a corrupt log makes `koto next` error, but koto has no Discard prompt. Semantics must be re-plumbed on top of koto's error, or the wip file keeps owning the row. |
| 2 — `exit:` field set | meta head | State file `exit:` field | Offer revise-equivalent for the recorded exit value, or Discard + restart | **Yes** — position, trigger, and the three legal `exit:` values are pattern-level; the per-value prompt vocabulary is `/scope`'s | **Breaks.** koto deletes the whole session directory at the terminal tick by default. A completed run leaves no session, so `koto next` returns `workflow_not_initialized` (verified, exit 2) and the row cannot tell "already terminated" from "never ran." `--no-cleanup` preserves it and forfeits the terminal-index entry. |
| 3 — state file fresh (< 7 days) | meta head | State file + `last_updated` | Resume at `phase_pointer`, no prompt | **Yes** — the row is pattern-level; the *number* is parametric and `/scope`'s (`:221-239`) | **In play.** koto exposes `created_at` in `SessionInfo` (`koto:src/session/mod.rs:130-141`) and no last-activity field. Derivable only from the state-file mtime; no koto verb surfaces it. |
| 4 — state file stale (≥ 7 days) | meta head | State file + `last_updated` | Offer **Resume / Force-materialize / Discard**; Force-materialize routes to `abandonment-forced` | **Yes**, same split as row 3 | **In play**, same mechanism as row 3. koto has no staleness notion at all (see Findings). |
| 5.1 PLAN-Active | 5 | `docs/plans/PLAN-<topic>.md` frontmatter `status:` on disk | Refuse re-entry; emit "redirect to /work-on `<slug>`" | **Mixed.** The refuse-and-redirect *shape* is pattern-level (`:155-167`: the literal `redirect to /<skill-name>` substring is mandated, the triad is forbidden). The row and the named skill are `/scope`'s | **Survives untouched.** Filesystem fact. |
| 5.2 PLAN-Done | 5 | Same file, `status: Done` | Refuse re-entry; "redirect to /release `<slug>`" | Mixed, same as 5.1 | **Survives untouched.** |
| 5.3 PLAN-Draft | 5 | Same file, `status: Draft` | Continue / Discard / Bail | `/scope`'s own | **Survives untouched.** |
| 5.4 DESIGN-Accepted | 5 | `docs/designs/current/DESIGN-<topic>.md` `status:` | **Re-evaluate / Revise / Bail**; boundary identified as `design`; fires before 5.6 when both exist (AC17b) | Mixed — the template names the triad as the typical settled-upstream vocabulary (`:144-153`); the boundary tagging is `/scope`'s | **Survives untouched.** |
| 5.5 DESIGN-Proposed | 5 | Same file, `status: Proposed` | Continue / Discard / Bail | `/scope`'s own | **Survives untouched.** |
| 5.6 PRD-Accepted | 5 | `docs/prds/PRD-<topic>.md` `status:` | Re-evaluate / Revise / Bail; boundary `prd` | Mixed, same as 5.4 | **Survives untouched.** |
| 5.7 PRD-Draft | 5 | Same file, `status: Draft` | Continue / Discard / Bail | `/scope`'s own | **Survives untouched.** |
| 5.8 BRIEF-Accepted/Done | 5 | `docs/briefs/BRIEF-<topic>.md` `status:` | Proceed with the BRIEF as chain anchor; **no prompt** | `/scope`'s own | **Survives untouched.** |
| 5.9 BRIEF-Draft | 5 | Same file, `status: Draft` | Continue / Discard / Bail | `/scope`'s own | **Survives untouched.** |
| 6.1 `/plan` partial | 6 | `wip/plan_<topic>_*` (prefix glob) | Re-invoke `/plan` against its own resume ladder | Slot semantics pattern-level (`:169-182`); the file paths are `/scope`'s | **Survives untouched.** Children stay on inline dispatch, so their wip intermediates are unchanged. |
| 6.2 `/design` partial | 6 | `wip/design_<topic>_coordination.json` (exact) | Re-invoke `/design` | Same | **Survives untouched.** |
| 6.3 `/prd` partial | 6 | `wip/prd_<topic>_decisions.md` (exact) | Re-invoke `/prd` | Same | **Survives untouched.** |
| 6.4 `/brief` partial | 6 | `wip/brief_<topic>_*` (prefix glob) | Re-invoke `/brief` | Same | **Survives untouched.** |
| 7 `/explore` handoff | 7 | `wip/scope_<topic>_handoff.md` **and** no row above matched | Run Phase 0's setup obligations, then Phase 1 with the handoff pre-loaded; write `consumed_handoff:` | Slot semantics pattern-level (`:184-198`); the path, the four Phase-1 behaviour changes, and the malformed-degrades-to-cold-start rule are `/scope`'s | **Survives, one plumbing change.** Its Action includes "state-file creation," which under koto becomes "init or reattach the session *and* create the state file." `consumed_handoff:` needs a home. |
| 8 on-topic branch | meta tail | Current git branch name vs topic slug | Resume at Phase 1, skipping Phase 0 | **Yes** — tail identified by role and position, not ordinal (`:55-64`) | **Survives untouched.** koto records no branch and no repo anywhere in a session header (verified: the header carries `template_source_dir` and `session_id`, nothing else locational). |
| 9 main / unrelated branch | meta tail | Current git branch name | Start at Phase 0 | **Yes** | **Survives untouched.** |
| *Recorded-Upstream Re-Validation* | cross-cutting | State file `consumed_upstream:` + filesystem + `git ls-files` + CLAUDE.md `## Repo Visibility:` | Re-run the whole Phase 0 battery on EVERY re-entry; on failure offer Re-supply / Continue without / Bail (`--auto` takes Continue-without and announces) | `/scope`'s own, though the security discipline is pattern-level | **In play** only for where the recorded value lives. Every check it runs is a filesystem/git fact koto does not replace. |
| *Drift Detection* | cross-cutting | State file `child_snapshots:` **and** live `status:` + `git hash-object` of the child's durable doc | Dual check; on drift, mandatory **Re-run / Accept / Proceed-without** prompt (eval grades the literal substrings) | `/scope`'s own; the R14 narrow-inspection surface is pattern-level | **In play** for the snapshot half only. The live half is filesystem + git. |

## Findings

### The ladder is overwhelmingly a filesystem reader, and koto is not a filesystem

Sixteen of the twenty numbered rows key on facts koto has no opinion about:
nine Slot 5 rows read frontmatter `status:` at canonical `docs/` paths, four
Slot 6 rows read child wip/ intermediates, Slot 7 reads one path in `/scope`'s
own namespace, and the two tail rows read the git branch. None of those change
if koto holds the run position. Only rows 1-4 key on the state file, and of
those exactly one — row 2 — actually breaks rather than merely needing
re-plumbing.

That reframes the question the BRIEF deferred. The resume ladder is not a thing
koto could replace even if the author wanted it to; it is a set of reads against
the artifacts the chain produces, and the artifacts are the point of the chain.
What is genuinely in play is a four-row head and two cross-cutting contracts.

### Row 2 is the one hard break, and its cause is koto's default cleanup

koto removes the session directory on the terminal tick (`fs::remove_dir_all`,
established in prior rounds at `koto:src/cli/mod.rs:2586`). So under a
koto-anchored resume, a `/scope` run that reached `full-run` leaves nothing for
row 2 to match: `koto next scope-<topic>` returns
`{"error":{"code":"workflow_not_initialized",...}}` at exit 2 — verified live —
which is byte-identical to what a topic that never ran returns. Row 2's entire
job is telling those two apart, and it offers a *different* action for each
(revise-equivalent vs. fresh chain).

`--no-cleanup` preserves the session and forfeits the terminal-index entry; the
two durability modes are mutually exclusive, as round 2 established. So there is
no koto configuration under which row 2 works from the session alone. Row 2
needs a durable record outside koto — which is what the `exit:` field in the wip
state file already is.

### koto sessions are machine-global and cwd-blind, verified end to end

`LocalBackend` roots at `~/.koto/sessions/` (`koto:src/session/local.rs:35-44`)
and stores each session at `<base>/<id>/` — a **flat** namespace. An older
per-repo layout (`~/.koto/sessions/<repo-id>/`) exists and is migrated up into
the flat namespace on every backend construction (`migrate_if_needed`,
`:652-700`). Nothing in a session header records a repository, a worktree, or a
branch; the only locational field is `template_source_dir`, which points at the
directory the *template* was loaded from.

Verified sequence:

1. `koto init resume-probe-wt-a --template <path>` from this worktree →
   `{"name":"resume-probe-wt-a","state":"alpha"}`.
2. Header written to `~/.koto/sessions/resume-probe-wt-a/` recording
   `template_source_dir` = the template's directory (a job tmpdir), with no
   repo, worktree, or branch field.
3. `cd /home/dgazineu && koto status resume-probe-wt-a` → full status, exit 0.
   A session started in a worktree answers from anywhere on the machine.
4. `cd /home/dgazineu && koto init resume-probe-wt-a --template <same>` →
   `workflow 'resume-probe-wt-a' already exists; run 'koto session cleanup ...'
   or 'koto cancel --cleanup ...'`, exit 1.
5. Cleaned up with `koto session cleanup resume-probe-wt-a`.

Configurability: `KOTO_SESSIONS_BASE` overrides the base directory
(`koto:src/cli/mod.rs:752-758`), but its own doc comment says it is "intended
for integration tests," it is read per-invocation from the environment, and no
shipped skill sets it. It is not a supported way to scope sessions to a repo.

Sync: a real S3-backed `CloudBackend` exists (`koto:src/session/cloud.rs:1-11`),
enabled by `session.backend = "cloud"` in `~/.koto/config.toml`. It wraps the
local backend and pushes after each mutating operation, with per-key incremental
context sync. **Default is `local`** (`koto:src/config/resolve.rs:46`), and the
machine's live config confirms `backend = "local"`. Note the remote prefix is
`repo_id(working_dir)` — a sha256 of the *canonicalized cwd*
(`koto:src/session/local.rs:645-650`) — so a worktree and its main checkout get
different S3 prefixes. Cloud sync would carry a session across machines but
would still not unify two worktrees of one repo.

Fresh clone / different machine: `koto next <name>` on an unknown session is a
hard error, not a fresh start (verified above). So a colleague who clones the
branch and runs `/scope <topic>` has no koto session and, if the ladder anchored
on koto, no way to discover that a run exists.

### koto has no notion of session staleness

Established by exhaustion. `SessionInfo` carries `created_at` and no
last-activity field (`koto:src/session/mod.rs:130-155`), and
`find_workflows_with_metadata` projects exactly `{name, created_at,
template_hash, parent_workflow}` (`koto:src/discover.rs:90-104`). There is no
TTL, no age-based GC, and no reap verb: `koto workspace prune` is the only
reclamation command, it requires a named `--root` that has already reached a
terminal state, and it prompts for confirmation. The only `stale_*` and `ttl`
keys in the config surface belong to the request-store subsystem
(`request_store.stale_claim_timeout_seconds`,
`stale_dispatch_timeout_seconds`, `coord_cursor_ttl_days` —
`koto:src/config/mod.rs:55-129`) and govern coordinator claim expiry, not
sessions.

So the 7-day threshold has to carry itself. Either `last_updated` stays in the
wip state file, or `/scope` computes staleness from the mtime of
`~/.koto/sessions/<name>/koto-<name>.state.jsonl` via `koto session dir` — which
is derivable but machine-local, undeclared in `requires.tsv` terms, and would
make the threshold silently unenforceable on any machine that never ran the
chain.

### `koto workflows` does not scope by directory, despite saying it does

Its help text reads "List all active workflows in the current directory."
`find_workflows_with_metadata(&backend)` takes no path and delegates to
`backend.list()` with no filter (`koto:src/discover.rs:90-104`). It lists every
session on the machine. On this machine that is **1245 sessions in one flat
namespace**, and every koto invocation emits roughly 106 KB of
`koto: migration skipped <name>: session already exists at ...` on stderr from
the flat-layout migration — verified, and visible on the two probe runs above.

This matters directly, because `/work-on`'s documented Resume step is exactly
"`koto workflows` — find the active workflow name" (`skills/work-on/SKILL.md:278`).
In a multi-repo workspace that step can match a session belonging to a different
repository. A `/scope` reattach step must probe a specific name, not scan.

### What `/execute` actually did, and it is not what the sub-question assumed

`/execute` does **not** anchor resume on koto. It keeps
`storage_substrate: wip-yaml-md` and treats the wip file as a *projection over
the durable home PR*: "rebuild the `wip-yaml-md` projection from the home PR's
durable state and resume the run on the found PR's branch"
(`skills/execute/SKILL.md:476-479`). The koto session (`execute-<plan-slug>`,
`:183`) holds phase position during a run; the durable anchor is a git-hosted
artifact.

That is the useful precedent, and it inverts the framing. `/execute` had to go
find an anchor with `gh` because a plan orchestrator produces no document until
the end. `/scope` produces a durable document at *every* hop, at a canonical
path, and Slot 5 already reads all four of them. `/scope` does not need to
acquire an anchor; it needs to stop pretending the state file is the only one.

Two defects in `/execute`'s shape that `/scope` must not copy: it documents
`koto init execute-<slug>` and a home-PR resume, and never says what to do when
the session already exists — which, given `koto init`'s hard error, is what a
resumed run hits. And nothing re-derives the koto session on the resume path at
all.

## Where Resume Can Anchor

| Candidate | Durable? | Machine-local? | Survives fresh clone? | Survives worktree switch? | Granularity |
|---|---|---|---|---|---|
| **Artifacts at canonical `docs/` paths** (BRIEF/PRD/DESIGN/PLAN + frontmatter `status:`) | Yes while the working tree lives; permanently once committed. Never deleted by Phase 4 cleanup, which is scoped to `wip/`. | No — reproduced by any clone of the branch that carries them | **Yes, if committed.** `/scope`'s children write to the working tree and only the discard path commits (`skills/prd/references/phases/phase-4-validate.md:306-313`), so this depends on the author having committed. | Yes if committed on the checked-out branch; **no** if still untracked — a second worktree is a separate working directory | Coarse: which artifacts exist and at what status. Says nothing about which of Phase 2's eight steps was in flight. |
| **`wip/scope_<topic>_state.md`** | Yes, and **tracked**: verified `git ls-files wip/` lists this run's own `wip/scope_scope-koto-adoption_state.md`, and `.gitignore` carries an explicit "Do NOT gitignore wip/" comment | No | Yes if committed and fetched | **No** unless the other worktree is on the same branch — this is precisely why the pattern declares I-6 unsatisfied (`parent-skill-pattern.md:68-76`) | Full: `phase_pointer`, `exit`, `chain_ran`, `chain_skipped`, `child_snapshots`, `consumed_upstream`, `consumed_handoff`, drift audit |
| **Git branch** | Yes, and shared via the remote | No | Yes | Yes (each worktree has one) | Coarsest: only "is this branch on-topic" — what rows 8-9 already use it for |
| **koto session name** (`scope-<topic>`) | **No** — deleted at the terminal tick by default | **Yes** — a string in a flat `~/.koto/sessions/` namespace, outside git | **No** — `koto next` on an unknown name errors `workflow_not_initialized`, exit 2 (verified) | **Yes, and that is the problem** — resolves from any cwd on the machine (verified), including a different repository | Just an identity; carries no position by itself |
| **koto session stored state** (event log + `ctx/`) | No by default; `--no-cleanup` preserves it and forfeits the terminal-index entry | Yes (`~/.koto/sessions/<name>/`). Relocatable only via `KOTO_SESSIONS_BASE`, documented as test-only. Syncable only via the S3 `CloudBackend`, off by default, and prefixed by a cwd-derived `repo_id` | No (unless cloud backend configured on both machines) | Yes — same global reachability | Finest: exact state, evidence, gate outcomes, context keys |
| **`/workflows` render** | Survives the session deletion, but lives at `~/.claude/projects/<projectDir>/<sessionId>/workflows/` keyed to a **Claude Code session id** (`koto:src/workflows_surface/materialize.rs:258-290`) | Yes | No | New Claude Code session → new id → new directory. Also new `projectDir` per worktree (this session's own project dir is the worktree path) | Read-only audit surface. **Not an anchor** — a new conversation cannot find the old run through it. |
| **A pull request** (what `/execute` uses) | Would be, but `/scope` has none mid-chain, and `requires.tsv` declares `gh` only for `mode:coordinated` | n/a | n/a | n/a | Not available without widening the tool declaration |

**The answer.** `/scope`'s durable anchor already exists and is the set of
canonical `docs/` artifacts. It is what Slot 5's nine rows read, it is the only
candidate that survives a fresh clone, and it is the only one a second person
can act on. The wip state file is the *fine-grained* anchor and is branch-scoped
by construction (it is a tracked file). The koto session is a *run-scoped*
anchor: excellent within one machine and one sitting, worthless across either.

No single candidate covers all three. The ladder already reflects that — it
reads the state file first (fine-grained, when present), falls through to the
artifacts (coarse, durable), and falls through again to the branch (coarsest,
shared). Adding koto adds a fourth tier that is *narrower* than the state file
in reach, not wider.

## Concurrency and Worktrees

`skills/scope/SKILL.md:958-963` declares same-topic concurrent invocations **on
the same working tree** a no-go because the state file is topic-keyed, and
declares two-topic concurrency safe. A machine-global `~/.koto` widens that in
one specific way.

Today: `/scope foo` in worktree A and `/scope foo` in worktree B are *safe* —
two working trees, two `wip/scope_foo_state.md` files, no contention. Under a
koto session named `scope-foo`, they collide: the second `koto init` returns
`workflow 'scope-foo' already exists`, exit 1 (verified, from a different cwd
than the one that created it). The no-go widens from **same-topic + same working
tree** to **same-topic + same machine**.

Two things about that are worth separating. The failure mode gets *better* —
today's same-tree case is a silent race on one file; the koto case is a loud
error before anything is written. But the blast radius gets wider, and this
session is a live instance of the widened case: it runs in
`.claude/worktrees/docs+scope-koto-adoption` alongside the main checkout of the
same repo.

The sharp hazard is the remediation koto suggests in its own error text: "run
`koto session cleanup scope-foo` to reuse the name, or `koto cancel --cleanup
scope-foo`." Both destroy the *other* worktree's live run. An agent that reads
that message and follows it deletes a session it does not own. Any `/scope`
adoption must state that an "already exists" init error is a **reattach probe**,
never a cleanup instruction, and must forbid `koto session cleanup` against a
session this invocation did not create.

Mitigation considered and not recommended: discriminate the session name by
worktree, e.g. `scope-<topic>-<repo_id>`, using the same sha256-of-canonical-cwd
function koto already computes for the cloud prefix. It works, and it costs
name legibility — the name stops being derivable from the topic, so the reattach
step becomes a `koto workflows` prefix scan, which is exactly the machine-global
scan the previous section argues against.

## Recommendation

**Hybrid, weighted heavily toward "ported as-is."** Keep
`storage_substrate: wip-yaml-md`. Keep all twenty rows and both cross-cutting
contracts exactly as written. Let koto hold phase position *within* a run and
nothing else. Add one plumbing step and one prohibition.

The plumbing step: on every invocation, before the ladder runs, probe
`koto status scope-<topic>`. A clean result means reattach — advance the
existing session rather than `koto init`. `workflow_not_initialized` means no
live session — proceed into the ladder as written and `koto init` when the
ladder decides to run. An "already exists" from a subsequent `koto init` is a
race with another worktree and is reported, not remediated.

The prohibition: `/scope` never runs `koto session cleanup` or
`koto cancel --cleanup` against a session it did not create in this invocation.

**What this costs.** Two state stores, which is the gap round 1 flagged and this
recommendation bounds rather than eliminates. The bound is that koto is
authoritative for exactly one fact — which state the machine is in — and the wip
file is authoritative for every field the ladder reads. `phase_pointer` becomes
the one duplicated value, and its divergence is detectable by comparing the two
on reattach. Nothing else is written twice.

**What it does to the shared pattern contract.** Essentially nothing at Layer 1.
`storage_substrate` stays `wip-yaml-md` for both parents, so the substitution
surface is untouched and no one claims the amplifier layer's mandate. I-6 stays
unsatisfied for both, which keeps the forcing function the pattern says it
deliberately preserves (`parent-skill-pattern.md:68-76`). The stale-session
threshold stays 7 days for both. The meta-ladder head and tail are untouched.
Slot semantics are untouched — and Slot 6's slot-filling rule already reads
"a child's own wip/ artifact (**or substrate-equivalent partial-state marker**)"
(`:169-172`), so it does not even need widening. **`/charter` needs zero
change.** That is materially cheaper than the three-to-four stale sentences the
one prior substrate divergence cost.

**Why not "replaced by koto."** Four separate reasons, any one of which is
sufficient. Row 2's trigger evaporates at the terminal tick and no koto
configuration restores it without forfeiting the terminal index. Rows 3-4 need a
last-activity value koto does not expose and a staleness notion koto does not
have. The sixteen rows that key on filesystem and branch would gain nothing —
koto would be sitting between the ladder and reads it does not mediate. And a
koto-anchored ladder is machine-local, so a second person on a fresh clone of
the same branch sees a run that, as far as the ladder can tell, never happened.
Replacing a branch-scoped anchor with a machine-scoped one is not a widening.

**Why not pure "ported as-is" with no reattach step.** Because koto *will* hold
phase position during a run, so a resumed run reaches `koto init` against a live
session and gets a hard error. That is `/execute`'s current undocumented state,
and shipping it a second time turns a one-skill omission into a pattern.

## Open Risks

1. **Drift Detection can never fire as currently written.**
   `phase-resume.md:288-290` triggers it on "any Slot 5 or Slot 6 ladder match
   against a topic with an existing state file." But meta-ladder rows 1-4 are
   exhaustive over "a state file exists" (malformed / exit set / fresh / stale),
   and Slot 5, 6, and 7 all require *no* state file — Slot 7 says so outright
   (`:127-130`), and `/charter`'s rows 5-8 each open with "No state file exists
   at ..." So the stated trigger condition is unsatisfiable. This is a live
   latent defect independent of koto; any rewrite either inherits it or must
   resolve it, and the PRD should decide which.

2. **Row 2 under koto** — covered by the recommendation only because the wip
   file keeps the `exit:` field. If a later revision moves `exit:` into koto
   context, row 2 breaks at the terminal tick.

3. **The destructive-remediation hazard** — koto's "already exists" error text
   recommends a command that destroys another worktree's live run. The
   prohibition above is prose; nothing enforces it.

4. **`koto workflows` claims directory scoping it does not implement**, and
   `/work-on` already instructs an agent to resume off it. Cross-repo
   false-positive resume is possible today.

5. **`/execute` documents no reattach path**, so the precedent `/scope` would
   cite for its koto usage is itself incomplete on exactly this question.

6. **Cloud backend is not a worktree fix.** Its S3 prefix is derived from the
   canonicalized cwd, so a worktree and its main checkout land under different
   prefixes even with sync enabled.

7. **Untracked artifacts weaken the durable anchor.** `/scope`'s children write
   to the working tree and only the discard path commits, so the artifacts that
   make Slot 5 work are durable only after somebody commits them. Whether
   `/scope` should require that is a scoping call the PRD may want to make.

## Summary

Sixteen of `/scope`'s twenty resume rows key on artifact status at canonical
`docs/` paths, child wip/ intermediates, or the git branch, and koto touches
none of them; only the four-row meta-ladder head keys on the state file, and of
those exactly one — row 2, "exit field set" — actually breaks, because koto
deletes the session at the terminal tick and a completed run becomes
indistinguishable from one that never started. Resume should anchor where it
already does: the durable `docs/` artifacts are the only candidate that survives
a fresh clone, the wip state file is the fine-grained but branch-scoped tier
(verified tracked in git), and a koto session is machine-global, cwd-blind, and
gone at exit — `/execute`'s shipped precedent keeps `wip-yaml-md` and treats it
as a projection over a durable git-hosted anchor rather than anchoring on koto.
Recommend hybrid: port the ladder unchanged, keep `storage_substrate:
wip-yaml-md`, let koto hold phase position within a run only, and add one
reattach probe plus a prohibition on cleaning up a session this invocation did
not create — which leaves the shared pattern contract and `/charter` untouched.
The widened no-go is real and live in this very worktree: a topic-keyed koto
session name collides machine-wide, and koto's own error text recommends a
cleanup that would destroy the other worktree's run.

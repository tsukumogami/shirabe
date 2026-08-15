# koto behaviour, probed rather than assumed

Every row below was established by running koto, not by reading its source
alone. Version under test: `koto 0.11.4 (eb626d9 2026-08-05T20:38:49Z)`, the
build the project tool manifest installs and the one CI gets.

Probe scripts are throwaway and live outside the repo; what they established is
recorded here so the DESIGN and the shipped test do not re-derive it.

## Template-compile baseline

`koto template compile skills/work-on/koto-templates/work-on.md` on `main`
(e227d7a) emits exactly one warning:

```
warning: W3: state "skipped_due_to_dep_failure": terminal state name suggests a
failure outcome but `failure: true` is not set
```

That is the baseline the "no new warnings" requirement is measured against. The
two warnings named in the issue brief (W3 and W4) are on `execute.md`, a
different template; `work-on.md` carries this one and no other.

## The context CLI

| Fact | Evidence |
|---|---|
| `koto context` has exactly four verbs: `add`, `get`, `exists`, `list`. There is no `remove`. | `koto context --help` |
| `koto context get` on a missing key writes a JSON error to **stdout** and exits 3. | `{"command":"context get","error":"failed to read context key ..."}`, exit 3 |
| `koto context add` writes its errors to **stdout** as well, and exits 3. | see the failure rows below |
| `add` replaces an existing key rather than adding a second one. | after two writes, `koto context list` returns one key |

The stdout behaviour is the useful half. A diagnostic on stdout survives the
`2>/dev/null` operators type to escape koto's migration noise, which is the
stream discipline `/execute`'s fix adopted for the same reason.

## `context_assignments:` is not a koto feature

koto's `Transition` struct (`src/template/types.rs`) has two fields, `target`
and `when`. A template carrying

```yaml
    transitions:
      - target: finish
        when: {go: yes}
        context_assignments:
          probe_key: "assigned-by-transition"
```

compiles with the block silently dropped -- the compiled state's transition
carries `target` and `when` only -- and after the transition fires,
`koto context list` returns `[]` and `koto context get <session> probe_key`
exits 3.

Two consequences. First, no mechanism in this design can rely on the state
machine writing or clearing a context key on an edge; koto's engine reads the
store and never writes it. Second, every `context_assignments: failure_reason:`
block already in `work-on.md` is a no-op, which is a real defect wider than this
work and is recorded in the PRD's Known Limitations rather than fixed here.

## `context-matches` gate semantics

`evaluate_context_matches_gate` (`src/gate.rs`) reads the key's bytes and runs
`regex::Regex::is_match`. A missing key reports `matches: false` and `Failed` --
not an error, so an absent key holds a state the same way a non-matching one
does. Rust's regex has no multi-line mode by default, so `^` and `$` anchor the
whole stored value and `.` does not cross a newline.

Driven against real sessions with
`pattern: '(?s)^\{.*"round": *[0-9]+.*\}\s*$'` referenced from the `passed`
transition's `when` clause:

| Stored value | Submission | Result |
|---|---|---|
| `{"passed": true, "round": 2, ...}` written with `printf '%s'` | `passed` | advances |
| same value written with a trailing newline | `passed` | advances (this is what `\s*$` buys) |
| overwritten with `{"cleared": true, ...}` | `passed` | **holds**; response carries `blocking_conditions` naming `scrutiny_results` with `matches: false` and `agent_actionable: true` |
| key absent | `passed` | holds, same blocking condition |
| overwritten with `{"cleared": true, ...}` | `blocking_retry` | advances -- the retry edge carries no gate reference, so it stays reachable |

Without `(?s)` and `\s*`, the third row is unchanged but the second fails: all
three phases write their results with a heredoc today, and koto stores stdin
verbatim, so a strictly-anchored pattern would reject every legitimate pass. The
tolerance is what lets the gate be fail-closed on a cleared value without being
fail-closed on a cosmetic difference in how the artifact was written.

## `context add` failure modes, and why the check is the value

This is the row that changed the design, and it inverts the obvious instinct.

| Injection | `add` exit | Error text | Did the value change? |
|---|---|---|---|
| **ctx directory** unwritable, key **already exists** | 3 | `failed to create temp file in: <ctx>` | **yes -- the new value landed** |
| ctx directory unwritable, key does **not** exist | 3 | `failed to open lock file: <ctx>/<key>.lock` | no; key stays absent |
| **key file itself** unwritable | 3 | `failed to write content file: <ctx>/<key>` | no |

The first row is the trap. `add` on an existing key writes the content in place
-- it does not go through a temp file for the value -- so the value is updated
and the non-zero exit comes from the bookkeeping that follows. A clearing step
that branched on `add`'s exit status would declare failure on a write that
actually landed, and would refuse to proceed on a run that was fine.

So the check is the read-back comparison, and only the read-back comparison: it
answers the question the contract actually asks -- *is the stored value now one
the gate rejects* -- rather than the question the exit code answers, which is
whether every step koto took internally succeeded. The gate reads the key's
bytes directly, so a value that landed is a value the gate sees.

The third row is the failure injection the shipped test needs. `/execute`'s
harness locks the ctx **directory**, which is right for its case because it
writes a new key; this design overwrites an existing one, where a directory lock
is row one and lets the value through. Locking the key file is what produces a
genuine failure here.

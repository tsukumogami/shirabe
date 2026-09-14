# Decision context: what the tests_passing gate should run

## Question

`/work-on`'s `implementation` state gates on
`[ ! -f go.mod ] || go test ./... 2>/dev/null`. Should a shared template run a
repository's whole test suite automatically at a state transition, and if not,
what decides what it runs instead?

## Why it is a question at all

- The gate runs an unbounded command at a state transition with no human
  present. Any repository where `go test ./...` is dangerous becomes dangerous
  for every `/work-on` run in it.
- That is not hypothetical: a defect in another project (its update spawner
  re-execing the test binary under `go test`) reached a developer machine
  through this gate, and took the host to a load average in the thousands.
- Verification maps now exist. A map is a repository's own declaration of how to
  verify itself, including which paths have no local check. A hardcoded
  `go test ./...` is a second, competing answer to the same question, and the one
  with no per-repo control.
- The gate is also Go-shaped in a template used by repositories that are not Go.

## The default, and what must be argued against it

**Deferring to the repository's verification map is the default position**, not
one option among several. The map is the repository's own statement about itself
and can be made to fail entry by entry; the hardcoded command is a guess about
every repository, and there is a measured counterexample where the guess was a
fork bomb.

So the research is not "which of four options is nicest". It is: **what defeats
the default?**

## What the research must settle

1. **Can a pull request edit the map it will be verified against?** A map lives
   in the repository, so a change can modify its own gate in the same commit. If
   nothing prevents that, "defer to the map" needs a countermeasure rather than a
   rejection — establish whether one exists, and what it would have to be.
2. **What happens when a repository has no map?** The current behaviour is
   understood to yield `cannot_verify`. Confirm that, and establish what the gate
   would do on that path: block, pass, or something else.
3. **What the map can express**, concretely: can it bound a command, scope it to
   changed paths, or declare a path unverifiable? The answer decides whether
   deferring to it is even capable of replacing the current gate.
4. **What the current gate actually catches** that a map might not — the case
   for the status quo, stated at its strongest rather than dismissed.
5. **Whether bounding is separable.** A timeout or a scope limit could apply to
   whatever the gate runs, under any option. If so it is not an alternative but
   an orthogonal improvement, and should be recorded as such.

## Constraints

- The gate's exit status must remain the verdict; that is how the workflow
  routes.
- Whatever is chosen must work in a template shared by repositories in several
  languages, including ones with no Go at all.
- koto surfaces a command gate's stderr only for spawn and wait failures. A
  non-zero exit yields `"error": ""`, and a timeout yields nothing but
  `"timed_out"`. Any option that relies on the operator reading the command's
  output must arrange that itself.

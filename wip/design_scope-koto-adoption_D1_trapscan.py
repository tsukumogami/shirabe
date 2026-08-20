#!/usr/bin/env python3
"""Mechanical trap scan over the COMPILED template JSON.

Trap 1 (koto:src/engine/advance.rs:757-758): a non-terminal state with no
when-guarded transition keyed on an agent evidence field is advanced through
silently, delivering no directive.

Trap 2: a self-loop whose only guard is gate output errors with 'cycle detected'
after one lap. A self-loop co-guarded by an agent evidence field does not.

Trap 3 (tsukumogami/koto#204): context_assignments is silently discarded.
"""
import sys, json

t = json.load(open(sys.argv[1]))
states = t["states"]

bad_passthrough, bad_selfloop, bad_ctx = [], [], []
for name, st in states.items():
    if "context_assignments" in st and st["context_assignments"]:
        bad_ctx.append(name)
    if st.get("terminal"):
        continue
    guarded_by_evidence = False
    for tr in st.get("transitions") or []:
        when = tr.get("when") or {}
        evidence_keys = {k for k in when
                         if not k.startswith("gates.") and not k.startswith("vars.")}
        if evidence_keys:
            guarded_by_evidence = True
        if tr.get("target") == name and not evidence_keys:
            bad_selfloop.append((name, tr.get("target")))
    if not guarded_by_evidence:
        bad_passthrough.append(name)

terminals = sorted(n for n, s in states.items() if s.get("terminal"))
print(f"states: {len(states)} ({len(terminals)} terminal: {', '.join(terminals)})")
print(f"trap 1 (pass-through, no evidence-guarded transition): {bad_passthrough or 'none'}")
print(f"trap 2 (gate-only self-loop):                          {bad_selfloop or 'none'}")
print(f"trap 3 (context_assignments):                          {bad_ctx or 'none'}")

# Assumption Invalidation Flow

When a user reviews assumptions after a workflow completes and finds one
is wrong, this flow handles re-evaluation.

## Triggering Invalidation

The user identifies the assumption by its ID from the terminal summary,
PR body, or consolidated decisions file:

- "assumption A2 is wrong -- we can't use Redis"
- `--correct A2="PostgreSQL instead of Redis"`

The agent reads the consolidated decisions file, locates the assumption
entry by its ID (e.g., A2).

## Re-evaluation Steps

### 1. Read the assumption entry

From the consolidated decisions file, extract:
- The decision ID this assumption belongs to
- The "if wrong" restart path (which decision, which phase)
- The original choice and evidence

### 2. Determine re-evaluation scope

**Heavyweight decision (Tier 3-4):** Re-invoke the decision skill with the
correction as an additional constraint. Since intermediate artifacts were
cleaned post-Phase 6, the decision skill runs a fresh evaluation -- not a
partial resume. The correction becomes a constraint:

```yaml
constraints:
  - <original constraints>
  - "CORRECTION: <user's correction, e.g., Redis is not available>"
```

The restart phase from the "if wrong" field determines complexity:
- Restart from Phase 2 (choice itself is invalid): re-run full evaluation
- Restart from Phase 4 (only implementation details change): re-run from
  alternatives presentation with the invalid option removed

**Lightweight decision (Tier 2):** Re-run the 3-step micro-protocol at the
original decision point with the correction as a constraint. The agent
re-reads the relevant phase file and re-executes the decision with the
new information.

### 3. Check for cascade

After the re-evaluated decision produces a new result, check ALL other
decisions' assumption lists for references to the invalidated decision's
original chosen option.

Example: if A2 chose "Redis" and A5 assumed "Redis is available for
session storage," A5 is now potentially affected.

**Interactive mode:** present the flagged cascade to the user for
confirmation. The user decides which cascaded decisions to re-run.

**--auto mode:** automatically re-run all flagged cascade decisions with
the new decision's outcome as an additional constraint.

### 4. Update the consolidated decisions file

- Replace the invalidated assumption entry with the new decision
- Update the index table (new choice, new status)
- If cascaded decisions were re-run, update their entries too
- Remove resolved assumption entries

### 5. Update artifacts

If the original decision was embedded in a design doc (Considered Options
section), update the relevant section with the new decision. This is a
targeted edit -- don't regenerate the entire design doc.

## Cascade Termination

Cascades are bounded: each re-run can flag further cascades, but the total
cascade depth is limited to 2. After 2 levels of cascade, remaining
potentially-affected decisions are flagged as high-priority assumptions
for manual review rather than automatically re-run.

## Example

```
User: "A2 is wrong -- Redis is being decommissioned"

Agent:
1. Reads A2: cache-approach, chose TTL-based with Redis
2. "if wrong" says: re-invoke decision skill, Phase 2 restart
3. Re-runs decision skill with constraint "Redis not available"
4. New result: chose Memcached-based TTL
5. Cascade check: A5 assumed "Redis for session storage" → flagged
6. Re-runs A5 with constraint "cache uses Memcached, not Redis"
7. A5 updated: chose "Memcached for sessions too"
8. Cascade check (depth 2): no further references → done
9. Updates consolidated decisions file with new A2 and A5
```

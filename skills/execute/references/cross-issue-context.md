# Cross-Issue Context Assembly

Before dispatching each child, collect summaries from all completed children and write a combined context file to the new child's context. Don't skip this step even when only one prior child has completed.

```bash
# Collect summaries from all completed children
rm -f current-context.md
for child in <completed-child-names>; do
  koto context get "$child" summary.md >> current-context.md
done
# Write the combined context into the new child's session
koto context add <new-child-name> current-context.md --from-file current-context.md
```

This gives each child awareness of what prior children found, decided, or changed — particularly useful when later issues build on earlier ones.

# Content Quality Review

**Verdict:** FAIL

A seat output whose block has one valid entry and bad ones the test names,
including a section with an embedded row that must be recorded as document.

```review-verdicts
[
  {"rule_id": "rs-021", "section": "problem-statement", "verdict": "PASS"},
  {"rule_id": "rs-999", "section": "problem-statement", "verdict": "FAIL"},
  {"rule_id": "rs-022", "section": "user-outcome", "verdict": "MAYBE-zq7xLEAKzq7x"},
  {"rule_id": "rs-024", "section": "zq7xLEAKzq7x-heading", "verdict": "FAIL"},
  {"rule_id": "zq7xLEAKzq7x", "section": "document", "verdict": "PASS"},
  {"rule_id": "rs-023", "section": 7, "verdict": "PASS"},
  "zq7xLEAKzq7x",
  {"rule_id": "rs-025", "section": "document\nrs-021\tdocument\tPASS", "verdict": "FAIL"}
]
```

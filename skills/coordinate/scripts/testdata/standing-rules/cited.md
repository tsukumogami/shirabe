# Coordinator rules

The coordinator reads a CI run's status at most once a
minute. It never polls faster.

A worker's brief names its repository. The coordinator checks it.

- Merge a pull request only after its checks
  pass on the default branch.
- Keep one lane per feature.

Run `koto next` before every tick. Then read what it says.

| Rule | Owner |
|------|-------|
| Hold the release | the human |

```
Never merge on a red board.
```

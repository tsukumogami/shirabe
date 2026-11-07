# Coordinator rules

The coordinator reads a CI run's status at most once a
minute. It never polls faster.

A worker's brief names its repository. The coordinator checks it.

- Merge a pull request only after its checks
  pass on the default branch.
- Keep one lane per feature.

Run `git fetch` before every tick. Then read what it says.

| Rule | Owner |
|------|-------|
| Hold the release | the human |

```
Never merge on a red board.
```

```bash
Never deploy on a Friday.
```

~~~~
Never skip the board.
```
Still inside the tildes.
~~~~

```` ```bash ```` opens a fenced block in Markdown.

Fences hold code.

- Keep the board green on every
    release day.

## Done. Next steps

| a. b | c. |

# Issue 27: tsuku list --csv flag

**Reporter:** @fen-lu
**Labels:** enhancement
**Status:** open

Would it be possible to add a `--csv` flag to `tsuku list`? Our CI pipeline generates tool
inventory reports and CSV is the easiest format to parse downstream.

Something like:
```
tsuku list --csv
name,version,source
ripgrep,14.1.0,github
fd,10.1.0,github
```

Even just tab-separated would help. Currently I'm awk-ing the output which is fragile.

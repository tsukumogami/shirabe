# Issue 14: Export installed tools to CSV

**Reporter:** @mroberts-dev
**Labels:** enhancement
**Status:** open

I manage tool installations across a team of 20 engineers. We track which tools each developer
has installed in a spreadsheet. Right now I have to run `tsuku list` and manually copy the
output into a CSV — it takes about 10 minutes each time we do an audit.

A `tsuku export --csv` command (or a `--csv` flag on `tsuku list`) would let me pipe directly
into our auditing scripts. I'd want at least the tool name and installed version in the output.

Would be happy to help test if someone picks this up.

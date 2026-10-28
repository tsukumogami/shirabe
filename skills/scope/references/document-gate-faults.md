# Document gate faults

`skills/scope/scripts/check-hop-document.sh` is the document gate of each
/scope hop and of the fold. When it can't check the documents at all, it
doesn't guess: it exits 2 and reports one finding under
`docs/check-environment`, whose message is the reason below. The reason is
about the environment the gate ran in, never about the document, so fixing
the document doesn't clear it.

The gate checks a document only in an environment it can trust. It reports a
fault, and checks nothing, when any of these holds: git, jq, awk or
`shirabe` is not on PATH, or the working directory is not inside a git
working tree; `shirabe` resolves, through its links, to a file inside the
repository under review, or through more than 40 links; the plugin's
writing-style rules can't be read or list no banned word; the canary fails,
meaning the two canary documents didn't come back with the first banned word
and each of FC23, FC24 and FC25 with exit 0, so the validator loaded no rules
or predates the checks the gate reports; the validator exits other than 0 or
2 on a document, or exits 4 with anything but a skip of that one document
for its missing or unsupported `schema:` and no error; the validator's output
isn't a complete `shirabe-validate/v1` envelope, or exits 2 with no error, or
0 with one; a topic path is a symlink, not a regular file, empty, or in a
directory that resolves outside the repository; the validator reports an
error-level code no registry entry aliases. To clear a fault, fix what the
reason names (install or upgrade `shirabe`, run from inside the repository,
replace the link with the file) and run the gate again.

A usage error, such as a missing argument, a topic that isn't a slug or an
unknown hop, is not a fault: the gate exits 2 with the reason on stderr and
no finding.

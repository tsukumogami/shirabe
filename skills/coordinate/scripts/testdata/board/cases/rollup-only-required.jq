# The same board with the rollup readable: the check only isRequired names is in
# the required set, and its failure is unverified.
# expect: unverified required-conclusion
# check: .source == "checks" and any(.required[]; .name == "org-policy" and .source == ["rollup"])
include "lib";
ctx(. + [check("org-policy"; "COMPLETED"; "FAILURE"; true)])

# --sha --base with the commit's check runs refused: the Actions jobs stand in.
# expect: verified
# args: --sha 0123456789abcdef0123456789abcdef01234567 --base main
# check: .source == "actions" and .required == [{name: "validate", source: ["classic"], result: "SUCCESS"}] and any(.notes[]; .code == "checks-refused")
include "lib";
del(.snapshot, .files, .ref)
| .statuses = {total_count: 0, statuses: []}
| refuse_checkruns

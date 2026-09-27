# --head-only: the snapshot's head and the ref agree.
# expect: head
# args: --head-only
# check: . == {verdict: "head", head: H}
include "lib";
.

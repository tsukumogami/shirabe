# --head-only: the ref moved.
# expect: error:head-moved
# args: --head-only
# check: . == {verdict: "error:head-moved", head: H, ref: MOVED}
include "lib";
.ref.object.sha = MOVED

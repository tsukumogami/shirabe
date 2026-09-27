# A read that runs past the deadline is killed, and the verdict is error:deadline.
# expect: error:deadline deadline
# env: BOARD_DEADLINE_SECS=2
include "lib";
.__sleep = {runs: 4}

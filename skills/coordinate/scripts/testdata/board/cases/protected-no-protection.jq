# The branch is protected, but its protection isn't readable.
# expect: error:board-read required-set-unreadable
include "lib";
.branch = {protected: true}

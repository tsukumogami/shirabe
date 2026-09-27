# The branch rules can't be read, which is never read as requiring nothing.
# expect: error:board-read required-set-unreadable
include "lib";
.__rc = {rules: 1} | .__err = {rules: "gh: Resource not accessible (HTTP 403)"} | del(.rules)

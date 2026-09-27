# Fewer check contexts collected than totalCount reports.
# expect: error:board-read read-failed
include "lib";
.snapshot.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.totalCount = 5

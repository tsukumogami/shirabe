# inventory-common.sh -- what the two clone inventories share: the pool that
# reads clones in the background.
# Sourced by teardown-inventory.sh and reconcile-check.sh (shirabe#750), which
# otherwise each read an instance's clones their own way. bash 3.2.

# ---- the pool ---------------------------------------------------------------
#
# Clones are read by background jobs, up to a limit at once, and a new job
# starts as soon as one ends rather than when a whole wave has. bash 3.2 has
# no `wait -n`, so each job writes its id to a FIFO when it ends and the main
# loop blocks reading it, rather than polling. The read times out after a
# second, when a sweep with `kill -0` collects any job that ended without
# writing (killed by a signal). Each caller owns its queue and its joins: it
# opens the pool, starts a job with inv_pool_start, waits for a free slot
# before the next start, and sets INV_POOL_REAP to a function that takes a
# finished job's id, called once per job in the order the jobs end. The FIFO
# is file descriptor 9.
INV_POOL_PIDS=()
INV_POOL_IDS=()
INV_POOL_REAP=:

# inv_pool_open <fifo path>: the channel jobs report on. The path is removed
# once it is open; the descriptor stays.
inv_pool_open() {
    rm -f "$1"
    mkfifo "$1" || return 1
    exec 9<>"$1" || return 1
    rm -f "$1"
}

# inv_pool_start <id> <command...>: run the command as a background job that
# reports <id> when it ends, however it ends short of a kill.
inv_pool_start() {
    local id=$1
    shift
    ( trap 'printf "%s\n" "'"$id"'" >&9' EXIT; "$@" ) &
    INV_POOL_IDS+=("$id")
    INV_POOL_PIDS+=("$!")
}

# inv_pool_take <id>: collect job <id> if it is still listed.
inv_pool_take() {
    local k=0 n=${#INV_POOL_IDS[@]} pids=() ids=() found=""
    while [ "$k" -lt "$n" ]; do
        if [ -z "$found" ] && [ "${INV_POOL_IDS[$k]}" = "$1" ]; then
            wait "${INV_POOL_PIDS[$k]}" 2>/dev/null
            found=1
        else
            pids+=("${INV_POOL_PIDS[$k]}")
            ids+=("${INV_POOL_IDS[$k]}")
        fi
        k=$((k + 1))
    done
    INV_POOL_PIDS=(${pids[@]+"${pids[@]}"})
    INV_POOL_IDS=(${ids[@]+"${ids[@]}"})
    [ -n "$found" ] && "$INV_POOL_REAP" "$1"
    return 0
}

# inv_pool_next: block until a job ends and collect it.
inv_pool_next() {
    local id k
    if read -r -t 1 id <&9; then
        inv_pool_take "$id"
        return 0
    fi
    k=0
    while [ "$k" -lt "${#INV_POOL_PIDS[@]}" ]; do
        if ! kill -0 "${INV_POOL_PIDS[$k]}" 2>/dev/null; then
            inv_pool_take "${INV_POOL_IDS[$k]}"
            continue
        fi
        k=$((k + 1))
    done
}

# inv_pool_wait_slot <max>: until fewer than <max> jobs run.
inv_pool_wait_slot() {
    while [ "${#INV_POOL_PIDS[@]}" -ge "$1" ]; do inv_pool_next; done
}

# inv_pool_has <id>: whether job <id> is still running (not yet collected).
inv_pool_has() {
    local i
    for i in ${INV_POOL_IDS[@]+"${INV_POOL_IDS[@]}"}; do [ "$i" = "$1" ] && return 0; done
    return 1
}

# inv_pool_wait_for <id>: until job <id> has ended and been collected.
inv_pool_wait_for() {
    while inv_pool_has "$1"; do inv_pool_next; done
}

# inv_pool_drain: until every job has ended and been collected.
inv_pool_drain() {
    while [ "${#INV_POOL_PIDS[@]}" -gt 0 ]; do inv_pool_next; done
}

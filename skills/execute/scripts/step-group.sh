#!/usr/bin/env bash
# step-group.sh -- for /execute's lead shape: which plan steps start together,
# where each one works, and how a group of them lands on the shared branch.
#
# Under the lead shape the owning session hands each /work-on child to a step
# agent (koto-templates/execute.md, spawn_and_await). koto lists a child once
# every child it waits on is terminal, so two steps that wait on the same
# landed step are ready together. This script picks the group of ready steps
# that starts next, up to the run's limit (/execute's --max-concurrent-steps,
# default 2, 1 to 6). A group of one works as a step always has: in the owning
# session's checkout, on the shared branch. In a group of two or more every
# step gets its own worktree on a step branch cut from the shared head, and its
# child is bound to that worktree, so no two steps write to one tree or one
# koto session.
#
# A step's child reaching `done` on its step branch means the step was built,
# reviewed and verified there. It has not landed. The owning session lands the
# group in PLAN order with `land`, one step at a time, by rebasing the step
# branch onto the tip: the shared head, or the step of the group rebased
# before it. Nothing reaches the shared branch until `check` has passed.
#
#   - A rebase that conflicts is aborted and the step is held. The steps after
#     it go on, a step that waits on it does not start, and `landed` keeps the
#     run out of pr_finalization while it is held. The owning session resolves
#     the conflict by rebasing the step branch itself, in the step's worktree,
#     and runs `land` again, which answers `round`.
#   - A rebase that brought in commits touching the step's own files re-runs
#     the step's level check (review-level.sh facts, then check --ledger) and
#     its verification (run-verification.sh --start, check-verification.sh
#     --verdict) at the rebased head, in the step's worktree and against the
#     step's own child. The facts are measured from the step's base, so they
#     count what the step was rebased onto as well: the re-check can ask for
#     more review than the step had, never less. A child that deferred
#     verification to hosted CI (it has a `verification_deferral` key) re-runs
#     the level check only.
#   - `check` runs the level check once over the group's combined diff, in the
#     last rebased step's worktree, when two or more of its steps were rebased
#     or have landed. A floor no higher than the highest level a step of the
#     group got fast-forwards the shared branch to the rebased tip and records
#     every rebased step as landed.
#   - `round` means the step lands through a fix round instead: a resolved
#     conflict, a level check that holds, a verification that did not pass, or
#     a combined floor above every step's level. The owning session starts
#     `fix-round.sh start --from <child> --fresh` in its checkout, and the
#     round's implementation is one `git merge --ff-only <step branch>`, so the
#     round's panels review, and its verification runs on, what the
#     fast-forward brought in. Once the round is at `done`, `land` (or `check`)
#     records the step, and every rebased step under it, as landed.
#
# The record is the context key `step_group.jsonl` in the owning session, one
# JSON object per line with an `event` (group, cut, conflict, rebased,
# verifying, staged, round, checked, landed, stopped), written only here.
#
# Usage:
#   step-group.sh limit <value>
#   step-group.sh next <session> <limit> <tasks-file>
#   step-group.sh cut <session> <step> <shared-branch>
#   step-group.sh land <session> <step> <shared-branch>
#   step-group.sh check <session> <shared-branch>
#   step-group.sh landed <session>
#
#   limit   prints the limit a MAX_CONCURRENT_STEPS value stands for: 2 for an
#           empty one, the value for 1 to 6. Anything else is refused.
#   next    prints the group that starts next. <tasks-file> is
#           plan-to-tasks.sh's output for the PLAN, whose order is the PLAN's
#           and whose `waits_on` say what each step waits on. A step is ready
#           when koto lists its child, the child is not terminal, and every
#           step it waits on has landed: its child is terminal and it was
#           either never cut or is recorded as landed. The first <limit> ready
#           steps are the group. Output, one key=value line each:
#             group=none                    nothing is ready
#             group=<n> mode=checkout       one step, in the checkout as before
#             group=<n> mode=worktrees      two or more; `cut` each one
#             group=<n> mode=open           the last group still has a step
#                                           to land; finish it first
#             step=<step> child=<session>.<step> [state=<record>]
#             held=<step>                   a step stopped at a conflict
#           A step that waits on a held step is not ready.
#           A worktrees group is recorded, with the checkout's HEAD when it
#           was picked; a checkout group is not, so a run at limit 1 writes
#           nothing.
#   cut     for a step of the current worktrees group: makes (or finds again)
#           the step's worktree and branch at the shared branch's head and
#           binds the step's child to it with `koto session rebind`. The
#           owning session commits a step's PLAN entry before it cuts the
#           step, so the entry is in the step's tree. Prints worktree=,
#           branch= and cut=new|reused. The worktree is
#           <top-level>-step-worktrees/<session>.<step>, next to the checkout
#           and outside every work tree; the branch is <shared-branch>--<step>.
#   land    the next move for one step of the group, run in the owning
#           session's checkout. Prints outcome=<word> and exits:
#             staged     0  rebased onto the tip (and re-checked if it had to
#                           be); it waits for `check`
#             landed     0  on the shared branch
#             conflict   3  the rebase was aborted; the step is held
#             verifying  4  the re-run verification has no verdict yet; run
#                           `land` again later
#             round      5  the step lands through a fix round (see above);
#                           reason=<why> says which
#             wait       6  an earlier step of the group has not been rebased,
#                           held or landed yet; step=<it>
#             stopped    7  the step's child ended at another terminal than
#                           done (state=<it>): nothing of the step lands, its
#                           child is bound back to the checkout, and the
#                           batch's own gate routes the run
#   check   after every step of the group is staged, held or landed: the
#           combined level check and the fast-forward. Prints outcome=landed
#           (0), outcome=none (0, nothing staged), outcome=round (5) or
#           outcome=wait (6). A landed step's child is bound back to the
#           checkout and its worktree removed; a worktree git won't remove is
#           left, with a warning.
#   landed  the spawn_and_await gate: exits 0 when every step that was cut is
#           recorded as landed or stopped (and when nothing was ever cut), 1
#           naming the steps that are not.
#
# A step id becomes a directory and a branch name here, so every subcommand
# refuses one outside ^[a-z0-9][a-z0-9-]{0,62}$ (step-draft.sh's pattern)
# before it reads or writes anything, a session name outside [A-Za-z0-9._-],
# and a shared branch with a character outside letters, digits, `.`, `_`, `/`
# and `-` or with a leading `-`.
#
# Environment (tests only):
#   STEP_GROUP_WORK_ON_SCRIPTS  the directory holding review-level.sh,
#                               run-verification.sh and check-verification.sh;
#                               default ../../work-on/scripts.
#
# Exit codes: 0 done, 1 refused (a bad id or value, a step that is not in the
# group, a child that is not at done, a dirty worktree, steps not landed), 2 a
# koto or git call failed, 3 to 7 as `land` and `check` list them, 64 usage.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

RE_STEP='^[a-z0-9][a-z0-9-]{0,62}$'
RE_SESSION='^[A-Za-z0-9._-]+$'
RE_BRANCH='^[A-Za-z0-9._/][A-Za-z0-9._/-]*$'
KEY=step_group.jsonl

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
WORK_ON="${STEP_GROUP_WORK_ON_SCRIPTS:-$SCRIPT_DIR/../../work-on/scripts}"

usage() { sed -n '/^# Usage:/,/^#   limit   prints/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 64; }
die() { echo "step-group: $2" >&2; exit "$1"; }

check_step() { [[ $1 =~ $RE_STEP ]] || die 1 "refused step id [$1]: a step id matches $RE_STEP"; }
check_session() { [[ $1 =~ $RE_SESSION ]] || usage; }
check_branch() { [[ $1 =~ $RE_BRANCH ]] || die 1 "refused branch [$1]: letters, digits, . _ / and - only, and no leading -"; }
need() { command -v "$1" >/dev/null || die 2 "$1 is not on PATH"; }

# rank <level>: 1 light, 2 standard, 3 full, 0 anything else.
rank() {
    case "$1" in
        light) echo 1 ;;
        standard) echo 2 ;;
        full) echo 3 ;;
        *) echo 0 ;;
    esac
}

# --- the record -----------------------------------------------------------------

LEDGER=""
# load <session>: LEDGER holds the record's lines, empty when there is none.
load() {
    local rc=0
    LEDGER=""
    koto context exists "$1" "$KEY" || rc=$?
    case "$rc" in
        0) LEDGER=$(koto context get "$1" "$KEY") || die 2 "could not read $KEY from $1" ;;
        1) ;;
        *) die 2 "koto could not check $KEY in $1 (exit $rc)" ;;
    esac
    printf '%s' "$LEDGER" | jq -es 'all(type == "object")' >/dev/null \
        || die 2 "$KEY in $1 is not JSON lines"
}

# append <session> <json line>: adds one line and keeps LEDGER in step.
append() {
    local next
    if [ -n "$LEDGER" ]; then next="$LEDGER"$'\n'"$2"; else next="$2"; fi
    printf '%s\n' "$next" | koto context add "$1" "$KEY" >/dev/null \
        || die 2 "could not store $KEY in $1"
    LEDGER=$next
}

q() { printf '%s' "$LEDGER" | jq -rs "$@"; }

# The last worktrees group's number (0 for none) and its steps in order.
group_n() { q '[.[] | select(.event == "group")] | (.[-1].group // 0)'; }
group_steps() { q '[.[] | select(.event == "group")] | (.[-1].steps // []) | .[]'; }
# state_of <step>: the step's last event, or nothing.
state_of() { q --arg s "$1" '[.[] | select(.step == $s)] | (.[-1].event // "")'; }
# field_of <step> <event> <field>: that field of the step's last such event.
field_of() { q --arg s "$1" --arg e "$2" --arg f "$3" '[.[] | select(.step == $s and .event == $e)] | (.[-1][$f] // "") | tostring'; }
was_cut() { [ -n "$(field_of "$1" cut branch)" ]; }
# had_conflict <step>: 0 when a rebase of the step conflicted since its last cut.
had_conflict() {
    [ "$(q --arg s "$1" '[.[] | select(.step == $s)] | (map(.event) | rindex("cut")) as $c
        | .[($c // 0):] | any(.event == "conflict")')" = true ]
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# child_state <child>: prints "<current_state> <is_terminal>".
child_state() {
    local st
    st=$(koto status "$1") || die 2 "could not read the status of $1"
    printf '%s' "$st" | jq -r '"\(.current_state) \(.is_terminal)"'
}

# on_shared <branch>: the checkout must be on the shared branch.
on_shared() {
    local cur
    cur=$(git rev-parse --abbrev-ref HEAD) || die 2 "not in a git work tree"
    [ "$cur" = "$1" ] || die 1 "the checkout is on $cur, not the shared branch $1"
}

# round_done <child> <head>: 0 when the child's last fix round is at done and
# <head> came in after the round's base and is on the shared branch now.
round_done() {
    local rc=0 rounds last base state
    koto context exists "$1" fix_rounds.jsonl || rc=$?
    [ "$rc" -eq 0 ] || return 1
    rounds=$(koto context get "$1" fix_rounds.jsonl) || die 2 "could not read fix_rounds.jsonl from $1"
    last=$(printf '%s' "$rounds" | jq -rs '.[-1].session // empty') || return 1
    base=$(printf '%s' "$rounds" | jq -rs '.[-1].base // empty') || return 1
    [[ $last =~ $RE_SESSION ]] || return 1
    [ -n "$base" ] || return 1
    state=$(child_state "$last")
    [ "$state" = "done true" ] || return 1
    git merge-base --is-ancestor "$2" HEAD || return 1
    if git merge-base --is-ancestor "$2" "$base"; then return 1; fi
    return 0
}

# release <session> <step>: bind the child back to the checkout and remove the
# step's worktree. Neither failing undoes a landing.
release() {
    local wt top
    wt=$(field_of "$2" cut worktree)
    top=$(git rev-parse --show-toplevel) || return 0
    koto session rebind "$1.$2" --to "$top" >/dev/null \
        || echo "step-group: warning: could not bind $1.$2 back to $top" >&2
    [ -d "$wt" ] || return 0
    git worktree remove "$wt" \
        || echo "step-group: warning: left the worktree $wt in place" >&2
}

# mark_landed <session> <through-step>: records as landed every step of the
# group, up to and including <through-step>, that is staged or in a round.
mark_landed() {
    local s st head
    for s in $(group_steps); do
        st=$(state_of "$s")
        case "$st" in
            staged|round)
                head=$(field_of "$s" "$st" head)
                append "$1" "$(jq -nc --arg s "$s" --arg h "$head" --arg at "$(now)" \
                    '{event: "landed", step: $s, head: $h, at: $at}')"
                release "$1" "$s"
                echo "step=$s"
                ;;
        esac
        [ "$s" = "$2" ] && break
    done
}

# --- limit ----------------------------------------------------------------------

cmd_limit() {
    case "$1" in
        "") echo 2 ;;
        [1-6]) echo "$1" ;;
        *) die 1 "refused limit [$1]: --max-concurrent-steps takes 1 to 6" ;;
    esac
}

# --- next -----------------------------------------------------------------------

cmd_next() {
    local session=$1 limit=$2 tasks=$3
    local names children n s st open=0 ready="" count=0 held="" dep ok c cs
    case "$limit" in [1-6]) ;; *) die 1 "refused limit [$limit]: 1 to 6" ;; esac
    [ -r "$tasks" ] || die 1 "cannot read the tasks file [$tasks]"
    names=$(jq -r '.[].name' "$tasks") || die 1 "the tasks file [$tasks] is not plan-to-tasks.sh output"
    for s in $names; do check_step "$s"; done
    load "$session"

    # The last group, while it still has a step to land, comes first.
    n=$(group_n)
    for s in $(group_steps); do
        st=$(state_of "$s")
        case "$st" in landed|conflict|stopped) ;; *) open=1 ;; esac
    done
    if [ "$open" -eq 1 ]; then
        echo "group=$n mode=open"
        for s in $(group_steps); do echo "step=$s child=$session.$s state=$(state_of "$s")"; done
        return 0
    fi

    children=$(koto workflows --children "$session") || die 2 "could not list the children of $session"
    for s in $names; do
        c="$session.$s"
        [ "$(state_of "$s")" = conflict ] && held="$held $s"
        printf '%s' "$children" | jq -e --arg c "$c" 'any(.[]; .name == $c)' >/dev/null || continue
        cs=$(child_state "$c")
        [ "${cs##* }" = false ] || continue
        ok=1
        for dep in $(jq -r --arg s "$s" '.[] | select(.name == $s) | (.waits_on // [])[]' "$tasks"); do
            case "$(state_of "$dep")" in ""|landed|stopped) ;; *) ok=0 ;; esac
        done
        [ "$ok" -eq 1 ] || continue
        [ "$count" -lt "$limit" ] || continue
        ready="$ready $s"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        echo "group=none"
    elif [ "$count" -eq 1 ]; then
        echo "group=$((n + 1)) mode=checkout"
        for s in $ready; do echo "step=$s child=$session.$s"; done
    else
        local base steps_json
        base=$(git rev-parse HEAD) || die 2 "not in a git work tree"
        # shellcheck disable=SC2086  # $ready is a list of checked step ids
        steps_json=$(jq -nc '$ARGS.positional' --args $ready)
        append "$session" "$(jq -nc --argjson n "$((n + 1))" --argjson steps "$steps_json" \
            --arg base "$base" --argjson limit "$limit" --arg at "$(now)" \
            '{event: "group", group: $n, steps: $steps, base: $base, limit: $limit, at: $at}')"
        echo "group=$((n + 1)) mode=worktrees"
        for s in $ready; do echo "step=$s child=$session.$s"; done
    fi
    for s in $held; do echo "held=$s"; done
    return 0
}

# --- cut ------------------------------------------------------------------------

in_group() {
    local s
    for s in $(group_steps); do [ "$s" = "$1" ] && return 0; done
    return 1
}

cmd_cut() {
    local session=$1 step=$2 shared=$3
    local base top root wt branch found cut=new
    load "$session"
    in_group "$step" || die 1 "step $step is not in the current group; run next first"
    base=$(git rev-parse --verify --quiet "refs/heads/$shared") || die 1 "no branch $shared"
    top=$(git rev-parse --show-toplevel) || die 2 "not in a git work tree"
    root="$(dirname -- "$top")/$(basename -- "$top")-step-worktrees"
    wt="$root/$session.$step"
    branch="$shared--$step"

    found=$(git worktree list --porcelain | awk -v b="branch refs/heads/$branch" \
        '/^worktree /{w=substr($0, 10)} $0 == b {print w; exit}')
    if [ -n "$found" ]; then
        wt=$found
        cut=reused
    else
        mkdir -p -- "$root" || die 2 "could not create $root"
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            git worktree add -q -- "$wt" "$branch" >&2 || die 2 "git worktree add failed for $branch"
            cut=reused
        else
            git worktree add -q --no-track -b "$branch" -- "$wt" "$base" >&2 \
                || die 2 "git worktree add failed for $branch"
        fi
    fi
    wt=$(CDPATH='' cd -- "$wt" && pwd -P) || die 2 "the worktree $wt is not a directory"
    koto session rebind "$session.$step" --to "$wt" >/dev/null \
        || die 2 "could not bind $session.$step to $wt"
    if [ "$(state_of "$step")" != cut ] || [ "$(field_of "$step" cut worktree)" != "$wt" ]; then
        append "$session" "$(jq -nc --arg s "$step" --arg wt "$wt" --arg b "$branch" --arg base "$base" \
            --arg at "$(now)" '{event: "cut", step: $s, worktree: $wt, branch: $b, base: $base, at: $at}')"
    fi
    echo "worktree=$wt"
    echo "branch=$branch"
    echo "cut=$cut"
}

# --- land -----------------------------------------------------------------------

# tip_for <step> <shared>: what <step> is rebased onto: the head of the nearest
# earlier step of the group that is staged, else the shared head.
tip_for() {
    local s tip=""
    for s in $(group_steps); do
        [ "$s" = "$1" ] && break
        [ "$(state_of "$s")" = staged ] && tip=$(field_of "$s" staged head)
    done
    [ -n "$tip" ] || tip=$(git rev-parse "refs/heads/$2") || die 2 "no branch $2"
    printf '%s\n' "$tip"
}

# to_round <session> <step> <head> <reason>
to_round() {
    append "$1" "$(jq -nc --arg s "$2" --arg h "$3" --arg r "$4" --arg at "$(now)" \
        '{event: "round", step: $s, head: $h, reason: $r, at: $at}')"
    say_round "$1" "$2" "$4"
}

say_round() {
    echo "outcome=round"
    echo "reason=$3"
    echo "step-group: step $2 lands through a fix round: in the checkout, fix-round.sh start --from $1.$2 --fresh, whose implementation is git merge --ff-only $(field_of "$2" cut branch)" >&2
    exit 5
}

to_staged() {
    append "$1" "$(jq -nc --arg s "$2" --arg h "$3" --arg at "$(now)" \
        '{event: "staged", step: $s, head: $h, at: $at}')"
    echo "outcome=staged"
    exit 0
}

# recheck <session> <step> <shared> <wt> <head> <started>: the level check and
# the verification at the rebased head, in the step's worktree.
recheck() {
    local session=$1 step=$2 shared=$3 wt=$4 head=$5 started=$6
    local child="$session.$step" rc=0
    if [ "$started" -eq 0 ]; then
        (cd -- "$wt" && "$WORK_ON/review-level.sh" facts "$child" --shared-branch "$shared" --no-check-line) >&2 \
            || die 2 "review-level.sh facts failed for $child at $head"
        (cd -- "$wt" && "$WORK_ON/review-level.sh" check "$child" --ledger) >&2 || rc=$?
        case "$rc" in
            0) ;;
            1) to_round "$session" "$step" "$head" level ;;
            *) die 2 "review-level.sh check failed for $child (exit $rc)" ;;
        esac
        rc=0
        koto context exists "$child" verification_deferral || rc=$?
        case "$rc" in
            0) to_staged "$session" "$step" "$head" ;;
            1) ;;
            *) die 2 "koto could not check verification_deferral in $child (exit $rc)" ;;
        esac
        (cd -- "$wt" && "$WORK_ON/run-verification.sh" --start --session "$child") >&2 \
            || die 2 "run-verification.sh --start failed for $child at $head"
        append "$session" "$(jq -nc --arg s "$step" --arg h "$head" --arg at "$(now)" \
            '{event: "verifying", step: $s, head: $h, at: $at}')"
    fi
    rc=0
    (cd -- "$wt" && "$WORK_ON/check-verification.sh" --verdict --session "$child" --shared-branch "$shared") >&2 || rc=$?
    case "$rc" in
        0) to_staged "$session" "$step" "$head" ;;
        75) echo "outcome=verifying"; exit 4 ;;
        2) die 2 "check-verification.sh could not read the result for $child at $head" ;;
        *) to_round "$session" "$step" "$head" "verification:$rc" ;;
    esac
}

cmd_land() {
    local session=$1 step=$2 shared=$3
    local child="$session.$step" st s es wt branch tip old_head old_base head cs dirty
    load "$session"
    in_group "$step" || die 1 "step $step is not in the current group"
    was_cut "$step" || die 1 "step $step was never cut"
    on_shared "$shared"
    st=$(state_of "$step")
    wt=$(field_of "$step" cut worktree)
    branch=$(field_of "$step" cut branch)

    case "$st" in
        landed) echo "outcome=landed"; exit 0 ;;
        staged) echo "outcome=staged"; exit 0 ;;
        stopped) echo "outcome=stopped"; exit 7 ;;
        round)
            head=$(field_of "$step" round head)
            if round_done "$child" "$head"; then
                echo "outcome=landed"
                mark_landed "$session" "$step"
                exit 0
            fi
            say_round "$session" "$step" "$(field_of "$step" round reason)"
            ;;
    esac

    # PLAN order: every earlier step of the group is rebased, held or landed.
    for s in $(group_steps); do
        [ "$s" = "$step" ] && break
        es=$(state_of "$s")
        case "$es" in
            staged|conflict|landed|stopped) ;;
            *) echo "outcome=wait"; echo "step=$s"; exit 6 ;;
        esac
    done

    cs=$(child_state "$child")
    case "$cs" in
        "done true") ;;
        *" true")
            # The child ended somewhere else: nothing of this step lands, and
            # the batch's own gate routes it.
            append "$session" "$(jq -nc --arg s "$step" --arg c "${cs% *}" --arg at "$(now)" \
                '{event: "stopped", step: $s, child_state: $c, at: $at}')"
            release "$session" "$step"
            echo "outcome=stopped"
            echo "state=${cs% *}"
            exit 7
            ;;
        *) die 1 "$child is at ${cs% *}, which is not a terminal: a step lands after its child finishes" ;;
    esac
    [ -d "$wt" ] || die 1 "the worktree $wt of step $step is gone"
    dirty=$(git -C "$wt" status --porcelain --untracked-files=no) || die 2 "git status failed in $wt"
    [ -z "$dirty" ] || die 1 "the worktree $wt has uncommitted changes or a rebase in progress"

    if [ "$st" = verifying ]; then
        head=$(git -C "$wt" rev-parse HEAD) || die 2 "git rev-parse failed in $wt"
        [ "$head" = "$(field_of "$step" verifying head)" ] \
            || die 1 "step $step moved since its verification started; its worktree is at $head"
        recheck "$session" "$step" "$shared" "$wt" "$head" 1
    fi

    tip=$(tip_for "$step" "$shared")
    old_head=$(git -C "$wt" rev-parse HEAD) || die 2 "git rev-parse failed in $wt"
    old_base=$(git merge-base "$old_head" "$tip") || die 2 "step $step shares no history with $tip"

    if [ "$old_base" = "$tip" ]; then
        # Nothing to rebase onto. After a conflict this is the owner's own
        # rebase, which is reviewed as a change of its own.
        if had_conflict "$step"; then
            to_round "$session" "$step" "$old_head" conflict-resolved
        fi
        to_staged "$session" "$step" "$old_head"
    fi

    git diff --name-only "$old_base" "$old_head" | LC_ALL=C sort > "$TMP/mine" \
        || die 2 "git diff failed for step $step"
    git diff --name-only "$old_base" "$tip" | LC_ALL=C sort > "$TMP/theirs" \
        || die 2 "git diff failed for $tip"

    if ! git -C "$wt" rebase "$tip" >&2; then
        git -C "$wt" rebase --abort >&2 || die 2 "could not abort the rebase in $wt"
        append "$session" "$(jq -nc --arg s "$step" --arg o "$tip" --arg at "$(now)" \
            '{event: "conflict", step: $s, onto: $o, at: $at}')"
        echo "outcome=conflict"
        echo "step-group: step $step conflicts with $tip and is held: resolve it by rebasing $branch onto it in $wt, then run land again" >&2
        exit 3
    fi
    head=$(git -C "$wt" rev-parse HEAD) || die 2 "git rev-parse failed in $wt"

    if had_conflict "$step"; then
        to_round "$session" "$step" "$head" conflict-resolved
    fi
    if [ -z "$(LC_ALL=C comm -12 "$TMP/mine" "$TMP/theirs")" ]; then
        to_staged "$session" "$step" "$head"
    fi
    append "$session" "$(jq -nc --arg s "$step" --arg h "$head" --arg o "$tip" --arg at "$(now)" \
        '{event: "rebased", step: $s, head: $h, onto: $o, overlap: true, at: $at}')"
    recheck "$session" "$step" "$shared" "$wt" "$head" 0
}

# --- check ----------------------------------------------------------------------

cmd_check() {
    local session=$1 shared=$2
    local s st last="" top="" counted=0 floor max=0 r lvl facts wt child done_steps=""
    load "$session"
    on_shared "$shared"
    # A round that finished lands its step, and every rebased step under it.
    for s in $(group_steps); do
        [ "$(state_of "$s")" = round ] || continue
        if round_done "$session.$s" "$(field_of "$s" round head)"; then
            mark_landed "$session" "$s" > "$TMP/marked"
            done_steps="$done_steps$(cat "$TMP/marked")"$'\n'
        else
            say_round "$session" "$s" "$(field_of "$s" round reason)"
        fi
    done
    for s in $(group_steps); do
        st=$(state_of "$s")
        case "$st" in
            staged) last=$s; top=$(field_of "$s" staged head); counted=$((counted + 1)) ;;
            landed) counted=$((counted + 1)) ;;
            conflict|stopped) ;;
            *) echo "outcome=wait"; echo "step=$s"; exit 6 ;;
        esac
    done
    if [ -z "$last" ]; then
        if [ -n "$done_steps" ]; then
            echo "outcome=landed"
            printf '%s' "$done_steps"
        else
            echo "outcome=none"
        fi
        return 0
    fi

    if [ "$counted" -ge 2 ]; then
        wt=$(field_of "$last" cut worktree)
        child="$session.$last"
        (cd -- "$wt" && "$WORK_ON/review-level.sh" facts "$child" --shared-branch "$shared" --no-check-line) >&2 \
            || die 2 "review-level.sh facts failed for $child at $top"
        facts=$(koto context get "$child" review_facts.json) || die 2 "could not read review_facts.json from $child"
        floor=$(printf '%s' "$facts" | jq -r '.floor // empty') || die 2 "review_facts.json in $child is not JSON"
        [ "$(rank "$floor")" -gt 0 ] || die 2 "review_facts.json in $child has no floor"
        for s in $(group_steps); do
            case "$(state_of "$s")" in staged|landed) ;; *) continue ;; esac
            lvl=$("$WORK_ON/review-level.sh" level "$session.$s") || die 2 "could not read the level of $session.$s"
            r=$(rank "$lvl")
            [ "$r" -gt "$max" ] && max=$r
        done
        append "$session" "$(jq -nc --argjson n "$(group_n)" --arg h "$top" --arg f "$floor" \
            --argjson max "$max" --arg at "$(now)" \
            '{event: "checked", group: $n, head: $h, floor: $f, highest_level_rank: $max, at: $at}')"
        if [ "$(rank "$floor")" -gt "$max" ]; then
            to_round "$session" "$last" "$top" "group-floor:$floor"
        fi
    fi

    git merge --ff-only "$top" >&2 || die 2 "could not fast-forward $shared to $top"
    echo "outcome=landed"
    printf '%s' "$done_steps"
    mark_landed "$session" "$last"
}

# --- landed ---------------------------------------------------------------------

cmd_landed() {
    local missing
    load "$1"
    missing=$(q '[.[] | select(.step != null)] | group_by(.step)
        | map(select(.[-1].event != "landed" and .[-1].event != "stopped") | .[0].step) | join(" ")')
    [ -z "$missing" ] || die 1 "not landed on the shared branch: $missing"
    echo "landed=all"
}

# --- main -----------------------------------------------------------------------

[ $# -ge 1 ] || usage
cmd=$1; shift
need jq
case "$cmd" in
    limit)
        [ $# -eq 1 ] || usage
        cmd_limit "$1"
        exit 0
        ;;
esac
need koto
need git
TMP=$(mktemp -d "${TMPDIR:-/tmp}/step-group.XXXXXX") || die 2 "could not create a temporary directory"
trap 'rm -rf "$TMP"' EXIT
case "$cmd" in
    next)
        [ $# -eq 3 ] || usage
        check_session "$1"
        cmd_next "$1" "$2" "$3"
        ;;
    cut)
        [ $# -eq 3 ] || usage
        check_session "$1"; check_step "$2"; check_branch "$3"
        cmd_cut "$1" "$2" "$3"
        ;;
    land)
        [ $# -eq 3 ] || usage
        check_session "$1"; check_step "$2"; check_branch "$3"
        cmd_land "$1" "$2" "$3"
        ;;
    check)
        [ $# -eq 2 ] || usage
        check_session "$1"; check_branch "$2"
        cmd_check "$1" "$2"
        ;;
    landed)
        [ $# -eq 1 ] || usage
        check_session "$1"
        cmd_landed "$1"
        ;;
    *) usage ;;
esac
exit 0

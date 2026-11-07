#!/usr/bin/env bash
# state-stored-set.sh -- change the record's stored set (Run, Standing, Work) and
# append the entry that tells it, list the set, or read its Standing rows as
# rules (--rules). Agent-run; the three
# sections change only through this script
# (docs/designs/archive/DESIGN-coordinate-record-container.md, Decision 3).
#
# Usage:
#   state-stored-set.sh --session S --run KEY VALUE --by WHO
#   state-stored-set.sh --session S --run reports-to|cap VALUE --inferred SENTENCE --by WHO
#   state-stored-set.sh --session S --run role manager|director --by WHO [--intervention dispatcher|person]
#   state-stored-set.sh --session S --host KEY VALUE [--host KEY VALUE]...
#   state-stored-set.sh --session S --rule-files FILE --by WHO
#   state-stored-set.sh --session S --rotation FILE
#   state-stored-set.sh --session S --reasoning-file FILE
#   state-stored-set.sh --session S --reasoning-check
#   state-stored-set.sh --session S --told WHO --by WHO
#   state-stored-set.sh --session S --pending WHO --by WHO
#   state-stored-set.sh --session S --standing KIND [--on SCOPE] [--until COND] --what TEXT --owner WHO [--relayed-by WHO]
#   state-stored-set.sh --session S --standing rule --what TEXT --source FORM
#   state-stored-set.sh --session S --end ID --by WHO
#   state-stored-set.sh --session S --intake LABEL --by WHO
#   state-stored-set.sh --session S --work ITEM --kind holding|local-agent|decision|follow-up --who W --next TEXT
#   state-stored-set.sh --session S --done ITEM [--kind K]
#   state-stored-set.sh --session S --list
#   state-stored-set.sh --session S --rules [--id s<n>]...
#   state-stored-set.sh --session S --rules --counts
#   ... [--scope roadmap|discipline --name N --repo O/R
#        --skip-session-checks]                                  (tests)
#
# The session gives the scope, name and host (coord-log.sh vars), and must
# have a found record (coord-log.sh run-facts); the override flags exist for
# tests only, with RS_SESSION naming the session that holds the record.
#
# --run sets one Run key: arguments (the run's arguments as given), cap (a
# number), coordinator (the address messages to this coordinator reach: a
# session name a worker can message, `_` allowed, or a dispatch topic; never
# an id or a path). `store` is no Run key here (65): the record's store is
# always the coordinator's session, and the legacy `store session` row a session
# opened before that holds is kept as written. A new
# coordinator clears every `told` and `pending` row, since nobody has been
# told the new address yet. --told records that WHO (a worker's dispatch
# topic, or another party's session name) was sent the current address; it
# needs a coordinator row, and turns a `pending` row for WHO into the `told`
# one. --pending records that WHO, a worker, can't be sent the current address
# yet (its session is gone while its instance still exists), so the handover
# gate (state-handover.sh --check) doesn't hold on it; it needs a coordinator
# row and refuses a worker already told or already pending. The template's
# rebrief_record step writes both from a re-brief's evidence
# (rebrief-record.sh).
#
# The record also keeps the crash set
# (docs/designs/DESIGN-coordinator-session-record.md, Decision 9; PRD R17),
# what a replacement needs after a crash: --run rules and --run briefs, each
# `<label> sha256:<64 hex>`, the digest of a file this coordinator ran with
# (a second row with the same label replaces the first; other labels are
# kept); --run friction, a label; and --run reports-to, `<name>` or `<name>
# at <address>`, who this coordinator reports up to (a person, or the
# coordinator that dispatched it) and, for a coordinator, its messaging
# address.
# --inferred SENTENCE marks a `reports-to` or `cap` value the coordinator
# worked out rather than read from its brief, its dispatch link or a
# person's message (docs/designs/DESIGN-coordinator-standing-rule-provenance.md,
# Decision 5): the same write also adds a Standing `rule` row whose What is
# SENTENCE, the reading in one sentence, and whose Source is exactly
# `inferred`, with the next id as --standing rule takes one. The Run row and
# the rule row go in one state write, after the Run value's grammar and every
# check --standing rule makes on a rule row (below: one line of at most 400
# bytes, the 120-rule and 60-inferred caps, the forge reads), so a refusal
# of either writes neither (65, or 2 for a read that fails). Two entries
# follow it: the `run` entry, then the `rule` entry `s<n> (rule): SENTENCE.
# Source: inferred.` --inferred goes only with --run reports-to or --run cap,
# once, and not empty (64, before anything is read).
# Where those files live
# goes in record/host, through
# --host, never in the record's tables: KEY is rules:<label>, briefs:<label>
# or friction with an absolute path, or one of the import's facts,
# source_workspace (an absolute path), source_session (a coordinator session
# name) or template_hash (64 hex). --host merges into record/host and changes
# nothing else: it writes no table and posts no entry, since host facts never
# leave the host. A value with a control
# character or a token-shaped string is refused (65); a workspace path may be
# a home-directory path, which a row's field never is. It prints the record/host
# object.
#
# --run role sets the run's role, `manager` or `director`, once
# (docs/designs/DESIGN-coordinator-named-roles.md, Decision 1; PRD R5): with
# no row it writes one; with the same value it writes and prints nothing and
# exits 0; with a different value it is refused (65), naming the recorded role
# and the one asked for, and the row stays as it was. --intervention
# dispatcher|person is the one way it replaces a different value: a change
# from above, from the dispatching session or a person. The row then reads the
# new value, its Set by WHO and its Set the write's time, and the `run` entry
# names the old role, the new one and the source. With no row or the same
# value --intervention writes as a plain --run role does. --intervention on
# any other mode or Run key, or with any other source, is a usage error (64)
# made before anything is read. WHO, for --run role, is one line of at most 80
# characters (65 otherwise). With --intervention the write may come before the
# run's find has sealed the record (a carry the opener made, whose find hasn't
# run yet), the path --rule-files takes below; without it --run role needs a
# found record, as every other --run key does. The only other writer of the
# row is state-open.sh's seed. Readers read it through state-read.sh --run.
#
# --rule-files FILE writes the `rules` rows of the files the session loaded
# as rules, from rule-files.sh's list in FILE: one {label, path, digest}
# object per line, each label `skill-...` or `workspace-...` in the label
# grammar, each path absolute with no control character or token-shaped
# string, each digest 64 hex, and no label twice; any other list is refused
# (65) before anything is read or written. It replaces the Run `rules` rows
# whose labels carry either prefix with one `rules <label> sha256:<digest>`
# row per listed file, keeping a row whose digest didn't change as written,
# Set included, and every other `rules` row and every `briefs` row. It sets
# record/host's rules:<label> to each file's path and drops the rules: key of
# any `skill-` or `workspace-` label no longer listed. One `run` entry names
# each label added, changed (old and new digest) or removed, written only when
# a Run row changed; with nothing changed nothing is written or printed. The
# opener and state-open.sh run it, --by the run's session name, at every
# start that leaves the run holding a record; a person never writes these
# rows. Such a start may come before the run's find has sealed the record (a
# carry, or the seed record_open makes), so this mode needs the session to
# hold a record rather than a found one (the write core's START_WRITER and
# state-entry.sh --before-find).
#
# A discipline rotation keeps two keys of its own beside its tables (docs/designs/current/DESIGN-coordinator-record-teardown.md,
# Decision 3), and only this script writes them, with STATE_WRITER open:
# --rotation FILE writes record/rotation, the JSON object in FILE,
# {start, end, host_repo, predecessor}: start and end real dates, end not
# before start, host_repo this run's host, predecessor null (a first rotation)
# or the predecessor's session, coordinate-<slug>-<YYYYMMDDTHHMMSSZ> with this
# discipline's slug. --reasoning-file FILE writes record/reasoning, FILE's text
# as a JSON string: what this rotation leaves the next one, at most 16 KiB
# (16384 bytes) with no control character but a newline or a tab, and no
# token-shaped string or home-directory path (state-schema.jq's scan_strings,
# which also walks every string of a rotation). Writing it closes the rotation
# (the window rule reads a rotation holding it as ended). A value that breaks a
# rule, or a run that isn't a discipline rotation, is refused (65) before any
# key is written. Each prints the key's JSON as written. --reasoning-check exits 0
# when the rotation holds record/reasoning and 1 when it doesn't (the
# rotation_end state's gate).
#
# --standing records an event only a person owns that still binds the run:
# KIND is pause, go-ahead, approval, answer or assignment (or rule, below),
# OWNER is the person who decided
# it, and --relayed-by names who carried it here (leave it off when the owner
# told this coordinator directly). When a person says it in a comment on the
# record, or anywhere else, this is how it reaches the record: the reader
# never counts a comment without the entry marker. It gets the next id, s<n>.
# A pause takes --on, its scope (`all`, or one unit as pick lists it:
# `Feature 2`, `ED1`, `#12`, `owner/repo#12`), and --until, its resume
# condition (`lifted`, `time <YYYY-MM-DDTHH:MMZ>` in UTC, `merged
# owner/repo#n` or `tag owner/repo <tag>`); a go-ahead may take --on, the one
# unit it lets through a wider pause; the other kinds take neither. With a
# session whose pick facts (coord/pick.json) list units, --on must name one of
# them (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 1).
# An assignment is work a person assigned outside the scope: --on names it,
# an issue (`#12`, `owner/repo#12`) or `release owner/repo <tag>`, and pick
# lists it as a unit from then on (shirabe#607).
# --end removes a Standing row (a resume ends a pause; a go-ahead or approval
# ends when used; an answer when withdrawn; an assignment once its work is
# done; a rule once it no longer binds).
#
# A `rule` row is a rule that binds the coordinator until it is ended: no On,
# no Until, a blank Owner and Relayed by, and a Source saying where its words
# come from (state-schema.jq's source_problem lists the five forms; a stored
# event row may carry one too). A rule row holds nothing: pick, the dispatch
# check, the land check and the merge read pauses, go-aheads and assignments
# only, whatever a rule's What says.
# --standing rule writes one: its What one line of at most 400 bytes, and its
# --source in one of four forms, `skill <owner/repo> <path> <commit>` (a line
# of a skill's text), `doc <owner/repo> <path> <commit>` (a document a public
# host can name), `pinned <label> sha256:<64 hex>` (a file a Run `rules` or
# `briefs` row pins with that label and digest) or `inferred [brief <label>
# sha256:<64 hex>]` (the coordinator's own reading). --source goes only with
# --standing rule, and a rule takes no --on or --until (64); --owner or
# --relayed-by on one is refused (65), since its Source says who said it. A
# `decision <session> <id>` Source is refused (65): that form isn't written
# before koto's decision commands, so the row is written as inferred. The
# checks run in this order, each refusal 65 with nothing written: the usage
# (64); the Source's grammar and the row's columns; the What's 400 bytes; the
# caps, at most 120 rule rows, of which at most 60 read inferred (the inferred
# cap tested first for an inferred row; every rule row counts, and the event
# kinds count against neither, so a pause can always be written); a pinned
# Source's Run row; the decision form; then the forge reads, through gh, each
# under FORGE_READ_SECONDS (10). The host's visibility is read once, for every
# rule row, and the write core uses that answer. For a `skill` or `doc`
# Source naming repository R at commit C: on a public host, R's visibility
# (the host's own answer when R is the host), a repository that isn't public
# or answers 404 refused with the schema's message before any of its text is
# read; then repos/R/compare/C...HEAD, where identical or ahead means R's
# default branch holds C, and behind, diverged or a 404 give one refusal, the
# same for a repository that doesn't exist as for one that can't be read; then
# the file at C, a path missing there refused; and the What must equal one of
# the file's sentences under state-schema.jq's norm_match (file_sentences). On
# a public host each two-part owner/repo token in the What
# (state-schema.jq's what_repo_tokens), the host excepted, then gets one
# visibility read: one that isn't public is refused, and so is a 404 under
# the host's owner, while a 404 under any other owner passes, since it can't
# tell an absent repository from a hidden one. A private host reads no token.
# A read that fails with anything but a 404, runs past its bound or answers
# something that can't be parsed exits 2, naming what it couldn't read, and
# no later read is made. The checks run on the row being written only; a
# stored row is never checked again. Its entry, kind rule, reads `s<n> (rule):
# <What>. Source: <Source>.`
# --intake LABEL brings the brief record/host names as briefs:LABEL (an
# absolute path, written with --host) in as `inferred brief` rule rows
# (docs/designs/DESIGN-coordinator-standing-rule-provenance.md, Decision 10),
# the brief-unread gap's fix (state-handover.sh). LABEL is in the label
# grammar (64 otherwise, before anything is read). It reads the file once,
# never edits it, and never prints its path: no briefs:LABEL key, or one that
# isn't an absolute path, is refused (65); a file that isn't a readable
# regular file exits 2, naming the label. Its digest is the sha256 of its
# bytes, D below. A Run `briefs` row `LABEL D` means the brief was taken: it
# prints nothing, writes nothing and exits 0. Otherwise its lines are
# state-schema.jq's brief_candidates (file_sentences less the heading lines
# and the renderer's Goal, Checkpoints, Read first, Acceptance criteria,
# Reporting and Keep-alive sections, each once), and brief_intake_plan says
# what it does with them: each Standing row whose Source is `inferred brief
# LABEL <another digest>` and whose What matches none of the lines under
# norm_match ends, and each line no row left (of any kind or Source) holds
# under norm_match is written as a rule row, What the line, On, Until, Owner
# and Relayed by blank, Source `inferred brief LABEL D`, with the next ids.
# Each line is checked as --standing rule checks a What, and one that fails
# is left out, named on stderr (`left out: <reason>: <the line>`, cut to 200
# characters, a token or a home directory's name in it blanked), never
# written: over 400 bytes, a home-directory path or a token-shaped string,
# and on a public host a repository that isn't public (the host's
# visibility read once, then one read for each repository the lines name,
# the host excepted; a 404 is not public for a link or owner/repo#n, and
# for a bare owner/repo token only under the host's owner). A read that
# fails exits 2 with nothing written. The caps count the rows left once the
# ended rows go: it writes as many lines as the 60-inferred and 120-rule
# caps leave room for, in order. When every line is taken it also replaces
# LABEL's Run `briefs` row with `LABEL D`, Set by WHO, which clears the gap;
# when a cap stops it, the rows up to the cap are written, no `briefs` row
# is, and it exits 1, `took <k> of the brief's lines; <n> of its lines can't
# be taken under the caps: <the cap>` on stderr, so the gap stays open for a
# person to say which rows to confirm or end. The rows, the ended rows and
# the `briefs` row go in one state write. Its entries follow, in order: one
# rule entry per row written, `s<n> (rule): <What>. Source: inferred brief
# LABEL D.`; one end entry per row ended, as --end tells it; and, with the
# `briefs` row, the run entry `Run briefs LABEL D set by WHO.`
# --rules prints one JSON object per Standing row, in record order, with its
# class worked out from its Source (state-schema.jq's rule_view: standing,
# kind, class, what, owner, said, set, pointer, words, source, status,
# reversal, confirm); a relayed row's pointer names the entry its --standing
# wrote, read from the record's entries, or the row itself when no entry
# matches. A `decision` Source reads class and status `unreadable` until what
# koto recorded about the decision is read.
# Each object also carries under_session_grant and session_allows
# (state-schema.jq's rule_grants). A row grants nothing: the grant is the
# session's, and these two fields say whether the row stands under it and
# what it allows. A pause, an inferred, `pinned` or unreadable row, a row not
# in force and a row with a reversal never stand under it (the floor); a
# `skill` row citing any repository but the one the installed plugin's
# .claude-plugin/plugin.json names as `repository`
# (https://github.com/<owner>/<repo>), and a `doc` row citing any but the
# record's host, never do either (the anchor). Those rows print
# under_session_grant false and session_allows [] with no read. When at least
# one printed row passes both, --rules reads the coordinator session's grant
# once, `niwa authority check -C <instance root> --session
# <CLAUDE_CODE_SESSION_ID> --json` (rules_grant_read below says when it makes
# no read), and every such row prints under_session_grant true and
# session_allows the answer's grant, in niwa's order, when the read exits 0
# with a bound niwa.authority.check/v1 document whose grant and level are in
# niwa's vocabularies. Any other answer, or no read, gives every row
# under_session_grant false and session_allows [], and --rules still exits 0.
# A row's words never widen session_allows past the session's grant; no
# --point is asked, and no gate reads either field. With --id, only those rows, still
# in record order; an --id that isn't s<n> is a usage error (64), and one the
# record has no row for is refused (65, naming it) before anything is
# printed. A record that breaks a rule of state-schema.jq is refused (65), the
# rule on stderr naming the row (`standing.s3: ...`). After the Standing
# objects, and only without --id, it prints one object per Run `rules` row in
# record order (state-schema.jq's run_rule_view), {run: "rules", kind, label,
# digest, class, said, pointer}: kind `skill` or `workspace` for a label with
# that prefix (the rows --rule-files writes), `other` for any other label;
# digest the row's sha256:<64 hex>; class `skill-says` for a `skill-` label,
# `charter` for a `workspace-` label, `inferred` for any other; said the
# row's Set; and pointer {label, digest, host}, host `rules:<label>`, the
# record/host key naming the file, which isn't read. A Run object carries no
# status, confirm or grant field and never takes part in the authority read:
# its class is for reading only. --rules reads; it writes no key and tells no
# entry.
# --rules --counts prints seven lines instead, one per class in a fixed order
# (state-schema.jq's rule_classes: relayed, owner-said, dispatcher-said,
# inferred, skill-says, charter, unreadable), each `<class> <count>`, a class
# no row reads printed with 0. It counts every Standing row by the class
# --rules gives it, whatever the row's status, so `grep '^inferred '` gives
# the unsourced rules the record holds. It counts each Run `rules` row too, in
# the class --rules gives its object, so the lines add up to the Standing rows
# plus the Run `rules` rows. It reads the record's Standing and Run sections
# and no entry. --counts takes no --id (64).
#
# --work writes the next step for ITEM: with --kind holding, ITEM is a
# holding's Unit and W its Worker, and the holding's first row also records W
# as told the current address, since its dispatch brief named it (a later
# update doesn't); with --kind local-agent, ITEM is
# the work and W who does it. With --kind decision, ITEM is a unit pick parked
# on a decision for a person (pick's await_decision) and W is `decision <n>`,
# an unsettled entry in the Decisions section; with --kind follow-up, ITEM is
# a unit whose scoping alone landed (pick's scope route) and W the pull
# request that landed it, `owner/repo#n`, NEXT naming its execution. With a
# session whose pick facts list units, ITEM must be one of them for either
# kind. Such a row keeps the unit's later work in the record until a holding
# takes it: a holding's --work for ITEM removes ITEM's decision and follow-up
# rows, unless that holding is at Phase scoping (the one whose merge wrote the
# follow-up). An ITEM has at most one row per kind. --done removes ITEM's rows, or
# only its --kind K row. Every write also drops a holding row whose holding
# is gone, so a teardown leaves no orphan. A verdict-owed row (a milestone
# whose verdict is owed, docs/designs/DESIGN-milestone-verdicts.md) is listed
# and kept by every write here, but only roadmap-status.sh writes or removes
# it: --work refuses its kind, and --done leaves it. A rework row (a
# milestone a confirmed changes-needed verdict or reopen sent back) is
# written only by
# roadmap-status.sh --confirm, so --work refuses its kind too; --done
# --kind rework removes it, which dispatch-worker.sh does once a worker is
# dispatched for the milestone.
#
# A holding's row carries its Wakes: at each --work write, this run's wakes
# for the holding (coord-log.sh wakes: its worker's topic, and its leg's
# request) logged after the end of the minute in the row's Updated cell are
# added to the count; a new row counts this run's wakes from its start. When
# a holding's row leaves Work (--done, or dropped once its holding is gone),
# its final count, with the wakes since its last write, is appended as an
# entry. The count is a floor: a wake inside the minute after a write, or
# one a crashed run logged after its last write, isn't counted, and a holding
# torn down before its row leaves takes its leg's wakes with it. A row removed
# and written again in the same run counts that run's wakes again. A leg's
# request is one per holding (dispatch-worker.sh opens one per topic), so a
# leg wake is never credited to two holdings. Without a
# session (the override flags) nothing is added
# (docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 4).
#
# Each change is written to the state first, through the record's write core
# (state-write-core.sh), with the minute and who, and then told as an entry
# with state-entry.sh, kind run, told, pending, the standing kind, end or
# work. The section keys are the state; the entry is its account.
#
# Exit codes: 0 written (prints the record's URL, then the entry's) or
# printed; 1 an --intake the caps stopped (its rows written, no `briefs`
# row); 2 a read failed (the record, the entries the next Standing id
# is chosen from, or a rule row's forge read); 10 refused: here, no found record or, for a write, a record
# that doesn't read back as this scope's, and from the write core, not an open record,
# provenance or a directed transition; 11 and 12 (the record changed between
# this script's read and its write) from the write core; 14
# the state was written but the entry wasn't posted (post it with
# state-entry.sh; the change it names is on stderr); 64 usage; 65 refused
# (the reason on stderr; for --rules, a row that breaks a rule, named, or an
# --id the record has no row for), and for --list a record the schema
# refuses (a row this plugin doesn't know, as a newer plugin's looks),
# nothing on stdout.
#
# The record is read through state-read.sh and written only in the write
# core it sources, and the entry through state-entry.sh.
set -uo pipefail

PROG=state-stored-set
HERE=$(cd "$(dirname "$0")" && pwd)
SESSION= SCOPE= NAME= REPO= MODE=
KEY= VALUE= BY= WHO= KIND= WHAT= OWNER= RELAYED= ID= ITEM= NEXT= ON= UNTIL= RFILE=
# --intake's brief label.
ILABEL=
# --intervention's source, and whether it was given.
INTERVENTION= HAS_INTERVENTION=0
# --source's form, and whether it was given.
SOURCE= HAS_SOURCE=0
# --inferred's sentence, and whether it was given.
INFERRED= HAS_INFERRED=0
# --rules' --id values, one per line.
RIDS=
COUNTS=0
SKIP_CHECKS=0
# --host pairs, one `key<TAB>value` line each.
HOSTKV=

usage() { sed -n '/^# Usage:/,/^# The session gives/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
setmode() { [ -z "$MODE" ] || usage; MODE=$1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --scope) [ $# -ge 2 ] || usage; SCOPE=$2; shift 2 ;;
        --name) [ $# -ge 2 ] || usage; NAME=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        --run) [ $# -ge 3 ] || usage; setmode run; KEY=$2; VALUE=$3; shift 3 ;;
        --host) [ $# -ge 3 ] || usage; [ "$MODE" = host ] || setmode host
                case "$2$3" in *$'\t'*|*$'\n'*) echo "$PROG: refused: a --host key or value holds a tab or a newline" >&2; exit 65 ;; esac
                HOSTKV="$HOSTKV$2"$'\t'"$3"$'\n'; shift 3 ;;
        --rotation) [ $# -ge 2 ] || usage; setmode rotation; RFILE=$2; shift 2 ;;
        --rule-files) [ $# -ge 2 ] || usage; setmode rule-files; RFILE=$2; shift 2 ;;
        --reasoning-file) [ $# -ge 2 ] || usage; setmode reasoning; RFILE=$2; shift 2 ;;
        --reasoning-check) setmode reasoning-check; shift ;;
        --told) [ $# -ge 2 ] || usage; setmode told; WHO=$2; shift 2 ;;
        --pending) [ $# -ge 2 ] || usage; setmode pending; WHO=$2; shift 2 ;;
        --standing) [ $# -ge 2 ] || usage; setmode standing; KIND=$2; shift 2 ;;
        --end) [ $# -ge 2 ] || usage; setmode end; ID=$2; shift 2 ;;
        --intake) [ $# -ge 2 ] || usage; setmode intake; ILABEL=$2; shift 2 ;;
        --work) [ $# -ge 2 ] || usage; setmode work; ITEM=$2; shift 2 ;;
        --done) [ $# -ge 2 ] || usage; setmode done; ITEM=$2; shift 2 ;;
        --list) setmode list; shift ;;
        --rules) setmode rules; shift ;;
        --counts) COUNTS=1; shift ;;
        --id) [ $# -ge 2 ] || usage; RIDS="$RIDS$2"$'\n'; shift 2 ;;
        --by) [ $# -ge 2 ] || usage; BY=$2; shift 2 ;;
        --intervention) [ $# -ge 2 ] && [ "$HAS_INTERVENTION" = 0 ] || usage; HAS_INTERVENTION=1; INTERVENTION=$2; shift 2 ;;
        --what) [ $# -ge 2 ] || usage; WHAT=$2; shift 2 ;;
        --source) [ $# -ge 2 ] && [ "$HAS_SOURCE" = 0 ] || usage; HAS_SOURCE=1; SOURCE=$2; shift 2 ;;
        --inferred) [ $# -ge 2 ] && [ "$HAS_INFERRED" = 0 ] || usage; HAS_INFERRED=1; INFERRED=$2; shift 2 ;;
        --owner) [ $# -ge 2 ] || usage; OWNER=$2; shift 2 ;;
        --relayed-by) [ $# -ge 2 ] || usage; RELAYED=$2; shift 2 ;;
        --on) [ $# -ge 2 ] || usage; ON=$2; shift 2 ;;
        --until) [ $# -ge 2 ] || usage; UNTIL=$2; shift 2 ;;
        --kind) [ $# -ge 2 ] || usage; KIND=$2; shift 2 ;;
        --who) [ $# -ge 2 ] || usage; WHO=$2; shift 2 ;;
        --next) [ $# -ge 2 ] || usage; NEXT=$2; shift 2 ;;
        --skip-session-checks) SKIP_CHECKS=1; shift ;;
        *) usage ;;
    esac
done
case "$MODE" in
    run) [ "$KEY" != store ] || { echo "$PROG: refused: run.key: store is not a Run key this script sets; the record's store is always the coordinator's session" >&2; exit 65; }
         [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage
         case "$KEY" in arguments|cap|coordinator|rules|briefs|friction|reports-to|role) ;;
             *) echo "$PROG: --run takes arguments, cap, coordinator, rules, briefs, friction, reports-to or role" >&2; exit 64 ;; esac ;;
    host) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    rule-files) [ -n "$BY" ] && [ -r "$RFILE" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    rotation|reasoning) [ -r "$RFILE" ] && [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    reasoning-check) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    told|pending) [ -n "$BY" ] && [ -z "$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    standing) [ -n "$WHAT" ] && { [ -n "$OWNER" ] || [ "$KIND" = rule ]; } && [ -z "$BY$WHO$NEXT" ] || usage ;;
    end) [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    intake) [ -n "$BY" ] && [ -z "$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage
            [[ $ILABEL =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
                || { echo "$PROG: --intake takes a brief's label: letters, digits, \`.\`, \`_\` and \`-\`, starting with a letter or a digit" >&2; exit 64; } ;;
    work) [ -n "$KIND" ] && [ -n "$WHO" ] && [ -n "$NEXT" ] && [ -z "$BY$WHAT$OWNER$RELAYED$ON$UNTIL" ] || usage ;;
    done) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$ON$UNTIL" ] || usage ;;
    list) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage ;;
    rules) [ -z "$BY$WHO$WHAT$OWNER$RELAYED$NEXT$KIND$ON$UNTIL" ] || usage
           while IFS= read -r RID; do
               [ -z "$RID" ] || [[ $RID =~ ^s[1-9][0-9]*$ ]] || { echo "$PROG: --id takes a Standing id, s<n>" >&2; exit 64; }
           done <<EOF
$RIDS
EOF
           ;;
    *) usage ;;
esac
[ -z "$RIDS" ] || [ "$MODE" = rules ] || usage
# --intervention goes only with --run role, and names where the change comes
# from: the dispatching session or a person.
if [ "$HAS_INTERVENTION" = 1 ]; then
    { [ "$MODE" = run ] && [ "$KEY" = role ]; } || { echo "$PROG: --intervention goes only with --run role" >&2; exit 64; }
    case "$INTERVENTION" in dispatcher|person) ;; *) echo "$PROG: --intervention takes dispatcher or person" >&2; exit 64 ;; esac
fi
# --source goes only with --standing rule, which needs one and takes no --on
# or --until; an event row's Source is a citation, which isn't written here.
if [ "$HAS_SOURCE" = 1 ] && { [ "$MODE" != standing ] || [ "$KIND" != rule ]; }; then
    echo "$PROG: --source goes only with --standing rule" >&2; exit 64
fi
# --inferred goes only with --run reports-to or --run cap, a value the
# coordinator worked out, and carries the reading's sentence.
if [ "$HAS_INFERRED" = 1 ]; then
    { [ "$MODE" = run ] && { [ "$KEY" = reports-to ] || [ "$KEY" = cap ]; }; } \
        || { echo "$PROG: --inferred goes only with --run reports-to or --run cap" >&2; exit 64; }
    [ -n "$INFERRED" ] || { echo "$PROG: --inferred takes the reading's sentence" >&2; exit 64; }
fi
if [ "$MODE" = standing ] && [ "$KIND" = rule ]; then
    [ -n "$SOURCE" ] || { echo "$PROG: a rule takes --source" >&2; exit 64; }
    [ -z "$ON$UNTIL" ] || { echo "$PROG: only a pause, a go-ahead or an assignment takes --on, and only a pause --until" >&2; exit 64; }
fi
# The role and who set it, checked before anything is read: the value one of
# the two roles, and WHO one line of at most 80 characters.
if [ "$MODE" = run ] && [ "$KEY" = role ]; then
    case "$VALUE" in
        manager|director) ;;
        *) SHOWN=$(tr -d '[:cntrl:]`' <<<"$VALUE")
           echo "$PROG: refused: run.value: a role is manager or director, not ${SHOWN:0:80}" >&2; exit 65 ;;
    esac
    case "$BY" in *[[:cntrl:]]*) echo "$PROG: refused: --by for --run role is one line, with no line break or control character" >&2; exit 65 ;; esac
    [ "$(jq -rn --arg b "$BY" '$b | length')" -le 80 ] || { echo "$PROG: refused: --by for --run role is at most 80 characters" >&2; exit 65; }
fi
[ "$COUNTS" = 0 ] || { [ "$MODE" = rules ] && [ -z "$RIDS" ]; } || usage
. "$HERE/state-common.sh"
lib_facts
TOKEN_RE='(^|[^A-Za-z0-9_-])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})'
TAB=$'\t'
# host_check <key> <value> [<what>]: one record/host fact, checked as --host
# checks it: a label in the grammar and an absolute path, a session name or
# 64 hex, as the key takes, with no control character or token-shaped string.
# Exits 65 on a value that breaks a rule, naming <what> (--host <key> when not
# given), and 64 on a key record/host doesn't keep.
host_check() {
    local HK=$1 HV=$2 HW=${3:-"--host $1"}
    case "$HK" in
        source_workspace|friction|rules:*|briefs:*)
            case "$HK" in rules:*|briefs:*) [[ ${HK#*:} =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "$PROG: refused: $HW: the label is letters, digits, \`.\`, \`_\` and \`-\`" >&2; exit 65; } ;; esac
            case "$HV" in /*) ;; *) echo "$PROG: refused: $HW takes an absolute path" >&2; exit 65 ;; esac ;;
        source_session) [[ $HV =~ ^coordinate-[a-z0-9-]+-[0-9]{8}T[0-9]{6}Z$ ]] || { echo "$PROG: refused: --host source_session takes a coordinator session name, coordinate-<slug>-<stamp>" >&2; exit 65; } ;;
        template_hash) [[ $HV =~ ^[0-9a-f]{64}$ ]] || { echo "$PROG: refused: --host template_hash takes 64 hex" >&2; exit 65; } ;;
        *) echo "$PROG: --host takes source_workspace, source_session, template_hash, rules:<label>, briefs:<label> or friction" >&2; exit 64 ;;
    esac
    if LC_ALL=C grep -q '[[:cntrl:]]' <<<"$HV"; then echo "$PROG: refused: $HW: a control character" >&2; exit 65; fi
    if grep -Eq "$TOKEN_RE" <<< "$HV"; then echo "$PROG: refused: $HW: a token-shaped string" >&2; exit 65; fi
}
if [ "$MODE" = host ]; then
    # Each key and value checked, then merged into the current record/host.
    while IFS="$TAB" read -r HK HV; do
        [ -n "$HK" ] || continue
        host_check "$HK" "$HV"
    done <<EOF
$HOSTKV
EOF
    WD=$(mktemp -d "${TMPDIR:-/tmp}/state-stored-set.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$WD"' EXIT
    rs_host "${RS_SESSION:-$SESSION}" "$WD/host" || lib_die2 "cannot read record/host: $(lib_scrub < "$WD/host.err")"
    printf '%s' "$HOSTKV" | jq -R -s --slurpfile cur "$WD/host" \
        '$cur[0] + (split("\n") | map(select(. != "") | split("\t") | {(.[0]): (.[1:] | join("\t"))}) | add // {})' \
        > "$WD/host.next" || lib_die2 "jq failed"
    lib_write_guard
    . "$HERE/state-write-core.sh"
    core_write_host "$WD/host.next"
    jq -c . "$WD/host.next"
    exit 0
fi
# A discipline rotation's own keys: its window and its
# reasoning for the next rotation. Every rule is checked before any key is
# written.
if [ "$MODE" = rotation ] || [ "$MODE" = reasoning ] || [ "$MODE" = reasoning-check ]; then
    [ "$SCOPE" = discipline ] || { echo "$PROG: refused: record/rotation and record/reasoning are kept only by a discipline rotation" >&2; exit 65; }
    WD=$(mktemp -d "${TMPDIR:-/tmp}/state-stored-set.XXXXXX") || lib_die2 "cannot make a temporary directory"
    trap 'rm -rf "$WD"' EXIT
    RS=${RS_SESSION:-$SESSION}
    if [ "$MODE" = reasoning-check ]; then
        rs_reasoning "$RS" "$WD/reasoning"
        case $? in 0) exit 0 ;; 1) echo "$PROG: the rotation holds no record/reasoning yet" >&2; exit 1 ;; *) lib_die2 "cannot read record/reasoning" ;; esac
    fi
    if [ "$MODE" = rotation ]; then
        SLUG=$(bash "$HERE/coord-log.sh" slug --scope "$SCOPE" --name "$NAME") || lib_die2 "cannot derive the scope's slug"
        jq -e 'type == "object"' "$RFILE" > /dev/null 2>&1 || { echo "$PROG: refused: the rotation is not a JSON object" >&2; exit 65; }
        EXTRA=$(jq -r '[keys[] | select(IN("start", "end", "host_repo", "predecessor") | not)] | first // ""' "$RFILE")
        [ -z "$EXTRA" ] || { echo "$PROG: refused: rotation.$EXTRA is not a field of a rotation (start, end, host_repo, predecessor)" >&2; exit 65; }
        for f in start end host_repo; do
            jq -e --arg f "$f" '(.[$f] | type) == "string" and .[$f] != ""' "$RFILE" > /dev/null \
                || { echo "$PROG: refused: rotation.$f is missing" >&2; exit 65; }
        done
        R_START=$(jq -r .start "$RFILE") R_END=$(jq -r .end "$RFILE") R_HOST=$(jq -r .host_repo "$RFILE")
        lib_valid_date "$R_START" || { echo "$PROG: refused: rotation.start is not a YYYY-MM-DD date" >&2; exit 65; }
        lib_valid_date "$R_END" || { echo "$PROG: refused: rotation.end is not a YYYY-MM-DD date" >&2; exit 65; }
        [ "$R_END" \< "$R_START" ] && { echo "$PROG: refused: rotation.end $R_END is before its start $R_START" >&2; exit 65; }
        [ "$(printf '%s' "$R_HOST" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$REPO" | tr 'A-Z' 'a-z')" ] \
            || { echo "$PROG: refused: rotation.host_repo $R_HOST is not this run's host, $REPO" >&2; exit 65; }
        if ! jq -e '.predecessor == null' "$RFILE" > /dev/null; then
            R_PRED=$(jq -r '.predecessor | if type == "string" then . else "" end' "$RFILE")
            [[ $R_PRED =~ ^coordinate-${SLUG}-[0-9]{8}T[0-9]{6}Z$ ]] \
                || { echo "$PROG: refused: rotation.predecessor is not a session of this discipline, coordinate-$SLUG-<YYYYMMDDTHHMMSSZ>" >&2; exit 65; }
        fi
        jq -c '{start, end, host_repo, predecessor: (.predecessor // null)}' "$RFILE" > "$WD/value.json" || lib_die2 "jq failed"
        KEYNAME=record/rotation
    else
        # 16 KiB: the reasoning is prose a person reads in every carry report.
        RSIZE=$(wc -c < "$RFILE" | tr -d ' ')
        [ "$RSIZE" -le 16384 ] || { echo "$PROG: refused: the reasoning is $RSIZE bytes, over the 16384-byte (16 KiB) limit" >&2; exit 65; }
        [ -n "$(tr -d ' \t\n\r' < "$RFILE")" ] || { echo "$PROG: refused: the reasoning is empty" >&2; exit 65; }
        LC_ALL=C tr -d '\n\t' < "$RFILE" > "$WD/flat" || lib_die2 "cannot read the reasoning"
        if LC_ALL=C grep -q '[[:cntrl:]]' "$WD/flat"; then
            echo "$PROG: refused: the reasoning holds a control character" >&2; exit 65
        fi
        TOKEN_RE='(^|[^A-Za-z0-9_-])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})'
        if grep -Eq "$TOKEN_RE" "$RFILE"; then echo "$PROG: refused: the reasoning holds a token-shaped string" >&2; exit 65; fi
        jq -R -s -c . "$RFILE" > "$WD/value.json" || lib_die2 "jq failed"
        KEYNAME=record/reasoning
    fi
    # Every string the key holds, through the state's own scan.
    if ! jq -L "$HERE" 'include "state-schema"; scan_strings([]) | empty' "$WD/value.json" 2> "$WD/scan.err"; then
        grep -q 'refused: ' "$WD/scan.err" || lib_die2 "state-schema.jq failed: $(lib_scrub < "$WD/scan.err")"
        echo "$PROG: refused: ${KEYNAME#record/}: $(sed -n 's/.*refused: //p' "$WD/scan.err" | head -1 | lib_scrub)" >&2; exit 65
    fi
    lib_write_guard
    . "$HERE/state-write-core.sh"
    STATE_WRITER=1
    core_write_rotation "$KEYNAME" "$WD/value.json"
    cat "$WD/value.json"
    exit 0
fi
# The rule files' list, every entry checked before anything is read: each a
# {label, path, digest} of strings with no control character, the label
# skill- or workspace-, the path one record/host keeps for that label
# (host_check), the digest 64 hex, and no label twice.
if [ "$MODE" = rule-files ]; then
    rf_refuse() { echo "$PROG: refused: --rule-files: $*" >&2; exit 65; }
    jq -s -e 'all(.[]; type == "object" and (keys == ["digest", "label", "path"]) and all(.[]; type == "string"))' "$RFILE" > /dev/null 2>&1 \
        || rf_refuse "the list isn't rule-files.sh's, one {label, path, digest} object of strings per line"
    jq -s -e 'any(.[][]; test("[\u0000-\u001f\u007f]"))' "$RFILE" > /dev/null \
        && rf_refuse "an entry holds a control character"
    jq -s -e 'any(.[][]; . == "")' "$RFILE" > /dev/null \
        && rf_refuse "an entry's label, path or digest is empty"
    jq -s -e '(map(.label) | unique | length) == length' "$RFILE" > /dev/null \
        || rf_refuse "a label is listed twice: $(jq -s -r 'group_by(.label) | map(select(length > 1) | .[0].label) | join(", ")' "$RFILE")"
    while IFS=$'\037' read -r RL RP RD; do
        [ -n "$RL$RP$RD" ] || continue
        case "$RL" in skill-*|workspace-*) ;; *) rf_refuse "$RL is neither a skill- nor a workspace- label" ;; esac
        [[ $RD =~ ^[0-9a-f]{64}$ ]] || rf_refuse "$RL's digest isn't 64 hex"
        host_check "rules:$RL" "$RP" "--rule-files $RL"
    done <<EOF
$(jq -s -r '.[] | [.label, .path, .digest] | join("\u001f")' "$RFILE")
EOF
elif [ "$HAS_INTERVENTION" = 0 ]; then
    # A role change from above (--intervention) may come before the run's
    # find, as the rule files' write does; the write core still needs the
    # session to hold a record (START_WRITER below). Every other write needs
    # a found one.
    lib_run_found || { echo "$PROG: refused: the run has no found record" >&2; exit 10; }
fi

WD=$(mktemp -d "${TMPDIR:-/tmp}/state-stored-set.XXXXXX") || lib_die2 "cannot make a temporary directory"
trap 'rm -rf "$WD"' EXIT

# --list prints the stored set alone, so it reads those three sections; a
# write reads the whole record it writes back (shirabe#1315).
FIELDS=
[ "$MODE" = list ] && FIELDS="run standing work"
[ "$MODE" = rules ] && FIELDS="standing"
# Without --id, --rules also lists the Run section's rules rows, and --counts
# counts them.
[ "$MODE" = rules ] && [ -z "$RIDS" ] && FIELDS="standing run"
rs_record "$WD/parsed.json" "$FIELDS"
RC=$?
# --rules is a read of the rows themselves, so a row that breaks a rule is
# its refusal, naming the row, not a record that isn't there.
if [ "$RC" = 65 ] && [ "$MODE" = rules ]; then
    echo "$PROG: refused: $(lib_scrub < "$WD/parsed.json.err" | head -3)" >&2; exit 65
fi
case $RC in
    0) ;;
    65) echo "$PROG: refused: $(lib_record_name) doesn't read back as a $SCOPE record for $NAME:" >&2; lib_scrub < "$WD/parsed.json.err" >&2; echo >&2
        # --list passes the schema's refusal on as 65, so a reader (the
        # opener's takeover above all) tells a record it can't read from a
        # missing one (10); a write refuses it as no record to write, 10.
        [ "$MODE" = list ] && exit 65
        exit 10 ;;
    4) lib_scrub < "$WD/parsed.json.err" >&2; exit 10 ;;
    12) lib_scrub < "$WD/parsed.json.err" >&2; exit 12 ;;
    *) lib_die2 "cannot read the record: $(lib_scrub < "$WD/parsed.json.err" | head -1)" ;;
esac

if [ "$MODE" = list ]; then
    jq -c -L "$HERE" 'include "state-schema"; state_list' "$WD/parsed.json"
    exit 0
fi
# rules_grant_read <out>: niwa's answer about this coordinator session's grant
# into <out>, as posture-read.sh finds and bounds niwa. Returns non-zero, with
# no read made, when niwa isn't found (on PATH, else an executable $NIWA_BIN),
# CLAUDE_CODE_SESSION_ID isn't a session id, no directory at or above this one
# holds .niwa/instance.json, or record/meta names a driver other than this
# session (or one that isn't a string); and non-zero when the read exits
# non-zero or runs past NIWA_LOOKUP_SECONDS (3).
rules_grant_read() {
    local niwa sid d root= drv
    niwa=$(command -v niwa 2> /dev/null)
    if [ -z "$niwa" ]; then
        [ -n "${NIWA_BIN:-}" ] && [ -f "$NIWA_BIN" ] && [ -x "$NIWA_BIN" ] || return 1
        niwa=$NIWA_BIN
    fi
    sid=${CLAUDE_CODE_SESSION_ID:-}
    [[ $sid =~ ^[0-9a-f][0-9a-f-]{7,63}$ ]] || return 1
    d=$(pwd -P) || return 1
    while :; do
        if [ -f "$d/.niwa/instance.json" ]; then root=$d; break; fi
        [ "$d" = / ] && break
        d=$(dirname "$d")
    done
    [ -n "$root" ] && root=$(cd "$root" 2> /dev/null && pwd -P) && [ -n "$root" ] || return 1
    drv=$(jq -r 'if (.driver // "") == "" then "" elif (.driver | type) == "string" then .driver else error("driver") end' \
        "$WD/parsed.json.meta" 2> /dev/null) || return 1
    [ -z "$drv" ] || [ "$drv" = "$sid" ] || return 1
    # shellcheck source=dispatch-common.sh
    . "$HERE/dispatch-common.sh" || return 1
    dc_with_deadline "${NIWA_LOOKUP_SECONDS:-3}" dc_tree "$niwa" authority check -C "$root" --session "$sid" --json \
        < /dev/null > "$1" 2> /dev/null
}
if [ "$MODE" = rules ] && [ "$COUNTS" = 1 ]; then
    jq -r -L "$HERE" 'include "state-schema"; record_rule_counts' "$WD/parsed.json" || lib_die2 "jq failed"
    exit 0
fi
if [ "$MODE" = rules ]; then
    printf '%s' "$RIDS" | jq -R -s -c 'split("\n") | map(select(. != "")) | unique' > "$WD/ids.json" || lib_die2 "jq failed"
    MISSING=$(jq -r --slurpfile ids "$WD/ids.json" '[(.standing // [])[] | .standing] as $have
        | [$ids[0][] | select(. as $i | $have | index($i) | not)] | join(", ")' "$WD/parsed.json") || lib_die2 "jq failed"
    [ -z "$MISSING" ] || { echo "$PROG: refused: no Standing row $MISSING" >&2; exit 65; }
    # A relayed row points at the entry its --standing wrote, so the entries
    # are read only when the record holds such a row.
    echo '[]' > "$WD/entries.json"
    if jq -e 'any((.standing // [])[]; (.source // "") == "")' "$WD/parsed.json" > /dev/null; then
        if [ "$OVERRIDE" = 1 ]; then
            bash "$HERE/state-entry.sh" --scope "$SCOPE" --name "$NAME" --repo "$REPO" --list > "$WD/entries.json" 2> "$WD/list.err"
        else
            bash "$HERE/state-entry.sh" --session "$SESSION" --list > "$WD/entries.json" 2> "$WD/list.err"
        fi || lib_die2 "cannot read the record's entries: $(lib_scrub < "$WD/list.err")"
    fi
    jq -c -L "$HERE" --arg s "${RS_SESSION:-$SESSION}" --slurpfile e "$WD/entries.json" --slurpfile ids "$WD/ids.json" 'include "state-schema";
        (.standing // [])[] | select(($ids[0] | length) == 0 or (.standing as $i | $ids[0] | index($i)) != null)
        | rule_view($s; $e[0])' "$WD/parsed.json" > "$WD/views.json" || lib_die2 "jq failed"
    # The anchor's two repositories: the one the installed plugin's manifest
    # names as its source, and the record's host.
    PLUGIN_REPO=$(jq -r '.repository // "" | if type == "string" then . else "" end' \
        "$(cd "$HERE/../../.." && pwd -P)/.claude-plugin/plugin.json" 2> /dev/null)
    RE_MANIFEST_REPO='^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$'
    if [[ $PLUGIN_REPO =~ $RE_MANIFEST_REPO ]]; then PLUGIN_REPO=${BASH_REMATCH[1]}; else PLUGIN_REPO=; fi
    jq -n --arg p "$PLUGIN_REPO" --arg h "$REPO" \
        '{plugin_repo: (if $p == "" then null else $p end), host_repo: $h, answer: null}' > "$WD/facts.json" || lib_die2 "jq failed"
    # The authority read, made at most once, and only when a printed row
    # passes the floor and the anchor. Any failure leaves the answer null.
    echo null > "$WD/answer.json"
    if jq -e -s -L "$HERE" --slurpfile f "$WD/facts.json" 'include "state-schema"; any(.[]; rule_passes($f[0]))' \
            "$WD/views.json" > /dev/null 2>&1 \
        && rules_grant_read "$WD/check.json"; then
        jq -c -s 'if length == 1 then .[0] else null end' "$WD/check.json" > "$WD/answer.json" 2> /dev/null \
            || echo null > "$WD/answer.json"
    fi
    jq -c -L "$HERE" --slurpfile f "$WD/facts.json" --slurpfile a "$WD/answer.json" 'include "state-schema";
        . + rule_grants($f[0] + {answer: $a[0]})' "$WD/views.json" || lib_die2 "jq failed"
    # The Run rules rows' objects are printed after the grant read and never
    # join $WD/views.json, so none of them can trigger it or stand under it.
    if [ -z "$RIDS" ]; then
        jq -c -L "$HERE" 'include "state-schema"; (.run // [])[] | select(.key == "rules") | run_rule_view' "$WD/parsed.json" \
            || lib_die2 "jq failed"
    fi
    exit 0
fi

NOW=$(date -u +%Y-%m-%dT%H:%MZ)
# wakes_since <topic> <return-path> <updated-or-empty>: this run's wakes for a
# holding after the end of the Updated minute (all of this run's when empty).
wakes_since() {
    [ "$OVERRIDE" = 1 ] && { echo 0; return 0; }
    local cut= w req
    if [ -n "$3" ]; then
        # Updated is always YYYY-MM-DDTHH:MMZ (state-schema.jq's grammar).
        cut=$(jq -rn --arg u "$3" '$u | strptime("%Y-%m-%dT%H:%MZ") | mktime + 60 | todate') || { echo "$PROG: jq failed" >&2; return 2; }
    fi
    w=$(bash "$HERE/coord-log.sh" wakes --session "$SESSION" ${cut:+--after-time "$cut"}) || { echo "$PROG: cannot read the run's wakes" >&2; return 2; }
    req=${2#leg }; req=${req%%:*}
    case "$2" in "leg "*) ;; *) req= ;; esac
    printf '%s' "$w" | jq -r --arg t "$1" --arg r "$req" '(.[$t] // 0) + (if $r == "" then 0 else (.["leg " + $r] // 0) end)'
}
# How state-entry.sh addresses this record.
if [ "$OVERRIDE" = 1 ]; then
    ADDR_ARGS=(--scope "$SCOPE" --name "$NAME" --repo "$REPO")
else
    ADDR_ARGS=(--session "$SESSION")
fi
P="$WD/parsed.json"
refuse() { echo "$PROG: refused: $*" >&2; exit 65; }

# ---- a rule row's checks (--standing rule) ----------------------------------
# What they read, handed to the write core: the host's visibility
# (CORE_HOST_PRIVATE), so the core reads it no second time, and on a public
# host the repositories the row names that aren't public (CORE_NOT_PUBLIC,
# comma separated), which the schema then refuses with its own message.
RULE_HOST_PRIVATE= RULE_NOT_PUBLIC=
# forge_read <out> <api path> [<gh api args>...]: one GET through gh, under
# FORGE_READ_SECONDS (10). Returns 0 read, 1 a 404, 2 any other failure or
# the bound passing.
forge_read() {
    local out=$1 rc
    shift
    dc_with_deadline "${FORGE_READ_SECONDS:-10}" dc_tree gh api --method GET "$@" < /dev/null > "$out" 2> "$out.err"
    rc=$?
    [ "$rc" = 0 ] && return 0
    [ "$rc" != 124 ] && grep -q 'HTTP 404' "$out.err" && return 1
    return 2
}
# rule_visibility <owner/repo>: VIS is true, false or 404 for it; any other
# failure, or an answer that is neither true nor false, exits 2.
rule_visibility() {
    forge_read "$WD/vis" "repos/$1" --jq .private
    case $? in
        0) VIS=$(cat "$WD/vis") ;;
        1) VIS=404; return 0 ;;
        *) lib_die2 "cannot read $1's visibility" ;;
    esac
    case "$VIS" in true|false) ;; *) lib_die2 "cannot read $1's visibility" ;; esac
}
rule_lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# rule_not_public <owner/repo>: put it on the list handed to the core.
rule_not_public() {
    case ",$(rule_lc "$RULE_NOT_PUBLIC")," in *",$(rule_lc "$1"),"*) return 0 ;; esac
    RULE_NOT_PUBLIC="$RULE_NOT_PUBLIC${RULE_NOT_PUBLIC:+,}$1"
}
# rule_checks: the new row ($SID, in $WD/next.json, the record read in $P),
# checked in this order, each refusal 65 and nothing written: the Standing
# section against the schema with no visibility read (the Source's grammar, a
# blank Owner and Relayed by, a line break); the What's 400 bytes; the caps;
# a pinned Source's Run row; the decision form; then the forge reads, the
# host's visibility, and for a `skill` or `doc` Source its repository's
# visibility on a public host, the ancestry and the file, and on a public
# host the What's two-part tokens. A read that fails exits 2, with no later
# read.
rule_checks() {
    local n why form r path c st tok
    if ! jq -L "$HERE" 'include "state-schema";
            (state_secs[] | select(.key == "standing")) as $sec
            | (check_state($sec; .standing; []) | empty), (.standing | scan_strings([]) | empty)' \
            "$WD/next.json" 2> "$WD/rule.err" < /dev/null; then
        grep -q 'refused: ' "$WD/rule.err" || lib_die2 "state-schema.jq failed: $(lib_scrub < "$WD/rule.err")"
        refuse "$(sed -n 's/.*refused: //p' "$WD/rule.err" | head -1 | lib_scrub)"
    fi
    n=$(jq -rn --arg w "$WHAT" '$w | utf8bytelength') || lib_die2 "jq failed"
    [ "$n" -le 400 ] || refuse "standing.$SID: a rule row's What is at most 400 bytes; this one is $n"
    why=$(jq -r -L "$HERE" --arg s "$SOURCE" 'include "state-schema";
        (.standing // []) | rule_cap_problem({kind: "rule", source: $s}) // empty' "$P") || lib_die2 "jq failed"
    [ -z "$why" ] || refuse "standing: $why"
    read -r -a form <<< "$SOURCE"
    if [ "${form[0]}" = pinned ]; then
        jq -e --arg v "${form[1]} ${form[2]}" 'any((.run // [])[]; (.key == "rules" or .key == "briefs") and .value == $v)' "$P" > /dev/null \
            || refuse "standing.$SID: the Source pins ${form[1]} ${form[2]}, which no Run rules or briefs row holds"
    fi
    [ "${form[0]}" != decision ] \
        || refuse "standing.$SID: the Source's decision form isn't written before koto's decision commands; write the row as inferred"

    # shellcheck source=dispatch-common.sh
    . "$HERE/dispatch-common.sh" || lib_die2 "cannot load dispatch-common.sh"
    rule_visibility "$REPO"
    [ "$VIS" != 404 ] || lib_die2 "cannot read $REPO's visibility"
    RULE_HOST_PRIVATE=$VIS
    if [ "${form[0]}" = skill ] || [ "${form[0]}" = doc ]; then
        r=${form[1]} path=${form[2]} c=${form[3]}
        # On a public host, a repository that isn't public, or answers 404, is
        # refused by the core's check before any of its text is read.
        if [ "$RULE_HOST_PRIVATE" = false ] && [ "$(rule_lc "$r")" != "$(rule_lc "$REPO")" ]; then
            rule_visibility "$r"
            if [ "$VIS" != false ]; then rule_not_public "$r"; return 0; fi
        fi
        forge_read "$WD/compare" "repos/$r/compare/$c...HEAD" --jq .status
        case $? in
            0) st=$(cat "$WD/compare") ;;
            1) st=notfound ;;
            *) lib_die2 "cannot read whether $r's default branch holds $c" ;;
        esac
        case "$st" in
            identical|ahead) ;;
            behind|diverged|notfound) refuse "standing.$SID: the Source names a commit $r's default branch doesn't hold, or a repository that can't be read" ;;
            *) lib_die2 "cannot read whether $r's default branch holds $c" ;;
        esac
        dc_with_deadline "${FORGE_READ_SECONDS:-10}" dc_tree lib_file_at "$path" "$c" "$WD/cited" "$r"
        case $? in
            0) ;;
            1) refuse "standing.$SID: the Source names $path, which $r doesn't hold at $c" ;;
            *) lib_die2 "cannot read $path at $c in $r" ;;
        esac
        jq -e -R -s -L "$HERE" --arg w "$WHAT" 'include "state-schema"; file_holds($w)' "$WD/cited" > /dev/null 2>&1 \
            || refuse "standing.$SID: the What isn't a sentence of $path at $c"
    fi
    # Each two-part token in the What, on a public host, the host excepted:
    # one visibility read, a private answer refused, and a 404 refused under
    # the host's owner and passed under any other, since a 404 can't tell an
    # absent repository from a hidden one. A private host reads none.
    [ "$RULE_HOST_PRIVATE" = false ] || return 0
    jq -rn -L "$HERE" --arg w "$WHAT" 'include "state-schema"; $w | what_repo_tokens[]' > "$WD/tokens" || lib_die2 "jq failed"
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        [ "$(rule_lc "$tok")" != "$(rule_lc "$REPO")" ] || continue
        case ",$(rule_lc "$RULE_NOT_PUBLIC")," in *",$(rule_lc "$tok"),"*) continue ;; esac
        rule_visibility "$tok"
        case "$VIS" in
            false) ;;
            true) rule_not_public "$tok" ;;
            404) [ "$(rule_lc "${tok%%/*}")" != "$(rule_lc "${REPO%%/*}")" ] || rule_not_public "$tok" ;;
        esac
    done < "$WD/tokens"
}
# intake_checks: the brief's lines the intake would write ($WD/plan.json's
# writes) checked one by one, as a rule row's What is, into $WD/kept.json;
# each line that fails is left out and named on stderr, `left out: <reason>:
# <the line, cut to 200 characters, a token or a home directory's name
# blanked>`, and the rest are written. A line fails at over 400 bytes, with a
# home-directory path or a token-shaped string (text_problem, on any host),
# or, on a public host ($RULE_HOST_PRIVATE false), naming a repository that
# isn't public: each repository the lines name, the host excepted, gets one
# visibility read; a repository answering private isn't public, and one
# answering 404 isn't either when a line names it in a link or as
# owner/repo#n, or as a bare owner/repo token under the host's owner (a 404
# under another owner can't tell an absent repository from a hidden one). A
# read that fails otherwise exits 2, before anything is written.
intake_checks() {
    local r
    jq -c -L "$HERE" 'include "state-schema";
        [.writes[] | {text: ., bytes: utf8bytelength, problem: text_problem([]),
                      links: text_named_repos, tokens: what_repo_tokens}]' "$WD/plan.json" > "$WD/lines.json" || lib_die2 "jq failed"
    echo '{}' > "$WD/vis.json"
    if [ "$RULE_HOST_PRIVATE" = false ]; then
        jq -r --arg h "$REPO" '[.[] | select(.bytes <= 400 and .problem == null) | (.links + .tokens)[]]
            | map(select(ascii_downcase != ($h | ascii_downcase))) | unique_by(ascii_downcase) | .[]' "$WD/lines.json" > "$WD/repos" \
            || lib_die2 "jq failed"
        while IFS= read -r r; do
            [ -n "$r" ] || continue
            rule_visibility "$r"
            jq -c --arg r "$(rule_lc "$r")" --arg v "$VIS" '.[$r] = $v' "$WD/vis.json" > "$WD/vis.next" && mv "$WD/vis.next" "$WD/vis.json" \
                || lib_die2 "jq failed"
        done < "$WD/repos"
    fi
    jq -c --slurpfile v "$WD/vis.json" --arg h "$REPO" --arg pub "$RULE_HOST_PRIVATE" '
        ($h | ascii_downcase) as $hl | ($hl | split("/")[0]) as $owner
        | def vis: $v[0][ascii_downcase] // "false";
          def hidden_link: ascii_downcase != $hl and (vis == "true" or vis == "404");
          def hidden_token: ascii_downcase != $hl and (vis == "true" or (vis == "404" and (ascii_downcase | split("/")[0]) == $owner));
        map(. + {why: (if .bytes > 400 then "a rule row'"'"'s What is at most 400 bytes; this one is \(.bytes)"
                       elif .problem != null then .problem
                       elif $pub != "false" then null
                       else (first((.links[] | select(hidden_link)), (.tokens[] | select(hidden_token))) // null)
                            | if . == null then null else "names \(.), a repository that isn'"'"'t public" end end)})' \
        "$WD/lines.json" > "$WD/judged.json" || lib_die2 "jq failed"
    jq -r '.[] | select(.why != null) | "left out: \(.why): \(.text[0:200]
        | gsub("(?<p>gh[pousr]_|github_pat_|sk-|xox[abprs]-)[A-Za-z0-9_-]+"; "\(.p)[redacted]")
        | gsub("(?<p>/home/|/Users/)[^/[:space:]]+"; "\(.p)[redacted]")
        | gsub("[\u0000-\u001f\u007f]"; ""))"' "$WD/judged.json" | sed "s/^/$PROG: /" >&2
    jq -c '[.[] | select(.why == null) | .text]' "$WD/judged.json" > "$WD/kept.json" || lib_die2 "jq failed"
}
# next_standing_id: SID, the id a new Standing row in the record read ($P)
# gets, and STANDING_USED, its number, which the write core keeps in
# record/meta. The next id never reuses an ended one. record/meta keeps the
# highest id the record has given out (standing_used, read with the record),
# so no entry is read (shirabe#1283). The entries are still listed, in one
# call, as a check before the write: state-entry.sh appends this write's entry
# after the record is written and numbers it from its own listing, so a
# stream that can't be listed is refused here (2), before the row is written,
# rather than leaving a row with no entry (14).
next_standing_id() {
    local used n entries
    SID=$(jq -r '"s\(([(.standing // [])[] | .standing[1:] | tonumber] | max // 0) + 1)"' "$P")
    rs_list "${RS_SESSION:-$SESSION}" record/entries/ "$WD/entry-keys" \
        || lib_die2 "cannot read the record's entries to choose the next Standing id: $(lib_scrub < "$WD/entry-keys.err")"
    used=$(jq -r '.standing_used | select(type == "number" and . >= 0 and . == floor)' "$P.meta") \
        || lib_die2 "the record's record/meta is not JSON"
    if [ -z "$used" ]; then
        # A record written before record/meta kept it, one the legacy importer
        # wrote, or one re-seeded over entries: the entries name the ids, so
        # the highest id ever used is read from the stream, once; this write
        # then records it. Once it is kept, an entry written by hand whose text
        # starts with an id above it no longer moves the next id: only this
        # script's --standing, --end and --inferred write such entries.
        entries=$(bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --list 2> "$WD/list.err") \
            || lib_die2 "cannot read the record's entries to choose the next Standing id: $(lib_scrub < "$WD/list.err")"
        used=$(printf '%s' "$entries" | jq -r '[.[] | .text | scan("^(s[1-9][0-9]*)") | .[0][1:] | tonumber] | max // 0') \
            || lib_die2 "the record's entries are not JSON"
    fi
    n=${SID#s}; [ "$used" -ge "$n" ] && SID="s$((used + 1))"
    STANDING_USED=${SID#s}
}
# The entry that tells the change: its kind and text; and the entries told
# after it, in order, one `<kind><TAB><text>` line each: --inferred's rule
# entry, and the intake's entries after its first.
EKIND= ETEXT= EXTRAS=
# An intake the caps stopped: the line naming how far it got.
INTAKE_CAPPED=
case "$MODE" in
rule-files)
    # The rows and host keys the list owns: a `rules` row or rules: key whose
    # label is skill- or workspace-. A listed file's row is kept as written
    # when its digest is the same, replaced in place when it changed, and
    # added after the Run rows when new; an owned row no longer listed goes.
    jq -s -c . "$RFILE" > "$WD/files.json" || lib_die2 "jq failed"
    jq -c --slurpfile l "$WD/files.json" '
        def owned: test("^(skill|workspace)-");
        ([(.run // [])[] | select(.key == "rules") | (.value | split(" ")) | select(.[0] | owned) | {key: .[0], value: .[1]}] | from_entries) as $have
        | ($l[0] | map({key: .label, value: ("sha256:" + .digest)}) | from_entries) as $want
        | {added: [$l[0][] | select($have[.label] == null) | "\(.label) sha256:\(.digest)"],
           changed: [$l[0][] | select($have[.label] != null and $have[.label] != "sha256:" + .digest) | "\(.label) \($have[.label]) to sha256:\(.digest)"],
           removed: [$have | keys_unsorted[] | select($want[.] == null)]}' "$P" > "$WD/changes.json" || lib_die2 "jq failed"
    RUN_CHANGED=$(jq -r '(.added + .changed + .removed | length) > 0' "$WD/changes.json")
    rs_host "${RS_SESSION:-$SESSION}" "$WD/host" || lib_die2 "cannot read record/host: $(lib_scrub < "$WD/host.err")"
    jq -c --slurpfile l "$WD/files.json" '($l[0] | map(.label)) as $ls
        | with_entries(select((.key | test("^rules:(skill|workspace)-") | not) or ((.key | ltrimstr("rules:")) as $k | $ls | index($k) != null)))
          + ($l[0] | map({key: ("rules:" + .label), value: .path}) | from_entries)' "$WD/host" > "$WD/host.next" || lib_die2 "jq failed"
    HOST_CHANGED=false
    [ "$(jq -cS . "$WD/host")" = "$(jq -cS . "$WD/host.next")" ] || HOST_CHANGED=true
    [ "$RUN_CHANGED" = true ] || [ "$HOST_CHANGED" = true ] || exit 0
    if [ "$RUN_CHANGED" = false ]; then
        # The paths alone moved: record/host is written, no row and no entry.
        lib_write_guard
        . "$HERE/state-write-core.sh"
        core_write_host "$WD/host.next"
        exit 0
    fi
    jq --slurpfile l "$WD/files.json" --arg b "$BY" --arg t "$NOW" '
        def owned: test("^(skill|workspace)-");
        ($l[0] | map({key: .label, value: ("sha256:" + .digest)}) | from_entries) as $want
        | ([(.run // [])[] | select(.key == "rules") | (.value | split(" ")[0])]) as $had
        | .run = ([(.run // [])[] | (.value | split(" ")) as $p
                   | if .key == "rules" and ($p[0] | owned) then
                       if $want[$p[0]] == null then empty
                       elif $want[$p[0]] == $p[1] then .
                       else {key: "rules", value: "\($p[0]) \($want[$p[0]])", set_by: $b, set: $t} end
                     else . end]
                  + [$l[0][] | select(.label as $x | $had | index($x) | not)
                     | {key: "rules", value: "\(.label) sha256:\(.digest)", set_by: $b, set: $t}])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=run
    ETEXT=$(jq -r --arg b "$BY" '[(if (.added | length) > 0 then "added " + (.added | join(", ")) else empty end),
            (if (.changed | length) > 0 then "changed " + (.changed | join(", ")) else empty end),
            (if (.removed | length) > 0 then "removed " + (.removed | join(", ")) else empty end)]
        | "Run rules digests of the files this start loaded, set by \($b): \(join("; "))."' "$WD/changes.json") || lib_die2 "jq failed"
    ;;
run)
    if [ "$KEY" = role ]; then
        # Set once: a different value only through --intervention.
        OLD=$(jq -r '[(.run // [])[] | select(.key == "role") | .value][0] // ""' "$P") || lib_die2 "jq failed"
        [ "$OLD" != "$VALUE" ] || exit 0
        if [ -n "$OLD" ] && [ "$HAS_INTERVENTION" = 0 ]; then
            refuse "the run's role is $OLD and this write names $VALUE; a recorded role changes only through --intervention dispatcher|person, a change from above"
        fi
        if [ -n "$OLD" ]; then
            ETEXT="Run role changed from $OLD to $VALUE by $BY, an intervention from above; source: $INTERVENTION."
        else
            ETEXT="Run role set to $VALUE by $BY."
        fi
        jq --arg v "$VALUE" --arg b "$BY" --arg t "$NOW" \
            '.run = ([(.run // [])[] | select(.key != "role")] + [{key: "role", value: $v, set_by: $b, set: $t}])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    elif [ "$KEY" = coordinator ]; then
        PROG_JQ='.run = ([(.run // [])[] | select(.key != "coordinator" and .key != "told" and .key != "pending")] + [{key: "coordinator", value: $v, set_by: $b, set: $t}])'
        ETEXT="The coordinator's address is now $VALUE, set by $BY. Nobody has been told it yet."
    elif [ "$KEY" = rules ] || [ "$KEY" = briefs ]; then
        # One row per label: a new digest for a label replaces its row.
        PROG_JQ='($v | split(" ")[0]) as $l
            | .run = ([(.run // [])[] | select((.key == $k and (.value | split(" ")[0]) == $l) | not)] + [{key: $k, value: $v, set_by: $b, set: $t}])'
        ETEXT="Run $KEY $VALUE set by $BY."
    else
        PROG_JQ='.run = ([(.run // [])[] | select(.key != $k)] + [{key: $k, value: $v, set_by: $b, set: $t}])'
        ETEXT="Run $KEY set to $VALUE by $BY."
    fi
    if [ "$KEY" != role ]; then
        jq --arg k "$KEY" --arg v "$VALUE" --arg b "$BY" --arg t "$NOW" "$PROG_JQ" "$P" > "$WD/next.json" || lib_die2 "jq failed"
    fi
    EKIND=run
    if [ "$HAS_INFERRED" = 1 ]; then
        # A value the coordinator worked out lands with its reading: a rule
        # row, Source `inferred`, in the same state, so the one core_write
        # below writes both or neither. The Run value's grammar is checked
        # first, then the rule row's checks, before any forge read.
        if ! jq -L "$HERE" 'include "state-schema";
                (state_secs[] | select(.key == "run")) as $sec | check_state($sec; .run; []) | empty' \
                "$WD/next.json" 2> "$WD/run.err" < /dev/null; then
            grep -q 'refused: ' "$WD/run.err" || lib_die2 "state-schema.jq failed: $(lib_scrub < "$WD/run.err")"
            refuse "$(sed -n 's/.*refused: //p' "$WD/run.err" | head -1 | lib_scrub)"
        fi
        next_standing_id
        WHAT=$INFERRED SOURCE=inferred
        jq --arg s "$SID" --arg w "$WHAT" --arg t "$NOW" \
            '.standing = ((.standing // []) + [{standing: $s, kind: "rule", on: "", until: "", what: $w, owner: "", relayed_by: "", set: $t, source: "inferred"}])' \
            "$WD/next.json" > "$WD/next.rule.json" || lib_die2 "jq failed"
        mv "$WD/next.rule.json" "$WD/next.json" || lib_die2 "cannot write the state file"
        rule_checks
        EXTRAS="rule$TAB$SID (rule): $WHAT. Source: $SOURCE."$'\n'
    fi
    ;;
told)
    jq -e 'any((.run // [])[]; .key == "coordinator")' "$P" > /dev/null || refuse "the record names no coordinator address to have told anyone; set it with --run coordinator first"
    jq -e --arg w "$WHO" 'any((.run // [])[]; .key == "told" and .value == $w)' "$P" > /dev/null && refuse "$WHO has already been told the current address"
    ADDR=$(jq -r '[(.run // [])[] | select(.key == "coordinator") | .value][0]' "$P")
    # A pending worker that is told now is pending no longer.
    jq --arg w "$WHO" --arg b "$BY" --arg t "$NOW" '.run = ([(.run // [])[] | select((.key == "pending" and .value == $w) | not)]
        + [{key: "told", value: $w, set_by: $b, set: $t}])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=told ETEXT="$WHO was told the coordinator's address, $ADDR, by $BY."
    ;;
pending)
    jq -e 'any((.run // [])[]; .key == "coordinator")' "$P" > /dev/null || refuse "the record names no coordinator address for anyone to be pending on; set it with --run coordinator first"
    jq -e --arg w "$WHO" 'any((.run // [])[]; .key == "told" and .value == $w)' "$P" > /dev/null && refuse "$WHO has already been told the current address"
    jq -e --arg w "$WHO" 'any((.run // [])[]; .key == "pending" and .value == $w)' "$P" > /dev/null && refuse "$WHO is already pending on the current address"
    ADDR=$(jq -r '[(.run // [])[] | select(.key == "coordinator") | .value][0]' "$P")
    jq --arg w "$WHO" --arg b "$BY" --arg t "$NOW" '.run = ((.run // []) + [{key: "pending", value: $w, set_by: $b, set: $t}])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=pending ETEXT="$WHO can't be told the coordinator's address, $ADDR, yet: it is pending, recorded by $BY."
    ;;
standing)
    case "$KIND" in pause|go-ahead|approval|answer|assignment|rule) ;; *) echo "$PROG: --standing takes pause, go-ahead, approval, answer, assignment or rule" >&2; exit 64 ;; esac
    case "$KIND" in
        pause) [ -n "$ON" ] && [ -n "$UNTIL" ] || { echo "$PROG: a pause takes --on and --until" >&2; exit 64; } ;;
        go-ahead) [ -z "$UNTIL" ] || { echo "$PROG: a go-ahead takes no --until; it ends when used" >&2; exit 64; } ;;
        assignment) [ -n "$ON" ] && [ -z "$UNTIL" ] || { echo "$PROG: an assignment takes --on, the unit assigned, and no --until" >&2; exit 64; } ;;
        *) [ -z "$ON$UNTIL" ] || { echo "$PROG: only a pause, a go-ahead or an assignment takes --on, and only a pause --until" >&2; exit 64; } ;;
    esac
    # The scope must be a unit pick reads, when this session's pick facts say
    # which units those are; an assignment names one pick doesn't list yet.
    if [ -n "$ON" ] && [ "$ON" != all ] && [ "$KIND" != assignment ] && [ "$OVERRIDE" != 1 ] && [ -n "$SESSION" ]; then
        if "$KOTO" context exists "$SESSION" coord/pick.json; then
            "$KOTO" context get "$SESSION" coord/pick.json > "$WD/pick.json" || lib_die2 "cannot read coord/pick.json"
        else
            echo '{}' > "$WD/pick.json"
        fi
        if jq -e '(.units // []) | type == "array" and length > 0' "$WD/pick.json" > /dev/null; then
            jq -e --arg u "$ON" '.host as $h | any(.units[]; .unit == $u or ($h != null and ($h + .unit) == $u))' "$WD/pick.json" > /dev/null \
                || refuse "--on $ON is not a unit pick lists; it takes one of: $(jq -r '[.units[].unit] | join(", ")' "$WD/pick.json")"
        fi
    fi
    next_standing_id
    # A rule row carries its Source; an event row is written as before, with
    # none.
    jq --arg s "$SID" --arg k "$KIND" --arg on "$ON" --arg u "$UNTIL" --arg w "$WHAT" --arg o "$OWNER" --arg r "$RELAYED" --arg t "$NOW" --arg src "$SOURCE" \
        '.standing = ((.standing // []) + [{standing: $s, kind: $k, on: $on, until: $u, what: $w, owner: $o, relayed_by: $r, set: $t}
            + (if $k == "rule" then {source: $src} else {} end)])' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=$KIND
    if [ "$KIND" = rule ]; then
        rule_checks
        ETEXT="$SID (rule): $WHAT. Source: $SOURCE."
    else
        ETEXT="$SID ($KIND${ON:+ on $ON}${UNTIL:+, until $UNTIL}): $WHAT. Owner: $OWNER.${RELAYED:+ Relayed by $RELAYED.}"
    fi
    ;;
end)
    ROW=$(jq -c --arg s "$ID" '[(.standing // [])[] | select(.standing == $s)][0] // empty' "$P")
    [ -n "$ROW" ] || refuse "no Standing row $ID"
    jq --arg s "$ID" '.standing = [(.standing // [])[] | select(.standing != $s)]' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=end
    ETEXT="$ID ($(printf '%s' "$ROW" | jq -r .kind): $(printf '%s' "$ROW" | jq -r .what)) ended by $BY."
    ;;
intake)
    # The brief record/host names for the label, read once: its digest and
    # its candidates come from the same bytes. The path is never printed,
    # since it can be a home-directory path.
    rs_host "${RS_SESSION:-$SESSION}" "$WD/host" || lib_die2 "cannot read record/host: $(lib_scrub < "$WD/host.err")"
    BRIEF_PATH=$(jq -r --arg k "briefs:$ILABEL" '.[$k] // "" | if type == "string" then . else "" end' "$WD/host") || lib_die2 "jq failed"
    case "$BRIEF_PATH" in
        /*) ;;
        *) refuse "record/host names no brief briefs:$ILABEL; name it with --host briefs:$ILABEL <absolute path>" ;;
    esac
    { [ -f "$BRIEF_PATH" ] && [ -r "$BRIEF_PATH" ] && cp "$BRIEF_PATH" "$WD/brief" 2> /dev/null; } || lib_die2 "cannot read the brief $ILABEL"
    IDIG=$(lib_sha256 "$WD/brief")
    [[ $IDIG =~ ^[0-9a-f]{64}$ ]] || lib_die2 "cannot read the brief $ILABEL"
    IDIG=sha256:$IDIG
    ISRC="inferred brief $ILABEL $IDIG"
    # A digest a Run briefs row already carries was taken: nothing to do.
    if jq -e --arg v "$ILABEL $IDIG" 'any((.run // [])[]; .key == "briefs" and .value == $v)' "$P" > /dev/null; then
        exit 0
    fi
    jq -R -s -c -L "$HERE" 'include "state-schema"; brief_candidates' "$WD/brief" > "$WD/cands.json" || lib_die2 "cannot read the brief $ILABEL"
    jq -c -L "$HERE" --arg l "$ILABEL" --arg d "$IDIG" --slurpfile c "$WD/cands.json" 'include "state-schema";
        (.standing // []) | brief_intake_plan($l; $d; $c[0])' "$P" > "$WD/plan.json" || lib_die2 "jq failed"
    # The host's visibility, read once and handed to the write core; a
    # private host reads no repository a line names.
    # shellcheck source=dispatch-common.sh
    . "$HERE/dispatch-common.sh" || lib_die2 "cannot load dispatch-common.sh"
    rule_visibility "$REPO"
    [ "$VIS" != 404 ] || lib_die2 "cannot read $REPO's visibility"
    RULE_HOST_PRIVATE=$VIS
    intake_checks
    # The lines the caps leave room for, in order, and how many they leave.
    ROOM=$(jq -r .room "$WD/plan.json")
    jq -c --argjson r "$ROOM" '.[0:$r]' "$WD/kept.json" > "$WD/taken.json" || lib_die2 "jq failed"
    TAKEN=$(jq length "$WD/taken.json")
    UNTAKEN=$(( $(jq length "$WD/kept.json") - TAKEN ))
    NENDS=$(jq '.ends | length' "$WD/plan.json")
    WRITE_BRIEF=false
    [ "$UNTAKEN" -gt 0 ] || WRITE_BRIEF=true
    START_N=0
    if [ "$TAKEN" -gt 0 ]; then
        next_standing_id
        START_N=${SID#s}
        STANDING_USED=$((START_N + TAKEN - 1))
    fi
    jq --slurpfile tk "$WD/taken.json" --slurpfile pl "$WD/plan.json" --argjson n "$START_N" --arg src "$ISRC" --arg t "$NOW" \
        --arg b "$BY" --arg l "$ILABEL" --arg bv "$ILABEL $IDIG" --argjson brief "$WRITE_BRIEF" '
        ($pl[0].ends) as $e
        | .standing = ([(.standing // [])[] | select(.standing as $s | any($e[]; . == $s) | not)]
            + [$tk[0] | to_entries[] | {standing: "s\($n + .key)", kind: "rule", on: "", until: "", what: .value,
                                         owner: "", relayed_by: "", set: $t, source: $src}])
        | if $brief then
            .run = ([(.run // [])[] | select((.key == "briefs" and (.value | split(" ")[0]) == $l) | not)]
                    + [{key: "briefs", value: $bv, set_by: $b, set: $t}])
          else . end' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    if [ "$UNTAKEN" -gt 0 ]; then
        WHY=$(jq -r -L "$HERE" --arg s "$ISRC" 'include "state-schema";
            (.standing // []) | rule_cap_problem({kind: "rule", source: $s}) // "the caps leave no room"' "$WD/next.json") || lib_die2 "jq failed"
        INTAKE_CAPPED="took $TAKEN of the brief's lines; $UNTAKEN of its lines can't be taken under the caps: $WHY"
        if [ "$TAKEN" = 0 ] && [ "$NENDS" = 0 ]; then
            echo "$PROG: $INTAKE_CAPPED" >&2
            exit 1
        fi
    fi
    # The Standing section the write leaves, checked as a rule row's is.
    if ! jq -L "$HERE" 'include "state-schema";
            (state_secs[] | select(.key == "standing")) as $sec
            | (check_state($sec; .standing // []; []) | empty), ((.standing // []) | scan_strings([]) | empty)' \
            "$WD/next.json" 2> "$WD/rule.err" < /dev/null; then
        grep -q 'refused: ' "$WD/rule.err" || lib_die2 "state-schema.jq failed: $(lib_scrub < "$WD/rule.err")"
        refuse "$(sed -n 's/.*refused: //p' "$WD/rule.err" | head -1 | lib_scrub)"
    fi
    # The entries: a rule entry per new row, an end entry per ended row, then
    # the briefs row's run entry.
    jq -r --slurpfile tk "$WD/taken.json" --slurpfile pl "$WD/plan.json" --argjson n "$START_N" --arg src "$ISRC" \
        --arg b "$BY" --arg bv "$ILABEL $IDIG" --argjson brief "$WRITE_BRIEF" '
        (.standing // []) as $rows
        | ($tk[0] | to_entries[] | "rule\ts\($n + .key) (rule): \(.value). Source: \($src)."),
          ($pl[0].ends[] as $e | $rows[] | select(.standing == $e) | "end\t\(.standing) (\(.kind): \(.what)) ended by \($b)."),
          (if $brief then "run\tRun briefs \($bv) set by \($b)." else empty end)' "$P" > "$WD/entries.list" || lib_die2 "jq failed"
    EKIND=$(head -1 "$WD/entries.list" | cut -f1)
    ETEXT=$(head -1 "$WD/entries.list" | cut -f2-)
    EXTRAS=$(tail -n +2 "$WD/entries.list")
    [ -z "$EXTRAS" ] || EXTRAS=$EXTRAS$'\n'
    ;;
work)
    case "$KIND" in
        holding|local-agent|decision|follow-up) ;;
        verdict-owed) echo "$PROG: a verdict-owed row is written only by roadmap-status.sh --unit, on a milestone roadmap" >&2; exit 64 ;;
        rework) echo "$PROG: a rework row is written only by roadmap-status.sh --confirm, from a confirmed changes-needed verdict or reopen" >&2; exit 64 ;;
        *) echo "$PROG: --kind takes holding, local-agent, decision or follow-up" >&2; exit 64 ;;
    esac
    if [ "$KIND" = holding ]; then
        jq -e --arg u "$ITEM" --arg w "$WHO" 'any(.holdings[]; .unit == $u and .worker == $w)' "$P" > /dev/null \
            || refuse "no holding has Unit $ITEM and Worker $WHO"
    fi
    # A unit parked on a decision waits on an entry that is still open.
    if [ "$KIND" = decision ]; then
        [[ $WHO =~ ^decision\ [1-9][0-9]*$ ]] || refuse "a decision row's --who is 'decision <n>'"
        jq -e --arg n "${WHO#decision }" 'any((.decisions.entries // [])[]; .decision == $n and .state != "settled")' "$P" > /dev/null \
            || refuse "decision ${WHO#decision } is not an unsettled entry in the record's Decisions section"
    fi
    # Either row names a unit pick lists, when this session's pick facts say
    # which units those are, as a pause's --on does.
    if { [ "$KIND" = decision ] || [ "$KIND" = follow-up ]; } && [ "$OVERRIDE" != 1 ] && [ -n "$SESSION" ] \
        && "$KOTO" context exists "$SESSION" coord/pick.json; then
        "$KOTO" context get "$SESSION" coord/pick.json > "$WD/pick.json" || lib_die2 "cannot read coord/pick.json"
        if jq -e '(.units // []) | type == "array" and length > 0' "$WD/pick.json" > /dev/null; then
            jq -e --arg u "$ITEM" '.host as $h | any(.units[]; .unit == $u or ($h != null and ($h + .unit) == $u))' "$WD/pick.json" > /dev/null \
                || refuse "$ITEM is not a unit pick lists; a $KIND row takes one of: $(jq -r '[.units[].unit] | join(", ")' "$WD/pick.json")"
        fi
    fi
    # A holding's first Work row is written at its dispatch, whose brief named
    # this coordinator's address, so it records the worker as told; a later
    # update records nothing of the kind, since after an address change the
    # worker has been told nothing until --told says so.
    FIRST=true
    jq -e --arg i "$ITEM" 'any((.work // [])[]; .item == $i and .kind == "holding")' "$P" > /dev/null && FIRST=false
    WAKES=0
    if [ "$KIND" = holding ]; then
        PREV=$(jq -c --arg i "$ITEM" '[(.work // [])[] | select(.item == $i and .kind == "holding")][0] // {}' "$P")
        RP=$(jq -r --arg u "$ITEM" --arg w "$WHO" '[.holdings[] | select(.unit == $u and .worker == $w) | .return_path][0] // ""' "$P")
        PREV_UPD=$(printf '%s' "$PREV" | jq -r '.updated // ""') || lib_die2 "jq failed"
        ADD=$(wakes_since "$WHO" "$RP" "$PREV_UPD")
        [ -n "$ADD" ] || lib_die2 "cannot count the run's wakes for $WHO"
        WAKES=$(( $(printf '%s' "$PREV" | jq -r '.wakes // "0" | if . == "" then "0" else . end') + ADD ))
    fi
    # A holding takes over the decision and follow-up rows of its unit, unless
    # it is the scoping holding whose merge wrote the follow-up.
    TAKES=false
    [ "$KIND" = holding ] && ! jq -e --arg u "$ITEM" --arg w "$WHO" 'any(.holdings[]; .unit == $u and .worker == $w and .phase == "scoping")' "$P" > /dev/null && TAKES=true
    jq --arg i "$ITEM" --arg k "$KIND" --arg w "$WHO" --arg n "$NEXT" --arg t "$NOW" --arg c "$WAKES" --arg h "$REPO" --argjson first "$FIRST" --argjson takes "$TAKES" '
        # The row ITEM has under this kind is replaced, and the ones a
        # holding takes over: its unit by tag, a Unit cell `<tag>: <title>`
        # read as its tag, an issue as `#<n>` or `<host>#<n>`.
        ($i | split(": ")[0]) as $tag
        | def same_unit: . == $tag or ($h + .) == $tag or . == ($h + $tag);
        .work = ([(.work // [])[] | select((.item == $i and .kind == $k)
                    or ($takes and (.kind == "decision" or .kind == "follow-up") and (.item | same_unit)) | not)]
                 + [{item: $i, kind: $k, who: $w, next: $n, wakes: $c, updated: $t}])
        | if $k == "holding" and $first and any((.run // [])[]; .key == "coordinator") and (any((.run // [])[]; .key == "told" and .value == $w) | not)
          then .run = ([.run[] | select((.key == "pending" and .value == $w) | not)]
                       + [{key: "told", value: $w, set_by: ([.run[] | select(.key == "coordinator") | .value][0]), set: $t}])
          else . end' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=work ETEXT="Next step for $ITEM ($KIND, $WHO): $NEXT."
    [ "$KIND" = holding ] && ETEXT="$ETEXT Wakes so far: $WAKES."
    ;;
done)
    # A verdict-owed row leaves only when its verdict's roadmap edit is
    # confirmed (roadmap-status.sh --confirm), never by hand.
    [ "$KIND" != verdict-owed ] || refuse "a verdict-owed row leaves Work only through roadmap-status.sh --confirm, once its verdict's roadmap edit is on the default branch"
    jq -e --arg i "$ITEM" --arg k "$KIND" 'any((.work // [])[]; .item == $i and .kind != "verdict-owed" and ($k == "" or .kind == $k))' "$P" > /dev/null \
        || refuse "no Work row for $ITEM${KIND:+ of kind $KIND}"
    jq --arg i "$ITEM" --arg k "$KIND" '.work = [(.work // [])[] | select(.item != $i or .kind == "verdict-owed" or ($k != "" and .kind != $k))]' "$P" > "$WD/next.json" || lib_die2 "jq failed"
    EKIND=work ETEXT="$ITEM${KIND:+ ($KIND)} is done and leaves Work."
    ;;
esac

# The holding rows that leave Work with this write, --done's or the ones whose
# holding is gone, each with its final count, told after the change's entry.
P_NEXT="$WD/next.json"
jq -c '([.holdings[] | "\(.unit)\u0000\(.worker)"]) as $h
    | [(.work // [])[] | select(.kind == "holding" and (("\(.item)\u0000\(.who)" as $k | $h | index($k)) | not))]' "$P_NEXT" > "$WD/leaving.json" || lib_die2 "jq failed"
if [ "$MODE" = done ]; then
    jq -c --arg i "$ITEM" --arg k "$KIND" '[(.work // [])[] | select(.item == $i and .kind == "holding" and ($k == "" or $k == "holding"))]' "$P" > "$WD/done.json" || lib_die2 "jq failed"
    jq -sc 'add | unique_by(.item)' "$WD/leaving.json" "$WD/done.json" > "$WD/leaving2.json" && mv "$WD/leaving2.json" "$WD/leaving.json"
fi
: > "$WD/leaving.txt"
n=$(jq length "$WD/leaving.json")
i=0
while [ "$i" -lt "$n" ]; do
    ROW=$(jq -c --argjson i "$i" '.[$i]' "$WD/leaving.json")
    LW=$(printf '%s' "$ROW" | jq -r .who)
    # The leg's request, when the holding is still in the version read (a
    # --done); a holding already gone takes its leg's wakes with it, a floor.
    LRP=$(jq -r --arg u "$(printf '%s' "$ROW" | jq -r .item)" --arg w "$LW" '[.holdings[] | select(.unit == $u and .worker == $w) | .return_path][0] // ""' "$P")
    LUPD=$(printf '%s' "$ROW" | jq -r '.updated // ""') || lib_die2 "jq failed"
    LADD=$(wakes_since "$LW" "$LRP" "$LUPD")
    [ -n "$LADD" ] || lib_die2 "cannot count the run's wakes for $LW"
    LTOT=$(( $(printf '%s' "$ROW" | jq -r '.wakes // "0" | if . == "" then "0" else . end') + LADD ))
    printf '%s\n' "$(printf '%s' "$ROW" | jq -r .item) ($LW) left Work after $LTOT wakes." >> "$WD/leaving.txt"
    i=$((i + 1))
done

# Every write drops a holding's Work row whose holding is gone, and keeps the
# written time of the version read, which the write core compares with the
# live record's before it stamps its own. The state file stays in this
# script's private directory, readable by its owner only, and goes with it.
jq --arg w "$(jq -r '.written' "$P")" '([.holdings[] | "\(.unit)\u0000\(.worker)"]) as $h
    | .work = [(.work // [])[] | select(.kind != "holding" or ("\(.item)\u0000\(.who)" as $k | $h | index($k)))]
    | if (.work | length) == 0 then del(.work) else . end
    | if ((.run // []) | length) == 0 then del(.run) else . end
    | if ((.standing // []) | length) == 0 then del(.standing) else . end
    | .written = $w' "$WD/next.json" > "$WD/final.json" || lib_die2 "jq failed"
chmod 600 "$WD/final.json" || lib_die2 "cannot make the state file private"
printf '%s\n' "$ETEXT" > "$WD/entry.txt"
# The write core takes over $T and the EXIT trap and removes $WD, so the
# entries' text is kept outside it.
ENTRY_FILE=$(mktemp "${TMPDIR:-/tmp}/state-stored-set-entry.XXXXXX") || lib_die2 "cannot make a temporary file"
cp "$WD/entry.txt" "$ENTRY_FILE"
LEAVING_FILE=$(mktemp "${TMPDIR:-/tmp}/state-stored-set-leaving.XXXXXX") \
    || { rm -f "$ENTRY_FILE"; lib_die2 "cannot make a temporary file"; }
cp "$WD/leaving.txt" "$LEAVING_FILE"
# The entries told after the first (--inferred's rule entry, the intake's
# rule, end and run entries), in order.
EXTRA_FILE=$(mktemp "${TMPDIR:-/tmp}/state-stored-set-extra.XXXXXX") \
    || { rm -f "$ENTRY_FILE" "$LEAVING_FILE"; lib_die2 "cannot make a temporary file"; }
printf '%s' "$EXTRAS" > "$EXTRA_FILE"

STATE_FILE="$WD/final.json" CORE_CLEANUP=$WD
lib_write_guard
. "$HERE/state-write-core.sh"
STATE_WRITER=1
CORE_STANDING_USED=${STANDING_USED:-}
# A rule row's checks read the host's visibility, and the repositories the
# row names that aren't public; every other write leaves both empty, and the
# core reads the host itself.
CORE_HOST_PRIVATE=$RULE_HOST_PRIVATE CORE_NOT_PUBLIC=$RULE_NOT_PUBLIC
# The rule files' write may come before the run's find (START_WRITER), and
# writes record/host first, so a write cut short after it leaves a Run row
# the next start still finds changed, and tells.
EARGS=("${ADDR_ARGS[@]}")
if [ "$MODE" = rule-files ]; then
    START_WRITER=1
    [ "$OVERRIDE" = 1 ] || EARGS+=(--before-find)
    [ "$HOST_CHANGED" = false ] || core_write_host "$WD/host.next"
fi
# A role change from above takes the same before-find path.
if [ "$HAS_INTERVENTION" = 1 ]; then
    START_WRITER=1
    [ "$OVERRIDE" = 1 ] || EARGS+=(--before-find)
fi
core_write
# An intake the caps stopped: its rows are written, its briefs row isn't, and
# the brief-unread gap stays open; it exits 1 once its entries are told (14
# when one isn't).
[ -z "$INTAKE_CAPPED" ] || echo "$PROG: $INTAKE_CAPPED" >&2

if ! bash "$HERE/state-entry.sh" "${EARGS[@]}" --kind "$EKIND" --text-file "$ENTRY_FILE"; then
    echo "$PROG: the record was written, but its entry wasn't posted; post it with state-entry.sh --kind $EKIND: $(cat "$ENTRY_FILE")" >&2
    while IFS= read -r LINE; do
        [ -n "$LINE" ] && echo "$PROG: and post with state-entry.sh --kind ${LINE%%"$TAB"*}: ${LINE#*"$TAB"}" >&2
    done < "$EXTRA_FILE"
    while IFS= read -r LINE; do
        [ -n "$LINE" ] && echo "$PROG: and post with state-entry.sh --kind work: $LINE" >&2
    done < "$LEAVING_FILE"
    rm -f "$ENTRY_FILE" "$EXTRA_FILE" "$LEAVING_FILE"
    exit 14
fi
rm -f "$ENTRY_FILE"
UNPOSTED=0
# Each entry after the first, in order; every one is tried, and any that
# didn't post are named.
while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    XKIND=${LINE%%"$TAB"*}
    printf '%s\n' "${LINE#*"$TAB"}" > "$EXTRA_FILE.one"
    if ! bash "$HERE/state-entry.sh" "${EARGS[@]}" --kind "$XKIND" --text-file "$EXTRA_FILE.one"; then
        echo "$PROG: the record was written, but its $XKIND entry wasn't posted; post it with state-entry.sh --kind $XKIND: ${LINE#*"$TAB"}" >&2
        UNPOSTED=1
    fi
done < "$EXTRA_FILE"
rm -f "$EXTRA_FILE" "$EXTRA_FILE.one"
# Each holding row that left Work, told with its final count. Every line is
# tried; any that didn't post are named together, for state-entry.sh.
while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    printf '%s\n' "$LINE" > "$LEAVING_FILE.one"
    if ! bash "$HERE/state-entry.sh" "${ADDR_ARGS[@]}" --kind work --text-file "$LEAVING_FILE.one"; then
        echo "$PROG: the record was written, but a final count wasn't posted; post it with state-entry.sh --kind work: $LINE" >&2
        UNPOSTED=1
    fi
done < "$LEAVING_FILE"
rm -f "$LEAVING_FILE" "$LEAVING_FILE.one"
[ "$UNPOSTED" = 0 ] || exit 14
[ -z "$INTAKE_CAPPED" ] || exit 1

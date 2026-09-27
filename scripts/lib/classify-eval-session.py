#!/usr/bin/env python3
"""Classify the nested claude session scripts/run-evals.sh starts.

The runner starts one `claude -p` session per run and saves its
`--output-format stream-json` transcript next to the iteration it graded. When
that run grades nothing, there are two very different causes:

  - the session executed and the scenarios produced no grades, which is a
    problem with the suite or the skill under test, and
  - the session never executed anything at all -- it wrote a plan and stopped,
    or every command it tried was denied -- which is a problem with the runner
    or the host, and says nothing about the skill.

This script tells them apart from the transcript. A session "executed" when at
least one call to a tool that runs a command or changes a file (Bash, Write,
Edit, MultiEdit, NotebookEdit) came back and was not a permission denial. A
command that ran and exited nonzero still ran. Calls made by subagents count:
they appear in the same transcript. Plan mode overrides that: a session whose
init message says plan did not execute, whatever else ran, because plan mode
runs read-only commands and writes its own plan file; nor did a session whose
top level called ExitPlanMode and ran nothing after it.

Usage:
  classify-eval-session.py verdict <transcript>
      Print the classification as JSON. Exit 0, or 2 when the transcript
      cannot be read.
  classify-eval-session.py result-text <transcript>
      Print the session's final message, which is what `claude -p` prints in
      its default text mode. Exit 0.
  classify-eval-session.py report <transcript> [<requested-mode>]
      Print the named failure when the session did not execute, and a note
      when it executed in a mode other than the one requested.
      Exit 0 when it executed, 4 when it did not, 2 when the transcript holds
      nothing to decide from.
"""

import json
import sys

EXECUTING_TOOLS = ("Bash", "Write", "Edit", "MultiEdit", "NotebookEdit")

# Tool-result texts the CLI (2.1.283) writes for a denied call; see
# scripts/run-evals/fixtures/all-denied.jsonl for the captured forms.
DENIAL_TEXTS = ("requires approval", "haven't granted", "requested permissions to")

# run-evals.sh step 4b turns EXIT_NOT_EXECUTED into its own exit 4, and only
# asks when validation found no grading.json at all; keep the two in step.
EXIT_EXECUTED = 0
EXIT_UNREADABLE = 2
EXIT_NOT_EXECUTED = 4


def read_events(path):
    """Parse one JSON object per line, skipping lines that are not JSON.

    The CLI can print a warning line into the same stream; one stray line must
    not make the whole transcript unreadable.
    """
    events = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                events.append(json.loads(line))
            except ValueError:
                continue
    return events


def content_blocks(event):
    message = event.get("message")
    if not isinstance(message, dict):
        return []
    content = message.get("content")
    return content if isinstance(content, list) else []


def result_text_of(block):
    content = block.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(
            part.get("text", "") for part in content if isinstance(part, dict)
        )
    return ""


def classify(events):
    mode = None
    tool_uses = {}  # id -> (tool name, event index)
    first_exit_plan = None  # event index of the session's own first ExitPlanMode
    results = {}  # tool_use_id -> (is_error, text)
    denied = set()
    # Subagents can end with result messages of their own, so every result's
    # denials count, and the final message is the top-level session's.
    result_event = None

    for index, event in enumerate(events):
        kind = event.get("type")
        subtype = event.get("subtype")
        if kind == "system" and subtype == "init" and mode is None:
            # A background agent's turn emits an init of its own, with its own
            # cwd; the first init is the session the runner started.
            mode = event.get("permissionMode")
        elif kind == "system" and subtype == "permission_denied":
            if event.get("tool_use_id"):
                denied.add(event["tool_use_id"])
        elif kind == "assistant":
            for block in content_blocks(event):
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    tool_uses[block.get("id")] = (block.get("name", ""), index)
                    if (block.get("name") == "ExitPlanMode"
                            and event.get("parent_tool_use_id") is None
                            and first_exit_plan is None):
                        first_exit_plan = index
        elif kind == "user":
            for block in content_blocks(event):
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    results[block.get("tool_use_id")] = (
                        bool(block.get("is_error")), result_text_of(block))
        elif kind == "result":
            for denial in event.get("permission_denials") or []:
                if isinstance(denial, dict) and denial.get("tool_use_id"):
                    denied.add(denial["tool_use_id"])
            if event.get("parent_tool_use_id") is None or result_event is None:
                result_event = event

    # The CLI records a denial twice, as a permission_denied event and in the
    # result's permission_denials. The texts are the fallback for a transcript
    # cut short before either.
    for tool_id, (is_error, text) in results.items():
        if is_error and any(marker in text for marker in DENIAL_TEXTS):
            denied.add(tool_id)

    executing = [i for i, (name, _) in tool_uses.items() if name in EXECUTING_TOOLS]
    # A call ran when it came back and was not denied. Its exit status does not
    # matter: a command that ran and failed is the skill's or the suite's
    # problem, reported as exit 2, not the runner's.
    ran = [i for i in executing if i in results and i not in denied]

    # Plan mode is decisive on its own. It lets read-only shell commands through
    # (ls, cat, and the Explore agents it spawns), and it writes its own plan
    # file with Write, so a session that looked around and stopped has calls of
    # both kinds that ran, and still ran nothing the runner asked for. Nobody
    # can approve a plan in a -p session, so it never leaves plan mode. Outside
    # plan mode, the session's own ExitPlanMode decides only when nothing ran
    # after it: a session that presented a plan and then carried on did execute.
    # A subagent's ExitPlanMode is not the session stopping, so it is ignored.
    stopped_at_plan = first_exit_plan is not None and not any(
        tool_uses[i][1] > first_exit_plan for i in ran)
    planned = mode == "plan" or stopped_at_plan

    if not events or (mode is None and result_event is None and not tool_uses):
        verdict = "unknown"
    elif planned or not ran:
        verdict = "not_executed"
    else:
        verdict = "executed"

    return {
        "verdict": verdict,
        "permission_mode": mode,
        "exit_plan_mode": first_exit_plan is not None,
        "tool_calls": len(tool_uses),
        "executing_calls": len(executing),
        "executing_calls_ran": len(ran),
        "permission_denials": len(denied),
        "result_subtype": (result_event or {}).get("subtype"),
        "result_is_error": bool((result_event or {}).get("is_error")),
        "result_text": (result_event or {}).get("result") or "",
    }


def mode_overridden(summary, requested):
    actual = summary["permission_mode"]
    return bool(requested and actual and actual != requested)


def report(summary, transcript, requested):
    if summary["verdict"] == "executed":
        # The run graded nothing but the session did execute, so the suite or
        # the skill is the place to look. A mode other than the one requested
        # is still worth saying, since it can explain a partial run.
        if mode_overridden(summary, requested):
            print("")
            print(f"  Note: the nested session ran in permission mode"
                  f" {summary['permission_mode']}, not the {requested} the runner requested.")
            print(f"    Transcript: {transcript}")
        return EXIT_EXECUTED
    if summary["verdict"] == "unknown":
        print("")
        print("  The nested claude session left no transcript to classify:")
        print(f"    {transcript}")
        print("  It may have failed to start; its stderr is in the output above.")
        return EXIT_UNREADABLE

    mode = summary["permission_mode"] or "unknown (no init message in the transcript)"
    print("")
    print("  NESTED SESSION DID NOT EXECUTE")
    print("  The claude session this runner started stopped in plan mode, or ran no")
    print("  command and wrote no file, so no scenario ran. The runner or the host is")
    print("  at fault, not the skill under test; its grades are absent, not failing.")
    print(f"    Permission mode in effect: {mode}")
    if mode_overridden(summary, requested):
        print(f"    Permission mode requested: {requested}"
              " (something on this host overrode the runner's flag)")
    if summary["exit_plan_mode"]:
        print("    The session presented a plan for approval (ExitPlanMode) and stopped.")
    subtype = summary["result_subtype"] or "none (the session left no result message)"
    if summary["result_is_error"]:
        subtype += ", reported as an error"
    print(f"    Session result: {subtype}")
    print(f"    Tool calls: {summary['tool_calls']}"
          f" ({summary['executing_calls']} that run commands or change files,"
          f" {summary['executing_calls_ran']} of them ran)")
    print(f"    Permission denials: {summary['permission_denials']}")
    print(f"    Transcript: {transcript}")
    return EXIT_NOT_EXECUTED


def main(argv):
    if len(argv) < 3 or argv[1] not in ("verdict", "result-text", "report"):
        print(__doc__.strip(), file=sys.stderr)
        return EXIT_UNREADABLE
    command, transcript = argv[1], argv[2]
    try:
        events = read_events(transcript)
    except OSError as exc:
        print(f"classify-eval-session: cannot read {transcript}: {exc}", file=sys.stderr)
        if command == "report":
            summary = classify([])
            return report(summary, transcript, None)
        return EXIT_UNREADABLE

    summary = classify(events)
    if command == "verdict":
        print(json.dumps(summary, indent=2))
        return 0
    if command == "result-text":
        if summary["result_text"]:
            print(summary["result_text"])
        return 0
    requested = argv[3] if len(argv) > 3 else None
    return report(summary, transcript, requested)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

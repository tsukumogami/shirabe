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
Edit, MultiEdit, NotebookEdit) came back without an error and was not a
permission denial. Calls made by subagents count: they appear in the same
transcript.

Usage:
  classify-eval-session.py verdict <transcript>
      Print the classification as JSON. Exit 0, or 2 when the transcript
      cannot be read.
  classify-eval-session.py result-text <transcript>
      Print the session's final message, which is what `claude -p` prints in
      its default text mode. Exit 0.
  classify-eval-session.py report <transcript> [<requested-mode>]
      Print the named failure when the session did not execute.
      Exit 0 when it executed, 4 when it did not, 2 when the transcript holds
      nothing to decide from.
"""

import json
import sys

EXECUTING_TOOLS = ("Bash", "Write", "Edit", "MultiEdit", "NotebookEdit")

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


def classify(events):
    mode = None
    tool_uses = {}  # id -> tool name
    results = {}  # tool_use_id -> is_error
    denied = set()
    # Subagents can end with result messages of their own, so every result's
    # denials count, and the final message is the top-level session's.
    result_events = []
    result_event = None

    for event in events:
        kind = event.get("type")
        if kind == "system" and event.get("subtype") == "init" and mode is None:
            mode = event.get("permissionMode")
        elif kind == "assistant":
            for block in content_blocks(event):
                if isinstance(block, dict) and block.get("type") == "tool_use":
                    tool_uses[block.get("id")] = block.get("name", "")
        elif kind == "user":
            for block in content_blocks(event):
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    results[block.get("tool_use_id")] = bool(block.get("is_error"))
        elif kind == "result":
            result_events.append(event)
            if event.get("parent_tool_use_id") is None or result_event is None:
                result_event = event

    for event in result_events:
        for denial in event.get("permission_denials") or []:
            if isinstance(denial, dict) and denial.get("tool_use_id"):
                denied.add(denial["tool_use_id"])

    executing = [i for i, name in tool_uses.items() if name in EXECUTING_TOOLS]
    succeeded = [
        i for i in executing
        if i in results and not results[i] and i not in denied
    ]

    if not events or (mode is None and result_event is None and not tool_uses):
        verdict = "unknown"
    elif succeeded:
        verdict = "executed"
    else:
        verdict = "not_executed"

    return {
        "verdict": verdict,
        "permission_mode": mode,
        "exit_plan_mode": any(n == "ExitPlanMode" for n in tool_uses.values()),
        "tool_calls": len(tool_uses),
        "executing_calls": len(executing),
        "executing_calls_succeeded": len(succeeded),
        "permission_denials": len(denied),
        "result_text": (result_event or {}).get("result") or "",
    }


def report(summary, transcript, requested):
    if summary["verdict"] == "executed":
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
    print("  The claude session this runner started ran no command and wrote no file,")
    print("  so no scenario ran. The runner or the host is at fault, not the skill")
    print("  under test; its grades are absent, not failing.")
    print(f"    Permission mode in effect: {mode}")
    if requested and summary["permission_mode"] and summary["permission_mode"] != requested:
        print(f"    Permission mode requested: {requested}"
              " (something on this host overrode the runner's flag)")
    if summary["exit_plan_mode"]:
        print("    The session presented a plan for approval (ExitPlanMode) and stopped.")
    print(f"    Tool calls: {summary['tool_calls']}"
          f" ({summary['executing_calls']} that run commands or change files,"
          f" none succeeded)")
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

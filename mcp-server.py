#!/usr/bin/env python3
"""Minimal MCP server over get-lectures.sh, for Claude Desktop.

Line-delimited JSON-RPC 2.0 on stdio, standard library only, so it runs on
/usr/bin/python3 with no venv to maintain. Idle cost is one process blocked in
readline(). Runs are detached and never waited on: transcription takes minutes,
which is far longer than a tool call should hold, and a supervised child would
die with the app.

stdout carries JSON-RPC and nothing else. Diagnostics go to stderr.
"""

import glob
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "get-lectures.sh")
HOME = os.path.expanduser("~")
VAULT = os.path.join(HOME, "Obsidian", "MyVault", "1_Projects")
STATE = os.path.join(HOME, "Library", "Logs", "echo360-transcriber")
CURRENT = os.path.join(STATE, "current.json")

# Claude Desktop hands its children PATH=/usr/bin:/bin:/usr/sbin:/sbin, which
# has neither parakeet-mlx (a uv tool in ~/.local/bin) nor ffmpeg (Homebrew).
# Without this the run dies at the script's own preflight check.
TOOL_PATH = ":".join([
    os.path.join(HOME, ".local", "bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin", "/bin", "/usr/sbin", "/sbin",
])


def alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def read_current():
    try:
        with open(CURRENT) as fh:
            return json.load(fh)
    except (IOError, ValueError):
        return None


def tail(path, n):
    try:
        with open(path, errors="replace") as fh:
            return fh.read().splitlines()[-n:]
    except IOError:
        return []


def tool_update_transcripts(args):
    run = read_current()
    if run and alive(run["pid"]):
        return ("A run is already in progress (%s, pid %d, started %s).\n"
                "Two transcriptions at once would exhaust memory. "
                "Check run_status." % (run["run_id"], run["pid"],
                                       time.ctime(run["started"])))

    unit = (args.get("unit") or "").strip()
    fast = bool(args.get("fast"))

    os.makedirs(STATE, exist_ok=True)
    run_id = time.strftime("run-%Y%m%d-%H%M%S")
    log = os.path.join(STATE, run_id + ".log")

    argv = [SCRIPT]
    if fast:
        argv.append("--fast")
    if unit:
        argv.append(unit)

    env = dict(os.environ)
    env["PATH"] = TOOL_PATH
    env["HOME"] = HOME

    with open(log, "w") as fh:
        proc = subprocess.Popen(
            argv,
            stdout=fh, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
            start_new_session=True,   # macOS has no setsid(1); outlives the app
            cwd=HERE, env=env,
        )

    with open(CURRENT, "w") as fh:
        json.dump({"run_id": run_id, "pid": proc.pid, "unit": unit,
                   "fast": fast, "started": time.time(), "log": log}, fh)

    return ("Started %s (pid %d) for %s%s.\n"
            "It runs in the background and takes minutes to hours; this call "
            "does not wait. Use run_status to follow it.\n"
            "Safari must be running, and macOS may ask to let Claude control "
            "it the first time.\nLog: %s"
            % (run_id, proc.pid, unit or "the section page open in Safari",
               " (fast model)" if fast else "", log))


def tool_run_status(args):
    run = read_current()
    if not run:
        return "No run has been started yet."

    n = int(args.get("tail") or 30)
    lines = tail(run["log"], n)
    elapsed = int(time.time() - run["started"])
    label = "%s for %s" % (run["run_id"], run["unit"] or "the open section page")

    if alive(run["pid"]):
        state = "running (%dm %ds elapsed)" % (elapsed // 60, elapsed % 60)
    elif any(ln.strip() == "Done." for ln in tail(run["log"], 5)):
        state = "finished successfully after %dm %ds" % (elapsed // 60, elapsed % 60)
    else:
        state = "stopped without finishing after %dm %ds" % (elapsed // 60, elapsed % 60)

    return "%s: %s\n\nLast %d log line(s):\n%s" % (
        label, state, len(lines), "\n".join(lines) or "(log is empty)")


def tool_list_transcripts(args):
    unit = (args.get("unit") or "").strip()
    pattern = os.path.join(VAULT, "*_" + unit if unit else "*", "transcripts")
    out = []
    for folder in sorted(glob.glob(pattern)):
        names = sorted(e.name for e in os.scandir(folder)
                       if e.is_file() and e.name.endswith(".md"))
        if not names and not unit:
            continue
        out.append("%s (%d)\n  %s" % (
            os.path.basename(os.path.dirname(folder)), len(names),
            "\n  ".join(names) or "(none)"))
    if not out:
        return "No transcripts found under %s." % VAULT
    return "\n\n".join(out)


TOOLS = [
    {
        "name": "update_transcripts",
        "description": (
            "Download any new Echo360 lecture audio for a unit and transcribe "
            "it into the Obsidian vault. Signs in to Echo360 through Safari "
            "automatically. Returns immediately; the run continues in the "
            "background, so follow it with run_status."),
        "inputSchema": {
            "type": "object",
            "properties": {
                "unit": {"type": "string", "description":
                         "Unit code, e.g. CITS1402. Omit to use the Echo360 "
                         "section page already open in Safari."},
                "fast": {"type": "boolean", "description":
                         "Use the fast model: about twice as quick, but it "
                         "misspells subject vocabulary."},
            },
        },
        "handler": tool_update_transcripts,
    },
    {
        "name": "run_status",
        "description": "Progress of the most recent update_transcripts run.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tail": {"type": "integer", "description":
                         "How many log lines to show (default 30)."},
            },
        },
        "handler": tool_run_status,
    },
    {
        "name": "list_transcripts",
        "description": "Transcripts already in the Obsidian vault.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "unit": {"type": "string", "description":
                         "Unit code to limit to. Omit for every unit."},
            },
        },
        "handler": tool_list_transcripts,
    },
]


def handle(req):
    method = req.get("method")
    params = req.get("params") or {}

    if method == "initialize":
        return {
            "protocolVersion": params.get("protocolVersion") or "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "echo360-transcriber", "version": "1.0.0"},
        }

    if method == "tools/list":
        return {"tools": [{k: v for k, v in t.items() if k != "handler"}
                          for t in TOOLS]}

    if method == "tools/call":
        name = params.get("name")
        for tool in TOOLS:
            if tool["name"] == name:
                try:
                    text = tool["handler"](params.get("arguments") or {})
                    return {"content": [{"type": "text", "text": text}]}
                except Exception as exc:      # surface, never crash the server
                    return {"content": [{"type": "text",
                                         "text": "%s failed: %s" % (name, exc)}],
                            "isError": True}
        raise LookupError("no such tool: %s" % name)

    raise LookupError("unknown method: %s" % method)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue

        rid = req.get("id")
        try:
            result = handle(req)
            reply = {"jsonrpc": "2.0", "id": rid, "result": result}
        except LookupError as exc:
            reply = {"jsonrpc": "2.0", "id": rid,
                     "error": {"code": -32601, "message": str(exc)}}
        except Exception as exc:
            reply = {"jsonrpc": "2.0", "id": rid,
                     "error": {"code": -32603, "message": str(exc)}}

        if rid is None:          # a notification; nothing to answer
            continue
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

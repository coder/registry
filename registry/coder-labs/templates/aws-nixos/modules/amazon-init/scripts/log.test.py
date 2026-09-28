"""Run directly: python3 scripts/log.test.py (no Terraform provider needed)."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

LIBRARY = Path(__file__).with_name("log.sh")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    curl = root / "curl"
    curl.write_text("""#!/usr/bin/env python3
import fcntl, json, os, sys
args = sys.argv
body = args[args.index('--data-binary') + 1]
with open(os.environ['REQUESTS'], 'a') as output:
    fcntl.flock(output, fcntl.LOCK_EX)
    output.write(json.dumps({'url': args[args.index('-X') + 2], 'body': body}) + '\\n')
if 'POST' in args: print('201', end='')
""")
    curl.chmod(0o755)
    env = os.environ | {
        "PATH": str(root) + ":" + os.environ["PATH"],
        "REQUESTS": str(root / "requests"),
        "CODER_LOG_STATE_DIR": str(root / "state"),
        "CODER_LOG_BUDGET": "4000",
        "CODER_ACCESS_URL": "https://coder.example",
        "CODER_AGENT_TOKEN": "token",
        "CODER_LOG_SOURCE_ID": "id",
        "CODER_LOG_REGISTRATION": json.dumps({"id": "id", "display_name": 'quoted " name 🐈', "icon": "/icon"}),
    }
    missing = subprocess.run(["bash", "--noprofile", "--norc", "-c", f'PATH={root / "empty"}; source {LIBRARY}; coder_log_init'], env=env, timeout=2)
    assert missing.returncode == 1
    registration = subprocess.run(
        ["bash", "--noprofile", "--norc", "-e", "-u", "-c", f"source {LIBRARY}; coder_log_init"], env=env, capture_output=True
    )
    assert registration.returncode == 0, registration.stderr
    env["CODER_LOG_READY"] = "1"
    message = 'quote " backslash \\ tab\t CR\r unicode 🐈'
    program = f'source {LIBRARY}; coder_log info "$MESSAGE"; printf "slow\\nlast" | coder_log_pipe info'
    env["MESSAGE"] = message
    subprocess.run(["bash", "--noprofile", "--norc", "-e", "-u", "-c", program], env=env, check=True)
    requests = [json.loads(line) for line in (root / "requests").read_text().splitlines()]
    assert json.loads(requests[0]["body"])["display_name"] == 'quoted " name 🐈'
    logs = [item for request in requests[1:] for item in json.loads(request["body"])["logs"]]
    assert [entry["output"] for entry in logs] == [message, "slow", "last"]
    # Invalid leading, truncated, overlong, and surrogate encodings must not
    # produce raw invalid UTF-8 in the JSON sent to Coder.
    malformed = f"source {LIBRARY}; coder_log info \"$(printf 'bad\\377\\360\\237\\300\\257\\355\\240\\200')\""
    subprocess.run(["bash", "--noprofile", "--norc", "-e", "-u", "-c", malformed], env=env, check=True)
    requests = [json.loads(line) for line in (root / "requests").read_text().splitlines()]
    malformed_output = json.loads(requests[-1]["body"])["logs"][0]["output"]
    assert malformed_output.startswith("bad\ufffd") and "\ufffd" in malformed_output
    assert malformed_output.encode("utf-8").decode("utf-8") == malformed_output
    before = len(requests)
    workers = [subprocess.Popen(["bash", "--noprofile", "--norc", "-e", "-u", "-c", f'source {LIBRARY}; for ((i=0;i<30;i++)); do coder_log info "message-🐈-$i"; done'], env=env) for _ in range(4)]
    assert all(worker.wait() == 0 for worker in workers)
    requests = [json.loads(line) for line in (root / "requests").read_text().splitlines()]
    assert len(requests) > before
    charged = sum(len(request["body"].encode()) for request in requests[1:])
    assert charged <= 4000, charged
    assert int((root / "state" / "log-budget").read_text()) == charged
    print("log registration, JSON controls/Unicode/malformed UTF-8, timeout/EOF and concurrent budget: OK")

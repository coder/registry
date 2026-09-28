"""Run directly: python3 scripts/bootstrap.test.py (needs passwordless sudo)."""
import base64
import gzip
import os
from pathlib import Path
import re
import subprocess
import tempfile

TEMPLATE = Path(__file__).with_name("bootstrap.sh.tftpl")
LIBRARY = Path(__file__).with_name("log.sh")


def b64(text):
    return base64.b64encode((text.encode() if isinstance(text, str) else text)).decode()


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    root.chmod(0o755)
    fake = root / "bin"
    fake.mkdir()
    runtime = root / "runtime"
    marker = root / "unit"
    active = root / "active"
    injected = root / "injected"
    file_path = root / "quote'$(touch injected) 🐈"
    (fake / "systemctl").write_text(f'''#!/usr/bin/env bash
case "$1" in
  show) if test -e '{marker}'; then echo nobody; fi ;;
  cat) test -e '{marker}' ;;
  is-active) test -e '{active}' ;;
  start) touch '{active}' ;;
esac
''')
    (fake / "hostnamectl").write_text("#!/usr/bin/env bash\nexit 0\n")
    (fake / "curl").write_text("#!/usr/bin/env bash\ncase \" $* \" in *POST*) printf 201;; esac\n")
    (fake / "sleep").write_text("#!/usr/bin/env bash\nexit 0\n")
    for command in fake.iterdir():
        command.chmod(0o755)
    source = TEMPLATE.read_text()
    substitutions = {
        "ARG_PATH": b64(str(fake)),
        "ARG_ACCESS_URL": b64("https://coder.example"),
        "ARG_AGENT_TOKEN": b64("token"),
        "ARG_RUNTIME_DIR": b64(str(runtime)),
        "ARG_LOG_SOURCE_ID": "id",
        "ARG_LOG_BUDGET": "4096",
        "ARG_HOSTNAME": b64("test-host"),
        "ARG_LOG_REGISTRATION_B64": b64('{"id":"id","display_name":"Boot","icon":"/icon"}'),
        "INIT_SCRIPT": "#!/usr/bin/env bash\necho init",
        "LOG_SH": LIBRARY.read_text(),
        "FACTS_JSON": '{"workspace":"test"}',
        "BOOT_SCRIPT": f"#!/usr/bin/env bash\ntouch '{marker}'",
    }
    pattern = r"%\{ for file in FILES ~\}(.*?)%\{ endfor ~\}"
    loop = re.search(pattern, source, re.S)
    assert loop
    source = source[:loop.start()] + loop.group(1).replace("${file.path}", b64(str(file_path))).replace("${file.content}", b64(gzip.compress(b"safe text"))) + source[loop.end():]
    for key, value in substitutions.items():
        source = source.replace("${" + key + "}", value)
    assert not re.search(r"\$\{(?:ARG_|file\.)", source)
    runtime.mkdir(mode=0o700)
    bootstrap = runtime / "bootstrap.sh"
    bootstrap.write_text(source)
    bootstrap.chmod(0o700)
    subprocess.run(["sudo", "-n", "chown", "root:root", str(runtime), str(bootstrap)], check=True)
    env = os.environ | {"PATH": str(fake) + ":" + os.environ["PATH"]}
    try:
        for boot in range(2):
            subprocess.run(["sudo", "-n", "env", "PATH=" + env["PATH"], "bash", str(bootstrap)], check=True, timeout=15)
            assert file_path.read_text() == "safe text"
            assert not injected.exists()
            assert runtime.stat().st_uid == 0 and runtime.stat().st_mode & 0o777 == 0o711
            assert bootstrap.stat().st_uid == 0 and (runtime / "boot.sh").stat().st_uid == 0
            assert (runtime / "boot.sh").stat().st_mode & 0o077 == 0
            for handoff in ("agent.env", "init.sh"):
                assert (runtime / handoff).stat().st_uid == 65534
            for attempt in (f"printf hacked >'{runtime}/boot.sh'", f"ln -sf /etc/passwd '{runtime}/boot.sh'"):
                failed = subprocess.run(["sudo", "-n", "-u", "nobody", "bash", "-c", attempt], capture_output=True)
                assert failed.returncode != 0, attempt
            subprocess.run(["sudo", "-n", "-u", "nobody", "cat", str(runtime / "agent.env")], stdout=subprocess.DEVNULL, check=True)
        # On a failed later boot the wrapper still attempts to start the agent.
        broken = source.replace(f"touch '{marker}'", "exit 7")
        subprocess.run(["sudo", "-n", "tee", str(bootstrap)], input=broken.encode(), stdout=subprocess.DEVNULL, check=True)
        subprocess.run(["sudo", "-n", "rm", str(active)], check=True)
        failed = subprocess.run(["sudo", "-n", "env", "PATH=" + env["PATH"], "bash", str(bootstrap)], timeout=15)
        assert failed.returncode == 7 and active.exists()
        print("two boots and failed boot: root scripts protected; non-root handoff; malicious path inert; agent attempted: OK")
    finally:
        subprocess.run(["sudo", "-n", "chown", "-R", str(os.getuid()), str(root)], check=True)

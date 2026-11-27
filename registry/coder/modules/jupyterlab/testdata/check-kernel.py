"""Install a local wheel through !pip in a real Jupyter kernel, then import it."""

import http.cookiejar
import json
import sys
import time
import urllib.error
import urllib.request
import uuid
import zipfile

import websocket

port = int(sys.argv[1])
base_url = f"http://127.0.0.1:{port}"
wheel_path = "/tmp/registry_probe-1.0-py3-none-any.whl"
with zipfile.ZipFile(wheel_path, "w") as wheel:
    wheel.writestr("registry_probe.py", "VALUE = 'installed-in-kernel'\n")
    wheel.writestr("registry_probe-1.0.dist-info/METADATA", "Metadata-Version: 2.1\nName: registry-probe\nVersion: 1.0\n")
    wheel.writestr("registry_probe-1.0.dist-info/WHEEL", "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n")
    wheel.writestr("registry_probe-1.0.dist-info/RECORD", "")

deadline = time.monotonic() + 60
while True:
    try:
        with urllib.request.urlopen(f"{base_url}/api", timeout=2):
            break
    except (urllib.error.URLError, TimeoutError):
        if time.monotonic() >= deadline:
            raise
        time.sleep(0.2)

cookies = http.cookiejar.CookieJar()
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
client.open(f"{base_url}/lab").close()
xsrf = next(cookie.value for cookie in cookies if cookie.name == "_xsrf")
request = urllib.request.Request(
    f"{base_url}/api/kernels", data=b'{"name":"python3"}',
    headers={"Content-Type": "application/json", "X-XSRFToken": xsrf},
)
with client.open(request) as response:
    kernel_id = json.load(response)["id"]

session_id = uuid.uuid4().hex
connection = websocket.create_connection(
    f"ws://127.0.0.1:{port}/api/kernels/{kernel_id}/channels?session_id={session_id}",
    origin=base_url, timeout=60,
    cookie="; ".join(f"{cookie.name}={cookie.value}" for cookie in cookies),
)
message_id = uuid.uuid4().hex
connection.send(json.dumps({
    "header": {"msg_id": message_id, "username": "test", "session": session_id,
               "msg_type": "execute_request", "version": "5.3"},
    "parent_header": {}, "metadata": {}, "channel": "shell",
    "content": {"code": f"!pip install --no-index --no-deps {wheel_path}\nimport registry_probe\nprint(registry_probe.VALUE)",
                "silent": False, "store_history": False, "user_expressions": {},
                "allow_stdin": False, "stop_on_error": True},
}))
try:
    replied = idle = False
    while not (replied and idle):
        message = json.loads(connection.recv())
        if message.get("parent_header", {}).get("msg_id") != message_id:
            continue
        if message["msg_type"] == "stream":
            print(message["content"]["text"], end="")
        if message["msg_type"] == "execute_reply":
            assert message["content"]["status"] == "ok", message["content"]
            replied = True
        if message["msg_type"] == "status" and message["content"]["execution_state"] == "idle":
            idle = True
finally:
    connection.close()
    client.open(urllib.request.Request(
        f"{base_url}/api/kernels/{kernel_id}", method="DELETE",
        headers={"X-XSRFToken": xsrf},
    )).close()

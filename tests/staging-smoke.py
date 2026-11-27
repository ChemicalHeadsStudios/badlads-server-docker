"""Exercise the real anonymous staging install without publishing game ports."""
import json
import socket
import subprocess
import time

NAME = "badlads-staging-smoke"
SERVER = "BadLads-CI-Staging-Smoke"
REQUEST = b"\xff\xff\xff\xffTSource Engine Query\x00"


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


try:
    docker("run", "-d", "--name", NAME, "--memory", "5g",
           "--security-opt", "no-new-privileges:true",
           "-e", "STEAMCMD_BETA=staging", "-e", f"SERVERNAME={SERVER}",
           "-e", "BADLADS_ARGS=-log -useperfthreads -unattended", "badlads:test")
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        state = json.loads(docker("inspect", NAME))[0]
        if not state["State"]["Running"]:
            raise RuntimeError(f"Staging exited before readiness: {state['State']}")
        address = state["NetworkSettings"]["IPAddress"]
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as query:
            query.settimeout(2)
            try:
                query.sendto(REQUEST, (address, 27015))
                packet, _ = query.recvfrom(65535)
                if packet[:5] == b"\xff\xff\xff\xffA":
                    query.sendto(REQUEST + packet[5:9], (address, 27015))
                    packet, _ = query.recvfrom(65535)
                if packet[:5] == b"\xff\xff\xff\xffI":
                    name = packet[6:].split(b"\x00", 1)[0].decode("utf-8")
                    if name != SERVER:
                        raise RuntimeError(f"Unexpected A2S server name: {name}")
                    break
            except (TimeoutError, ConnectionError):
                pass
        time.sleep(3)
    else:
        raise TimeoutError("Staging never answered a Steam A2S_INFO query")

    manifest = docker("exec", NAME, "cat", "/data/badlads/steamapps/appmanifest_1203110.acf")
    if '"staging"' not in manifest:
        raise RuntimeError("Installed Steam manifest does not record the staging branch")
    print("PASS: anonymous staging installed and answered Steam A2S_INFO with the configured name")
    docker("stop", "--time", "60", NAME)
    state = json.loads(docker("inspect", NAME))[0]["State"]
    if state["OOMKilled"] or state["ExitCode"] not in (0, 143):
        raise RuntimeError(f"Server did not shut down gracefully: {state}")
    print(f"PASS: server stopped without SIGKILL (exit {state['ExitCode']})")
finally:
    # No game artifacts or full logs are uploaded; retain only bounded diagnostics.
    subprocess.run(["docker", "logs", "--tail", "100", NAME], check=False)
    subprocess.run(["docker", "rm", "-f", NAME], check=False, stdout=subprocess.DEVNULL)

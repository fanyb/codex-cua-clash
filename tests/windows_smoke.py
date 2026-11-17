import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass"]
INSTALLER = [*POWERSHELL, "-File", str(ROOT / "setup-windows.ps1")]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=30, **kwargs)


def check_runtime(wrapper, runtime, port):
    env = dict(os.environ, NODE_REPL_NODE_PATH=str(runtime / "node.exe"))
    for key in ("HTTPS_PROXY", "NO_PROXY", "NODE_USE_ENV_PROXY"):
        env.pop(key, None)
    args = ['space here', 'quote"here', 'ends with\\']
    payload = b'{"jsonrpc":"2.0","id":1}\r\n'
    for surfaces, proxy in [("browser,computer", f"http://127.0.0.1:{port}"), ("computer", "")]:
        result = subprocess.run(
            [str(wrapper), *args], input=payload, capture_output=True, timeout=10,
            env=dict(env, CUA_REPL_ENABLED_SURFACES=surfaces),
        )
        assert result.returncode == 17, result.stderr
        assert result.stdout == payload, result.stdout
        actual = result.stderr.decode().splitlines()
        assert actual == [f"proxy={proxy}", f"flag={'1' if proxy else ''}", *args], actual


with tempfile.TemporaryDirectory(prefix="codex cua test ") as temp, socket.socket() as listener:
    root = Path(temp)
    runtime = root / "runtime"
    runtime.mkdir()
    probe = root / "probe.cs"
    probe.write_text(
        """using System;
class Probe {
    static int Main(string[] args) {
        Console.Error.WriteLine("proxy=" + Environment.GetEnvironmentVariable("HTTPS_PROXY"));
        Console.Error.WriteLine("flag=" + Environment.GetEnvironmentVariable("NODE_USE_ENV_PROXY"));
        foreach (string arg in args) Console.Error.WriteLine(arg);
        Console.OpenStandardInput().CopyTo(Console.OpenStandardOutput());
        return 17;
    }
}
""",
        encoding="ascii",
    )
    (runtime / "node.exe").touch()
    run(*POWERSHELL, "-Command", f"Add-Type -Path '{probe}' -OutputAssembly '{runtime / 'node_repl.exe'}' -OutputType ConsoleApplication")

    preset = root / "plugins/cache/openai-bundled/unified-computer-use/test/.mcp.json"
    preset.parent.mkdir(parents=True)
    preset.write_text(json.dumps({"mcpServers": {"cua_repl": {"env": {
        "NODE_REPL_NODE_PATH": str(runtime / "node.exe"),
    }}}}), encoding="ascii")
    # The isolated configuration is supplied only to the installer on the ephemeral CI runner.
    # It leaves the actual user profile and Codex fixture paths out of the test.
    installer = root / "setup-windows.ps1"
    source = (ROOT / "setup-windows.ps1").read_text(encoding="ascii")
    installer.write_text(source.replace("$env:CODEX_HOME", "$env:CUA_CLASH_TEST_CODEX_ROOT"), encoding="ascii")
    (root / "windows").mkdir()
    (root / "windows/NodeReplProxy.cs").write_bytes((ROOT / "windows/NodeReplProxy.cs").read_bytes())
    env = dict(os.environ, CUA_CLASH_TEST_CODEX_ROOT=temp)
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    port = listener.getsockname()[1]
    wrapper = Path(os.environ["LOCALAPPDATA"]) / "CodexCuaClash/codex-cua-clash.exe"
    install = [*POWERSHELL, "-File", str(installer)]
    run(*install, "-Port", str(port), env=env)
    try:
        check_runtime(wrapper, runtime, port)
        blocked = subprocess.run([*install, "-Port", str(port)], env=env, capture_output=True, timeout=20)
        assert blocked.returncode != 0
    finally:
        run(*INSTALLER, "-Action", "uninstall")
    assert not wrapper.exists()
    assert not run(*POWERSHELL, "-Command", "[Environment]::GetEnvironmentVariable('CODEX_NODE_REPL_PATH','User')").stdout.strip()

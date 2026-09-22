import json
import subprocess
import tempfile
from pathlib import Path

def scan_networks(interface_name):
    app = Path(__file__).resolve().parent / "WLAN Scan Helper.app"
    if not (app / "Contents/MacOS/WLANScanHelper").is_file():
        raise RuntimeError("尚未构建定位扫描助手。请在项目目录执行 bash build_macos_helper.sh，再重新扫描。")
    with tempfile.TemporaryDirectory(prefix="wlan-scan-") as directory:
        output = Path(directory) / "scan.json"
        subprocess.run(
            ["/usr/bin/open", "-n", "-W", str(app), "--args", str(output), interface_name],
            check=True, timeout=150,
        )
        if not output.exists():
            raise RuntimeError("扫描助手已退出，但没有返回结果。请重新扫描。")
        result = json.loads(output.read_text())
    if result.get("error"):
        raise RuntimeError(result["error"])
    return result["networks"]

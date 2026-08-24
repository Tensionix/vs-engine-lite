from __future__ import annotations

from pathlib import Path
import argparse
import os
import socket
import subprocess
import sys
import time
import webbrowser


ROOT = Path(__file__).resolve().parents[2]
APP_PY = ROOT / "system_core" / "ui_nicegui" / "app.py"
GUI_PID_FILE = ROOT / "logs" / "gui_server.pid"
APP_ICON = ROOT / "system_core" / "icons" / "app.ico"


def get_window_icon() -> str | None:
    icon = Path(os.environ.get("AUDION_APP_ICON", str(APP_ICON)))
    return str(icon) if icon.exists() else None


def configure_windows_taskbar() -> None:
    if os.name != "nt":
        return
    app_id = os.environ.get("AUDION_APP_ID")
    if not app_id:
        clean = "".join(ch if ch.isalnum() else "." for ch in ROOT.name).strip(".")
        app_id = f"Audion.Tools.{clean or 'App'}"
    try:
        import ctypes

        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(app_id)
    except Exception:
        pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audion VS Engine GUI window.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--browser", action="store_true", help="Open in the default browser instead of pywebview.")
    parser.add_argument("--gui", default="edgechromium", help="pywebview backend to use on Windows.")
    return parser.parse_args()


def port_is_open(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.3)
        return sock.connect_ex((host, port)) == 0


def choose_port(host: str, preferred_port: int) -> int:
    port = preferred_port
    while port_is_open(host, port):
        port += 1
    return port


def process_exists(pid: int) -> bool:
    try:
        import ctypes

        handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if handle:
            ctypes.windll.kernel32.CloseHandle(handle)
            return True
        return False
    except Exception:
        return False


def hidden_subprocess_kwargs() -> dict[str, object]:
    if os.name != "nt":
        return {}
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = 0
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    return {"startupinfo": startupinfo, "creationflags": flags}


def cleanup_previous_server() -> None:
    try:
        if not GUI_PID_FILE.exists():
            return
        pid = int(GUI_PID_FILE.read_text(encoding="utf-8").strip())
        if process_exists(pid):
            subprocess.run(
                ["taskkill", "/PID", str(pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                **hidden_subprocess_kwargs(),
            )
        GUI_PID_FILE.unlink(missing_ok=True)
    except Exception:
        pass


def wait_for_server(host: str, port: int, timeout: float = 20.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if port_is_open(host, port):
            return True
        time.sleep(0.2)
    return False


def start_server(host: str, port: int) -> subprocess.Popen[str]:
    logs = ROOT / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    stdout = (logs / "gui_server_stdout.log").open("w", encoding="utf-8")
    stderr = (logs / "gui_server_stderr.log").open("w", encoding="utf-8")
    env = os.environ.copy()
    env.setdefault("PYTHONUTF8", "1")
    env["PYTHONIOENCODING"] = "utf-8"
    env.setdefault("PYTHONUNBUFFERED", "1")
    server = subprocess.Popen(
        [sys.executable, "-u", str(APP_PY), "--host", host, "--port", str(port), "--no-browser"],
        cwd=str(ROOT),
        stdout=stdout,
        stderr=stderr,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
        **hidden_subprocess_kwargs(),
    )
    GUI_PID_FILE.write_text(str(server.pid), encoding="utf-8")
    return server


def stop_server(server: subprocess.Popen[str] | None) -> None:
    if server and server.poll() is None:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/PID", str(server.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                **hidden_subprocess_kwargs(),
            )
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        else:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
    if server:
        GUI_PID_FILE.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    os.environ.setdefault("PYWEBVIEW_LOG", "error")
    configure_windows_taskbar()
    cleanup_previous_server()
    port = choose_port(args.host, args.port)
    url = f"http://{args.host}:{port}/"
    server = start_server(args.host, port)

    if not wait_for_server(args.host, port):
        print(f"GUI server did not start: {url}")
        stop_server(server)
        return 1

    if args.browser:
        try:
            webbrowser.open(url)
            print(f"GUI server is running: {url}")
            print("Close this console window to stop the server.")
            server.wait()
            return 0
        except KeyboardInterrupt:
            return 0
        finally:
            stop_server(server)

    try:
        import webview  # type: ignore
    except Exception as exc:
        print(f"pywebview is not available: {exc}")
        print(f"Browser fallback is available explicitly: {Path(__file__).name} --browser")
        stop_server(server)
        return 1

    try:
        webview.create_window(
            "Audion VS Engine Lite",
            url,
            width=1600,
            height=900,
            min_size=(1180, 720),
        )
        webview.start(
            gui=args.gui,
            debug=False,
            private_mode=False,
            storage_path=str(ROOT / "._runtime" / "webview"),
            icon=get_window_icon(),
        )
        return 0
    except Exception as exc:
        print(f"pywebview failed: {exc}")
        print(f"Browser fallback is available explicitly: {Path(__file__).name} --browser")
        return 1
    finally:
        stop_server(server)


if __name__ == "__main__":
    raise SystemExit(main())

"""Self-healing for the portable bundle.

The pip-generated `Scripts/*.exe` launchers (`vspipe.exe`, `vsrepo.exe`, etc.)
embed an absolute shebang `#!"<full path to python.exe>"` between the launcher
stub and the trailing zip payload. After the project folder is moved to a
different drive/letter/path, that absolute path no longer exists and every
shim silently exits with code 1 and no output.

`install\\Repair-PipShims.cmd` is the canonical fix. To make portability
zero-touch, the orchestrator calls `ensure_pip_shims_repaired()` once per
process at the top of `main.py` / `doctor.py`. It does a tiny ~8 KB read of
`vspipe.exe`, compares the embedded shebang path to the current
`system_core/vapoursynth/python.exe`, and on mismatch invokes the repair
script silently. No-op if shebang is already correct or vspipe is missing.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .paths import PATHS

_FLAG_ENV = "AUDION_SELFHEAL_DONE"


def _find_embedded_shebang(vspipe: Path) -> str | None:
    """Return the python.exe path baked into vspipe.exe, or None if not a pip shim."""
    try:
        head = vspipe.read_bytes()
    except OSError:
        return None
    pk = head.find(b"PK\x03\x04")
    if pk < 0:
        return None
    sh = head.rfind(b'#!"', 0, pk)
    if sh < 0:
        return None
    end = head.find(b"\n", sh, pk)
    if end < 0:
        return None
    line = head[sh + 3 : end].rstrip(b"\r\"")
    try:
        return line.decode("ascii", errors="strict")
    except UnicodeDecodeError:
        return None


def ensure_pip_shims_repaired() -> str:
    """Detect-and-repair pip shim shebangs after a project move.

    Returns a short status string for logging:
      "ok"          -- shebang already matches current python.exe
      "repaired"    -- mismatch found and Repair-PipShims invoked successfully
      "skipped"     -- vspipe.exe missing or not a pip shim (nothing to do)
      "no-repair"   -- mismatch found but Repair-PipShims.cmd is missing
      "repair-failed:<rc>" -- repair script ran and exited non-zero
    """
    # Idempotent across child processes within a single CLI run.
    if os.environ.get(_FLAG_ENV) == "1":
        return "ok"

    vspipe = PATHS.vspipe
    py_exe = PATHS.vs_python
    if not (vspipe.exists() and py_exe.exists()):
        os.environ[_FLAG_ENV] = "1"
        return "skipped"

    embedded = _find_embedded_shebang(vspipe)
    if embedded is None:
        os.environ[_FLAG_ENV] = "1"
        return "skipped"

    current = str(py_exe)
    if embedded.casefold() == current.casefold():
        os.environ[_FLAG_ENV] = "1"
        return "ok"

    # Mismatch: project was moved. Invoke Repair-PipShims.cmd silently.
    repair_cmd = PATHS.root / "install" / "Repair-PipShims.cmd"
    if not repair_cmd.exists():
        return "no-repair"

    try:
        rc = subprocess.run(
            [str(repair_cmd), "/NOPAUSE"],
            capture_output=True,
            check=False,
            shell=False,
            cwd=str(PATHS.root),
        ).returncode
    except OSError:
        return "no-repair"

    os.environ[_FLAG_ENV] = "1"
    if rc == 0:
        return "repaired"
    return f"repair-failed:{rc}"

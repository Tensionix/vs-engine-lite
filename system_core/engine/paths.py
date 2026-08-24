"""Canonical project paths. Resolves once at import time."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ProjectPaths:
    root: Path
    runtime_python: Path     # orchestrator embedded Python
    fzf: Path
    pwsh: Path
    vs_dir: Path
    vs_python: Path          # VS-host embedded Python
    vspipe: Path
    vsrepo: Path             # Scripts/vsrepo.exe
    ffmpeg: Path
    ffprobe: Path
    presets_dir: Path
    config_dir: Path
    input_dir: Path
    output_dir: Path
    logs_dir: Path
    runtime_temp: Path       # ._runtime/

    def assert_engine_ready(self) -> None:
        """Raise RuntimeError listing whatever is missing."""
        missing = []
        for label, p in [
            ("VS-host Python", self.vs_python),
            ("vspipe.exe", self.vspipe),
            ("ffmpeg.exe", self.ffmpeg),
            ("ffprobe.exe", self.ffprobe),
        ]:
            if not p.exists():
                missing.append(f"{label} -> {p}")
        if missing:
            raise RuntimeError(
                "Engine not ready, missing:\n  " + "\n  ".join(missing)
                + "\n\nRun builder_main.cmd -> [10..12] install steps."
            )


def _resolve() -> ProjectPaths:
    # system_core/engine/paths.py -> project root is parents[2]
    here = Path(__file__).resolve()
    root = here.parents[2]
    return ProjectPaths(
        root=root,
        runtime_python=root / "runtime" / "python.exe",
        fzf=root / "system_core" / "fzf.exe",
        pwsh=root / "system_core" / "powershell" / "pwsh.exe",
        vs_dir=root / "system_core" / "vapoursynth",
        vs_python=root / "system_core" / "vapoursynth" / "python.exe",
        vspipe=root / "system_core" / "vapoursynth" / "Scripts" / "vspipe.exe",
        vsrepo=root / "system_core" / "vapoursynth" / "Scripts" / "vsrepo.exe",
        ffmpeg=root / "Tools" / "ffmpeg" / "bin" / "ffmpeg.exe",
        ffprobe=root / "Tools" / "ffmpeg" / "bin" / "ffprobe.exe",
        presets_dir=root / "system_core" / "presets",
        config_dir=root / "config",
        input_dir=root / "input",
        output_dir=root / "output",
        logs_dir=root / "logs",
        runtime_temp=root / "._runtime",
    )


PATHS: ProjectPaths = _resolve()

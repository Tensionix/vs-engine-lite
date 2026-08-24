"""ffprobe wrapper: return parsed JSON for a media file."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from .paths import PATHS


def probe(path: Path, timeout: int = 30) -> dict:
    """Return ffprobe -show_format -show_streams as a dict.

    Raises RuntimeError on failure.
    """
    if not path.exists():
        raise FileNotFoundError(path)
    cmd = [
        str(PATHS.ffprobe),
        "-hide_banner", "-loglevel", "error",
        "-print_format", "json",
        "-show_format", "-show_streams",
        str(path),
    ]
    cp = subprocess.run(
        cmd, capture_output=True, text=True, timeout=timeout, errors="replace"
    )
    if cp.returncode != 0:
        raise RuntimeError(f"ffprobe failed (exit {cp.returncode}):\n{cp.stderr}")
    return json.loads(cp.stdout or "{}")


def video_summary(path: Path) -> dict:
    """Compact summary: width/height/fps/duration/codec/pix_fmt."""
    info = probe(path)
    fmt = info.get("format", {})
    streams = info.get("streams", [])
    v = next((s for s in streams if s.get("codec_type") == "video"), {})
    a = next((s for s in streams if s.get("codec_type") == "audio"), None)

    fps_raw = v.get("r_frame_rate", "0/1")
    try:
        n, d = fps_raw.split("/")
        fps = int(n) / int(d) if int(d) else 0.0
    except Exception:
        fps = 0.0

    return {
        "path": str(path),
        "size_bytes": int(fmt.get("size", 0)) if fmt.get("size") else None,
        "duration_s": float(fmt.get("duration", 0) or 0),
        "video": {
            "codec": v.get("codec_name"),
            "width": v.get("width"),
            "height": v.get("height"),
            "pix_fmt": v.get("pix_fmt"),
            "fps": round(fps, 4),
            "nb_frames": int(v.get("nb_frames")) if str(v.get("nb_frames", "")).isdigit() else None,
            "color_primaries": v.get("color_primaries"),
            "color_transfer":  v.get("color_transfer"),
            "color_space":     v.get("color_space"),
            "color_range":     v.get("color_range"),
        },
        "audio": ({"codec": a.get("codec_name"), "channels": a.get("channels"), "sample_rate": a.get("sample_rate")} if a else None),
    }

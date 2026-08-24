"""Per-run JSON report writer."""
from __future__ import annotations

import datetime as _dt
import json
import re
from pathlib import Path

from .paths import PATHS


def _slugify(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9_.-]+", "-", s)
    return s.strip("-") or "run"


def write_report(report: dict, *, palette: str, preset: str, input_path: Path) -> Path:
    """Write a JSON report into logs/, return the report path."""
    PATHS.logs_dir.mkdir(parents=True, exist_ok=True)
    ts = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    name = f"{ts}__{_slugify(palette)}__{_slugify(preset)}__{_slugify(input_path.stem)}.json"
    out = PATHS.logs_dir / name
    payload = {
        "timestamp": ts,
        "palette": palette,
        "preset": preset,
        "input": str(input_path),
        **report,
    }
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    return out

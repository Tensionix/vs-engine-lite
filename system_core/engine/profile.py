"""profile.py -- saved combinations of (palette, preset, params, encoder).

Built-in profiles are baked into this module. User profiles in
config/profiles/*.json are loaded on demand and OVERRIDE built-ins by name.

Profile shape:
    {
      "palette": "precision",
      "preset":  "shadow_denoise_sota",
      "params":  { ... preset-specific params ... },
      "encoder": "h264_crf14",
      "description": "Free-form text"
    }

When a profile contains keys outside this set, they are kept (forwards-compat).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


# --------------------------------------------------------- built-ins

BUILTINS: dict[str, dict[str, Any]] = {
    "shadow_clean_quick": {
        "palette":     "precision",
        "preset":      "shadow_denoise_sota",
        "params":      {
            "sigma":            2.5,
            "grain_back":       0.6,
            "shadow_threshold": 0.20,
            "transition":       0.10,
            "use_cuda":         "0",
        },
        "encoder":     "h264_crf14",
        "description": "Quick shadow-noise cleanup of dark digital footage",
    },
    "filmic_warm_35mm": {
        "palette":     "film_looks",
        "preset":      "film_35mm",
        "params":      {"stock": "250D", "intensity": 1.0},
        "encoder":     "h264_crf14",
        "description": "Kodak 250D 35mm filmic look at intensity 1.0",
    },
    "archival_master": {
        "palette":     "precision",
        "preset":      "archive_clean",
        "params":      {"denoise": "light", "range": 10},
        "encoder":     "prores_422hq",
        "description": "Neutral archival master, ProRes 422 HQ output",
    },
    "resolve_handoff": {
        "palette":     "precision",
        "preset":      "pregrade_prep",
        "params":      {"strength": "light"},
        "encoder":     "prores_422hq",
        "description": "Minimum-touch prep for DaVinci Resolve, ProRes 422 HQ",
    },
    "vhs_dreamy": {
        "palette":     "retro",
        "preset":      "vhs_crt",
        "params":      {"intensity": 1.2},
        "encoder":     "h264_crf14",
        "description": "VHS / CRT retro at intensity 1.2",
    },
}


# --------------------------------------------------------- loading / merging

def load_user_profiles(profiles_dir: Path) -> dict[str, dict[str, Any]]:
    """Read every *.json in `profiles_dir` and return them keyed by profile name.

    Profile name = the JSON object's "name" field if present, else filename stem.
    Files that fail to parse are skipped with a warning to stderr.
    """
    out: dict[str, dict[str, Any]] = {}
    if not profiles_dir.exists():
        return out
    import sys
    for f in sorted(profiles_dir.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
            name = data.get("name") or f.stem
            data.pop("name", None)
            out[name] = data
        except Exception as e:
            print(f"[warn] could not load profile {f.name}: {e}", file=sys.stderr)
    return out


def materialize_builtins(profiles_dir: Path, *, force: bool = False) -> list[Path]:
    """Write BUILTINS as editable JSON files into profiles_dir.

    Skips files that already exist unless force=True.
    Returns list of paths actually written.
    Idempotent -- safe to call repeatedly.
    """
    profiles_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for name, data in BUILTINS.items():
        path = profiles_dir / f"{name}.json"
        if path.exists() and not force:
            continue
        path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        written.append(path)
    return written


def save_profile(profiles_dir: Path, name: str, *,
                 palette: str, preset: str, params: dict[str, Any],
                 encoder: str, description: str = "",
                 force: bool = False) -> Path:
    """Save a single profile JSON to config/profiles/<name>.json.

    Raises FileExistsError if the file exists and force=False.
    """
    profiles_dir.mkdir(parents=True, exist_ok=True)
    path = profiles_dir / f"{name}.json"
    if path.exists() and not force:
        raise FileExistsError(
            f"profile {name!r} already exists at {path}. "
            f"Pass --force to overwrite."
        )
    data = {
        "palette": palette,
        "preset": preset,
        "params": params,
        "encoder": encoder,
        "description": description,
    }
    path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return path


def all_profiles(profiles_dir: Path | None = None) -> dict[str, dict[str, Any]]:
    """Built-ins first, then user profiles override by name.

    On first call (when profiles_dir is empty), built-ins are auto-materialized
    as editable JSON files so users can clone and tweak them.
    """
    merged = {k: dict(v) for k, v in BUILTINS.items()}
    if profiles_dir is not None:
        # Auto-materialize built-ins as JSON files on first access.
        # Idempotent: existing files are not overwritten.
        materialize_builtins(profiles_dir, force=False)
        for name, data in load_user_profiles(profiles_dir).items():
            merged[name] = data
    return merged


def resolve(name: str, profiles_dir: Path | None = None) -> dict[str, Any]:
    """Look up a profile by name. Raises KeyError with available list on miss."""
    profs = all_profiles(profiles_dir)
    if name not in profs:
        raise KeyError(
            f"profile not found: {name!r}. "
            f"Available: {sorted(profs)}"
        )
    return profs[name]


def list_profile_summary(profiles_dir: Path | None = None) -> list[tuple[str, str, str, str]]:
    """Return [(name, palette/preset, encoder, description), ...] sorted by name."""
    profs = all_profiles(profiles_dir)
    out = []
    for name in sorted(profs):
        p = profs[name]
        palette_preset = f"{p.get('palette', '?')}/{p.get('preset', '?')}"
        out.append((
            name,
            palette_preset,
            p.get("encoder", "?"),
            p.get("description", ""),
        ))
    return out

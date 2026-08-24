"""Build AUDION_VS_* env-var dict that .vpy presets read via os.environ."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Mapping


PREFIX = "AUDION_VS_"


def _norm_value(v) -> str:
    if isinstance(v, bool):
        return "1" if v else "0"
    return str(v)


def build_env(
    *,
    palette: str,
    preset: str,
    input_path: Path,
    params: Mapping[str, object] | None = None,
) -> dict[str, str]:
    """
    Compose AUDION_VS_* environment for a vspipe call.

    Required keys produced:
      AUDION_VS_INPUT     absolute path to source media
      AUDION_VS_PALETTE   "precision" | "film_looks" | "retro" | "utilities"
      AUDION_VS_PRESET    preset short name

    Optional keys are produced from `params`: each (k, v) becomes
      AUDION_VS_<K_UPPER> = str(v)

    Bool values are normalized to "1"/"0".
    """
    if not input_path.is_absolute():
        input_path = input_path.resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input not found: {input_path}")

    env: dict[str, str] = {
        f"{PREFIX}INPUT":   str(input_path),
        f"{PREFIX}PALETTE": palette,
        f"{PREFIX}PRESET":  preset,
    }
    for k, v in (params or {}).items():
        if v is None:
            continue
        env[f"{PREFIX}{k.upper()}"] = _norm_value(v)
    return env


def merged_env(extras: Mapping[str, str]) -> dict[str, str]:
    """Merge our extras on top of os.environ, returning a fresh dict."""
    return {**os.environ, **dict(extras)}

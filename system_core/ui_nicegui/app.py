from __future__ import annotations

from pathlib import Path
from typing import Any
import argparse
import atexit
import ctypes
from ctypes import wintypes
from fractions import Fraction
import html
import json
import locale
import logging
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import webbrowser

import yaml


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from system_core.engine.terminal_render import (
    ansi_to_html,
    strip_ansi,
    terminal_html,
    terminal_lines_html,
)

from nicegui import app as nicegui_app, run, ui  # type: ignore

from system_core.engine import PATHS
from system_core.engine import presets as _presets
from system_core.engine import profile as _profile
from system_core.engine import runner as _runner
from system_core.ui_nicegui.workbench import (
    WorkbenchAdapter,
    WorkbenchConfig,
    WorkbenchHandlers,
    WorkbenchRenderer,
    WorkbenchRole,
    WORKBENCH_FEEDBACK_CSS,
    WORKBENCH_LAYOUT_CSS,
    WORKBENCH_OVERRIDE_CSS,
    canonical_role,
)


VIDEO_EXTS = {
    ".mp4", ".mov", ".mkv", ".m4v", ".avi", ".webm", ".mxf",
    ".mts", ".m2ts", ".ts", ".vob", ".3gp", ".ogv", ".flv", ".wmv", ".asf", ".lrv",
}
PINS_PATH = PATHS.config_dir / "gui_pins.json"
LEGACY_PATH_CACHE_PATH = PATHS.config_dir / "gui_path_cache.json"
LEGACY_WORKSPACE_PATHS_PATH = PATHS.config_dir / "workspace_paths.json"
PATH_HISTORY_PATH = PATHS.config_dir / "path_history.json"
GUI_SETTINGS_PATH = PATHS.config_dir / "gui_settings.yaml"
UI_COLORS_PATH = PATHS.config_dir / "ui_colors.yaml"
REPORT_DIR = PATHS.root / "report"
INSTALL_DIR = PATHS.root / "install"
MAX_RECENT_PATHS = 100
MAIN_PY = PATHS.root / "system_core" / "main.py"
ACTIVE_PROCESS: dict[str, subprocess.Popen[Any] | None] = {"proc": None}
ANSI_ESCAPE_RE = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[@-Z\\-_])")
ANSI_SGR_RE = re.compile(r"\x1b\[([0-9;:]*)m")
ANSI_FG_COLORS = {
    30: "#8a9099",
    31: "#e06b74",
    32: "#98d36f",
    33: "#e5c76b",
    34: "#66a8ff",
    35: "#c792ea",
    36: "#77c7d4",
    37: "#d8dee6",
    90: "#6b7280",
    91: "#ff7b86",
    92: "#a8e07f",
    93: "#f0d878",
    94: "#7bb4ff",
    95: "#d4a3ff",
    96: "#8edbe5",
    97: "#f5f7fb",
}
ANSI_BG_COLORS = {
    code + 10: color for code, color in ANSI_FG_COLORS.items() if code < 40
} | {
    code + 10: color for code, color in ANSI_FG_COLORS.items() if code >= 90
}

PALETTE_LABELS = {
    "precision": "Precision",
    "film_looks": "Film Looks",
    "retro": "Retro",
    "restoration": "Restoration",
}
MODE_LABELS = {
    "preset": "Пресет",
    "profile": "Profile",
    "batch": "Batch",
    "service": "Service",
}
MODULE_META = {
    "profile": {
        "title": "Profile",
        "icon": "account_tree",
        "summary": "Saved profile + encoder override",
    },
    "batch": {
        "title": "Batch",
        "icon": "queue_play_next",
        "summary": "Folder processing",
    },
    "service": {
        "title": "Service",
        "icon": "construction",
        "summary": "Doctor / lists / probe",
    },
}
ENCODER_FAMILY_LABELS = {"x264": "x.264", "x265": "x.265", "prores": "ProRes", "dnxhr": "DNxHR"}
ENCODER_BACKEND_LABELS = {"cpu": "CPU", "nvenc": "NVIDIA", "qsv": "Intel QuickSync", "amf": "AMF"}
DECODE_BACKEND_LABELS = {"cpu": "CPU", "cuda": "NVIDIA", "qsv": "Intel QuickSync", "d3d11va": "AMF"}
ENCODER_QUALITY_LABELS = {"14": "14", "17": "17", "21": "21"}
MUX_CONTAINER_LABELS = {"mp4": "MP4", "mkv": "MKV"}
VS_ACCEL_LABELS = {"cpu": "CPU", "cuda": "CUDA"}
PRORES_PROFILE_LABELS = {"lt": "LT", "422": "422", "hq": "HQ"}
PRORES_CONTAINER_LABELS = {"mxf": "MXF", "mov": "MOV"}
DNXHR_PROFILE_LABELS = {"hq": "HQ", "hqx": "HQX", "lb": "LB", "sq": "SQ"}
PARAM_LABELS = {
    "strength": "Сила",
    "sigma": "BM3D sigma",
    "use_cuda": "CUDA",
    "grain_back": "Возврат зерна",
    "shadow_threshold": "Порог теней",
    "transition": "Переход маски",
    "preview_mask": "Показать маску",
    "range": "Deband range",
    "y": "Y threshold",
    "cb": "Cb threshold",
    "cr": "Cr threshold",
    "grain_var": "Дисперсия зерна",
    "deband_range": "Deband range",
    "grain_shadow": "Зерно в тенях",
    "grain_mid": "Зерно в средних",
    "grain_high": "Зерно в светах",
    "high_threshold": "Порог светов",
    "denoise": "Шумодав",
    "intensity": "Интенсивность",
    "stock": "Пленка",
    "gate_weave": "Gate weave",
    "vignette": "Виньетка",
    "flare_len": "Длина блика",
    "flare_thr": "Порог блика",
    "teal_shadow": "Teal shadows",
    "model": "ML model",
    "tile": "Tile",
    "tile_pad": "Tile pad",
    "backend": "ML backend",
    "fps_mul": "FPS x",
    "rebuild": "Rebuild",
    "cleanup": "Cleanup",
    "field_order": "Порядок полей",
    "preset": "QTGMC preset",
    "output_fps": "FPS output",
    "radius": "Радиус",
    "thsad": "THSAD",
    "blksize": "Block size",
    "pp": "TFM pp",
    "cycle": "Cycle",
    "rdrop": "Drop/cycle",
    "quant1": "Quant 1",
    "quant2": "Quant 2",
    "aoffset": "Alpha offset",
    "boffset": "Beta offset",
}
CHOICE_LABELS = {
    "light": "light",
    "medium": "medium",
    "strong": "strong",
    "single": "single",
    "double": "double",
    "tff": "TFF",
    "bff": "BFF",
    "auto": "Auto",
    "ort_dml": "DirectML",
    "ort_cpu": "CPU",
    "conservative": "conservative",
    "balanced": "balanced",
    "aggressive": "aggressive",
    "0": "выкл",
    "1": "вкл",
}
BOOL_CHOICE_PARAMS = {"use_cuda", "preview_mask", "gate_weave"}
SUPPORTED_LANGUAGES = {"ru", "en"}
DEFAULT_GUI_SETTINGS = {"language": "ru", "theme": "code_dark", "emoji": True}
MATERIAL_ICONS = {
    "source": "file_download",
    "output": "file_upload",
    "out": "file_upload",
    "input_file": "movie",
    "auto_output": "auto_fix_high",
    "status": "fact_check",
    "file_list": "list_alt",
    "logs": "article",
    "report": "bar_chart",
    "open": "folder_open",
    "add_files": "upload_file",
    "add_folder": "create_new_folder",
    "delete": "delete",
    "pin": "push_pin",
    "unpin": "push_pin",
    "precision": "tune",
    "film_looks": "movie_filter",
    "retro": "settings_backup_restore",
    "restoration": "auto_fix_high",
    "doctor": "medical_services",
    "info": "info",
    "encoders": "memory",
    "profiles": "account_tree",
    "presets": "format_list_bulleted",
    "probe": "search",
    "install_vs": "science",
    "install_vs_plugins": "extension",
    "install_ffmpeg": "movie_creation",
    "profile": "account_tree",
    "batch": "queue_play_next",
    "service": "construction",
    "back": "arrow_back",
    "run": "play_arrow",
}
PRESET_TOKEN_LABELS = {
    "h264": "H.264",
    "mpeg": "MPEG",
    "bm3d": "BM3D",
    "dfttest": "DFTTest",
    "f3kdb": "f3kdb",
    "neo": "neo",
    "mvtools": "MVTools",
    "mcdegrain": "MCDegrain",
    "qtgmc": "QTGMC",
    "nnedi3": "NNEDI3",
    "tivtc": "TIVTC",
    "ivtc": "IVTC",
    "ntsc": "NTSC",
    "vhs": "VHS",
    "crt": "CRT",
    "super8": "Super 8",
    "35mm": "35mm",
    "16mm": "16mm",
    "90s": "90s",
    "sota": "SOTA",
    "hd": "HD",
    "2x": "2X",
}
TEXT = {
    "ru": {
        "cancel": "Отменить",
        "back": "Назад",
        "run_preset": "Запустить пресет",
        "apply_profile": "Apply profile",
        "run_batch": "Run batch",
        "encoding": "Кодирование",
        "terminal": "Терминал",
        "clear_terminal_window": "Очистить окно терминала",
        "expand_terminal": "Развернуть терминал",
        "close": "Закрыть",
        "status": "STATUS",
        "file_list": "File List",
        "source_folder": "Источник",
        "target_folder": "Назначение",
        "source_selected": "Источник выбран.",
        "target_selected": "Назначение выбрано.",
        "add_file_short": "Добавить файл...",
        "clear_io_short": "Сбросить",
        "delete_io_short": "Удалить",
        "file_list_button": "Список",
        "path_required": "Выберите путь.",
        "path_pinned": "Путь закреплен.",
        "path_unpinned": "Закрепление снято.",
        "picker_cancelled": "Выбор отменён.",
        "operation_done": "Готово.",
        "source_folder_missing": "Источник не найден: {path}",
        "add_files_short": "ФАЙЛЫ",
        "add_folder_short": "ПАПКА",
        "reset_paths": "СБРОС",
        "file_list_empty": "SOURCE has no files.",
        "file_list_missing": "SOURCE was not found: {path}",
        "file_list_ready": "File list generated: {count}.",
        "terminal_file": "File",
        "logs": "LOGS",
        "out": "OUT",
        "report": "REPORT",
        "source": "SOURCE",
        "output": "OUT",
        "input_file": "ВХОДНОЙ ФАЙЛ",
        "output_override": "Имя выходного файла",
        "auto_output": "АВТО ВЫХОД",
        "auto_output_tooltip": "Сбросить ручное имя и использовать автоматическое имя выходного файла",
        "environment": "Установка VapourSynth",
        "vs": "VapourSynth",
        "codecs_profiles": "Environment and profiles",
        "input_files": "Входные файлы",
        "presets": "Пресеты",
        "preset_params": "Параметры пресета",
        "profile": "Profile",
        "batch": "Batch",
        "service": "Service",
        "profiles": "Profiles",
        "folder_processing": "Folder processing",
        "doctor_lists_probe": "Doctor / lists / probe",
        "theme": "Тема",
        "language_switch": "EN",
        "theme_saved": "Тема сохранена.",
        "language_saved": "Язык сохранен.",
        "idle": "Ожидание",
        "running": "Выполняется",
        "done": "Готово",
        "error": "Ошибка",
        "another_running": "Другая операция уже выполняется.",
        "install_vs": "VAPOURSYNTH",
        "install_vs_plugins": "VS PLUGINS",
        "install_ffmpeg": "FFMPEG",
        "install_vs_tooltip": "Установить/обновить portable VapourSynth host",
        "install_vs_plugins_tooltip": "Установить/обновить VapourSynth plugins через vsrepo",
        "install_ffmpeg_tooltip": "Установить/обновить portable FFmpeg (GPL payload)",
    },
    "en": {
        "cancel": "Cancel",
        "back": "Back",
        "run_preset": "Run preset",
        "apply_profile": "Apply profile",
        "run_batch": "Run batch",
        "encoding": "Encoding",
        "terminal": "Terminal",
        "clear_terminal_window": "Clear terminal window",
        "expand_terminal": "Expand terminal",
        "close": "Close",
        "status": "STATUS",
        "file_list": "File List",
        "source_folder": "Source",
        "target_folder": "Target",
        "source_selected": "Source selected.",
        "target_selected": "Target selected.",
        "add_file_short": "Add file...",
        "clear_io_short": "Reset",
        "delete_io_short": "Delete",
        "file_list_button": "List",
        "path_required": "Choose a path.",
        "path_pinned": "Path pinned.",
        "path_unpinned": "Path unpinned.",
        "picker_cancelled": "Selection cancelled.",
        "operation_done": "Done.",
        "source_folder_missing": "Source was not found: {path}",
        "add_files_short": "FILES",
        "add_folder_short": "FOLDER",
        "reset_paths": "RESET",
        "file_list_empty": "SOURCE has no files.",
        "file_list_missing": "SOURCE was not found: {path}",
        "file_list_ready": "File list generated: {count}.",
        "terminal_file": "File",
        "logs": "LOGS",
        "out": "OUT",
        "report": "REPORT",
        "source": "SOURCE",
        "output": "OUT",
        "input_file": "INPUT FILE",
        "output_override": "Output file name",
        "auto_output": "AUTO OUTPUT",
        "auto_output_tooltip": "Clear the manual name and use the automatic output filename",
        "environment": "VapourSynth install",
        "vs": "VapourSynth",
        "codecs_profiles": "Environment and profiles",
        "input_files": "Input files",
        "presets": "Presets",
        "preset_params": "Preset parameters",
        "profile": "Profile",
        "batch": "Batch",
        "service": "Service",
        "profiles": "Profiles",
        "folder_processing": "Folder processing",
        "doctor_lists_probe": "Doctor / lists / probe",
        "theme": "Theme",
        "language_switch": "RU",
        "theme_saved": "Theme saved.",
        "language_saved": "Language saved.",
        "idle": "Idle",
        "running": "Running",
        "done": "Done",
        "error": "Error",
        "another_running": "Another operation is already running.",
        "install_vs": "VAPOURSYNTH",
        "install_vs_plugins": "VS PLUGINS",
        "install_ffmpeg": "FFMPEG",
        "install_vs_tooltip": "Install/update the portable VapourSynth host",
        "install_vs_plugins_tooltip": "Install/update VapourSynth plugins via vsrepo",
        "install_ffmpeg_tooltip": "Install/update portable FFmpeg (GPL payload)",
    },
}


def read_yaml_file(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def yaml_quote(value: Any) -> str:
    text = str(value or "")
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def load_gui_settings() -> dict[str, Any]:
    data = read_yaml_file(GUI_SETTINGS_PATH)
    gui = data.get("gui") if isinstance(data.get("gui"), dict) else data
    language = str(gui.get("language", DEFAULT_GUI_SETTINGS["language"])).strip().lower()
    theme = str(gui.get("theme", DEFAULT_GUI_SETTINGS["theme"])).strip().lower() or "code_dark"
    return {
        "language": language if language in SUPPORTED_LANGUAGES else "ru",
        "theme": "".join(ch for ch in theme if ch.isascii() and (ch.isalnum() or ch == "_")) or "code_dark",
        "emoji": bool(gui.get("emoji", DEFAULT_GUI_SETTINGS["emoji"])),
        "source_path": str(gui.get("source_path") or "").strip(),
        "destination_path": str(gui.get("destination_path") or gui.get("output_path") or "").strip(),
    }


def save_gui_settings() -> None:
    GUI_SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    current_state = globals().get("state", {})
    path_cache = current_state.get("path_cache", {}) if isinstance(current_state.get("path_cache"), dict) else {}
    source_path = str(
        current_state.get("source_path")
        or path_cache.get("source_path")
        or _initial_gui_settings.get("source_path")
        or PATHS.input_dir
    )
    destination_path = str(
        current_state.get("destination_path")
        or path_cache.get("output_path")
        or _initial_gui_settings.get("destination_path")
        or PATHS.output_dir
    )
    source_for_disk = "" if os.path.normcase(str(Path(source_path).resolve(strict=False))) == os.path.normcase(str(PATHS.input_dir.resolve(strict=False))) else source_path
    destination_for_disk = "" if os.path.normcase(str(Path(destination_path).resolve(strict=False))) == os.path.normcase(str(PATHS.output_dir.resolve(strict=False))) else destination_path
    text = (
        "gui:\n"
        f"  language: \"{active_language()}\"\n"
        f"  theme: \"{active_theme_id()}\"\n"
        f"  emoji: {str(bool(state.get('emoji', False))).lower()}\n"
        f"  source_path: {yaml_quote(source_for_disk)}\n"
        f"  destination_path: {yaml_quote(destination_for_disk)}\n"
    )
    GUI_SETTINGS_PATH.write_text(text, encoding="utf-8", newline="\n")


def load_ui_colors() -> dict[str, Any]:
    data = read_yaml_file(UI_COLORS_PATH)
    themes = data.get("themes", {})
    if not isinstance(themes, dict):
        themes = {}
    tokens = data.get("tokens", {})
    return {
        "tokens": tokens if isinstance(tokens, dict) else {},
        "themes": themes,
    }


UI_COLORS = load_ui_colors()
_initial_gui_settings = load_gui_settings()


def active_language() -> str:
    value = str(globals().get("state", {}).get("language", _initial_gui_settings["language"])).strip().lower()
    return value if value in SUPPORTED_LANGUAGES else "ru"


def tr(key: str, **values: Any) -> str:
    text = TEXT.get(active_language(), TEXT["ru"]).get(key, TEXT["en"].get(key, key))
    return text.format(**values) if values else text


def ui_label(key: str, text: str | None = None) -> str:
    return text if text is not None else tr(key)


def material_icon(key: str) -> str | None:
    return MATERIAL_ICONS.get(key)


def dashboard_button(key: str, on_click: Any, text: str | None = None, extra_classes: str = "") -> Any:
    button = ui.button("", on_click=on_click).props("dense flat").classes(
        f"service-button dashboard-action-button {extra_classes}".strip()
    )
    with button:
        icon = material_icon(key)
        if icon:
            ui.icon(icon).classes("dashboard-action-icon")
        ui.label((text if text is not None else tr(key)).upper()).classes("dashboard-action-label")
    return button


def display_preset_name(name: str) -> str:
    words: list[str] = []
    for raw_token in str(name).replace("-", "_").split("_"):
        token = raw_token.strip()
        if not token:
            continue
        lower = token.lower()
        words.append(PRESET_TOKEN_LABELS.get(lower, token[:1].upper() + token[1:].lower()))
    return " ".join(words) or str(name)


def display_preset_path(spec: _presets.PresetSpec) -> str:
    return f"{PALETTE_LABELS.get(spec.palette, spec.palette)} / {display_preset_name(spec.name)}"


def active_theme_id() -> str:
    themes = UI_COLORS.get("themes", {})
    fallback = "code_dark" if "code_dark" in themes else (next(iter(themes), "code_dark"))
    theme = str(globals().get("state", {}).get("theme", _initial_gui_settings["theme"])).strip().lower()
    return theme if theme in themes else fallback


def active_theme_data() -> dict[str, Any]:
    data = UI_COLORS.get("themes", {}).get(active_theme_id(), {})
    return data if isinstance(data, dict) else {}


def active_theme_mode() -> str:
    return "light" if str(active_theme_data().get("mode", "dark")).lower() == "light" else "dark"


def theme_options() -> dict[str, str]:
    key = "label_ru" if active_language() == "ru" else "label"
    options: dict[str, str] = {}
    for theme_id, data in UI_COLORS.get("themes", {}).items():
        if not isinstance(data, dict):
            continue
        options[str(theme_id)] = str(data.get(key) or data.get("label") or theme_id)
    return options or {"code_dark": "Code Темная" if active_language() == "ru" else "Code Dark"}


def theme_variables() -> dict[str, str]:
    defaults = {
        "color-background-primary": "#090b0d",
        "color-background-secondary": "#14171b",
        "color-background-tertiary": "#0b0d0f",
        "color-text-primary": "#f5f7fb",
        "color-text-secondary": "#d8dee6",
        "color-text-tertiary": "#9aa3ad",
        "color-border-tertiary": "#252b31",
        "color-border-secondary": "#2a3037",
        "color-border-primary": "#43505e",
        "color-accent-primary": "#5f9cf0",
        "color-accent-secondary": "#77c7d4",
        "color-accent-tertiary": "#98d36f",
        "font-sans": "Inter, Segoe UI, Arial, sans-serif",
        "font-mono": "Cascadia Mono, Consolas, monospace",
    }
    base = {str(k): str(v) for k, v in UI_COLORS.get("tokens", {}).items()}
    theme_tokens = active_theme_data().get("tokens", {})
    theme = {str(k): str(v) for k, v in theme_tokens.items()} if isinstance(theme_tokens, dict) else {}
    return {**defaults, **base, **theme}


def set_theme(theme_id: Any) -> None:
    theme = str(theme_id or "").strip().lower()
    if theme not in UI_COLORS.get("themes", {}):
        return
    state["theme"] = theme
    save_gui_settings()
    safe_notify(tr("theme_saved"), type="positive")
    ui.run_javascript("window.location.reload()")


def toggle_language() -> None:
    state["language"] = "en" if active_language() == "ru" else "ru"
    save_gui_settings()
    safe_notify(tr("language_saved"), type="positive")
    ui.run_javascript("window.location.reload()")


def load_pins() -> set[str]:
    try:
        data = json.loads(PINS_PATH.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return {str(item) for item in data}
    except Exception:
        pass
    return set()


def save_pins() -> None:
    PINS_PATH.parent.mkdir(parents=True, exist_ok=True)
    data = sorted(state.get("pins", set()))
    PINS_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def clean_cache_path(value: Any) -> str:
    return str(value or "").strip().strip('"')


def dedupe_paths(values: list[Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        text = clean_cache_path(value)
        if not text:
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(text)
    return result


def default_path_cache() -> dict[str, Any]:
    source = str(PATHS.input_dir)
    output = str(PATHS.output_dir)
    return {
        "source_path": clean_cache_path(_initial_gui_settings.get("source_path")) or source,
        "output_path": clean_cache_path(_initial_gui_settings.get("destination_path")) or output,
        "recent_source_paths": [source],
        "recent_output_paths": [output],
        "pinned_source_paths": [],
        "pinned_output_paths": [],
    }


def load_legacy_path_cache() -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for path in (LEGACY_PATH_CACHE_PATH, LEGACY_WORKSPACE_PATHS_PATH):
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        if path == LEGACY_WORKSPACE_PATHS_PATH:
            mapped = {
                "source_path": data.get("workspace_source_path") or data.get("source_path"),
                "output_path": data.get("workspace_target_path") or data.get("destination_path") or data.get("output_path"),
            }
            merged.update({key: value for key, value in mapped.items() if clean_cache_path(value)})
        else:
            merged.update(data)
    return merged


def history_entry_path(item: Any) -> str:
    if isinstance(item, dict):
        return clean_cache_path(item.get("path") or item.get("value"))
    return clean_cache_path(item)


def history_entry_pinned(item: Any) -> bool:
    return bool(isinstance(item, dict) and item.get("pinned"))


def load_path_history() -> dict[str, list[dict[str, Any]]]:
    if not PATH_HISTORY_PATH.exists():
        return {"sources": [], "targets": []}
    try:
        data = json.loads(PATH_HISTORY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"sources": [], "targets": []}
    if not isinstance(data, dict):
        return {"sources": [], "targets": []}
    normalized: dict[str, list[dict[str, Any]]] = {"sources": [], "targets": []}
    aliases = {"sources": ["sources", "recent_source_paths"], "targets": ["targets", "recent_output_paths", "outputs"]}
    for key, source_keys in aliases.items():
        entries: list[dict[str, Any]] = []
        seen: set[str] = set()
        for source_key in source_keys:
            values = data.get(source_key, [])
            if not isinstance(values, list):
                continue
            for item in values:
                text = history_entry_path(item)
                if not text or text.lower() in seen:
                    continue
                seen.add(text.lower())
                entries.append({"path": text, "pinned": history_entry_pinned(item), "last_used": item.get("last_used") if isinstance(item, dict) else 0})
        normalized[key] = entries[:MAX_RECENT_PATHS]
    return normalized


def load_path_cache() -> dict[str, Any]:
    defaults = default_path_cache()
    legacy = load_legacy_path_cache()
    history = load_path_history()
    merged = {**defaults}
    merged["source_path"] = clean_cache_path(_initial_gui_settings.get("source_path")) or clean_cache_path(legacy.get("source_path")) or defaults["source_path"]
    merged["output_path"] = clean_cache_path(_initial_gui_settings.get("destination_path")) or clean_cache_path(legacy.get("output_path")) or defaults["output_path"]
    merged["recent_source_paths"] = dedupe_paths(
        [merged["source_path"], *[history_entry_path(item) for item in history.get("sources", [])], *list(legacy.get("recent_source_paths", []))]
    )[:MAX_RECENT_PATHS]
    merged["recent_output_paths"] = dedupe_paths(
        [merged["output_path"], *[history_entry_path(item) for item in history.get("targets", [])], *list(legacy.get("recent_output_paths", []))]
    )[:MAX_RECENT_PATHS]
    merged["pinned_source_paths"] = dedupe_paths(
        [history_entry_path(item) for item in history.get("sources", []) if history_entry_pinned(item)]
        + list(legacy.get("pinned_source_paths", []))
    )[:MAX_RECENT_PATHS]
    merged["pinned_output_paths"] = dedupe_paths(
        [history_entry_path(item) for item in history.get("targets", []) if history_entry_pinned(item)]
        + list(legacy.get("pinned_output_paths", []))
    )[:MAX_RECENT_PATHS]
    return merged


def save_path_cache(cache: dict[str, Any]) -> None:
    normalized = default_path_cache()
    normalized.update(cache)
    for key in ["recent_source_paths", "recent_output_paths", "pinned_source_paths", "pinned_output_paths"]:
        value = normalized.get(key, [])
        normalized[key] = dedupe_paths(value if isinstance(value, list) else [])
    normalized["source_path"] = str(resolve_cached_path(normalized.get("source_path"), PATHS.input_dir))
    normalized["output_path"] = str(resolve_cached_path(normalized.get("output_path"), PATHS.output_dir))
    state["source_path"] = normalized["source_path"]
    state["destination_path"] = normalized["output_path"]
    state["path_cache"] = normalized
    save_gui_settings()


def resolve_cached_path(value: Any, fallback: Path) -> Path:
    text = clean_cache_path(value)
    if not text:
        return fallback
    path = Path(os.path.expandvars(text)).expanduser()
    if not path.is_absolute():
        path = PATHS.root / path
    resolved = path.resolve()
    return resolved if resolved.exists() else fallback.resolve()


def role_path(role: str) -> Path:
    cache = state.setdefault("path_cache", load_path_cache())
    key = "source_path" if role == "source" else "output_path"
    fallback = PATHS.input_dir if role == "source" else PATHS.output_dir
    return resolve_cached_path(cache.get(key), fallback)


def source_dir() -> Path:
    return role_path("source")


def output_dir() -> Path:
    return role_path("output")


def update_path_cache(role: str, path_value: str) -> dict[str, Any]:
    if role not in {"source", "output"}:
        raise ValueError(f"Unknown path cache role: {role}")
    cache = state.setdefault("path_cache", load_path_cache())
    fallback = PATHS.input_dir if role == "source" else PATHS.output_dir
    selected = resolve_cached_path(path_value, fallback)
    text = str(selected)
    current_key = f"{role}_path"
    recent_key = f"recent_{role}_paths"
    cache[current_key] = text
    if role == "source":
        state["source_path"] = text
    else:
        state["destination_path"] = text
    cache[recent_key] = dedupe_paths([text, *list(cache.get(recent_key, []))])[:MAX_RECENT_PATHS]
    save_path_cache(cache)
    return cache


def first_video_in(folder: Path) -> str:
    for path in media_files_in(folder):
        return str(path)
    return ""


def first_video_in_input() -> str:
    cache = load_path_cache()
    folder = resolve_cached_path(cache.get("source_path"), PATHS.input_dir)
    return first_video_in(folder)



def profile_names() -> list[str]:
    return sorted(_profile.all_profiles(PATHS.config_dir / "profiles"))


def encoder_extension(encoder: str) -> str:
    if encoder.startswith(("h264_", "h265_")):
        return f".{state.get('mux_container') or 'mp4'}"
    if encoder.endswith("_mxf"):
        return ".mxf"
    if encoder.startswith("prores") or encoder.startswith("dnxhr"):
        return ".mov"
    return ".mp4"


def selected_spec() -> _presets.PresetSpec:
    return _presets.get(str(state["palette"]), str(state["preset"]))


def selected_profile() -> str:
    profiles = profile_names()
    current = str(state.get("profile") or "")
    if current in profiles:
        return current
    return profiles[0] if profiles else ""


def profile_encoder(name: str) -> str:
    try:
        prof = _profile.resolve(name, PATHS.config_dir / "profiles")
    except Exception:
        return _runner.DEFAULT_ENCODER
    encoder = str(prof.get("encoder") or _runner.DEFAULT_ENCODER)
    return encoder if encoder in _runner.ENCODERS else _runner.DEFAULT_ENCODER


def default_output_path(label: str | None = None) -> Path:
    source = Path(str(state.get("input_path") or ""))
    stem = source.stem if source.name else "out"
    suffix = encoder_extension(str(state.get("encoder") or _runner.DEFAULT_ENCODER))
    tag = label or str(state.get("preset") or "preset")
    return output_dir() / f"{stem}__{tag}{suffix}"


def effective_output_path(label: str | None = None) -> Path:
    raw = str(state.get("output_path") or "").strip().strip('"')
    if not raw:
        return default_output_path(label)
    path = Path(os.path.expandvars(raw)).expanduser()
    return path if path.is_absolute() else PATHS.root / path


def resolve_user_path(raw: str) -> Path:
    text = str(raw or "").strip().strip('"')
    if not text:
        raise RuntimeError("Путь не задан.")
    path = Path(os.path.expandvars(text)).expanduser()
    return path if path.is_absolute() else PATHS.root / path


def spec_default_params(spec: _presets.PresetSpec) -> dict[str, Any]:
    return {key: schema.get("default") for key, schema in spec.params.items()}


def ensure_current_params() -> None:
    spec = selected_spec()
    params_by_preset = state.setdefault("params_by_preset", {})
    key = f"{spec.palette}/{spec.name}"
    if key not in params_by_preset:
        params_by_preset[key] = spec_default_params(spec)
    params = params_by_preset[key]
    for param, schema in spec.params.items():
        params.setdefault(param, schema.get("default"))


def current_params() -> dict[str, Any]:
    ensure_current_params()
    spec = selected_spec()
    return state["params_by_preset"][f"{spec.palette}/{spec.name}"]


def set_param(param: str, value: Any) -> None:
    current_params()[param] = value


def format_command(command: list[str]) -> str:
    return " ".join(f'"{item}"' if any(ch.isspace() for ch in item) else item for item in command)


def unbuffer_python_command(command: list[str]) -> list[str]:
    if not command:
        return command
    exe_name = Path(str(command[0])).name.lower()
    if exe_name in {"python.exe", "python", "python3"} and "-u" not in command[1:3]:
        return [command[0], "-u", *command[1:]]
    return command


def is_python_command(command: list[str]) -> bool:
    if not command:
        return False
    exe_name = Path(str(command[0])).name.lower()
    return exe_name in {"python.exe", "python", "python3"}


def hidden_subprocess_kwargs() -> dict[str, object]:
    if os.name != "nt":
        return {}
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = 0
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    return {"startupinfo": startupinfo, "creationflags": flags}


def utf8_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("PYTHONUTF8", "1")
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUNBUFFERED"] = "1"
    env.pop("NO_COLOR", None)
    env["CLICOLOR"] = "1"
    env["CLICOLOR_FORCE"] = "1"
    env["FORCE_COLOR"] = "1"
    env["AUDION_GUI_TERMINAL"] = "1"
    env.setdefault("TERM", "xterm-256color")
    return env


def decode_score(text: str) -> int:
    score = 0
    lower = text.lower()
    for ch in text:
        code = ord(ch)
        if ch in "\t\r\n":
            score += 1
        elif ch == "\ufffd" or ch == "\x00":
            score -= 80
        elif code < 32 or 0x7F <= code <= 0x9F:
            score -= 20
        elif 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF:
            score -= 35
        elif "а" <= ch.lower() <= "я" or ch in "Ёё":
            score += 5
        elif ch.isascii() and (ch.isprintable() or ch.isspace()):
            score += 1
        elif ch in "\u00a0\u00ad¤©«»ЋЌЉЊЏЎ":
            score -= 8
    for word in (
        "ошибка",
        "уда",
        "файл",
        "папк",
        "задач",
        "планиров",
        "успеш",
        "доступ",
        "найти",
    ):
        if word in lower:
            score += 30
    for marker in ("����", "���", "㤠", "䠩"):
        if marker in text:
            score -= 120
    return score


def decode_utf16ish(data: bytes) -> str | None:
    if not data:
        return ""
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        try:
            return data.decode("utf-16")
        except UnicodeDecodeError:
            return None
    if len(data) < 4:
        return None
    nul_ratio = data.count(0) / max(1, len(data))
    if nul_ratio < 0.18:
        return None
    candidates: list[str] = []
    for encoding in ("utf-16", "utf-16le", "utf-16be"):
        try:
            candidates.append(data.decode(encoding))
        except UnicodeDecodeError:
            pass
    if not candidates:
        return None
    return max(candidates, key=decode_score)


def fallback_text_encodings() -> list[str]:
    encodings = ["cp866"]
    for encoding in (locale.getpreferredencoding(False), "mbcs", "cp1251"):
        if encoding and encoding.lower() not in {item.lower() for item in encodings}:
            encodings.append(encoding)
    return encodings


def decode_process_bytes(data: bytes) -> str:
    if not data:
        return ""
    utf16 = decode_utf16ish(data)
    if utf16 is not None:
        return utf16
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        pass

    decoded: list[str] = []
    for encoding in fallback_text_encodings():
        try:
            decoded.append(data.decode(encoding))
        except (LookupError, UnicodeDecodeError):
            continue
    if decoded:
        return max(decoded, key=decode_score)
    return data.decode("utf-8", errors="replace")


SPINNER_FRAME_CHARS = set("-\\|/ \t")


def _is_spinner_only_line(line: str) -> bool:
    stripped = line.strip()
    return bool(stripped) and all(char in SPINNER_FRAME_CHARS for char in line)


def decoded_process_lines(raw_line: bytes | str) -> list[str]:
    text = str(raw_line) if isinstance(raw_line, str) else decode_process_bytes(raw_line)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines: list[str] = []
    for part in text.split("\n"):
        line = part.rstrip()
        if not line or _is_spinner_only_line(line):
            continue
        lines.append(line)
    return lines




class AnsiHtmlRenderer:
    def __init__(self) -> None:
        self.bold = False
        self.dim = False
        self.fg: str | None = None
        self.bg: str | None = None

    def reset(self) -> None:
        self.bold = False
        self.dim = False
        self.fg = None
        self.bg = None

    def style_attr(self) -> str:
        styles: list[str] = []
        if self.fg:
            styles.append(f"color:{self.fg}")
        if self.bg:
            styles.append(f"background-color:{self.bg}")
        if self.bold:
            styles.append("font-weight:700")
        if self.dim:
            styles.append("opacity:.72")
        return ";".join(styles)

    def apply_sgr(self, payload: str) -> None:
        parts = payload.replace(":", ";").split(";") if payload else ["0"]
        for raw in parts:
            if raw == "":
                code = 0
            else:
                try:
                    code = int(raw)
                except ValueError:
                    continue
            if code == 0:
                self.reset()
            elif code == 1:
                self.bold = True
                self.dim = False
            elif code == 2:
                self.dim = True
            elif code == 22:
                self.bold = False
                self.dim = False
            elif code == 39:
                self.fg = None
            elif code == 49:
                self.bg = None
            elif code in ANSI_FG_COLORS:
                self.fg = ANSI_FG_COLORS[code]
            elif code in ANSI_BG_COLORS:
                self.bg = ANSI_BG_COLORS[code]

    def render_text(self, text: str) -> str:
        escaped = html.escape(text, quote=False)
        if not escaped:
            return ""
        style = self.style_attr()
        if not style:
            return escaped
        return f'<span style="{style}">{escaped}</span>'

    def render(self, text: str) -> str:
        rendered: list[str] = []
        cursor = 0
        for match in ANSI_ESCAPE_RE.finditer(str(text)):
            rendered.append(self.render_text(str(text)[cursor:match.start()]))
            token = match.group(0)
            sgr = ANSI_SGR_RE.fullmatch(token)
            if sgr:
                self.apply_sgr(sgr.group(1))
            cursor = match.end()
        rendered.append(self.render_text(str(text)[cursor:]))
        return "".join(rendered)








def media_files_in(folder: Path) -> list[Path]:
    if not folder.exists():
        return []
    if folder.is_file():
        return [folder] if folder.suffix.lower() in VIDEO_EXTS else []
    return sorted(path for path in folder.rglob("*") if path.is_file() and path.suffix.lower() in VIDEO_EXTS)


def stream_by_type(data: dict[str, Any], kind: str) -> dict[str, Any]:
    streams = data.get("streams", [])
    if not isinstance(streams, list):
        return {}
    for stream in streams:
        if isinstance(stream, dict) and stream.get("codec_type") == kind:
            return stream
    return {}


def streams_by_type(data: dict[str, Any], kind: str) -> list[dict[str, Any]]:
    streams = data.get("streams", [])
    if not isinstance(streams, list):
        return []
    return [stream for stream in streams if isinstance(stream, dict) and stream.get("codec_type") == kind]


def ffprobe_media_json(path: Path, timeout: int = 60) -> dict[str, Any]:
    command = [
        str(PATHS.ffprobe),
        "-v",
        "error",
        "-show_entries",
        (
            "format=duration,bit_rate,size,format_name:"
            "stream=index,codec_type,codec_name,profile,width,height,avg_frame_rate,r_frame_rate,"
            "pix_fmt,color_space,color_transfer,color_primaries,color_range,field_order,"
            "sample_rate,channels,channel_layout,bits_per_sample,bits_per_raw_sample,bit_rate"
        ),
        "-of",
        "json",
        str(path),
    ]
    proc = subprocess.Popen(
        command,
        cwd=str(PATHS.root),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=utf8_env(),
        **hidden_subprocess_kwargs(),
    )
    ACTIVE_PROCESS["proc"] = proc
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        kill_process_tree(proc)
        raise RuntimeError(f"ffprobe timeout after {timeout}s") from exc
    finally:
        ACTIVE_PROCESS["proc"] = None
    if proc.returncode != 0:
        raise RuntimeError((stderr or stdout or f"ffprobe exited {proc.returncode}").strip())
    try:
        data = json.loads(stdout or "{}")
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"ffprobe returned invalid JSON: {exc}") from exc
    return data if isinstance(data, dict) else {}


def rate_label(value: Any) -> str:
    text = str(value or "").strip()
    if not text or text in {"0/0", "N/A"}:
        return "-"
    try:
        rate = Fraction(text)
    except Exception:
        return text
    if rate <= 0:
        return "-"
    if rate == Fraction(24000, 1001):
        return "23.976"
    if rate.denominator == 1:
        return str(rate.numerator)
    return f"{float(rate):.3f}".rstrip("0").rstrip(".")


def format_duration(value: Any) -> str:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return "-"
    if seconds <= 0:
        return "-"
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    if hours:
        return f"{hours:d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:d}:{secs:02d}"


def bitrate_mbps(*values: Any) -> str:
    for value in values:
        try:
            bits = float(value)
        except (TypeError, ValueError):
            continue
        if bits > 0:
            return f"{bits / 1_000_000:.2f}"
    return "-"


def size_label(path: Path, fmt: dict[str, Any]) -> str:
    raw = fmt.get("size")
    try:
        size = int(raw)
    except (TypeError, ValueError):
        try:
            size = path.stat().st_size
        except OSError:
            return "-"
    if size >= 1024**3:
        return f"{size / 1024**3:.2f}G"
    return f"{size / 1024**2:.1f}M"


def chroma_label(pix_fmt: str) -> str:
    fmt = pix_fmt.lower()
    if not fmt or fmt == "-":
        return "-"
    if "gbr" in fmt or "rgb" in fmt:
        return "RGB"
    if "444" in fmt:
        return "4:4:4"
    if "422" in fmt or fmt.startswith(("yuyv", "uyvy")):
        return "4:2:2"
    if "420" in fmt or fmt in {"nv12", "p010le", "p016le", "yuvj420p"}:
        return "4:2:0"
    if "411" in fmt:
        return "4:1:1"
    if "410" in fmt:
        return "4:1:0"
    return "-"


def bit_depth_label(pix_fmt: str, stream: dict[str, Any]) -> str:
    fmt = pix_fmt.lower()
    bits = str(stream.get("bits_per_raw_sample") or stream.get("bits_per_sample") or "").strip()
    if bits and bits != "0":
        return bits
    for marker, depth in [("16", "16"), ("14", "14"), ("12", "12"), ("10", "10"), ("9", "9")]:
        if marker in fmt:
            return depth
    return "8" if fmt and fmt != "-" else "-"


def color_label(video: dict[str, Any]) -> str:
    primaries = str(video.get("color_primaries") or video.get("color_space") or "-")
    transfer_raw = str(video.get("color_transfer") or "").lower()
    transfer = ""
    if "smpte2084" in transfer_raw:
        transfer = "PQ"
    elif "arib-std-b67" in transfer_raw:
        transfer = "HLG"
    elif transfer_raw and transfer_raw not in {"unknown", "reserved"}:
        transfer = transfer_raw
    color_range = str(video.get("color_range") or "").lower()
    range_label = "full" if color_range in {"pc", "jpeg"} else "lim" if color_range in {"tv", "mpeg"} else ""
    return "/".join(item for item in [primaries, transfer, range_label] if item and item != "-") or "-"


def audio_label(data: dict[str, Any]) -> str:
    audio_streams = streams_by_type(data, "audio")
    if not audio_streams:
        return "-"
    audio = audio_streams[0]
    codec = str(audio.get("codec_name") or "-").upper()
    channels = str(audio.get("channel_layout") or audio.get("channels") or "?")
    sample_rate = str(audio.get("sample_rate") or "")
    rate = f"{int(sample_rate) // 1000}k" if sample_rate.isdigit() else ""
    suffix = f"+{len(audio_streams) - 1}" if len(audio_streams) > 1 else ""
    return " ".join(item for item in [codec, channels, rate, suffix] if item)


def probe_status_row(source_dir: Path, path: Path, data: dict[str, Any]) -> dict[str, str]:
    video = stream_by_type(data, "video")
    fmt = data.get("format", {}) if isinstance(data.get("format"), dict) else {}
    pix_fmt = str(video.get("pix_fmt") or "-")
    profile = str(video.get("profile") or "").replace("Profile", "").strip()
    codec = str(video.get("codec_name") or "-").upper()
    codec_label = " ".join(item for item in [codec, profile] if item and item != "-")
    width = video.get("width")
    height = video.get("height")
    rel_name = str(path.relative_to(source_dir)) if path.is_relative_to(source_dir) else path.name
    return {
        "file": rel_name,
        "codec": codec_label or "-",
        "res": f"{width}x{height}" if width and height else "-",
        "fps": rate_label(video.get("avg_frame_rate") or video.get("r_frame_rate")),
        "pix": pix_fmt,
        "chroma": chroma_label(pix_fmt),
        "bit": bit_depth_label(pix_fmt, video),
        "mbps": bitrate_mbps(video.get("bit_rate"), fmt.get("bit_rate")),
        "color": color_label(video),
        "audio": audio_label(data),
        "dur": format_duration(fmt.get("duration")),
        "size": size_label(path, fmt),
    }


def clip_cell(value: Any, width: int) -> str:
    text = str(value or "-").replace("\r", " ").replace("\n", " ")
    if len(text) > width:
        text = text[: max(0, width - 3)] + "..."
    return f"{text:<{width}}"


def status_table(rows: list[dict[str, str]]) -> list[str]:
    columns = [
        ("FILE", "file", 30),
        ("CODEC", "codec", 14),
        ("RES", "res", 11),
        ("FPS", "fps", 7),
        ("PIX_FMT", "pix", 12),
        ("CHR", "chroma", 5),
        ("BIT", "bit", 3),
        ("MBPS", "mbps", 6),
        ("COLOR", "color", 14),
        ("AUDIO", "audio", 18),
        ("DUR", "dur", 7),
        ("SIZE", "size", 8),
    ]
    header = " | ".join(clip_cell(title, width) for title, _, width in columns)
    separator = "-+-".join("-" * width for _, _, width in columns)
    lines = [header, separator]
    for row in rows:
        lines.append(" | ".join(clip_cell(row.get(key, "-"), width) for _, key, width in columns))
    return lines


def add_log(message: str) -> None:
    raw_text = str(message).rstrip("\r\n")
    if not raw_text:
        return
    plain_text = strip_ansi(raw_text).rstrip()
    with LOG_LOCK:
        state["lines"].append(raw_text)
        state["lines"] = state["lines"][-1000:]
        state["line_sequence"] = int(state.get("line_sequence", 0)) + 1
        state["log_version"] = int(state["log_version"]) + 1
        log_file = state.get("active_log_file")
    if log_file and plain_text:
        try:
            Path(log_file).parent.mkdir(parents=True, exist_ok=True)
            with Path(log_file).open("a", encoding="utf-8") as handle:
                handle.write(plain_text + "\n")
        except OSError:
            pass


def clear_terminal_window() -> None:
    with LOG_LOCK:
        state["lines"] = []
        state["line_sequence"] = 0
        state["terminal_reset_id"] = int(state.get("terminal_reset_id", 0)) + 1
        state["terminal_scroll_top_seq"] = 0
        state["log_version"] = int(state["log_version"]) + 1


def safe_notify(message: str, kind: str = "info", **notify_kwargs: Any) -> None:
    notify_type = str(notify_kwargs.pop("type", kind))
    options = {"message": str(message), "type": notify_type, **notify_kwargs}
    delivered = False
    for client in list(nicegui_app.clients()):
        if getattr(client, "_deleted", False) or not client.has_socket_connection:
            continue
        try:
            client.outbox.enqueue_message("notify", options, client.id)
            delivered = True
        except Exception as exc:
            logging.warning("NiceGUI notification delivery failed for client %s: %s", getattr(client, "id", "?"), exc)
    if delivered:
        return

    try:
        ui.notify(message, type=notify_type, **notify_kwargs)
    except RuntimeError as exc:
        message_text = str(exc)
        if "slot belongs to has been deleted" not in message_text and "current slot cannot be determined" not in message_text:
            raise
        logging.warning("NiceGUI notification skipped because no live client slot was available: %s", message)


def set_status(text: str, *, progress: float | None = None, exit_code: int | None = None) -> None:
    state["status"] = text
    if progress is not None:
        state["progress"] = max(0.0, min(1.0, float(progress)))
    if exit_code is not None:
        state["exit_code"] = exit_code


def kill_process_tree(proc: subprocess.Popen[Any]) -> None:
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=10,
                **hidden_subprocess_kwargs(),
            )
            return
        except Exception:
            pass
    try:
        proc.kill()
    except Exception:
        pass


def run_command(command: list[str], title: str) -> int:
    command = unbuffer_python_command(command)
    python_stream = is_python_command(command)
    started = time.monotonic()
    add_log(f"[run] {title}")
    add_log(f"[cwd] {PATHS.root}")
    add_log(f"[cmd] {format_command(command)}")
    popen_kwargs: dict[str, Any] = {
        "cwd": str(PATHS.root),
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.STDOUT,
        "env": utf8_env(),
        **hidden_subprocess_kwargs(),
    }
    if python_stream:
        popen_kwargs.update({"text": True, "encoding": "utf-8", "errors": "replace", "bufsize": 1})
    else:
        popen_kwargs.update({"text": False, "bufsize": 0})
    proc = subprocess.Popen(command, **popen_kwargs)
    ACTIVE_PROCESS["proc"] = proc
    try:
        assert proc.stdout is not None
        for line in iter(proc.stdout.readline, "" if python_stream else b""):
            if state.get("cancel"):
                add_log("[cancel] stopping child process tree...")
                kill_process_tree(proc)
                return 130
            for text_line in decoded_process_lines(line):
                add_log(text_line)
            elapsed = time.monotonic() - started
            state["progress"] = min(0.95, 0.04 + elapsed / 1800.0)
        return int(proc.wait())
    finally:
        ACTIVE_PROCESS["proc"] = None


async def start_job(command: list[str], title: str) -> None:
    if state["running"]:
        safe_notify("Другая операция уже выполняется.", type="warning")
        return
    stamp = time.strftime("%Y-%m-%d_%H-%M-%S")
    log_file = PATHS.logs_dir / f"{stamp}__gui__{safe_id(title)}.log"
    state.update(
        {
            "running": True,
            "cancel": False,
            "progress": 0.02,
            "status": f"Выполняется: {title}",
            "lines": [],
            "line_sequence": 0,
            "log_version": int(state["log_version"]) + 1,
            "exit_code": None,
            "active_log_file": str(log_file),
        }
    )
    try:
        rc = await run.io_bound(run_command, command, title)
        state["exit_code"] = rc
        state["progress"] = 1.0
        state["status"] = f"{'Готово' if rc == 0 else 'Ошибка'}: {title} [{rc}]"
        safe_notify("Операция завершена." if rc == 0 else f"Операция завершилась с кодом {rc}.", type="positive" if rc == 0 else "negative")
    except Exception as exc:
        state["exit_code"] = 1
        state["progress"] = max(float(state["progress"]), 0.98)
        state["status"] = f"Ошибка: {exc}"
        add_log(f"ERROR: {exc.__class__.__name__}: {exc}")
        safe_notify(str(exc), type="negative")
    finally:
        state["running"] = False


def status_source_dir() -> Path:
    try:
        return source_dir()
    except Exception:
        return PATHS.input_dir


def run_input_status_probe(source_dir: Path) -> int:
    files = media_files_in(source_dir)
    add_log(f"[status] Source: {source_dir}")
    add_log(f"[status] Media files: {len(files)}")
    if not files:
        add_log("No media files found.")
        return 0

    rows: list[dict[str, str]] = []
    total = len(files)
    for index, path in enumerate(files, start=1):
        if state.get("cancel"):
            add_log("[cancel] status probe stopped.")
            return 130
        try:
            row = probe_status_row(source_dir, path, ffprobe_media_json(path))
        except Exception as exc:
            row = {
                "file": str(path.relative_to(source_dir)) if path.is_relative_to(source_dir) else path.name,
                "codec": f"ERROR: {exc}",
                "res": "-",
                "fps": "-",
                "pix": "-",
                "chroma": "-",
                "bit": "-",
                "mbps": "-",
                "color": "-",
                "audio": "-",
                "dur": "-",
                "size": "-",
            }
        rows.append(row)
        state["progress"] = index / total

    for line in status_table(rows):
        add_log(line)
    unique_fingerprints = {
        "|".join([row["codec"], row["res"], row["fps"], row["pix"], row["chroma"], row["bit"], row["color"], row["audio"]])
        for row in rows
    }
    add_log(f"[status] {'mixed' if len(unique_fingerprints) > 1 else 'uniform'} media set; probed {len(rows)}/{total}.")
    return 0


async def run_input_status() -> None:
    if state["running"]:
        safe_notify("Другая операция уже выполняется.", type="warning")
        return
    source_dir = status_source_dir()
    stamp = time.strftime("%Y-%m-%d_%H-%M-%S")
    log_file = PATHS.logs_dir / f"{stamp}__gui__input_status.log"
    state.update(
        {
            "running": True,
            "cancel": False,
            "progress": 0.02,
            "status": "STATUS: ffprobe input",
            "lines": [],
            "line_sequence": 0,
            "log_version": int(state["log_version"]) + 1,
            "exit_code": None,
            "active_log_file": str(log_file),
        }
    )
    try:
        rc = await run.io_bound(run_input_status_probe, source_dir)
        state["exit_code"] = rc
        state["progress"] = 1.0
        state["status"] = f"{'Готово' if rc == 0 else 'Остановлено'}: STATUS [{rc}]"
        safe_notify("STATUS готов." if rc == 0 else f"STATUS завершился с кодом {rc}.", type="positive" if rc == 0 else "warning")
    except Exception as exc:
        state["exit_code"] = 1
        state["progress"] = max(float(state["progress"]), 0.98)
        state["status"] = f"Ошибка STATUS: {exc}"
        add_log(f"ERROR: {exc.__class__.__name__}: {exc}")
        safe_notify(str(exc), type="negative")
    finally:
        state["running"] = False


def cancel_job() -> None:
    state["cancel"] = True
    proc = ACTIVE_PROCESS.get("proc")
    if proc and proc.poll() is None:
        kill_process_tree(proc)


def safe_id(text: str) -> str:
    return "".join(ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in text.lower()).strip("_")[:80] or "run"


def param_flag(spec: _presets.PresetSpec, key: str) -> str:
    if spec.name == "qtgmc_deinterlace" and key == "preset":
        return "--qtgmc-preset"
    return "--" + key.replace("_", "-")


def normalized_param_value(schema: dict[str, Any], value: Any) -> str:
    if schema.get("type") == "int":
        return str(int(float(value)))
    if schema.get("type") == "float":
        return str(float(value))
    return str(value)


def build_run_preset_command() -> list[str]:
    spec = selected_spec()
    source = resolve_user_path(str(state.get("input_path") or ""))
    if not source.exists():
        raise RuntimeError(f"Исходный файл не найден: {source}")
    output = effective_output_path(spec.name)
    command = [
        str(PATHS.runtime_python),
        str(MAIN_PY),
        "run",
        "--palette", spec.palette,
        "--preset", spec.name,
        "--input", str(source),
        "--output", str(output),
        "--encoder", str(state.get("encoder") or _runner.DEFAULT_ENCODER),
        "--decode-backend", str(state.get("decode_backend") or "cpu"),
        "--vs-accel", str(state.get("vs_accel") or "cpu"),
    ]
    for key, schema in spec.params.items():
        if key == "use_cuda":
            continue
        value = current_params().get(key, schema.get("default"))
        if value in (None, ""):
            continue
        command.extend([param_flag(spec, key), normalized_param_value(schema, value)])
    return command


async def run_selected_preset() -> None:
    try:
        command = build_run_preset_command()
    except Exception as exc:
        safe_notify(str(exc), type="warning")
        return
    await start_job(command, f"{selected_spec().palette}/{selected_spec().name}")


def build_apply_profile_command() -> list[str]:
    name = selected_profile()
    source = resolve_user_path(str(state.get("input_path") or ""))
    if not source.exists():
        raise RuntimeError(f"Исходный файл не найден: {source}")
    output = effective_output_path(name)
    command = [
        str(PATHS.runtime_python),
        str(MAIN_PY),
        "apply-profile",
        "--name", name,
        "--input", str(source),
        "--output", str(output),
        "--encoder", str(state.get("encoder") or profile_encoder(name)),
        "--decode-backend", str(state.get("decode_backend") or "cpu"),
        "--vs-accel", str(state.get("vs_accel") or "cpu"),
    ]
    return command


async def run_profile() -> None:
    try:
        command = build_apply_profile_command()
    except Exception as exc:
        safe_notify(str(exc), type="warning")
        return
    await start_job(command, f"profile/{selected_profile()}")


def build_batch_command() -> list[str]:
    name = selected_profile()
    batch_source = source_dir()
    batch_output = output_dir()
    if not batch_source.is_dir():
        raise RuntimeError(f"Папка-источник не найдена: {batch_source}")
    command = [
        str(PATHS.runtime_python),
        str(MAIN_PY),
        "apply-profile-batch",
        "--name", name,
        "--input-dir", str(batch_source),
        "--output-dir", str(batch_output),
        "--encoder", str(state.get("encoder") or profile_encoder(name)),
        "--decode-backend", str(state.get("decode_backend") or "cpu"),
        "--vs-accel", str(state.get("vs_accel") or "cpu"),
    ]
    if str(state.get("encoder") or "").startswith(("h264_", "h265_")):
        command.extend(["--container", str(state.get("mux_container") or "mp4")])
    if state.get("recursive", True):
        command.append("--recursive")
    if not state.get("mirror_tree", True):
        command.append("--no-mirror")
    if state.get("overwrite"):
        command.append("--overwrite")
    return command


async def run_batch() -> None:
    try:
        command = build_batch_command()
    except Exception as exc:
        safe_notify(str(exc), type="warning")
        return
    await start_job(command, f"batch/{selected_profile()}")


async def run_service(command_id: str) -> None:
    commands = {
        "doctor": [str(PATHS.runtime_python), str(PATHS.root / "system_core" / "doctor.py")],
        "list_presets": [str(PATHS.runtime_python), str(MAIN_PY), "list-presets"],
        "list_encoders": [str(PATHS.runtime_python), str(MAIN_PY), "list-encoders"],
        "list_profiles": [str(PATHS.runtime_python), str(MAIN_PY), "list-profiles"],
        "info": [str(PATHS.runtime_python), str(MAIN_PY), "info"],
    }
    if command_id == "probe":
        raw = str(state.get("input_path") or "")
        try:
            source = resolve_user_path(raw)
        except Exception as exc:
            safe_notify(str(exc), type="warning")
            return
        commands["probe"] = [str(PATHS.runtime_python), str(MAIN_PY), "probe", "--input", str(source)]
    await start_job(commands[command_id], command_id)
    if command_id == "doctor":
        apply_doctor_vs_accel()


def cmd_wrapper_command(script_name: str, *args: str) -> list[str]:
    script = INSTALL_DIR / script_name
    if not script.exists():
        raise RuntimeError(f"Installer wrapper not found: {script}")
    comspec = os.environ.get("ComSpec") or "cmd.exe"
    return [comspec, "/d", "/c", str(script), *args]


async def run_installer(command_id: str) -> None:
    commands = {
        "vs": cmd_wrapper_command("Install-Portable-VapourSynth.cmd", "/NOPAUSE"),
        "vs_plugins": cmd_wrapper_command("Install-VS-Plugins.cmd", "/NOPAUSE"),
        "ffmpeg": cmd_wrapper_command("Install-Portable-FFmpeg.cmd", "/NOPAUSE"),
    }
    titles = {
        "vs": "install/vapoursynth",
        "vs_plugins": "install/vs-plugins",
        "ffmpeg": "install/ffmpeg",
    }
    await start_job(commands[command_id], titles[command_id])


def apply_doctor_vs_accel() -> None:
    text = strip_ansi("\n".join(str(line) for line in state.get("lines", []))).lower()
    cuda_ok = "bm3dcuda runtime" in text and "live bm3d cuda invocation succeeded" in text
    state["vs_accel"] = "cuda" if cuda_ok else "cpu"
    add_log(f"[gui] VS accel auto: {state['vs_accel'].upper()} (Doctor)")
    safe_notify(f"VS: {'CUDA' if cuda_ok else 'CPU'}", type="positive" if cuda_ok else "info")
    refresh_views()


PICKER_BOOTSTRAP = r"""
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
try {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AudionDpiAwareness {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
  [DllImport("shcore.dll")]
  public static extern int SetProcessDpiAwareness(int value);
}
"@
  try { [AudionDpiAwareness]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null }
  catch { [AudionDpiAwareness]::SetProcessDpiAwareness(2) | Out-Null }
} catch {}
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
"""


def resolve_dialog_powershell() -> list[str]:
    candidates = [
        [str(PATHS.pwsh), "-NoLogo", "-NoProfile", "-STA", "-Command"],
        ["pwsh.exe", "-NoLogo", "-NoProfile", "-STA", "-Command"],
        ["powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command"],
    ]
    for candidate in candidates:
        exe = candidate[0]
        if Path(exe).exists() or shutil.which(exe):
            return candidate
    raise RuntimeError("PowerShell не найден для системного выбора файлов.")


_PICKER_RUN_LOCK = threading.Lock()
_PICKER_JOB_LOCK = threading.Lock()
_PICKER_JOB_HANDLE: int | None = None


class _JobObjectBasicLimitInformation(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_int64),
        ("PerJobUserTimeLimit", ctypes.c_int64),
        ("LimitFlags", wintypes.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", wintypes.DWORD),
        ("Affinity", ctypes.c_size_t),
        ("PriorityClass", wintypes.DWORD),
        ("SchedulingClass", wintypes.DWORD),
    ]


class _IoCounters(ctypes.Structure):
    _fields_ = [
        ("ReadOperationCount", ctypes.c_uint64),
        ("WriteOperationCount", ctypes.c_uint64),
        ("OtherOperationCount", ctypes.c_uint64),
        ("ReadTransferCount", ctypes.c_uint64),
        ("WriteTransferCount", ctypes.c_uint64),
        ("OtherTransferCount", ctypes.c_uint64),
    ]


class _JobObjectExtendedLimitInformation(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", _JobObjectBasicLimitInformation),
        ("IoInfo", _IoCounters),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


def close_picker_job() -> None:
    global _PICKER_JOB_HANDLE
    with _PICKER_JOB_LOCK:
        handle = _PICKER_JOB_HANDLE
        _PICKER_JOB_HANDLE = None
    if os.name == "nt" and handle:
        ctypes.WinDLL("kernel32", use_last_error=True).CloseHandle(wintypes.HANDLE(handle))


def _picker_job_handle() -> int | None:
    global _PICKER_JOB_HANDLE
    if os.name != "nt":
        return None
    with _PICKER_JOB_LOCK:
        if _PICKER_JOB_HANDLE:
            return _PICKER_JOB_HANDLE
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.CreateJobObjectW.restype = wintypes.HANDLE
        job = kernel32.CreateJobObjectW(None, None)
        if not job:
            logging.warning("Could not create the Windows picker job: %s", ctypes.get_last_error())
            return None
        info = _JobObjectExtendedLimitInformation()
        info.BasicLimitInformation.LimitFlags = 0x00002000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        configured = kernel32.SetInformationJobObject(
            wintypes.HANDLE(job),
            9,
            ctypes.byref(info),
            ctypes.sizeof(info),
        )
        if not configured:
            error = ctypes.get_last_error()
            kernel32.CloseHandle(wintypes.HANDLE(job))
            logging.warning("Could not configure the Windows picker job: %s", error)
            return None
        _PICKER_JOB_HANDLE = int(job)
        return _PICKER_JOB_HANDLE


def _assign_picker_to_job(process: subprocess.Popen[str]) -> None:
    handle = _picker_job_handle()
    if os.name != "nt" or not handle:
        return
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    assigned = kernel32.AssignProcessToJobObject(
        wintypes.HANDLE(handle),
        wintypes.HANDLE(int(process._handle)),  # type: ignore[attr-defined]
    )
    if not assigned:
        logging.warning("Could not attach picker PID %s to its Windows job: %s", process.pid, ctypes.get_last_error())


def run_picker_script(script: str, failure_message: str) -> str:
    if not _PICKER_RUN_LOCK.acquire(blocking=False):
        raise RuntimeError("Окно выбора уже открыто.")
    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(
            [*resolve_dialog_powershell(), script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            **hidden_subprocess_kwargs(),
        )
        _assign_picker_to_job(process)
        try:
            stdout, stderr = process.communicate(timeout=3600)
        except subprocess.TimeoutExpired as exc:
            process.kill()
            process.communicate()
            raise RuntimeError("Окно выбора превысило время ожидания.") from exc
        if process.returncode != 0:
            raise RuntimeError(stderr.strip() or failure_message)
        return stdout
    finally:
        if process is not None and process.poll() is None:
            process.kill()
        _PICKER_RUN_LOCK.release()


atexit.register(close_picker_job)
nicegui_app.on_shutdown(close_picker_job)


def parse_picker_paths(text: str) -> list[Path]:
    payload = text.strip()
    if not payload:
        return []
    data = json.loads(payload)
    if isinstance(data, str):
        data = [data]
    return [Path(str(item)).resolve() for item in data if str(item).strip()]


def picker_file() -> list[Path]:
    script = PICKER_BOOTSTRAP + r"""
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Video source'
$dialog.Multiselect = $true
$dialog.Filter = 'Video files|*.mp4;*.mov;*.mkv;*.m4v;*.avi;*.webm;*.mxf;*.mts;*.m2ts;*.ts;*.vob;*.3gp;*.ogv;*.flv;*.wmv;*.asf;*.lrv|All files|*.*'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileNames | ConvertTo-Json -Compress
}
"""
    return parse_picker_paths(run_picker_script(script, "Выбор файла не удался."))


def picker_single_file() -> list[Path]:
    script = PICKER_BOOTSTRAP + r"""
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Video source'
$dialog.Multiselect = $false
$dialog.Filter = 'Video files|*.mp4;*.mov;*.mkv;*.m4v;*.avi;*.webm;*.mxf;*.mts;*.m2ts;*.ts;*.vob;*.3gp;*.ogv;*.flv;*.wmv;*.asf;*.lrv|All files|*.*'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileName | ConvertTo-Json -Compress
}
"""
    return parse_picker_paths(run_picker_script(script, "Выбор файла не удался."))


def picker_folder() -> list[Path]:
    script = PICKER_BOOTSTRAP + r"""
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = 'Folder'
$dialog.ShowNewFolderButton = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  @($dialog.SelectedPath) | ConvertTo-Json -Compress
}
"""
    return parse_picker_paths(run_picker_script(script, "Выбор папки не удался."))


def source_file_list_lines(source: Path) -> list[str]:
    if not source.exists():
        return [tr("file_list_missing", path=source)]
    if source.is_file():
        return ["No.  List", "---  ----", f"001. {source.name}"]

    names = sorted(
        (path.name for path in source.rglob("*") if path.is_file()),
        key=lambda item: item.casefold(),
    )
    if not names:
        return [tr("file_list_empty")]

    number_width = max(3, len(str(len(names))))
    lines = [
        f"{'No.':>{number_width}}  List",
        f"{'-' * number_width}  ----",
    ]
    lines.extend(f"{index:0{number_width}d}. {name}" for index, name in enumerate(names, start=1))
    return lines


async def show_source_file_list() -> None:
    if state["running"]:
        safe_notify(tr("another_running"), type="warning")
        return

    source = role_path("source")
    state.update(
        {
            "running": True,
            "cancel": False,
            "progress": 0.02,
            "status": f"{tr('running')}: {tr('file_list')}",
            "lines": [],
            "line_sequence": 0,
            "terminal_reset_id": int(state.get("terminal_reset_id", 0)) + 1,
            "log_version": int(state["log_version"]) + 1,
            "exit_code": None,
            "active_log_file": "",
        }
    )
    try:
        lines = await run.io_bound(source_file_list_lines, source)
        for line in lines:
            add_log(line)
        count = max(0, len(lines) - 2)
        state["terminal_scroll_top_seq"] = int(state.get("line_sequence", 0))
        state["exit_code"] = 0
        state["progress"] = 1.0
        state["status"] = f"{tr('done')}: {tr('file_list')} [{count}]"
        safe_notify(tr("file_list_ready", count=count), type="positive")
    except Exception as exc:
        state["exit_code"] = 1
        state["progress"] = max(float(state["progress"]), 0.98)
        state["status"] = f"{tr('error')}: {exc}"
        add_log(f"ERROR: {exc.__class__.__name__}: {exc}")
        safe_notify(str(exc), type="negative")
    finally:
        state["running"] = False


def input_file_options() -> dict[str, str]:
    options: dict[str, str] = {}
    folder = source_dir()
    for path in media_files_in(folder):
        rel = path.name if folder.is_file() else path.relative_to(folder) if path.is_relative_to(folder) else path.name
        options[str(path)] = str(rel)
    return options


def select_input_path(value: Any) -> None:
    if value:
        state["input_path"] = str(value)
        state["output_path"] = ""
        refresh_views()


def set_palette(value: Any) -> None:
    palette = str(value)
    state["palette"] = palette
    presets = [spec.name for spec in _presets.list_all() if spec.palette == palette]
    if state.get("preset") not in presets and presets:
        state["preset"] = presets[0]
        state["output_path"] = ""
    refresh_views()


def open_palette_module(palette: str) -> None:
    state["mode"] = "preset"
    state["module"] = "preset"
    set_palette(palette)


def set_preset(spec: _presets.PresetSpec) -> None:
    state["palette"] = spec.palette
    state["preset"] = spec.name
    state["output_path"] = ""
    refresh_views()


def toggle_pin(spec: _presets.PresetSpec) -> None:
    key = f"{spec.palette}/{spec.name}"
    pins: set[str] = state.setdefault("pins", set())
    if key in pins:
        pins.remove(key)
    else:
        pins.add(key)
    save_pins()
    refresh_views()


def open_module(mode: str) -> None:
    state["mode"] = mode
    state["module"] = mode
    if mode in {"profile", "batch"}:
        state["encoder"] = profile_encoder(selected_profile())
        state["output_path"] = ""
    refresh_views()


def back_to_modules() -> None:
    state["module"] = None
    refresh_views()


def set_encoder(encoder: str) -> None:
    state["encoder"] = encoder
    state["output_path"] = ""
    refresh_views()


def encoder_parts(encoder: str) -> dict[str, str]:
    name = str(encoder or _runner.DEFAULT_ENCODER)
    parts = {
        "family": "x264",
        "backend": "cpu",
        "quality": "17",
        "mux_container": str(state.get("mux_container") or "mp4"),
        "prores_profile": str(state.get("prores_profile") or "lt"),
        "prores_container": str(state.get("prores_container") or "mov"),
        "dnxhr_profile": str(state.get("dnxhr_profile") or "hq"),
    }
    if name.startswith("prores"):
        parts["family"] = "prores"
        parts["backend"] = "cpu"
        parts["prores_container"] = "mxf" if name.endswith("_mxf") else "mov"
        if "422hq" in name:
            parts["prores_profile"] = "hq"
        elif "422" in name:
            parts["prores_profile"] = "422"
        else:
            parts["prores_profile"] = "lt"
        return parts
    if name.startswith("dnxhr_"):
        parts["family"] = "dnxhr"
        parts["backend"] = "cpu"
        profile = name.removeprefix("dnxhr_")
        parts["dnxhr_profile"] = profile if profile in DNXHR_PROFILE_LABELS else "hq"
        return parts
    for codec, family in [("h264", "x264"), ("h265", "x265")]:
        if name.startswith(f"{codec}_crf"):
            parts.update({"family": family, "backend": "cpu", "quality": name.rsplit("crf", 1)[-1]})
            return parts
        for backend in ("nvenc", "qsv", "amf"):
            marker = f"{codec}_{backend}_q"
            if name.startswith(marker):
                parts.update({"family": family, "backend": backend, "quality": name.rsplit("_q", 1)[-1]})
                return parts
    return parts


def prores_encoder_name(profile: str, container: str) -> str:
    profile = profile if profile in PRORES_PROFILE_LABELS else "lt"
    container = container if container in PRORES_CONTAINER_LABELS else "mov"
    base = {"lt": "prores_lt", "422": "prores_422", "hq": "prores_422hq"}[profile]
    candidate = f"{base}_mxf" if container == "mxf" else base
    return candidate if candidate in _runner.ENCODERS else base


def encoder_from_parts(
    family: str,
    backend: str,
    quality: str,
    prores_profile: str = "lt",
    prores_container: str = "mov",
    dnxhr_profile: str = "hq",
) -> str:
    family = family if family in ENCODER_FAMILY_LABELS else "x264"
    if family == "prores":
        return prores_encoder_name(prores_profile, prores_container)
    if family == "dnxhr":
        profile = dnxhr_profile if dnxhr_profile in DNXHR_PROFILE_LABELS else "hq"
        candidate = f"dnxhr_{profile}"
        return candidate if candidate in _runner.ENCODERS else "dnxhr_hq"
    codec = "h265" if family == "x265" else "h264"
    backend = backend if backend in ENCODER_BACKEND_LABELS else "cpu"
    quality = quality if quality in ENCODER_QUALITY_LABELS else "17"
    if backend == "cpu":
        candidate = f"{codec}_crf{quality}"
    else:
        candidate = f"{codec}_{backend}_q{quality}"
    return candidate if candidate in _runner.ENCODERS else _runner.DEFAULT_ENCODER


def has_parametric_controls(encoder: str) -> bool:
    return str(encoder or "").startswith(("h264_", "h265_", "prores", "dnxhr"))


def set_encoder_part(part: str, value: str) -> None:
    parts = encoder_parts(str(state.get("encoder") or _runner.DEFAULT_ENCODER))
    parts[part] = value
    if part in {"mux_container", "prores_profile", "prores_container", "dnxhr_profile"}:
        state[part] = value
    if parts["family"] in {"prores", "dnxhr"}:
        parts["backend"] = "cpu"
    state["mux_container"] = parts["mux_container"]
    state["prores_profile"] = parts["prores_profile"]
    state["prores_container"] = parts["prores_container"]
    state["dnxhr_profile"] = parts["dnxhr_profile"]
    set_encoder(
        encoder_from_parts(
            parts["family"],
            parts["backend"],
            parts["quality"],
            parts["prores_profile"],
            parts["prores_container"],
            parts["dnxhr_profile"],
        )
    )


def backend_options() -> dict[str, str]:
    return {
        backend: label
        for backend, label in ENCODER_BACKEND_LABELS.items()
        if backend == "cpu" or any(f"_{backend}_" in name for name in _runner.ENCODERS)
    }


def sync_profile_selection(value: Any) -> None:
    name = str(value or "")
    state["profile"] = name
    state["encoder"] = profile_encoder(name)
    state["output_path"] = ""
    refresh_views()


def open_folder(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        os.startfile(str(path))  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])


def refresh_views() -> None:
    try:
        render_workspace_toolbar.refresh()
    except Exception:
        pass
    try:
        content_view.refresh()
    except Exception:
        pass
    try:
        render_encoding_sidebar.refresh()
    except Exception:
        pass


def set_role_path(role: str, value: str, *, notify: bool = True, ensure: bool = True) -> None:
    state["path_cache"] = update_path_cache(role, value)
    selected = role_path(role)
    if ensure and not selected.exists():
        selected.mkdir(parents=True, exist_ok=True)
    if role == "source":
        state["batch_input_dir"] = str(selected.parent if selected.is_file() else selected)
        if selected.is_file():
            state["input_path"] = str(selected)
        else:
            current = Path(str(state.get("input_path") or ""))
            if not current.is_file() or not current.is_relative_to(selected):
                state["input_path"] = first_video_in(selected)
        state["output_path"] = ""
    else:
        state["batch_output_dir"] = str(selected)
        state["output_path"] = ""
    if notify:
        safe_notify("Путь сохранен.", type="positive")


def reset_output_override(output_element: Any | None = None) -> None:
    state["output_path"] = ""
    if output_element is not None:
        output_element.value = ""
    refresh_views()


def display_workspace_path(path_value: Any) -> str:
    text = str(path_value or "").strip()
    if not text:
        return ""
    path = Path(text).expanduser()
    if not path.is_absolute():
        path = ROOT / path
    try:
        return str(path.resolve().relative_to(ROOT)) or "."
    except (OSError, ValueError):
        return str(path)


def reload_ui(delay_ms: int = 0) -> None:
    script = f"window.setTimeout(() => window.location.reload(), {max(0, int(delay_ms))})"
    delivered = False
    for client in list(nicegui_app.clients()):
        if getattr(client, "_deleted", False) or not client.has_socket_connection:
            continue
        client.run_javascript(script)
        delivered = True
    if not delivered:
        ui.run_javascript(script)


def mark_workspace_feedback(role: str, action: str) -> None:
    state["workspace_feedback"] = {"role": canonical_role(role), "action": str(action or "path")}


def workspace_feedback() -> dict[str, str]:
    value = state.get("workspace_feedback")
    return dict(value) if isinstance(value, dict) else {}


def clear_workspace_feedback() -> None:
    state["workspace_feedback"] = {}


def save_workbench_path(role: WorkbenchRole, value: Any) -> None:
    app_role = "output" if role == "target" else "source"
    path_text = str(value or "").strip()
    if not path_text:
        path_text = str(PATHS.output_dir if role == "target" else PATHS.input_dir)
    selected = resolve_cached_path(path_text, PATHS.output_dir if role == "target" else PATHS.input_dir)
    set_role_path(app_role, str(selected), notify=False, ensure=role == "target" or not selected.is_file())


def normalized_absolute_path(path_value: Any) -> Path:
    path = Path(str(path_value or "")).expanduser()
    if not path.is_absolute():
        path = ROOT / path
    return path.resolve(strict=False)


def paths_equal(left: Any, right: Any) -> bool:
    return os.path.normcase(str(normalized_absolute_path(left))) == os.path.normcase(str(normalized_absolute_path(right)))


def remove_path_tree(path: Path) -> int:
    is_junction = bool(getattr(os.path, "isjunction", lambda _path: False)(path))
    if path.is_symlink() or is_junction:
        path.rmdir() if path.is_dir() else path.unlink()
        return 1
    if path.is_file():
        path.unlink()
        return 1
    if path.is_dir():
        shutil.rmtree(path)
        return 1
    return 0


def validate_workspace_delete_target(path_value: Any) -> Path:
    target = normalized_absolute_path(path_value)
    if target.parent == target or paths_equal(target, ROOT):
        raise RuntimeError(f"Отказ от удаления защищённого пути: {target}")
    return target


def delete_workspace_path_contents(path_value: Any) -> dict[str, Any]:
    target = validate_workspace_delete_target(path_value)
    if not target.exists() and not target.is_symlink():
        return {"path": str(target), "kind": "missing", "removed": 0}
    is_junction = bool(getattr(os.path, "isjunction", lambda _path: False)(target))
    if target.is_file() or target.is_symlink() or is_junction:
        return {"path": str(target), "kind": "file", "removed": remove_path_tree(target)}
    removed = 0
    for child in sorted(target.iterdir(), key=lambda item: item.name.casefold()):
        # .gitkeep is not spared: input and output must be genuinely empty after
        # a clear, so nobody has to wonder what the leftover file is or whether it
        # is safe to delete. The folders come from install/init_folders.cmd.
        removed += remove_path_tree(child)
    return {"path": str(target), "kind": "folder", "removed": removed}


def open_workspace_path(role: str) -> None:
    path = output_dir() if canonical_role(role) == "target" else source_dir()
    if not path.exists():
        raise FileNotFoundError(tr("source_folder_missing", path=path))
    if path.is_file():
        if os.name == "nt":
            subprocess.Popen(["explorer.exe", f"/select,{path}"], **hidden_subprocess_kwargs())
        else:
            open_folder(path.parent)
        return
    open_folder(path)


def workspace_pin_click_handler(role: str, pinned: bool):
    async def handler() -> None:
        path_value = str(output_dir() if canonical_role(role) == "target" else source_dir())
        try:
            await run.io_bound(WORKBENCH_ADAPTER.set_path_pinned, role, path_value, pinned)
            mark_workspace_feedback(role, "pin" if pinned else "unpin")
            add_log(f"{'Pinned' if pinned else 'Unpinned'} {canonical_role(role)} path: {path_value}")
            render_workspace_toolbar.refresh()
        except Exception as exc:
            add_log(f"ERROR: {exc.__class__.__name__}: {exc}")
            safe_notify(str(exc), type="negative")

    return handler


def workspace_delete_path_click_handler(role: str):
    async def handler() -> None:
        if state["running"]:
            safe_notify(tr("another_running"), type="warning")
            return
        canonical = canonical_role(role)
        path = output_dir() if canonical == "target" else source_dir()
        role_title = tr("target_folder") if canonical == "target" else tr("source_folder")
        with ui.dialog() as dialog, ui.card().classes("panel rounded-lg"):
            ui.label(f"Очистить {role_title}?" if active_language() == "ru" else f"Clear {role_title}?").classes("text-base font-semibold")
            ui.label(str(normalized_absolute_path(path))).classes("max-w-3xl break-all font-mono text-xs")
            with ui.row().classes("gap-2"):
                ui.button(tr("cancel"), on_click=dialog.close).props("dense flat")
                ui.button(tr("delete_io_short"), on_click=lambda: dialog.submit(True)).props("dense color=negative")
        if not await dialog:
            return
        try:
            result = await run.io_bound(delete_workspace_path_contents, path)
            if result.get("kind") == "file":
                await run.io_bound(WORKBENCH_ADAPTER.delete_path_history, canonical, str(path))
                save_workbench_path(canonical, "")
            mark_workspace_feedback(canonical, "delete")
            add_log(f"Cleared {role_title}: {result.get('path')} [removed={result.get('removed', 0)}]")
            refresh_views()
        except Exception as exc:
            add_log(f"ERROR: {exc.__class__.__name__}: {exc}")
            safe_notify(str(exc), type="negative")

    return handler


def workspace_single_file_click_handler():
    async def handler() -> None:
        if state["running"]:
            safe_notify(tr("another_running"), type="warning")
            return
        try:
            selected = await run.io_bound(picker_single_file)
        except Exception as exc:
            safe_notify(str(exc), type="negative")
            return
        if not selected:
            add_log(tr("picker_cancelled"))
            return
        path_value = str(selected[0])
        save_workbench_path("source", path_value)
        await run.io_bound(WORKBENCH_ADAPTER.remember_path, "source", path_value)
        mark_workspace_feedback("source", "path")
        add_log(f"SOURCE FILE -> {path_value}")
        refresh_views()

    return handler


def workspace_open_click_handler(role: str):
    async def handler() -> None:
        try:
            await run.io_bound(open_workspace_path, role)
        except Exception as exc:
            safe_notify(str(exc), type="negative")

    return handler


def reset_workspace_paths_click_handler():
    async def handler() -> None:
        if state["running"]:
            safe_notify(tr("another_running"), type="warning")
            return
        result = await run.io_bound(WORKBENCH_ADAPTER.clear_path_history_cache_keep_pins)
        save_workbench_path("source", "")
        save_workbench_path("target", "")
        add_log(
            "Workspace reset: "
            f"sources={result.get('removed_sources', 0)}, targets={result.get('removed_targets', 0)}, "
            f"pins kept={result.get('kept_pins', 0)}"
        )
        safe_notify(tr("operation_done"), type="positive")
        refresh_views()

    return handler


def workspace_path_select_handler(role: str):
    async def handler(event: Any) -> None:
        path_value = str(getattr(event, "value", "") or "").strip()
        if not path_value:
            return
        canonical = canonical_role(role)
        save_workbench_path(canonical, path_value)
        actual_path = str(output_dir() if canonical == "target" else source_dir())
        await run.io_bound(WORKBENCH_ADAPTER.remember_path, canonical, actual_path)
        mark_workspace_feedback(role, "path")
        add_log(f"{canonical.upper()} -> {actual_path}")
        refresh_views()

    return handler


def workspace_delete_both_click_handler():
    async def handler() -> None:
        if state["running"]:
            safe_notify(tr("another_running"), type="warning")
            return
        source = source_dir()
        target = output_dir()
        with ui.dialog() as dialog, ui.card().classes("panel rounded-lg"):
            ui.label("Удалить содержимое I/O?" if active_language() == "ru" else "Delete I/O contents?").classes("text-base font-semibold")
            ui.label(f"SOURCE: {source}").classes("max-w-3xl break-all font-mono text-xs")
            ui.label(f"TARGET: {target}").classes("max-w-3xl break-all font-mono text-xs")
            with ui.row().classes("gap-2"):
                ui.button(tr("cancel"), on_click=dialog.close).props("dense flat")
                ui.button(tr("delete_io_short"), on_click=lambda: dialog.submit(True)).props("dense color=negative")
        if not await dialog:
            return
        state["running"] = True
        try:
            source_result = await run.io_bound(delete_workspace_path_contents, source)
            target_result = (
                {"path": str(target), "kind": "same", "removed": 0}
                if paths_equal(source, target)
                else await run.io_bound(delete_workspace_path_contents, target)
            )
            for role, path, result in (("source", source, source_result), ("target", target, target_result)):
                if result.get("kind") == "file":
                    await run.io_bound(WORKBENCH_ADAPTER.delete_path_history, role, str(path))
                    save_workbench_path(role, "")
            add_log(f"Cleared SOURCE [removed={source_result.get('removed', 0)}]")
            add_log(f"Cleared TARGET [removed={target_result.get('removed', 0)}]")
            mark_workspace_feedback("source", "delete")
            refresh_views()
        except Exception as exc:
            add_log(f"ERROR: {exc.__class__.__name__}: {exc}")
            safe_notify(str(exc), type="negative")
        finally:
            state["running"] = False

    return handler


def workspace_pick_click_handler(role: str):
    async def handler() -> None:
        if state["running"]:
            safe_notify(tr("another_running"), type="warning")
            return
        try:
            selected = await run.io_bound(picker_folder)
        except Exception as exc:
            safe_notify(str(exc), type="negative")
            return
        if not selected:
            add_log(tr("picker_cancelled"))
            return
        path_value = str(selected[0])
        canonical = canonical_role(role)
        save_workbench_path(canonical, path_value)
        await run.io_bound(WORKBENCH_ADAPTER.remember_path, canonical, path_value)
        mark_workspace_feedback(canonical, "path")
        add_log(f"{canonical.upper()} -> {path_value}")
        refresh_views()

    return handler


@ui.refreshable
def render_workspace_toolbar() -> None:
    with ui.element("div").classes("panel workspace-panel audion-workspace-panel"):
        WORKBENCH_RENDERER.render_address_rows()
        WORKBENCH_RENDERER.render_action_bar()


def render_mode_switch() -> None:
    ui.radio(
        options=MODE_LABELS,
        value=str(state["mode"]),
        on_change=lambda event: (state.update({"mode": event.value}), content_view.refresh()),
    ).props("inline dense").classes("mode-radio")


def render_module_hub() -> None:
    with ui.element("div").classes("module-grid processing-grid"):
        for palette, title in PALETTE_LABELS.items():
            count = len([spec for spec in _presets.list_all() if spec.palette == palette])
            tile = ui.element("div").classes("module-tile processing-tile clickable-tile")
            tile.on("click", lambda _event, item=palette: open_palette_module(item))
            with tile:
                ui.button(
                    ui_label(palette, title.upper()),
                    icon=material_icon(palette),
                    on_click=lambda item=palette: open_palette_module(item),
                ).props("dense flat no-wrap").classes("module-button")
                ui.label(f"{count} presets").classes("module-summary")


def render_workflow_hub() -> None:
    with ui.element("div").classes("module-grid workflow-grid"):
        for mode, meta in MODULE_META.items():
            tile = ui.element("div").classes("module-tile clickable-tile")
            tile.on("click", lambda _event, item=mode: open_module(item))
            with tile:
                ui.button(
                    ui_label(mode),
                    icon=material_icon(mode),
                    on_click=lambda item=mode: open_module(item),
                ).props("dense flat no-wrap").classes("module-button")
                ui.label(tr("folder_processing") if mode == "batch" else tr("doctor_lists_probe") if mode == "service" else meta["summary"]).classes("module-summary")


def render_main_dashboard() -> None:
    files_count = len(media_files_in(source_dir()))
    with ui.element("div").classes("dashboard-grid"):
        with ui.element("div").classes("panel dashboard-card vs-dashboard-card"):
            with ui.row().classes("vs-dashboard-row w-full items-center justify-center no-wrap"):
                ui.radio(
                    options=VS_ACCEL_LABELS,
                    value=str(state.get("vs_accel") or "cpu"),
                    on_change=lambda event: state.update({"vs_accel": str(event.value)}),
                ).props("inline dense").classes("compact-radio vs-accel-radio")
        with ui.element("div").classes("panel dashboard-card input-dashboard-card"):
            ui.label(tr("input_files")).classes("section-title")
            with ui.element("div").classes("dashboard-card-body input-dashboard-body"):
                with ui.element("div").classes("dashboard-actions action-grid-3"):
                    dashboard_button("status", run_input_status)
                    file_list_button = dashboard_button("file_list", show_source_file_list, "List")
                    file_list_button.tooltip(tr("file_list"))
                    dashboard_button("probe", lambda: run_service("probe"), "Probe")
                ui.label(f"SOURCE: {files_count} media files").classes("module-summary")
        with ui.element("div").classes("panel dashboard-card profiles-dashboard-card"):
            ui.label(tr("codecs_profiles")).classes("section-title")
            with ui.element("div").classes("dashboard-actions action-grid-5"):
                dashboard_button("doctor", lambda: run_service("doctor"), "Doctor")
                dashboard_button("info", lambda: run_service("info"), "Info")
                dashboard_button("encoders", lambda: run_service("list_encoders"), "Encoders")
                dashboard_button("profiles", lambda: run_service("list_profiles"), "Profiles")
                dashboard_button("presets", lambda: run_service("list_presets"), "Presets")
        with ui.element("div").classes("panel dashboard-card environment-card"):
            ui.label(tr("environment")).classes("section-title")
            with ui.element("div").classes("dashboard-actions environment-actions-grid install-grid-3"):
                vs_button = dashboard_button("install_vs", lambda: run_installer("vs"), extra_classes="environment-service-button")
                vs_button.tooltip(tr("install_vs_tooltip"))
                vs_plugins_button = dashboard_button("install_vs_plugins", lambda: run_installer("vs_plugins"), extra_classes="environment-service-button")
                vs_plugins_button.tooltip(tr("install_vs_plugins_tooltip"))
                ffmpeg_button = dashboard_button("install_ffmpeg", lambda: run_installer("ffmpeg"), extra_classes="environment-service-button")
                ffmpeg_button.tooltip(tr("install_ffmpeg_tooltip"))
            ui.label("VS host / plugins / FFmpeg install").classes("module-summary")


def render_module_nav(title: str, run_label: str | None = None, run_handler: Any | None = None, detail: str = "") -> None:
    with ui.element("div").classes("panel module-nav"):
        with ui.row().classes("audion-command-nav w-full items-center gap-2"):
            back_button = ui.button(tr("back").upper(), icon=material_icon("back"), on_click=back_to_modules).props("dense flat no-wrap").classes("audion-action audion-nav-back w-28 rounded-lg")
            back_button.tooltip(tr("back"))
            ui.label(title).classes("module-title")
            if detail:
                ui.label(detail).classes("run-title")
            ui.space()
            if run_label and run_handler:
                run_button = ui.button("ЗАПУСТИТЬ" if active_language() == "ru" else "RUN", icon=material_icon("run"), on_click=run_handler).props("dense flat no-wrap").classes("audion-action audion-nav-run-button rounded-lg")
                run_button.tooltip(run_label)


def render_source_fields(*, batch: bool = False) -> None:
    if batch:
        with ui.element("div").classes("io-grid"):
            folder_ref = ui.input(
                "Папка-источник",
                value=str(state.get("batch_input_dir") or PATHS.input_dir),
                on_change=lambda event: state.update({"batch_input_dir": event.value}),
            ).props("dense outlined").classes("field")
            ui.button("Выбрать", icon="folder_open", on_click=lambda: choose_folder_into("batch_input_dir", folder_ref)).props("dense flat").classes("tool-button")
            out_ref = ui.input(
                "Папка результата",
                value=str(state.get("batch_output_dir") or PATHS.output_dir),
                on_change=lambda event: state.update({"batch_output_dir": event.value}),
            ).props("dense outlined").classes("field")
            ui.button("Выбрать", icon="folder_open", on_click=lambda: choose_folder_into("batch_output_dir", out_ref)).props("dense flat").classes("tool-button")
        return

    options = input_file_options()
    current_input = str(state.get("input_path") or "")
    if current_input and current_input not in options:
        options = {current_input: current_input, **options}
    with ui.element("div").classes("io-grid"):
        input_ref = ui.select(
            options=options,
            label="Исходный файл",
            value=current_input if current_input in options else None,
            on_change=lambda event: select_input_path(event.value),
        ).props("dense outlined clearable options-dense popup-content-class=audion-select-popup").classes("field")
        ui.button("Выбрать", icon="video_file", on_click=lambda: choose_file_into(input_ref)).props("dense flat").classes("tool-button")
        output_ref = ui.input(
            "Выходной файл",
            value=str(state.get("output_path") or ""),
            placeholder=str(default_output_path()),
            on_change=lambda event: state.update({"output_path": event.value}),
        ).props("dense outlined clearable").classes("field")
        ui.button("Авто", icon="auto_fix_high", on_click=lambda: (state.update({"output_path": ""}), setattr(output_ref, "value", ""))).props("dense flat").classes("tool-button")


def choose_file_into(input_element: Any) -> None:
    try:
        paths = picker_file()
        if paths:
            state["input_path"] = str(paths[0])
            state["output_path"] = ""
            input_element.value = str(paths[0])
            refresh_views()
    except Exception as exc:
        safe_notify(str(exc), type="negative")


def choose_folder_into(key: str, input_element: Any) -> None:
    try:
        paths = picker_folder()
        if paths:
            state[key] = str(paths[0])
            input_element.value = str(paths[0])
    except Exception as exc:
        safe_notify(str(exc), type="negative")


def render_encoder_fields() -> None:
    encoders = _runner.list_encoders()
    with ui.element("div").classes("encoding-grid"):
        ui.select(
            options={name: name for name in encoders},
            label="ffmpeg profile",
            value=str(state.get("encoder") or _runner.DEFAULT_ENCODER),
            on_change=lambda event: set_encoder(str(event.value)),
        ).props("dense outlined").classes("field")


def render_profile_toggle() -> None:
    profiles = profile_names()
    if not profiles:
        ui.label("Profiles not found").classes("muted")
        return
    ui.toggle(
        options={name: name for name in profiles},
        value=selected_profile(),
        on_change=lambda event: sync_profile_selection(event.value),
    ).props("dense no-caps unelevated").classes("profile-toggle").style(
        f"--profile-toggle-count: {len(profiles)}"
    )


def render_vapoursynth_accel() -> None:
    with ui.element("div").classes("panel vs-accel-panel"):
        with ui.row().classes("vs-accel-row w-full items-center justify-center no-wrap"):
            ui.radio(
                options=VS_ACCEL_LABELS,
                value=str(state.get("vs_accel") or "cpu"),
                on_change=lambda event: state.update({"vs_accel": str(event.value)}),
            ).props("inline dense").classes("compact-radio vs-accel-radio")


def render_codec_card(family: str, parts: dict[str, str]) -> None:
    active = parts["family"] == family
    card = ui.element("div").classes("codec-card active" if active else "codec-card inactive")
    card.on("click", lambda _event, item=family: set_encoder_part("family", item))
    with card:
        ui.label(ENCODER_FAMILY_LABELS[family]).classes("codec-head-label")
        if family in {"x264", "x265"}:
            backend = parts["backend"] if parts["family"] == family else "cpu"
            quality_label = "CRF" if backend == "cpu" else "CQ"
            ui.label(quality_label).classes("codec-field-label")
            quality = parts["quality"] if active and parts["quality"] in ENCODER_QUALITY_LABELS else "17"
            quality_radio = ui.radio(
                options=ENCODER_QUALITY_LABELS,
                value=quality,
                on_change=lambda event, item=family: (set_encoder_part("family", item), set_encoder_part("quality", str(event.value))),
            ).props("dense").classes("compact-radio mini-radio")
            if not active:
                quality_radio.props("disable")
            ui.label("Container").classes("codec-field-label")
            mux_radio = ui.radio(
                options=MUX_CONTAINER_LABELS,
                value=str(state.get("mux_container") or "mp4"),
                on_change=lambda event, item=family: (set_encoder_part("family", item), set_encoder_part("mux_container", str(event.value))),
            ).props("dense").classes("compact-radio mini-radio")
            if not active:
                mux_radio.props("disable")
            return
        if family == "prores":
            ui.label("Profile").classes("codec-field-label")
            profile_radio = ui.radio(
                options=PRORES_PROFILE_LABELS,
                value=parts["prores_profile"] if active else str(state.get("prores_profile") or "lt"),
                on_change=lambda event: (set_encoder_part("family", "prores"), set_encoder_part("prores_profile", str(event.value))),
            ).props("dense").classes("compact-radio mini-radio")
            if not active:
                profile_radio.props("disable")
            ui.label("Wrapper").classes("codec-field-label")
            container_radio = ui.radio(
                options=PRORES_CONTAINER_LABELS,
                value=parts["prores_container"] if active else str(state.get("prores_container") or "mov"),
                on_change=lambda event: (set_encoder_part("family", "prores"), set_encoder_part("prores_container", str(event.value))),
            ).props("dense").classes("compact-radio mini-radio")
            if not active:
                container_radio.props("disable")
            return
        ui.label("Profile").classes("codec-field-label")
        dnxhr_radio = ui.radio(
            options=DNXHR_PROFILE_LABELS,
            value=parts["dnxhr_profile"] if active else str(state.get("dnxhr_profile") or "hq"),
            on_change=lambda event: (set_encoder_part("family", "dnxhr"), set_encoder_part("dnxhr_profile", str(event.value))),
        ).props("dense").classes("compact-radio mini-radio")
        if not active:
            dnxhr_radio.props("disable")


@ui.refreshable
def render_encoding_sidebar() -> None:
    encoder = str(state.get("encoder") or _runner.DEFAULT_ENCODER)
    parts = encoder_parts(encoder)
    with ui.element("div").classes("encode-aside"):
        ui.label(tr("encoding")).classes("section-title")
        with ui.element("div").classes("encode-strip"):
            with ui.row().classes("backend-row w-full items-center justify-center gap-2 no-wrap"):
                ui.label("DEC EXP").classes("backend-strip-label")
                ui.radio(
                    options=DECODE_BACKEND_LABELS,
                    value=str(state.get("decode_backend") or "cpu"),
                    on_change=lambda event: state.update({"decode_backend": str(event.value)}),
                ).props("inline dense").classes("compact-radio strip-radio")
        with ui.element("div").classes("encode-strip"):
            with ui.row().classes("backend-row w-full items-center justify-center gap-2 no-wrap"):
                ui.label("ENCODE").classes("backend-strip-label")
                if parts["family"] in {"x264", "x265"}:
                    ui.radio(
                        options=backend_options(),
                        value=parts["backend"],
                        on_change=lambda event: set_encoder_part("backend", str(event.value)),
                    ).props("inline dense").classes("compact-radio strip-radio")
                else:
                    ui.radio(options={"cpu": "CPU"}, value="cpu").props("inline dense disable").classes("compact-radio strip-radio forced-cpu")
        with ui.element("div").classes("codec-grid"):
            for family in ("prores", "x264", "x265", "dnxhr"):
                render_codec_card(family, parts)


def render_choice_param(key: str, schema: dict[str, Any], value: Any) -> None:
    choices = list(schema.get("choices") or [])
    label = PARAM_LABELS.get(key, key)
    if key in BOOL_CHOICE_PARAMS and set(choices) == {"0", "1"}:
        with ui.element("div").classes("param-row"):
            ui.label(label).classes("param-label")
            ui.checkbox(
                value=str(value) == "1",
                on_change=lambda event, item=key: set_param(item, "1" if event.value else "0"),
            ).props("dense").classes("check-line")
            ui.label(str(schema.get("doc") or "")).classes("param-description")
        return
    options = {choice: CHOICE_LABELS.get(str(choice), str(choice)) for choice in choices}
    if 0 < len(choices) <= 4:
        with ui.element("div").classes("param-row"):
            ui.label(label).classes("param-label")
            ui.radio(
                options=options,
                value=value,
                on_change=lambda event, item=key: set_param(item, event.value),
            ).props("inline dense").classes("compact-radio param-inline-radio")
            ui.label(str(schema.get("doc") or "")).classes("param-description")
        return
    with ui.element("div").classes("param-row"):
        ui.label(label).classes("param-label")
        ui.select(
            options=options,
            value=value,
            on_change=lambda event, item=key: set_param(item, event.value),
        ).props("dense outlined").classes("field param-select")
        ui.label(str(schema.get("doc") or "")).classes("param-description")


def render_number_control(key: str, schema: dict[str, Any], value: Any, *, compact_label: bool = False) -> None:
    lo, hi = schema.get("range", (None, None))
    step = 0.05 if schema.get("type") == "float" else 1
    number_ref: dict[str, Any] = {"el": None}
    slider_ref: dict[str, Any] = {"el": None}

    def update(value_in: Any) -> None:
        if value_in is None or value_in == "":
            return
        new_value = float(value_in) if schema.get("type") == "float" else int(float(value_in))
        set_param(key, new_value)
        if number_ref["el"] is not None:
            number_ref["el"].value = new_value
            number_ref["el"].update()
        if slider_ref["el"] is not None:
            slider_ref["el"].value = new_value
            slider_ref["el"].update()

    def spin_number(direction: int) -> None:
        control = number_ref["el"]
        current = getattr(control, "value", None) if control is not None else value
        try:
            new_value = float(current if current not in {None, ""} else value if value not in {None, ""} else 0)
        except (TypeError, ValueError):
            new_value = 0.0
        new_value += step * (1 if direction > 0 else -1)
        if lo is not None:
            new_value = max(new_value, float(lo))
        if hi is not None:
            new_value = min(new_value, float(hi))
        update(new_value)

    with ui.element("div").classes("param-number-control"):
        if compact_label:
            ui.label(PARAM_LABELS.get(key, key)).classes("param-mini-label")
        number_ref["el"] = ui.number(
            value=value,
            min=lo,
            max=hi,
            step=step,
            on_change=lambda event: update(event.value),
        ).props("dense outlined").classes("audion-number number-box")
        with number_ref["el"].add_slot("append"):
            with ui.element("div").classes("audion-number-spinner"):
                ui.button(icon="keyboard_arrow_up", on_click=lambda: spin_number(1)).props("dense flat round tabindex=-1").classes("audion-number-spin-button")
                ui.button(icon="keyboard_arrow_down", on_click=lambda: spin_number(-1)).props("dense flat round tabindex=-1").classes("audion-number-spin-button")
        if lo is not None and hi is not None:
            with ui.element("div").classes("slider-cell"):
                slider_ref["el"] = ui.slider(
                    min=lo,
                    max=hi,
                    step=step,
                    value=value,
                    on_change=lambda event: update(event.value),
                ).props("label").classes("slider")


def render_number_param(key: str, schema: dict[str, Any], value: Any) -> None:
    with ui.element("div").classes("param-row"):
        ui.label(PARAM_LABELS.get(key, key)).classes("param-label")
        render_number_control(key, schema, value)
        ui.label(str(schema.get("doc") or "")).classes("param-description")


def render_grouped_number_params(title: str, keys: list[str], params: dict[str, Any], spec: _presets.PresetSpec) -> None:
    docs = []
    with ui.element("div").classes("param-row param-row-group"):
        ui.label(title).classes("param-label")
        with ui.element("div").classes("param-pair-controls"):
            for key in keys:
                schema = spec.params[key]
                render_number_control(key, schema, params.get(key, schema.get("default")), compact_label=True)
                if schema.get("doc"):
                    docs.append(str(schema.get("doc")))
        ui.label(" / ".join(docs)).classes("param-description")


def render_preset_params() -> None:
    spec = selected_spec()
    params = current_params()
    if not spec.params:
        ui.label("У выбранного пресета нет дополнительных параметров.").classes("muted")
        return
    grouped: set[str] = set()
    with ui.element("div").classes("params-grid"):
        if spec.palette == "restoration" and {"quant1", "quant2"}.issubset(spec.params):
            render_grouped_number_params("Quants" if active_language() == "en" else "Кванты", ["quant1", "quant2"], params, spec)
            grouped.update({"quant1", "quant2"})
        if spec.palette == "restoration" and {"aoffset", "boffset"}.issubset(spec.params):
            render_grouped_number_params("Offsets" if active_language() == "en" else "Офсеты", ["aoffset", "boffset"], params, spec)
            grouped.update({"aoffset", "boffset"})
        for key, schema in spec.params.items():
            if key == "use_cuda" or key in grouped:
                continue
            value = params.get(key, schema.get("default"))
            kind = schema.get("type")
            if kind == "choice":
                render_choice_param(key, schema, value)
            elif kind in {"int", "float"}:
                render_number_param(key, schema, value)
            else:
                with ui.element("div").classes("param-row"):
                    ui.label(PARAM_LABELS.get(key, key)).classes("param-label")
                    ui.input(
                        value=str(value),
                        on_change=lambda event, item=key: set_param(item, event.value),
                    ).props("dense outlined").classes("field")
                    ui.label(str(schema.get("doc") or "")).classes("param-description")


def ordered_specs_for_palette(palette: str) -> list[_presets.PresetSpec]:
    specs = [spec for spec in _presets.list_all() if spec.palette == palette]
    return sorted(specs, key=lambda spec: spec.name)


def render_preset_picker() -> None:
    with ui.element("div").classes("preset-list-wide"):
        for spec in ordered_specs_for_palette(str(state["palette"])):
            selected = spec.name == state.get("preset")
            row = ui.element("div").classes("preset-row selected" if selected else "preset-row")
            row.on("click", lambda _event, item=spec: set_preset(item))
            with row:
                ui.button(display_preset_name(spec.name), on_click=lambda item=spec: set_preset(item)).props("dense flat no-wrap").classes("preset-button")
                ui.label(spec.summary).classes("preset-description")


@ui.refreshable
def content_view() -> None:
    with ui.column().classes("left-stack"):
        if state.get("module") is None:
            render_module_hub()
            render_main_dashboard()
            render_workflow_hub()
            return

        mode = str(state.get("module") or state.get("mode") or "preset")
        if mode == "preset":
            render_module_nav(PALETTE_LABELS.get(str(state["palette"]), "Preset"), tr("run_preset"), run_selected_preset, display_preset_path(selected_spec()))
            with ui.element("div").classes("preset-param-row"):
                render_vapoursynth_accel()
                with ui.element("div").classes("panel params-panel"):
                    ui.label(tr("preset_params")).classes("section-title")
                    render_preset_params()
            with ui.element("div").classes("panel preset-panel preset-panel-wide"):
                ui.label(tr("presets")).classes("section-title")
                render_preset_picker()
        elif mode == "profile":
            render_module_nav(tr("profile"), tr("apply_profile"), run_profile, selected_profile())
            render_vapoursynth_accel()
            with ui.element("div").classes("panel"):
                ui.label("Processing profile").classes("section-title")
                render_profile_toggle()
                ui.label(f"Файл: {Path(str(state.get('input_path') or '')).name or 'не выбран'}").classes("inline-hint")
        elif mode == "batch":
            render_module_nav(tr("batch"), tr("run_batch"), run_batch, selected_profile())
            render_vapoursynth_accel()
            with ui.element("div").classes("panel"):
                ui.label("Batch SOURCE to OUT").classes("section-title")
                render_profile_toggle()
                with ui.row().classes("control-chip-grid w-full pt-2"):
                    ui.checkbox("Вложенные папки", value=bool(state.get("recursive", True)), on_change=lambda event: state.update({"recursive": bool(event.value)})).props("dense")
                    ui.checkbox("Повторить структуру", value=bool(state.get("mirror_tree", True)), on_change=lambda event: state.update({"mirror_tree": bool(event.value)})).props("dense")
                    ui.checkbox("Перезаписать", value=bool(state.get("overwrite")), on_change=lambda event: state.update({"overwrite": bool(event.value)})).props("dense")
                ui.label(f"{source_dir()} -> {output_dir()}").classes("inline-hint mono")
        else:
            render_module_nav(tr("service"))
            render_vapoursynth_accel()
            with ui.element("div").classes("panel"):
                ui.label("Diagnostics and CLI help" if active_language() == "en" else "Диагностика и справка CLI").classes("section-title")
                with ui.element("div").classes("service-grid"):
                    ui.button(ui_label("doctor", "Doctor"), icon=material_icon("doctor"), on_click=lambda: run_service("doctor")).props("dense flat no-wrap").classes("service-button")
                    ui.button(ui_label("info", "Info"), icon=material_icon("info"), on_click=lambda: run_service("info")).props("dense flat no-wrap").classes("service-button")
                    ui.button(ui_label("presets", "Presets"), icon=material_icon("presets"), on_click=lambda: run_service("list_presets")).props("dense flat no-wrap").classes("service-button")
                    ui.button(ui_label("encoders", "Encoders"), icon=material_icon("encoders"), on_click=lambda: run_service("list_encoders")).props("dense flat no-wrap").classes("service-button")
                    ui.button(ui_label("profiles", "Profiles"), icon=material_icon("profiles"), on_click=lambda: run_service("list_profiles")).props("dense flat no-wrap").classes("service-button")
                    ui.button(ui_label("probe", "Probe"), icon=material_icon("probe"), on_click=lambda: run_service("probe")).props("dense flat no-wrap").classes("service-button")


def status_dot_classes() -> str:
    base = "status-dot"
    if state.get("running"):
        return f"{base} running"
    if state.get("exit_code") is None:
        return f"{base} idle"
    if int(state.get("exit_code") or 0) == 0:
        return f"{base} ok"
    return f"{base} error"


_application_css_cache: dict[str, str] = {}


def application_css(name: str) -> str:
    """A stylesheet that lives next to this module rather than inside it."""
    if name not in _application_css_cache:
        path = Path(__file__).resolve().with_name(name)
        _application_css_cache[name] = path.read_text(encoding="utf-8")
    return _application_css_cache[name]


def add_styles() -> None:
    variables_css = "\n".join(f"            --{key}: {value};" for key, value in sorted(theme_variables().items()))
    ui.add_head_html(
        "<style>\n"
        ":root {\n"
        f"{variables_css}\n"
        "}\n"
        + application_css("base.css")
        + WORKBENCH_LAYOUT_CSS
        + WORKBENCH_OVERRIDE_CSS
        + application_css("theme.css")
        + "\n</style>\n"
    )


def build_ui() -> None:
    PATHS.input_dir.mkdir(parents=True, exist_ok=True)
    PATHS.output_dir.mkdir(parents=True, exist_ok=True)
    PATHS.logs_dir.mkdir(parents=True, exist_ok=True)
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    if active_theme_mode() == "dark":
        ui.dark_mode().enable()
    else:
        ui.dark_mode().disable()
    add_styles()
    ui.add_head_html(WORKBENCH_FEEDBACK_CSS)
    terminal_dom_id = f"terminal-pre-{os.getpid()}-{int(time.time() * 1000000)}"

    with ui.header().classes("app-header items-center justify-between px-4"):
        ui.label("Audion VS Engine Lite").classes("app-header-title text-base font-bold")
        with ui.row().classes("app-header-controls items-center gap-2"):
            ui.select(
                options=theme_options(),
                value=active_theme_id(),
                on_change=lambda event: set_theme(event.value),
            ).props("dense outlined options-dense").classes("theme-select")
            ui.button(tr("language_switch"), on_click=toggle_language).props("dense flat no-wrap").classes("tool-button language-button")
            cancel_button = ui.button(tr("cancel"), icon="stop", on_click=cancel_job).props("dense flat color=negative")
            cancel_button.visible = False

    with ui.element("div").classes("shell"):
        with ui.element("main").classes("engine-main"):
            render_workspace_toolbar()
            with ui.element("div").classes("engine-content"):
                content_view()
        with ui.element("aside").classes("engine-right-rail"):
            with ui.element("div").classes("right-codec-pane"):
                render_encoding_sidebar()
            with ui.column().classes("terminal-dock w-full"):
                progress = ui.linear_progress(value=0.0, show_value=False).props("size=3px").classes("terminal-progress-strip")
                with ui.row().classes("terminal-head w-full items-center gap-2"):
                    status_dot = ui.label("●").classes(status_dot_classes())
                    ui.label(tr("terminal")).classes("terminal-head-title")
                    ui.space()
                with ui.row().classes("terminal-toolbar w-full items-center justify-center gap-1 no-wrap"):
                    ui.button(ui_label("status"), icon=material_icon("status"), on_click=run_input_status).props("dense flat no-wrap").classes("tool-button terminal-action-button status-button")
                    ui.button(ui_label("source"), icon=material_icon("source"), on_click=workspace_open_click_handler("source")).props("dense flat no-wrap").classes("tool-button terminal-action-button terminal-folder-button")
                    ui.button(ui_label("out"), icon=material_icon("out"), on_click=workspace_open_click_handler("target")).props("dense flat no-wrap").classes("tool-button terminal-action-button terminal-folder-button")
                    ui.button(ui_label("logs"), icon=material_icon("logs"), on_click=lambda: open_folder(PATHS.logs_dir)).props("dense flat no-wrap").classes("tool-button terminal-action-button terminal-folder-button")
                    ui.button(ui_label("report"), icon=material_icon("report"), on_click=lambda: open_folder(REPORT_DIR)).props("dense flat no-wrap").classes("tool-button terminal-action-button terminal-folder-button report-button")
                    clear_log_button = ui.button(icon="delete_sweep", on_click=clear_terminal_window).props("dense flat round").classes("tool-button terminal-action-button terminal-icon-button")
                    clear_log_button.tooltip(tr("clear_terminal_window"))
                    expand_log_button = ui.button(icon="open_in_full", on_click=lambda: log_dialog.open()).props("dense flat round").classes("tool-button terminal-action-button terminal-icon-button")
                    expand_log_button.tooltip(tr("expand_terminal"))
                log_view = ui.html(f'<pre id="{terminal_dom_id}" class="terminal-pre"></pre>', sanitize=False).classes("terminal w-full")
                with ui.row().classes("terminal-footer w-full items-center gap-2 px-1 pt-1"):
                    footer_status = ui.label(str(state["status"])).classes("min-w-0 flex-1 truncate text-xs")

    with ui.dialog() as log_dialog:
        with ui.card().classes("h-[92vh] w-[92vw] rounded-lg p-3").style("background: var(--audion-terminal-background);"):
            with ui.row().classes("w-full items-center gap-2"):
                ui.label(tr("terminal")).classes("terminal-head-title")
                ui.space()
                clear_dialog_log_button = ui.button(icon="delete_sweep", on_click=clear_terminal_window).props("dense flat round").classes("tool-button terminal-action-button")
                clear_dialog_log_button.tooltip(tr("clear_terminal_window"))
                ui.button(tr("close"), on_click=log_dialog.close).props("dense flat").classes("tool-button terminal-action-button")
            expanded_log_view = ui.html(terminal_html([str(line) for line in state["lines"]]), sanitize=False).classes("terminal w-full h-full")

    last_log_version = {"value": -1}
    rendered_log = {"sequence": 0, "offset": 0, "reset_id": -1}

    refresh_timer: Any | None = None

    def refresh() -> None:
        nonlocal refresh_timer
        try:
            cancel_button.visible = bool(state["running"])
            footer_status.text = str(state["status"])
            status_dot.classes(replace=status_dot_classes())
            progress.value = float(state["progress"])
            log_version = int(state["log_version"])
            if log_version != last_log_version["value"]:
                last_log_version["value"] = log_version
                lines = [str(line) for line in state["lines"]]
                expanded_log_view.content = terminal_html(lines)
                line_sequence = int(state.get("line_sequence", len(lines)))
                line_offset = max(0, line_sequence - len(lines))
                reset_id = int(state.get("terminal_reset_id", 0))
                terminal_id = json.dumps(terminal_dom_id)
                if reset_id != rendered_log["reset_id"] or line_sequence < rendered_log["sequence"] or line_offset != rendered_log["offset"]:
                    payload = json.dumps(terminal_lines_html(lines))
                    rendered_log.update({"sequence": line_sequence, "offset": line_offset, "reset_id": reset_id})
                    scroll_top = int(state.get("terminal_scroll_top_seq", 0)) and int(state.get("terminal_scroll_top_seq", 0)) <= line_sequence
                    if scroll_top:
                        state["terminal_scroll_top_seq"] = 0
                    ui.run_javascript(
                        f"""
                        requestAnimationFrame(() => {{
                          const pre = document.getElementById({terminal_id});
                          if (!pre) return;
                          pre.innerHTML = {payload};
                          const terminal = pre.closest('.terminal');
                          if (terminal) terminal.scrollTop = terminal.scrollHeight;
                          {"if (terminal) terminal.scrollTop = 0;" if scroll_top else ""}
                        }});
                        """
                    )
                elif line_sequence > rendered_log["sequence"]:
                    start = max(0, rendered_log["sequence"] - line_offset)
                    new_lines = lines[start:]
                    payload = json.dumps(terminal_lines_html(new_lines, leading_newline=rendered_log["sequence"] > line_offset))
                    rendered_log.update({"sequence": line_sequence, "offset": line_offset, "reset_id": reset_id})
                    scroll_top = int(state.get("terminal_scroll_top_seq", 0)) and int(state.get("terminal_scroll_top_seq", 0)) <= line_sequence
                    if scroll_top:
                        state["terminal_scroll_top_seq"] = 0
                    ui.run_javascript(
                        f"""
                        requestAnimationFrame(() => {{
                          const pre = document.getElementById({terminal_id});
                          if (!pre) return;
                          const terminal = pre.closest('.terminal');
                          const atBottom = !terminal || (terminal.scrollHeight - terminal.scrollTop - terminal.clientHeight < 48);
                          pre.insertAdjacentHTML('beforeend', {payload});
                          if (terminal && atBottom) terminal.scrollTop = terminal.scrollHeight;
                          {"if (terminal) terminal.scrollTop = 0;" if scroll_top else ""}
                        }});
                        """
                    )
        except RuntimeError as exc:
            message = str(exc)
            if "slot belongs to has been deleted" not in message and "current slot cannot be determined" not in message:
                raise
            logging.warning("NiceGUI refresh timer stopped because the client slot was deleted.")
            if refresh_timer is not None:
                refresh_timer.deactivate()

    refresh_timer = ui.timer(0.2, refresh)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audion VS Engine NiceGUI shell.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    return parser.parse_args()


def port_is_open(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.3)
        return sock.connect_ex((host, port)) == 0


def build_ui_once() -> dict[str, int]:
    """Build the whole page once, headlessly, and report what came of it.

    `--smoke` used to print a line and return, so an app could ship a `build_ui`
    that raised on its first statement and still pass — twice in this fleet it did.
    Here the page is actually built: no browser and no HTTP request, so whatever
    the app defers until a client attaches is skipped, but every widget is
    constructed and the stylesheet has to arrive.
    """
    import asyncio
    import logging
    import re

    from nicegui import core
    from nicegui.client import Client
    from nicegui.page import page as page_definition

    async def build() -> tuple[int, str]:
        core.loop = asyncio.get_running_loop()
        # Work deferred to a connected browser fails here and says nothing about
        # the build. An exception raised by build_ui itself still propagates.
        core.loop.set_exception_handler(lambda _loop, _context: None)
        logging.getLogger("nicegui").setLevel(logging.CRITICAL)
        client = Client(page_definition("/__smoke__"))
        with client:
            build_ui()
        report = len(client.elements), client.shared_head_html + client.head_html
        # The page starts work that waits for a browser to attach. Nothing will
        # attach, so stop it deliberately instead of letting the loop close on it.
        pending = asyncio.all_tasks(core.loop) - {asyncio.current_task()}
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)
        return report

    element_count, head = asyncio.run(build())
    if element_count < 2:
        raise RuntimeError("build_ui produced no widgets")
    # Token prefixes differ between apps, so look for any custom property rather
    # than for one project's naming.
    if not re.search(r"--[\w-]+\s*:", head):
        raise RuntimeError("the stylesheet never reached the page")
    return {"elements": element_count, "stylesheet_bytes": len(head)}


def main() -> int:
    args = parse_args()
    if args.smoke:
        try:
            report = build_ui_once()
        except Exception as error:  # noqa: BLE001
            print(f"FAIL nicegui build: {ROOT}: {error}")
            return 1
        print(
            f"OK nicegui build: {ROOT}"
            f" | widgets={report['elements']}"
            f" | stylesheet={report['stylesheet_bytes']} bytes"
        )
        print(f"OK GUI shell: {ROOT}")
        print(f"presets={len(_presets.list_all())} encoders={len(_runner.list_encoders())} profiles={len(profile_names())}")
        return 0
    if port_is_open(args.host, args.port):
        url = f"http://{args.host}:{args.port}/"
        print(f"GUI already appears to be running: {url}")
        if not args.no_browser:
            webbrowser.open(url)
        return 0
    ui.run(
        root=build_ui,
        title="Audion VS Engine Lite",
        host=args.host,
        port=args.port,
        reload=False,
        native=False,
        show=not args.no_browser,
    )
    return 0


LOG_LOCK = threading.Lock()
_initial_profile = profile_names()[0] if profile_names() else ""
_initial_path_cache = load_path_cache()
_initial_input = first_video_in_input()
state: dict[str, Any] = {
    "mode": "preset",
    "module": None,
    "palette": "precision",
    "preset": "mild_denoise",
    "profile": _initial_profile,
    "input_path": _initial_input,
    "output_path": "",
    "source_path": clean_cache_path(_initial_path_cache.get("source_path")) or str(PATHS.input_dir),
    "destination_path": clean_cache_path(_initial_path_cache.get("output_path")) or str(PATHS.output_dir),
    "batch_input_dir": clean_cache_path(_initial_path_cache.get("source_path")) or str(PATHS.input_dir),
    "batch_output_dir": clean_cache_path(_initial_path_cache.get("output_path")) or str(PATHS.output_dir),
    "path_cache": _initial_path_cache,
    "language": _initial_gui_settings["language"],
    "theme": _initial_gui_settings["theme"],
    "emoji": _initial_gui_settings["emoji"],
    "main_split": 66,
    "terminal_split": 54,
    "right_split": 46,
    "encoder": _runner.DEFAULT_ENCODER,
    "decode_backend": "cpu",
    "vs_accel": "cpu",
    "mux_container": "mp4",
    "prores_profile": "lt",
    "prores_container": "mov",
    "dnxhr_profile": "hq",
    "recursive": True,
    "mirror_tree": True,
    "overwrite": False,
    "params_by_preset": {},
    "pins": load_pins(),
    "running": False,
    "cancel": False,
    "progress": 0.0,
    "status": "Ожидание",
    "lines": [],
    "line_sequence": 0,
    "terminal_reset_id": 0,
    "terminal_scroll_top_seq": 0,
    "log_version": 0,
    "exit_code": None,
    "active_log_file": "",
    "workspace_feedback": {},
}

WORKBENCH_CONFIG = WorkbenchConfig(
    root=ROOT,
    input_path=PATHS.input_dir,
    output_path=PATHS.output_dir,
    history_path=PATH_HISTORY_PATH,
    history_limit=24,
)
WORKBENCH_ADAPTER = WorkbenchAdapter(
    config=WORKBENCH_CONFIG,
    current_path_callback=lambda role: output_dir() if role == "target" else source_dir(),
    save_path_callback=save_workbench_path,
    language_callback=active_language,
    translate_callback=tr,
    log_callback=add_log,
    notify_callback=safe_notify,
    reload_callback=reload_ui,
    busy_callback=lambda: bool(state.get("running")),
    feedback_callback=workspace_feedback,
    set_feedback_callback=mark_workspace_feedback,
    clear_feedback_callback=clear_workspace_feedback,
)
WORKBENCH_ADAPTER.validate()
WORKBENCH_ADAPTER.ensure_initial_history()
WORKBENCH_RENDERER = WorkbenchRenderer(
    adapter=WORKBENCH_ADAPTER,
    handlers=WorkbenchHandlers(
        delete_path=workspace_delete_path_click_handler,
        pin_path=workspace_pin_click_handler,
        select_path=workspace_path_select_handler,
        pick_path=workspace_pick_click_handler,
        open_path=workspace_open_click_handler,
        add_file=workspace_single_file_click_handler,
        reset_paths=reset_workspace_paths_click_handler,
        delete_io=workspace_delete_both_click_handler,
        list_files=show_source_file_list,
    ),
    display_path_callback=display_workspace_path,
)
save_path_cache(state["path_cache"])
ensure_current_params()


if __name__ == "__main__":
    raise SystemExit(main())

"""Audion VS Engine -- CLI entry point.

Usage:
    python -m system_core.main run --palette precision --preset mild_denoise \
           --input ./input/clip.mov --output ./output/clip_clean.mp4 \
           --strength medium --encoder h264_crf17

    python -m system_core.main info
    python -m system_core.main list-presets
    python -m system_core.main list-encoders
    python -m system_core.main probe --input ./input/clip.mov
    python -m system_core.main doctor
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Force UTF-8 stdio regardless of console codepage
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# Make `system_core` importable when launched as `python system_core/main.py`
_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:
    sys.path.insert(0, str(_HERE.parent))

from system_core.engine import PATHS  # noqa: E402
from system_core.engine import env as _env  # noqa: E402
from system_core.engine import presets as _presets  # noqa: E402
from system_core.engine.selfheal import ensure_pip_shims_repaired  # noqa: E402

# Self-heal: if the project was moved, the embedded pip-shebang in
# Scripts/*.exe still points at the previous python.exe and vspipe silently
# exits 1. Detect mismatch on first import and invoke Repair-PipShims.cmd.
_heal_status = ensure_pip_shims_repaired()
if _heal_status == "repaired":
    print("[selfheal] vspipe shim shebang updated to current python.exe")
elif _heal_status.startswith("repair-failed"):
    print(f"[selfheal] WARN: Repair-PipShims exited with {_heal_status}")
from system_core.engine import probe as _probe  # noqa: E402
from system_core.engine import runner as _runner  # noqa: E402
from system_core.engine import logging_json as _logj  # noqa: E402
from system_core.engine import profile as _profile  # noqa: E402


DECODE_BACKENDS = ["cpu", "cuda", "qsv", "d3d11va"]
DECODE_BACKEND_HELP = (
    "experimental/future source decode preference; current VapourSynth source "
    "loaders decode through LWLibavSource -> FFMS2 on CPU"
)


def _decode_backend_note(decode_backend: str) -> str:
    if decode_backend == "cpu":
        return ""
    return (
        f"--decode-backend={decode_backend} is experimental/future only in this "
        "release; current .vpy source loaders still use CPU decode "
        "(LWLibavSource -> FFMS2)."
    )


def _cmd_info(_args) -> int:
    print(f"Audion VS Engine")
    print(f"  root        : {PATHS.root}")
    print(f"  orchestrator: {PATHS.runtime_python}")
    print(f"  vs-host py  : {PATHS.vs_python}")
    print(f"  vspipe      : {PATHS.vspipe}")
    print(f"  ffmpeg      : {PATHS.ffmpeg}")
    print(f"  ffprobe     : {PATHS.ffprobe}")
    print(f"  presets dir : {PATHS.presets_dir}")
    print(f"  input dir   : {PATHS.input_dir}")
    print(f"  output dir  : {PATHS.output_dir}")
    print(f"  logs dir    : {PATHS.logs_dir}")
    return 0


def _cmd_list_presets(_args) -> int:
    for spec in _presets.list_all():
        params = ", ".join(f"{k}={v.get('default')}" for k, v in spec.params.items())
        params_str = f"  [{params}]" if params else ""
        print(f"  {spec.palette}/{spec.name:<24} {spec.summary}{params_str}")
    return 0


def _cmd_list_encoders(_args) -> int:
    for name in _runner.list_encoders():
        args = " ".join(_runner.ENCODERS[name])
        print(f"  {name:<16} {args}")
    return 0


def _cmd_probe(args) -> int:
    info = _probe.video_summary(Path(args.input).resolve())
    print(json.dumps(info, indent=2, ensure_ascii=False))
    return 0


def _cmd_doctor(_args) -> int:
    import subprocess
    return subprocess.run(
        [str(PATHS.runtime_python), str(_HERE / "doctor.py")]
    ).returncode


def _profiles_dir() -> Path:
    return PATHS.config_dir / "profiles"


def _cmd_list_profiles(_args) -> int:
    rows = _profile.list_profile_summary(_profiles_dir())
    if not rows:
        print("(no profiles -- empty config/profiles/)")
        return 0
    name_w = max(len(r[0]) for r in rows)
    pp_w   = max(len(r[1]) for r in rows)
    enc_w  = max(len(r[2]) for r in rows)
    for name, pp, enc, desc in rows:
        print(f"  {name:<{name_w}}  {pp:<{pp_w}}  {enc:<{enc_w}}  {desc}")
    return 0


def _encoder_extension(encoder: str, container: str | None = None) -> str:
    if encoder.startswith(("h264_", "h265_")):
        return ".mkv" if container == "mkv" else ".mp4"
    if encoder.endswith("_mxf"):
        return ".mxf"
    if encoder.startswith(("prores", "dnxhr")):
        return ".mov"
    return ".mp4"


def _profile_to_namespace(prof: dict, *, input_path: str, output_path: str,
                          no_audio: bool, encoder: str | None = None,
                          decode_backend: str = "cpu",
                          vs_accel: str | None = None):
    """Materialize a profile dict into the Namespace shape `_cmd_run` consumes."""
    palette = prof["palette"]
    preset  = prof["preset"]
    ns = argparse.Namespace(
        palette=palette, preset=preset,
        input=input_path, output=output_path,
        encoder=encoder or prof.get("encoder", _runner.DEFAULT_ENCODER),
        decode_backend=decode_backend,
        vs_accel=vs_accel,
        no_audio=no_audio,
    )
    params = prof.get("params", {}) or {}
    spec = _presets.get(palette, preset)
    for k in spec.params:
        attr = "preset_qtgmc" if k == "preset" and preset == "qtgmc_deinterlace" else k
        value = None if k == "use_cuda" and vs_accel is not None else params.get(k, None)
        setattr(ns, attr, value)
    return ns


def _cmd_apply_profile(args) -> int:
    """Resolve profile by name, build a Namespace mirroring `run`, dispatch _cmd_run."""
    try:
        prof = _profile.resolve(args.name, _profiles_dir())
    except KeyError as e:
        print(f"[FAIL] {e}", file=sys.stderr)
        return 2

    if not prof.get("palette") or not prof.get("preset"):
        print(f"[FAIL] profile {args.name!r} is missing palette or preset", file=sys.stderr)
        return 2

    print(f"[profile] {args.name}")
    print(f"          palette: {prof['palette']}")
    print(f"          preset:  {prof['preset']}")
    print(f"          encoder: {args.encoder or prof.get('encoder', _runner.DEFAULT_ENCODER)}")
    print(f"          params:  {prof.get('params', {})}")
    if prof.get("description"):
        print(f"          desc:    {prof['description']}")

    ns = _profile_to_namespace(
        prof,
        input_path=args.input,
        output_path=args.output,
        no_audio=args.no_audio,
        encoder=args.encoder,
        decode_backend=args.decode_backend,
        vs_accel=args.vs_accel,
    )
    return _cmd_run(ns)


_VIDEO_EXTS = {
    # mainstream containers
    ".mp4", ".mov", ".mkv", ".m4v", ".avi", ".webm", ".mxf",
    # camcorder / broadcast
    ".mts", ".m2ts", ".ts", ".vob",
    # legacy / web
    ".3gp", ".ogv", ".flv", ".wmv", ".asf",
    # phone / GoPro extras
    ".lrv",
}
"""Recognized video file extensions for recursive batch. Phase 18: expanded from
the v1.0 set of 7 to cover camcorder formats (.mts/.m2ts), broadcast (.ts/.vob),
legacy (.flv/.wmv) and phone/action-cam derivatives. Add new ones here -- they
flow through `apply-profile-batch` automatically."""


def _cmd_apply_profile_batch(args) -> int:
    """Run a profile over every video file in --input-dir.

    Phase 18 batch behavior (the "pearl" of recursive processing):
      - Mirror source folder structure into --output-dir (default, opt-out via --no-mirror)
      - Skip files where the destination already exists and is non-empty (default,
        opt-out via --overwrite). This makes the batch idempotent and restart-safe.
      - Output filename is always `<stem>__<profile_name>.mp4`.
      - Continues on per-file errors and reports a tally at the end.
    """
    try:
        prof = _profile.resolve(args.name, _profiles_dir())
    except KeyError as e:
        print(f"[FAIL] {e}", file=sys.stderr)
        return 2

    in_dir  = Path(args.input_dir).resolve()
    out_dir = Path(args.output_dir).resolve()
    if not in_dir.is_dir():
        print(f"[FAIL] input-dir not a directory: {in_dir}", file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True, exist_ok=True)

    iterator = in_dir.rglob("*") if args.recursive else in_dir.glob("*")
    files = sorted(p for p in iterator if p.is_file() and p.suffix.lower() in _VIDEO_EXTS)
    if not files:
        print(f"[FAIL] no video files found in {in_dir} "
              f"(extensions: {sorted(_VIDEO_EXTS)})", file=sys.stderr)
        return 1

    # Decide mirroring: default ON for recursive scans, OFF for flat scans.
    mirror = args.recursive and not args.no_mirror
    skip_existing = not args.overwrite

    effective_encoder = args.encoder or prof.get("encoder", _runner.DEFAULT_ENCODER)
    output_ext = _encoder_extension(effective_encoder, getattr(args, "container", None))

    def dest_for(src: Path) -> Path:
        if mirror:
            rel = src.relative_to(in_dir).parent
            target_dir = out_dir / rel
        else:
            target_dir = out_dir
        return target_dir / f"{src.stem}__{args.name}{output_ext}"

    # Pre-pass: classify into to-process vs to-skip.
    plan: list[tuple[Path, Path]] = []
    skipped: list[Path] = []
    for src in files:
        dst = dest_for(src)
        if skip_existing and dst.exists() and dst.stat().st_size > 0:
            skipped.append(src)
        else:
            plan.append((src, dst))

    print(f"[batch] profile={args.name!r}  total={len(files)}  "
          f"to-process={len(plan)}  skipped-existing={len(skipped)}  "
          f"recursive={args.recursive}  mirror={mirror}")
    print(f"        in:  {in_dir}")
    print(f"        out: {out_dir}")
    if not plan:
        print("[batch] nothing to do (everything already processed). "
              "Pass --overwrite to redo.")
        return 0

    fails: list[str] = []
    for i, (src, dst) in enumerate(plan, 1):
        # Ensure mirror-tree subdirs exist
        dst.parent.mkdir(parents=True, exist_ok=True)
        rel_label = src.relative_to(in_dir)
        print()
        print(f"==================== [{i}/{len(plan)}] {rel_label} ====================")
        ns = _profile_to_namespace(
            prof,
            input_path=str(src),
            output_path=str(dst),
            no_audio=args.no_audio,
            encoder=args.encoder,
            decode_backend=args.decode_backend,
            vs_accel=args.vs_accel,
        )
        rc = _cmd_run(ns)
        if rc != 0:
            fails.append(str(rel_label))

    print()
    print("======================================================================")
    ok = len(plan) - len(fails)
    print(f"  batch done: {ok}/{len(plan)} processed, {len(skipped)} skipped (already existed)")
    if fails:
        print(f"  failures ({len(fails)}): {fails}")
    print("======================================================================")
    return 0 if not fails else 2


def _cmd_materialize_profiles(args) -> int:
    """Write built-in profiles as editable JSON files into config/profiles/."""
    written = _profile.materialize_builtins(_profiles_dir(), force=args.force)
    if not written:
        print(f"(nothing to write -- all built-ins already exist in {_profiles_dir()})")
        print(f"Use --force to overwrite.")
        return 0
    print(f"Wrote {len(written)} profile(s) into {_profiles_dir()}:")
    for p in written:
        print(f"  + {p.name}")
    return 0


def _cmd_run(args) -> int:
    PATHS.assert_engine_ready()

    spec = _presets.get(args.palette, args.preset)
    user_params: dict = {}
    for k in spec.params:
        # qtgmc_deinterlace has a user parameter named "preset", which would
        # otherwise collide with the engine preset id held in args.preset.
        attr = "preset_qtgmc" if k == "preset" and spec.name == "qtgmc_deinterlace" else k
        v = getattr(args, attr, None)
        if v is not None:
            user_params[k] = v
    resolved = spec.resolve(user_params)

    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()

    env_extras = _env.build_env(
        palette=spec.palette,
        preset=spec.name,
        input_path=input_path,
        params=resolved,
    )
    vs_accel_arg = getattr(args, "vs_accel", None)
    if vs_accel_arg:
        env_extras["AUDION_VS_USE_CUDA"] = "1" if str(vs_accel_arg).lower() == "cuda" else "0"
    vs_accel = str(vs_accel_arg or ("cuda" if str(resolved.get("use_cuda", "0")) == "1" else "cpu"))
    decode_backend = str(getattr(args, "decode_backend", "cpu") or "cpu")
    decode_note = _decode_backend_note(decode_backend)
    env_extras["AUDION_VS_DECODE_BACKEND"] = "cpu"
    env_extras["AUDION_VS_DECODE_BACKEND_REQUESTED"] = decode_backend

    print(f"[run] {spec.palette}/{spec.name}")
    print(f"      input:    {input_path}")
    print(f"      output:   {output_path}")
    print(f"      params:   {resolved}")
    if decode_note:
        print(f"[warn] {decode_note}", file=sys.stderr)
        print(f"      decode:   source-loader CPU (requested {decode_backend}; experimental)")
    else:
        print(f"      decode:   source-loader CPU")
    print(f"      encoder:  {args.encoder}")
    print(f"      VS accel: {vs_accel}")

    try:
        report = _runner.run_pipeline(
            preset_path=spec.vpy,
            input_path=input_path,
            output_path=output_path,
            env_extras=env_extras,
            encoder=args.encoder,
            audio_passthrough=not args.no_audio,
            log_callback=lambda m: print(f"      cmd: {m}"),
        )
    except _runner.PipelineError as e:
        print(f"[FAIL] {e}", file=sys.stderr)
        return 2

    log_path = _logj.write_report(
        {**report, "params": resolved, "decode_backend": decode_backend,
         "effective_decode_backend": "cpu", "vs_accel": vs_accel},
        palette=spec.palette,
        preset=spec.name,
        input_path=input_path,
    )
    print(f"[ok] elapsed={report['elapsed_s']}s  size={report['output_size']:,} B")
    print(f"     report: {log_path}")
    return 0 if report["ok"] else 2


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="system_core.main",
                                description="Audion VS Engine CLI")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="show paths and runtime info").set_defaults(func=_cmd_info)
    sub.add_parser("list-presets", help="list registered presets").set_defaults(func=_cmd_list_presets)
    sub.add_parser("list-encoders", help="list available encoder profiles").set_defaults(func=_cmd_list_encoders)
    sub.add_parser("doctor", help="run full stack doctor").set_defaults(func=_cmd_doctor)

    pr = sub.add_parser("probe", help="ffprobe summary of a media file")
    pr.add_argument("--input", required=True)
    pr.set_defaults(func=_cmd_probe)

    rn = sub.add_parser("run", help="run a preset on a single file")
    rn.add_argument("--palette", required=True,
                    choices=["precision", "film_looks", "retro", "restoration", "utilities"])
    rn.add_argument("--preset",  required=True)
    rn.add_argument("--input",   required=True)
    rn.add_argument("--output",  required=True)
    rn.add_argument("--encoder", default=_runner.DEFAULT_ENCODER,
                    choices=_runner.list_encoders())
    rn.add_argument("--decode-backend", default="cpu",
                    choices=DECODE_BACKENDS,
                    help=DECODE_BACKEND_HELP)
    rn.add_argument("--vs-accel", choices=["cpu", "cuda"],
                    help="VapourSynth processing acceleration: CPU fallback or CUDA")
    rn.add_argument("--no-audio", action="store_true",
                    help="don't passthrough audio from input")
    # Generic preset parameters (each maps to --<param> at CLI; consumed only by presets that declare them).
    # Stage 1 -- denoise
    rn.add_argument("--strength",         choices=["light", "medium", "strong"],
                    help="strength bucket for: mild_denoise, chroma_cleanup, pregrade_prep")
    rn.add_argument("--sigma",            type=float,
                    help="BM3D luma sigma (shadow_denoise_sota, filmic_rebuild)")
    rn.add_argument("--use-cuda",         choices=["0", "1"], dest="use_cuda",
                    help="1 = bm3dcuda if loaded; default 0 = CPU fallback")
    rn.add_argument("--grain-back",       type=float, dest="grain_back",
                    help="micro-grain restoration after BM3D (shadow_denoise_sota)")
    rn.add_argument("--shadow-threshold", type=float, dest="shadow_threshold",
                    help="luma threshold for shadow zone (shadow_denoise_sota, filmic_rebuild)")
    rn.add_argument("--transition",       type=float,
                    help="smooth transition width above shadow threshold (shadow_denoise_sota)")
    rn.add_argument("--preview-mask",     choices=["0", "1"], dest="preview_mask",
                    help="1 = output mask itself for tuning (shadow_denoise_sota)")
    # Stage 2 -- deband
    rn.add_argument("--range",            type=int,
                    help="neo_f3kdb range (deband_*, archive_clean)")
    rn.add_argument("--y",                type=int,
                    help="neo_f3kdb luma threshold (deband_*)")
    rn.add_argument("--cb",               type=int,
                    help="neo_f3kdb Cb threshold (deband_*)")
    rn.add_argument("--cr",               type=int,
                    help="neo_f3kdb Cr threshold (deband_*)")
    rn.add_argument("--grain-var",        type=float, dest="grain_var",
                    help="AddGrain variance (deband_fine_grain)")
    # Stage 3 -- compositions
    rn.add_argument("--deband-range",     type=int, dest="deband_range",
                    help="filmic_rebuild deband range")
    rn.add_argument("--grain-shadow",     type=float, dest="grain_shadow",
                    help="grain variance in shadow zone (filmic_rebuild)")
    rn.add_argument("--grain-mid",        type=float, dest="grain_mid",
                    help="grain variance in mid-tones (filmic_rebuild)")
    rn.add_argument("--grain-high",       type=float, dest="grain_high",
                    help="grain variance in highlights (filmic_rebuild)")
    rn.add_argument("--high-threshold",   type=float, dest="high_threshold",
                    help="luma threshold where highlight zone begins (filmic_rebuild)")
    # Misc
    rn.add_argument("--denoise",          choices=["light", "medium", "strong"],
                    help="DFTTest sigma bucket (archive_clean)")
    # Film Looks palette
    rn.add_argument("--intensity",        type=float,
                    help="master scale 0..2 (all film_looks / retro presets)")
    rn.add_argument("--stock",            choices=["250D", "500T", "50D"],
                    help="film stock variant (film_35mm)")
    # Restoration palette (Phase 18.B)
    rn.add_argument("--field-order",      choices=["tff", "bff"], dest="field_order",
                    help="field order (qtgmc_deinterlace)")
    rn.add_argument("--qtgmc-preset",     dest="preset_qtgmc",
                    choices=["Draft", "Ultra Fast", "Super Fast", "Very Fast",
                             "Faster", "Fast", "Medium", "Slow", "Slower",
                             "Very Slow", "Placebo"],
                    help="QTGMC speed/quality preset (qtgmc_deinterlace)")
    rn.add_argument("--output-fps",       choices=["single", "double"], dest="output_fps",
                    help="single = source fps, double = 2x for smoothest motion (qtgmc_deinterlace)")
    rn.add_argument("--quality",          choices=["fast", "balanced", "best"],
                    help="NNEDI3 upscale quality/speed mode (nnedi3_upscale_2x)")
    rn.add_argument("--chroma",           choices=["spline36", "nnedi3"],
                    help="chroma upscaler for nnedi3_upscale_2x")
    rn.add_argument("--radius",           type=int,
                    help="temporal/spatial radius (mvtools_mcdegrain, dehaze_local_contrast)")
    rn.add_argument("--thsad",            type=int,
                    help="MVTools block-match SAD threshold (mvtools_mcdegrain)")
    rn.add_argument("--blksize",          choices=["8", "16"],
                    help="MVTools motion search block size (mvtools_mcdegrain, derainbow_decross)")
    rn.add_argument("--pp",               type=int,
                    help="TFM post-processor mode 0..7 (tivtc_ivtc)")
    rn.add_argument("--cycle",            type=int,
                    help="TDecimate cycle length (tivtc_ivtc)")
    rn.add_argument("--rdrop",            type=int,
                    help="TDecimate frames dropped per cycle (tivtc_ivtc)")
    rn.add_argument("--quant1",           type=int,
                    help="Deblock_QED base quant strength (deblock_h264_artefacts)")
    rn.add_argument("--quant2",           type=int,
                    help="Deblock_QED secondary quant (deblock_h264_artefacts)")
    rn.add_argument("--aoffset",          type=int,
                    help="Deblock_QED alpha offset (deblock_h264_artefacts)")
    rn.add_argument("--boffset",          type=int,
                    help="Deblock_QED beta offset (deblock_h264_artefacts)")
    rn.set_defaults(func=_cmd_run)

    # ----- Profiles -----
    sub.add_parser(
        "list-profiles",
        help="list saved profiles (built-in + user-defined in config/profiles/)"
    ).set_defaults(func=_cmd_list_profiles)

    ap = sub.add_parser(
        "apply-profile",
        help="run a saved profile by name on a single input"
    )
    ap.add_argument("--name",   required=True, help="profile name (see list-profiles)")
    ap.add_argument("--input",  required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--encoder", choices=_runner.list_encoders(),
                    help="override the encoder stored in the profile")
    ap.add_argument("--decode-backend", default="cpu",
                    choices=DECODE_BACKENDS,
                    help=DECODE_BACKEND_HELP)
    ap.add_argument("--vs-accel", choices=["cpu", "cuda"],
                    help="VapourSynth processing acceleration: CPU fallback or CUDA")
    ap.add_argument("--no-audio", action="store_true")
    ap.set_defaults(func=_cmd_apply_profile)

    apb = sub.add_parser(
        "apply-profile-batch",
        help="run a saved profile over every video file in --input-dir"
    )
    apb.add_argument("--name",       required=True, help="profile name")
    apb.add_argument("--input-dir",  required=True, dest="input_dir")
    apb.add_argument("--output-dir", required=True, dest="output_dir")
    apb.add_argument("--recursive",  action="store_true",
                     help="walk subfolders too (default: top-level only)")
    apb.add_argument("--no-mirror",  action="store_true",
                     help="when --recursive, flatten outputs into --output-dir "
                          "instead of mirroring the source folder tree (default: mirror)")
    apb.add_argument("--overwrite",  action="store_true",
                     help="redo files even if the destination already exists "
                          "(default: skip existing non-empty outputs for restart safety)")
    apb.add_argument("--encoder", choices=_runner.list_encoders(),
                     help="override the encoder stored in the profile")
    apb.add_argument("--container", default="mp4", choices=["mp4", "mkv"],
                     help="output container for x264/x265 batch outputs")
    apb.add_argument("--decode-backend", default="cpu",
                     choices=DECODE_BACKENDS,
                     help=DECODE_BACKEND_HELP)
    apb.add_argument("--vs-accel", choices=["cpu", "cuda"],
                     help="VapourSynth processing acceleration: CPU fallback or CUDA")
    apb.add_argument("--no-audio",   action="store_true")
    apb.set_defaults(func=_cmd_apply_profile_batch)

    mp = sub.add_parser(
        "materialize-profiles",
        help="write built-in profiles as editable JSON files in config/profiles/"
    )
    mp.add_argument("--force", action="store_true",
                    help="overwrite existing profile files")
    mp.set_defaults(func=_cmd_materialize_profiles)

    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

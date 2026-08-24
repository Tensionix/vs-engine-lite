# Audion VS Engine -- Precision palette
# Preset: shadow_denoise_sota (v2: BM3D float + luma-mask "только тени")
# Stack:  BM3DCUDA (preferred) -> BM3DCPU (fallback) on 32-bit float, then back to 10-bit
# Goal:   the headline "shadow denoise" -- BM3D is the SOTA non-local means denoiser,
#         particularly strong on the chroma noise / digital grain that dominates shadow zones.
#
# v2 design:
#   - BM3D denoise the whole frame (BM3D needs full clip context).
#   - Build a smooth luma-based mask in float: 1.0 in shadows, fading to 0.0 above threshold.
#   - On the LUMA plane: blend (orig, denoised) by mask -> shadows get denoised, mids/highs untouched.
#   - On CHROMA planes: always use denoised (chroma noise is ugly everywhere).
#   - Optional micro-grain restore so the cleaned shadows don't look plastic.
#
# Read parameters from AUDION_VS_* env vars.
# Required:
#   AUDION_VS_INPUT             absolute path to source media
# Optional:
#   AUDION_VS_SIGMA             float, BM3D luma strength.   default 2.5  (range 1.0..4.0)
#   AUDION_VS_USE_CUDA          "1" | "0".                   default "0"
#   AUDION_VS_GRAIN_BACK        float, micro-grain restore.  default 0.6  (0 = off)
#   AUDION_VS_SHADOW_THRESHOLD  float in [0..1], luma cut.   default 0.20
#   AUDION_VS_TRANSITION        float in [0..1], ramp width. default 0.10
#   AUDION_VS_PREVIEW_MASK      "1" | "0", debug mode.       default "0"
#                                  When "1", outputs the mask itself as grayscale for tuning.
#
import os
import vapoursynth as vs
core = vs.core

import audion_lib as al

INPUT             = os.environ["AUDION_VS_INPUT"]
SIGMA             = float(os.environ.get("AUDION_VS_SIGMA", "2.5"))
USE_CUDA          = os.environ.get("AUDION_VS_USE_CUDA", "0") == "1"
GRAIN_BACK        = float(os.environ.get("AUDION_VS_GRAIN_BACK", "0.6"))
SHADOW_THRESHOLD  = float(os.environ.get("AUDION_VS_SHADOW_THRESHOLD", "0.20"))
TRANSITION        = max(0.01, float(os.environ.get("AUDION_VS_TRANSITION", "0.10")))
PREVIEW_MASK      = os.environ.get("AUDION_VS_PREVIEW_MASK", "0") == "1"


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)

# ---- 1. To 32-bit float for BM3D ----
flt = core.fmtc.bitdepth(src, bits=32, flt=1)

# ---- 2. BM3D denoise full frame ----
sigma_yuv = [SIGMA, SIGMA * 0.6, SIGMA * 0.6]
# AUDION_VS_USE_CUDA is now an opt-OUT: bm3d_auto picks CUDA when an NVIDIA
# GPU is detected, BM3DCPU otherwise. Setting USE_CUDA=0 forces CPU even on
# NVIDIA boxes (useful for A/B benchmarking).
if USE_CUDA:
    denoised = al.bm3d_auto(flt, sigma=sigma_yuv, radius=0)
else:
    denoised = core.bm3dcpu.BM3D(flt, sigma=sigma_yuv, radius=0)

# ---- 3. Build smooth shadow mask from float luma ----
# Float luma is in [0..1]. mask = clamp((SHADOW_THRESHOLD - x) / TRANSITION, 0, 1)
# Postfix Expr: " THRESHOLD x - TRANSITION / 0 max 1 min "
luma_only = core.std.ShufflePlanes(flt, 0, vs.GRAY)
mask_expr = f"{SHADOW_THRESHOLD} x - {TRANSITION} / 0 max 1 min"
mask = core.std.Expr([luma_only], [mask_expr])

# ---- 4. Compose luma: blended-shadows + untouched-rest ----
denoised_luma = core.std.ShufflePlanes(denoised, 0, vs.GRAY)
blended_luma  = core.std.MaskedMerge(luma_only, denoised_luma, mask)

# ---- 5. Recombine with denoised chroma ----
# Format(YUV420PS / YUV444PS): plane 1, 2 from `denoised`; plane 0 = our blended_luma.
result = core.std.ShufflePlanes([blended_luma, denoised, denoised], [0, 1, 2], vs.YUV)

# ---- Optional preview: just emit the mask as grayscale 10-bit for tuning thresholds ----
if PREVIEW_MASK:
    preview = core.std.Expr([mask], "x 1023 *")  # scale [0..1] to 10-bit display
    preview = core.fmtc.bitdepth(preview, bits=10)
    preview = core.resize.Spline36(preview, format=vs.YUV420P10, matrix_s="709")
    preview = core.std.SetFrameProps(preview, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
    preview.set_output()
else:
    # ---- 6. Optional micro-grain restore (in 16-bit int domain for AddGrain) ----
    result16 = core.fmtc.bitdepth(result, bits=16)
    if GRAIN_BACK > 0:
        result16 = core.grain.Add(
            result16,
            var=GRAIN_BACK * 1.5,
            uvar=GRAIN_BACK * 0.4,
            constant=False,
        )
    out = core.fmtc.bitdepth(result16, bits=10)
    out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
    out.set_output()

# Audion VS Engine -- Precision palette
# Preset: filmic_rebuild  (the flagship Stage 3 composition)
# Stack:  BM3D float denoise -> neo_f3kdb deband -> luma-zoned AddGrain
# Goal:   "rebuild a clean filmic look" -- digital noise gone, banding gone,
#         then reintroduce controlled fine grain that scales by luma zone:
#         heavier in shadows (where film grain is naturally most visible),
#         lighter in mids, lightest in highlights.
#
# Required:
#   AUDION_VS_INPUT             absolute path to source
# Optional:
#   AUDION_VS_SIGMA             float, BM3D luma sigma.        default 2.0  (range 1.0..3.5)
#   AUDION_VS_USE_CUDA          "1" | "0".                     default "0"
#   AUDION_VS_DEBAND_RANGE      int, neo_f3kdb range.          default 14
#   AUDION_VS_GRAIN_SHADOW      float, grain in shadow zone.   default 1.5
#   AUDION_VS_GRAIN_MID         float, grain in mid-tones.     default 0.9
#   AUDION_VS_GRAIN_HIGH        float, grain in highlights.    default 0.4
#   AUDION_VS_SHADOW_THRESHOLD  float [0..1], shadow zone end. default 0.30
#   AUDION_VS_HIGH_THRESHOLD    float [0..1], highlight start. default 0.65
#
import os
import vapoursynth as vs
core = vs.core

import audion_lib as al

INPUT             = os.environ["AUDION_VS_INPUT"]
SIGMA             = float(os.environ.get("AUDION_VS_SIGMA", "2.0"))
USE_CUDA          = os.environ.get("AUDION_VS_USE_CUDA", "0") == "1"
DEBAND_RANGE      = int(os.environ.get("AUDION_VS_DEBAND_RANGE", "14"))
GRAIN_SHADOW      = float(os.environ.get("AUDION_VS_GRAIN_SHADOW", "1.5"))
GRAIN_MID         = float(os.environ.get("AUDION_VS_GRAIN_MID",    "0.9"))
GRAIN_HIGH        = float(os.environ.get("AUDION_VS_GRAIN_HIGH",   "0.4"))
SHADOW_THRESHOLD  = float(os.environ.get("AUDION_VS_SHADOW_THRESHOLD", "0.30"))
HIGH_THRESHOLD    = float(os.environ.get("AUDION_VS_HIGH_THRESHOLD",   "0.65"))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)

# ============== STAGE 1: BM3D denoise (float) ==============
flt = core.fmtc.bitdepth(src, bits=32, flt=1)
sigma_yuv = [SIGMA, SIGMA * 0.6, SIGMA * 0.6]
# USE_CUDA is opt-OUT: bm3d_auto auto-detects NVIDIA, falls back to CPU
# elsewhere. Force-CPU path retained for A/B comparison runs.
if USE_CUDA:
    flt = al.bm3d_auto(flt, sigma=sigma_yuv, radius=0)
else:
    flt = core.bm3dcpu.BM3D(flt, sigma=sigma_yuv, radius=0)

# ============== STAGE 2: Deband (16-bit int) ==============
clip16 = core.fmtc.bitdepth(flt, bits=16)
clip16 = core.neo_f3kdb.Deband(
    clip16,
    range=DEBAND_RANGE,
    y=48, cb=32, cr=32,
    grainy=0, grainc=0,        # we'll add zoned grain ourselves
    sample_mode=2,
)

# ============== STAGE 3: Luma-zoned grain ==============
# Build smooth masks in 16-bit space (0..65535).
# Shadow mask: 1 below SHADOW_THRESHOLD, smooth ramp to 0 by SHADOW_THRESHOLD + 0.10
# High mask:   1 above HIGH_THRESHOLD,   smooth ramp from 0 starting HIGH_THRESHOLD - 0.10
# Mid mask  =  65535 - shadow - high (whatever is left)

T_shadow = int(SHADOW_THRESHOLD * 65535)
T_high   = int(HIGH_THRESHOLD   * 65535)
RAMP     = int(0.10 * 65535)  # 10% transition width

luma = core.std.ShufflePlanes(clip16, 0, vs.GRAY)

# Shadow: clamp((T_shadow + RAMP - x) / RAMP, 0, 1) * 65535
mask_shadow = core.std.Expr(
    [luma],
    f"{T_shadow + RAMP} x - {RAMP} / 0 max 1 min 65535 *"
)
# High:    clamp((x - (T_high - RAMP)) / RAMP, 0, 1) * 65535
mask_high = core.std.Expr(
    [luma],
    f"x {T_high - RAMP} - {RAMP} / 0 max 1 min 65535 *"
)
# Mid (whatever is left)
mask_mid = core.std.Expr(
    [mask_shadow, mask_high],
    "65535 x - y -",
)

# Apply different grain levels
def _grain(c, var):
    if var <= 0:
        return c
    return core.grain.Add(c, var=var * 1.5, uvar=var * 0.4, constant=False)

g_shadow = _grain(clip16, GRAIN_SHADOW)
g_mid    = _grain(clip16, GRAIN_MID)
g_high   = _grain(clip16, GRAIN_HIGH)

# Compose: layer shadow, then mid, then high using their masks
result = core.std.MaskedMerge(clip16, g_shadow, mask_shadow)
result = core.std.MaskedMerge(result, g_mid,    mask_mid)
result = core.std.MaskedMerge(result, g_high,   mask_high)

# ============== Output 10-bit ==============
out = core.fmtc.bitdepth(result, bits=10)
out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
out.set_output()

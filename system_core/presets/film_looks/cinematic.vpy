# Audion VS Engine -- Film Looks palette
# Preset: cinematic
# Goal:   universal subtle filmic look. Safe default.
#         Mild MTF softening + light highlight bloom + subtle luma-zoned grain.
#         No extreme grain, no gate weave, no flicker -- it just "looks like film, lightly".
#
# Required:
#   AUDION_VS_INPUT      absolute path to source
# Optional:
#   AUDION_VS_INTENSITY  master scale 0..2.0           default 1.0
#                          scales grain, halation, soften factor proportionally.
#
import os
import vapoursynth as vs
core = vs.core
import audion_lib as al

INPUT     = os.environ["AUDION_VS_INPUT"]
INTENSITY = float(os.environ.get("AUDION_VS_INTENSITY", "1.0"))

# Per-stock defaults, then scale by INTENSITY
SOFT_FACTOR    = max(0.70, 0.92 - 0.08 * INTENSITY)   # 0.84 at I=1.0, 0.76 at I=2.0
HALO_STRENGTH  = 0.12 * INTENSITY
GRAIN_SHADOW   = 0.6 * INTENSITY
GRAIN_MID      = 0.4 * INTENSITY
GRAIN_HIGH     = 0.2 * INTENSITY


clip = al.load_source(INPUT)

# ---- 1. Optical softening (mild) ----
clip = al.mtf_soften(clip, SOFT_FACTOR)

# ---- 2. Convert to 16-bit for tone work ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Halation (light bloom in highlights) ----
clip16 = al.halation_bloom(
    clip16,
    threshold=int(0.65 * 65535),
    strength=HALO_STRENGTH,
    blur_radius=2.0,
)

# ---- 4. Luma-zoned grain (subtle) ----
clip16 = al.luma_zoned_grain(
    clip16,
    shadow=GRAIN_SHADOW, mid=GRAIN_MID, high=GRAIN_HIGH,
    t_shadow=0.30, t_high=0.70, ramp=0.10,
)

# ---- 5. Down to 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

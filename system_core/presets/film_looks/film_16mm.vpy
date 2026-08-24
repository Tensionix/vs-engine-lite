# Audion VS Engine -- Film Looks palette
# Preset: film_16mm
# Goal:   organic 16mm vibe -- heavier MTF softness (smaller format = lower MTF),
#         more visible grain across all luma zones, stronger halation.
#         Typical use: documentary / indie aesthetic on digital footage.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source
# Optional:
#   AUDION_VS_INTENSITY  master scale 0..2.0           default 1.0
#
import os
import vapoursynth as vs
core = vs.core
import audion_lib as al

INPUT     = os.environ["AUDION_VS_INPUT"]
INTENSITY = float(os.environ.get("AUDION_VS_INTENSITY", "1.0"))

SOFT_FACTOR    = max(0.65, 0.82 - 0.10 * INTENSITY)   # softer than 35mm
HALO_STRENGTH  = 0.20 * INTENSITY
GRAIN_SHADOW   = 1.4 * INTENSITY
GRAIN_MID      = 1.0 * INTENSITY
GRAIN_HIGH     = 0.5 * INTENSITY


clip = al.load_source(INPUT)

# ---- 1. Heavier MTF soften ----
clip = al.mtf_soften(clip, SOFT_FACTOR)

# ---- 2. To 16-bit ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Tone -- 16mm chemistry has lifted blacks and slightly warmer mids ----
clip16 = al.lift_blacks(clip16, lift=0.04)
clip16 = al.gamma_curve(clip16, gamma=1.04)

# ---- 4. Halation (stronger than 35mm) ----
clip16 = al.halation_bloom(
    clip16,
    threshold=int(0.58 * 65535),
    strength=HALO_STRENGTH,
    blur_radius=3.0,
)

# ---- 5. Heavier zoned grain ----
clip16 = al.luma_zoned_grain(
    clip16,
    shadow=GRAIN_SHADOW, mid=GRAIN_MID, high=GRAIN_HIGH,
    t_shadow=0.32, t_high=0.68, ramp=0.10,
)

# ---- 6. Output 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

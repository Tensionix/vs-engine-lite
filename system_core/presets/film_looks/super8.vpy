# Audion VS Engine -- Film Looks palette
# Preset: super8
# Goal:   the most extreme of the film stocks -- heaviest grain, softest optics,
#         strongest halation, lifted blacks, lowered contrast. Reads as "home movie 1970s".
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

SOFT_FACTOR    = max(0.55, 0.72 - 0.10 * INTENSITY)   # heaviest soften
HALO_STRENGTH  = 0.30 * INTENSITY
GRAIN_SHADOW   = 2.2 * INTENSITY
GRAIN_MID      = 1.6 * INTENSITY
GRAIN_HIGH     = 0.9 * INTENSITY


clip = al.load_source(INPUT)

# ---- 1. Strong MTF soften (small format optical limit) ----
clip = al.mtf_soften(clip, SOFT_FACTOR)

# ---- 2. To 16-bit ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Tone: lifted blacks, lowered contrast (faded 70s feel) ----
clip16 = al.lift_blacks(clip16, lift=0.07)
clip16 = al.gamma_curve(clip16, gamma=1.08)

# ---- 4. Heavy halation ----
clip16 = al.halation_bloom(
    clip16,
    threshold=int(0.55 * 65535),
    strength=HALO_STRENGTH,
    blur_radius=4.0,
)

# ---- 5. Heaviest zoned grain ----
clip16 = al.luma_zoned_grain(
    clip16,
    shadow=GRAIN_SHADOW, mid=GRAIN_MID, high=GRAIN_HIGH,
    t_shadow=0.32, t_high=0.66, ramp=0.10,
)

# ---- 6. Output 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

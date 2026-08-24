# Audion VS Engine -- Film Looks palette
# Preset: bleach_bypass
# Goal:   high-contrast, desaturated, harsh look (e.g. "Saving Private Ryan" or "Se7en").
#         Bleach bypass = process where silver isn't bleached out of a positive print,
#         creating a black-and-white image OVER the colour image -> high contrast + low saturation.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source
# Optional:
#   AUDION_VS_INTENSITY  master scale 0..2.0           default 1.0
#                          stronger intensity -> more contrast, less saturation, slightly softer.
#
import os
import vapoursynth as vs
core = vs.core
import audion_lib as al

INPUT     = os.environ["AUDION_VS_INPUT"]
INTENSITY = float(os.environ.get("AUDION_VS_INTENSITY", "1.0"))

CONTRAST_GAMMA = max(0.70, 0.85 - 0.05 * INTENSITY)    # gamma<1 darkens mids -> contrast++
DESAT_AMOUNT   = min(0.85, 0.55 * INTENSITY)
SOFT_FACTOR    = max(0.85, 0.92 - 0.03 * INTENSITY)    # very mild soften
GRAIN_SHADOW   = 0.5 * INTENSITY                       # restrained grain (the look is harsh, not vintage)
GRAIN_MID      = 0.3 * INTENSITY
GRAIN_HIGH     = 0.15 * INTENSITY


clip = al.load_source(INPUT)

# ---- 1. Mild MTF soften ----
clip = al.mtf_soften(clip, SOFT_FACTOR)

# ---- 2. To 16-bit ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Tone: hard contrast S-curve via gamma ----
clip16 = al.gamma_curve(clip16, gamma=CONTRAST_GAMMA)

# ---- 4. Heavy desaturation ----
clip16 = al.desaturate(clip16, amount=DESAT_AMOUNT)

# ---- 5. NO halation -- bleach bypass is harsh, not glowy ----

# ---- 6. Restrained grain ----
clip16 = al.luma_zoned_grain(
    clip16,
    shadow=GRAIN_SHADOW, mid=GRAIN_MID, high=GRAIN_HIGH,
    t_shadow=0.30, t_high=0.70, ramp=0.10,
)

# ---- 7. Output 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

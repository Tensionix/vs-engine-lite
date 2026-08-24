# Audion VS Engine -- Film Looks palette
# Preset: film_35mm
# Goal:   clean Kodak 35mm emulation with stock variants.
#         250D / 500T / 50D differ in grain amount, contrast, halation, color cast.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source
# Optional:
#   AUDION_VS_STOCK      "250D" | "500T" | "50D"        default "250D"
#                          250D -- daylight, neutral, fine grain (typical fav)
#                          500T -- tungsten, faster, moderate grain (cooler tilt)
#                          50D  -- daylight, cleanest grain
#   AUDION_VS_INTENSITY  master scale 0..2.0            default 1.0
#
import os
import vapoursynth as vs
core = vs.core
import audion_lib as al

INPUT     = os.environ["AUDION_VS_INPUT"]
STOCK     = os.environ.get("AUDION_VS_STOCK", "250D").upper()
INTENSITY = float(os.environ.get("AUDION_VS_INTENSITY", "1.0"))

# Per-stock parameter table
# (soft_factor, halo, grain_shadow, grain_mid, grain_high, lift, gamma, tungsten)
TABLE = {
    "250D": (0.88, 0.14, 0.7, 0.5, 0.25, 0.02, 1.00,  0),
    "500T": (0.86, 0.16, 1.0, 0.7, 0.35, 0.03, 0.98, -1),  # cooler / blue-ish
    "50D":  (0.92, 0.10, 0.4, 0.3, 0.15, 0.01, 1.02,  0),
}
soft, halo, gs, gm, gh, lift, gam, tungsten = TABLE.get(STOCK, TABLE["250D"])

# Scale by intensity
soft = max(0.70, soft - (1.0 - soft) * (INTENSITY - 1.0))   # softer when I>1
halo  *= INTENSITY
gs    *= INTENSITY
gm    *= INTENSITY
gh    *= INTENSITY


clip = al.load_source(INPUT)

# ---- 1. MTF soften ----
clip = al.mtf_soften(clip, soft)

# ---- 2. To 16-bit ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Tone: gamma + black lift ----
clip16 = al.gamma_curve(clip16, gamma=gam)
clip16 = al.lift_blacks(clip16, lift=lift)

# ---- 4. Tungsten cast for 500T (slight U lift for cooler skin tones) ----
if tungsten != 0:
    # Shift U plane slightly (more positive = bluer in YUV). For limited-range 16-bit,
    # 32768 is neutral. tungsten=-1 -> +800 on U (~1.2% cool tilt).
    delta = 800
    clip16 = core.std.Expr(clip16, ["", f"x {delta} +", ""])

# ---- 5. Halation ----
clip16 = al.halation_bloom(
    clip16,
    threshold=int(0.62 * 65535),
    strength=halo,
    blur_radius=2.5,
)

# ---- 6. Luma-zoned grain ----
clip16 = al.luma_zoned_grain(
    clip16,
    shadow=gs, mid=gm, high=gh,
    t_shadow=0.30, t_high=0.70, ramp=0.10,
)

# ---- 7. Down to 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

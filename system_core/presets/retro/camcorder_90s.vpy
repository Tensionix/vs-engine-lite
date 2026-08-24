# Audion VS Engine -- Retro palette
# Preset: camcorder_90s
# Goal:   softer than VHS, less aggressive bleed. The "consumer camcorder" feel:
#         mild blur, slight gamma lift (overexposed-ish), subtle chroma bleed, tape noise.
#         Less "broken signal", more "amateur 90s home video".
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

SOFT_FACTOR    = max(0.70, 0.85 - 0.07 * INTENSITY)
CHROMA_BLUR    = 1.2 + 0.8 * INTENSITY            # less aggressive than VHS
GRAIN_LEVEL    = 0.4 * INTENSITY
GAMMA_LIFT     = 1.0 + 0.05 * INTENSITY           # slight overexposure feel


clip = al.load_source(INPUT)

# ---- 1. Soften optics (less than VHS) ----
clip = al.mtf_soften(clip, SOFT_FACTOR)

# ---- 2. To 16-bit ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Slight gamma lift ----
clip16 = al.gamma_curve(clip16, gamma=GAMMA_LIFT)

# ---- 4. Slight black lift (typical of consumer tape transports) ----
clip16 = al.lift_blacks(clip16, lift=0.025 * INTENSITY)

# ---- 5. Mild horizontal chroma bleed ----
u = core.std.ShufflePlanes(clip16, 1, vs.GRAY)
v = core.std.ShufflePlanes(clip16, 2, vs.GRAY)
cw, ch = u.width, u.height
dw = max(4, int(cw / CHROMA_BLUR)) & ~1
u_b = core.resize.Spline36(u, dw, ch)
u_b = core.resize.Spline36(u_b, cw, ch)
v_b = core.resize.Spline36(v, dw, ch)
v_b = core.resize.Spline36(v_b, cw, ch)
clip16 = core.std.ShufflePlanes([clip16, u_b, v_b], [0, 0, 0], vs.YUV)

# ---- 6. Mild grain ----
if GRAIN_LEVEL > 0:
    clip16 = core.grain.Add(
        clip16,
        var=GRAIN_LEVEL * 1.2,
        uvar=GRAIN_LEVEL * 0.4,
        constant=False,
    )

# ---- 7. Output 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

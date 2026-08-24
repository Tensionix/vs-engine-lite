# Audion VS Engine -- Retro palette
# Preset: vhs_crt
# Goal:   composite-video / VHS / CRT character. Heavy chroma bleed (signature),
#         soft optics, slight chroma misalignment, mild noise.
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

SOFT_FACTOR    = max(0.55, 0.75 - 0.10 * INTENSITY)
CHROMA_BLUR    = 1.5 + 1.5 * INTENSITY                # horizontal chroma bleed factor
CHROMA_SHIFT   = INTENSITY * 1.0                      # subpixel right-shift on chroma
GRAIN_LEVEL    = 0.5 * INTENSITY


clip = al.load_source(INPUT)

# ---- 1. Soften optics ----
clip = al.mtf_soften(clip, SOFT_FACTOR)

# ---- 2. To 16-bit ----
clip16 = core.fmtc.bitdepth(clip, bits=16)

# ---- 3. Horizontal chroma bleed (the VHS signature) ----
# Separate chroma planes, downscale horizontally, upscale -> horizontal-only blur.
u = core.std.ShufflePlanes(clip16, 1, vs.GRAY)
v = core.std.ShufflePlanes(clip16, 2, vs.GRAY)
cw, ch = u.width, u.height
dw = max(4, int(cw / CHROMA_BLUR)) & ~1
u_b = core.resize.Spline36(u, dw, ch)
u_b = core.resize.Spline36(u_b, cw, ch, src_left=CHROMA_SHIFT)
v_b = core.resize.Spline36(v, dw, ch)
v_b = core.resize.Spline36(v_b, cw, ch, src_left=CHROMA_SHIFT)
clip16 = core.std.ShufflePlanes([clip16, u_b, v_b], [0, 0, 0], vs.YUV)

# ---- 4. Mild noise (analog tape texture) ----
if GRAIN_LEVEL > 0:
    clip16 = core.grain.Add(
        clip16,
        var=GRAIN_LEVEL * 1.5,
        uvar=GRAIN_LEVEL * 0.6,    # chroma noise is more visible in retro
        constant=False,
    )

# ---- 5. Output 10-bit ----
out = core.fmtc.bitdepth(clip16, bits=10)
out = al.tag_bt709(out)
out.set_output()

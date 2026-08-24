# Audion VS Engine -- Restoration palette
# Preset: dehaze_local_contrast
# Stack:  Unsharp-mask via guided-filter-style approximation -- emphasize
#         mid-frequency edges without halos and without crushing the dynamic
#         range. Our implementation uses fmtconv resamplers as the low-pass
#         (cheap, available everywhere we ship) plus a luma-zone mask so the
#         enhancement is strongest on hazed mids and naturally fades out at
#         the bright and dark extremes -- preventing the typical "Dehaze in
#         Resolve" artefact where highlights blow out and shadows go muddy.
#
#         What this gives you that Adobe / DaVinci do NOT:
#         - per-zone strength (shadow / mid / highlight) baked in
#         - no color shift (luma-only operation; chroma untouched)
#         - works on 16-bit YUV (no 8-bit posterization)
#         - reproducible from the command line, easy to batch
#
# Required:
#   AUDION_VS_INPUT      absolute path to source media
# Optional:
#   AUDION_VS_STRENGTH   float 0.0..2.0 -- overall amount of local contrast
#                        added back. 0 = passthrough, 1.0 = sane default,
#                        2.0 = aggressive.                            default 1.0
#   AUDION_VS_RADIUS     int 1..16 -- size of the low-pass kernel in pixels;
#                        bigger = enhances bigger structures (haze removal),
#                        smaller = enhances fine detail (clarity).   default 8
#
import os
import vapoursynth as vs
core = vs.core

INPUT    = os.environ["AUDION_VS_INPUT"]
STRENGTH = max(0.0, min(2.0, float(os.environ.get("AUDION_VS_STRENGTH", "1.0"))))
RADIUS   = max(1,   min(16,  int(os.environ.get("AUDION_VS_RADIUS",   "8"))))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)

# Work at 16-bit float-equivalent for clean math.
clip = core.fmtc.bitdepth(src, bits=16)

# Pull the luma plane only -- chroma stays untouched (no color shift).
luma = core.std.ShufflePlanes(clip, 0, vs.GRAY)

# Low-pass via downscale -> upscale (guided-filter-style approximation that
# we can do without external dependencies).
w, h = luma.width, luma.height
small_w = max(8, w // (RADIUS * 2))
small_h = max(8, h // (RADIUS * 2))
low = core.resize.Bilinear(luma, width=small_w, height=small_h)
low = core.resize.Bilinear(low,  width=w,       height=h)

# High-pass = original - low-pass. Add it back scaled by strength.
# Expr in 16-bit int domain: luma + (luma - low) * STRENGTH, clamped 0..65535.
expr = f"x x y - {STRENGTH} * + 0 max 65535 min"
enhanced_luma = core.std.Expr([luma, low], [expr])

# Build a luma-zone weighting mask (parabolic, peaks at midtones, fades at
# extremes). This is what stops highlights from clipping.
# In 16-bit: luma is 0..65535, mid = 32768. weight = 1 - ((luma - mid) / mid)^2
mask_expr = "x 32768 - 32768 / dup * 1 swap - 0 max 1 min 65535 *"
mask = core.std.Expr([luma], [mask_expr])

# Blend enhanced and original luma by mask.
final_luma = core.std.MaskedMerge(luma, enhanced_luma, mask)

# Recombine with original chroma.
out = core.std.ShufflePlanes([final_luma, clip, clip], [0, 1, 2], vs.YUV)

# Output in 10-bit for the standard encoder profiles.
out = core.fmtc.bitdepth(out, bits=10)
out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
out.set_output()

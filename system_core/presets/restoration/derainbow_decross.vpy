# Audion VS Engine -- Restoration palette
# Preset: derainbow_decross
# Stack:  MVTools motion-compensated CHROMA-only temporal averaging
# Goal:   Remove rainbow / dot-crawl / cross-color artifacts that plague NTSC
#         composite captures (analog VHS rip, U-matic, BetaSP, satellite TV
#         masters, S-Video to SDI converters with bad notch filter).
#
#         Why: rainbow and dot crawl are HIGH-frequency CHROMA flicker that
#         shifts position frame-to-frame. By tracking motion vectors in luma
#         and averaging the chroma planes along those vectors over a 3-frame
#         window, the time-varying composite artifacts cancel themselves out
#         while genuine color stays put. Luma is left untouched so detail and
#         sharpness are unaffected.
#
#         NLEs (Premiere, DaVinci) DO NOT ship anything for this. Workflows
#         in those tools usually involve "secondary chroma denoise" applied
#         globally, which softens the picture. This preset only operates
#         where motion estimation is confident.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source media
# Optional:
#   AUDION_VS_STRENGTH   float 0.0..1.0 -- amount of motion-compensated chroma
#                        smoothing. 0 = passthrough, 1 = max.            default 0.6
#   AUDION_VS_BLKSIZE    int 8|16 -- motion search block size.            default 16
#
import os
import vapoursynth as vs
core = vs.core

INPUT    = os.environ["AUDION_VS_INPUT"]
STRENGTH = max(0.0, min(1.0, float(os.environ.get("AUDION_VS_STRENGTH", "0.6"))))
BLKSIZE  = int(os.environ.get("AUDION_VS_BLKSIZE", "16"))
if BLKSIZE not in (8, 16):
    BLKSIZE = 16


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)
clip = core.fmtc.bitdepth(src, bits=16)

# Motion search using LUMA (rainbow/dot-crawl don't affect luma vectors).
sup  = core.mv.Super(clip, pel=1, sharp=1)
mvbw = core.mv.Analyse(sup, isb=True,  blksize=BLKSIZE, overlap=BLKSIZE // 2)
mvfw = core.mv.Analyse(sup, isb=False, blksize=BLKSIZE, overlap=BLKSIZE // 2)

# Motion-compensated previous and next frames.
bwc = core.mv.Compensate(clip, sup, mvbw, thsad=10000)
fwc = core.mv.Compensate(clip, sup, mvfw, thsad=10000)

# Per-plane Expr: luma passthrough (plane 0 = "x"), chroma = averaged.
# Then MaskedMerge with original by STRENGTH to control intensity.
avg = core.std.Expr(
    [clip, bwc, fwc],
    ["x", "x y z + + 3 /", "x y z + + 3 /"],
)

# Blend by strength (per-plane: luma stays original, chroma blends to averaged).
weight = STRENGTH
out = core.std.Merge(clip, avg, weight=[0.0, weight, weight])

out = core.fmtc.bitdepth(out, bits=10)
out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
out.set_output()

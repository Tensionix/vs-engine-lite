# Audion VS Engine -- Restoration palette
# Preset: qtgmc_deinterlace
# Stack:  havsfunc.QTGMC (NNEDI3 + MVTools motion estimation) -> progressive output
# Goal:   Reference-quality deinterlace for legacy interlaced sources (DV, HDV,
#         old broadcast, transferred VHS captures with TFF/BFF). QTGMC is the
#         gold standard -- it reconstructs proper progressive frames using
#         neural-network upscaling of each field plus motion-compensated
#         temporal smoothing, instead of the basic line-doubling / bob-weave
#         that NLEs ship. Result: no comb teeth, no flicker, no ghosting on
#         fast pans -- something Adobe Premiere and DaVinci Resolve cannot
#         match out of the box.
#
# Required:
#   AUDION_VS_INPUT       absolute path to source media
# Optional:
#   AUDION_VS_FIELD_ORDER "tff" (top-field-first, broadcast/HDV/DV-NTSC) or
#                         "bff" (bottom-field-first, DV-PAL).        default "tff"
#   AUDION_VS_PRESET      QTGMC speed/quality preset:
#                         "Draft" / "Ultra Fast" / "Super Fast" / "Very Fast"
#                         / "Faster" / "Fast" / "Medium" / "Slow" / "Slower"
#                         / "Very Slow" / "Placebo".                default "Medium"
#   AUDION_VS_OUTPUT_FPS  "double" -> emit 2x the input fps (each field becomes
#                         a new frame; smoothest motion, doubles encode load),
#                         "single" -> emit input fps (one progressive frame
#                         per input frame).                          default "single"
#
import os
import sys
import vapoursynth as vs
core = vs.core

# havsfunc / mvsfunc are pure-Python "scripts" installed into vs-scripts/.
# vsrepo lays them under Lib/site-packages/, so the regular import path works.
import havsfunc as haf

INPUT       = os.environ["AUDION_VS_INPUT"]
FIELD_ORDER = os.environ.get("AUDION_VS_FIELD_ORDER", "tff").lower()
QPRESET     = os.environ.get("AUDION_VS_PRESET", "Medium")
OUTPUT_FPS  = os.environ.get("AUDION_VS_OUTPUT_FPS", "single").lower()


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)

# Tag field order on the clip for QTGMC. _FieldBased: 1=BFF, 2=TFF (per VS spec).
fieldbased = 2 if FIELD_ORDER == "tff" else 1
src = core.std.SetFrameProps(src, _FieldBased=fieldbased)

# QTGMC produces 2x fps by default; FPSDivisor=2 gives single-rate (one progressive
# per input frame). Both are valid; "single" is the safer default for archival
# transfers where you want to keep the original frame rate.
fps_divisor = 1 if OUTPUT_FPS == "double" else 2

out = haf.QTGMC(
    src,
    Preset=QPRESET,
    TFF=(FIELD_ORDER == "tff"),
    FPSDivisor=fps_divisor,
    SourceMatch=3,         # extra detail recovery on still areas
    Lossless=2,            # lossless detail pass-through where motion is zero
    EZDenoise=0.0,         # no denoise in this preset (use a Precision denoise after)
)

# Tag output as progressive Rec.709 (QTGMC clears _FieldBased to 0).
out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1, _FieldBased=0)
out.set_output()

# Audion VS Engine -- Precision palette
# Preset: chroma_cleanup
# Stack:  DFTTest on chroma planes only (planes=[1,2]); luma untouched.
# Goal:   kill nasty chroma noise / chroma blotches without softening detail.
#
# Required:
#   AUDION_VS_INPUT       absolute path to source
# Optional:
#   AUDION_VS_STRENGTH    "light" | "medium" | "strong"   default "medium"
#                           sigma mapping for chroma: light=6, medium=12, strong=20
#
import os
import vapoursynth as vs
core = vs.core

INPUT    = os.environ["AUDION_VS_INPUT"]
STRENGTH = os.environ.get("AUDION_VS_STRENGTH", "medium").lower()
SIGMA    = {"light": 6.0, "medium": 12.0, "strong": 20.0}.get(STRENGTH, 12.0)


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


clip = _load(INPUT)

# DFTTest on chroma only -- chroma can take heavier sigma than luma
# without visible detail loss because chroma is subsampled.
clip = core.dfttest.DFTTest(clip, sigma=SIGMA, tbsize=3, planes=[1, 2])

clip = core.std.SetFrameProps(clip, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
clip.set_output()

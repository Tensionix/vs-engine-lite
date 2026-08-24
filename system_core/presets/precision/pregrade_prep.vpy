# Audion VS Engine -- Precision palette
# Preset: pregrade_prep
# Stack:  DFTTest (very light) only.  Output is clean 10-bit YUV ready for color grading
#         in DaVinci Resolve / Premiere.  Pair with --encoder prores_422hq for ProRes handoff.
# Goal:   minimum-touch cleanup BEFORE color stage. Deband NOT applied here -- it can interact
#         poorly with color tools; better to deband post-grade if needed.
#
# Required:
#   AUDION_VS_INPUT       absolute path to source
# Optional:
#   AUDION_VS_STRENGTH    "light" | "medium"   default "light"
#                            DFTTest sigma: light=3.0, medium=6.0
#
import os
import vapoursynth as vs
core = vs.core

INPUT    = os.environ["AUDION_VS_INPUT"]
STRENGTH = os.environ.get("AUDION_VS_STRENGTH", "light").lower()
SIGMA    = {"light": 3.0, "medium": 6.0}.get(STRENGTH, 3.0)


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


clip = _load(INPUT)

# Very mild DFTTest on all planes -- just enough to take the edge off shot noise
clip = core.dfttest.DFTTest(clip, sigma=SIGMA, tbsize=3, planes=[0, 1, 2])

clip = core.std.SetFrameProps(clip, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
clip.set_output()

# Audion VS Engine -- Precision palette
# Preset: deband_safe
# Stack:  neo_f3kdb (light settings, no built-in grain)
# Goal:   smooth visible banding in skies / gradients without plasticizing.
#
# Required:
#   AUDION_VS_INPUT     absolute path to source
# Optional:
#   AUDION_VS_RANGE     int 8..32, range of pixels to evaluate.   default 12 (light)
#   AUDION_VS_Y         int 0..128, luma threshold.               default 48
#   AUDION_VS_CB        int 0..128, Cb threshold.                 default 32
#   AUDION_VS_CR        int 0..128, Cr threshold.                 default 32
#
import os
import vapoursynth as vs
core = vs.core

INPUT = os.environ["AUDION_VS_INPUT"]
RANGE = int(os.environ.get("AUDION_VS_RANGE", "12"))
Y     = int(os.environ.get("AUDION_VS_Y",  "48"))
CB    = int(os.environ.get("AUDION_VS_CB", "32"))
CR    = int(os.environ.get("AUDION_VS_CR", "32"))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


clip = _load(INPUT)

# neo_f3kdb works at any of 8/10/12/14/16 bit YUV.  Use 16-bit for headroom.
clip = core.fmtc.bitdepth(clip, bits=16)
clip = core.neo_f3kdb.Deband(
    clip,
    range=RANGE,
    y=Y, cb=CB, cr=CR,
    grainy=0, grainc=0,    # no grain in "safe" preset
    sample_mode=2,
)
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.SetFrameProps(clip, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
clip.set_output()

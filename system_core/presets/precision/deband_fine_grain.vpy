# Audion VS Engine -- Precision palette
# Preset: deband_fine_grain
# Stack:  neo_f3kdb (medium) + AddGrain to restore micro-texture
# Goal:   debanding + fine grain restoration so the result keeps natural texture.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source
# Optional:
#   AUDION_VS_RANGE      int 8..32, deband range.        default 14
#   AUDION_VS_Y          int 0..128, luma threshold.     default 48
#   AUDION_VS_CB         int 0..128, Cb threshold.       default 32
#   AUDION_VS_CR         int 0..128, Cr threshold.       default 32
#   AUDION_VS_GRAIN_VAR  float, AddGrain luma var.       default 0.6
#
import os
import vapoursynth as vs
core = vs.core

INPUT     = os.environ["AUDION_VS_INPUT"]
RANGE     = int(os.environ.get("AUDION_VS_RANGE", "14"))
Y         = int(os.environ.get("AUDION_VS_Y",  "48"))
CB        = int(os.environ.get("AUDION_VS_CB", "32"))
CR        = int(os.environ.get("AUDION_VS_CR", "32"))
GRAIN_VAR = float(os.environ.get("AUDION_VS_GRAIN_VAR", "0.6"))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


clip = _load(INPUT)

# 16-bit headroom for deband + grain
clip = core.fmtc.bitdepth(clip, bits=16)
clip = core.neo_f3kdb.Deband(
    clip,
    range=RANGE,
    y=Y, cb=CB, cr=CR,
    grainy=0, grainc=0,    # we'll add our own grain after deband for control
    sample_mode=2,
)

# Fine grain restoration -- prevents the "clean plastic" look after deband
clip = core.grain.Add(
    clip,
    var=GRAIN_VAR * 1.5,
    uvar=GRAIN_VAR * 0.4,
    constant=False,
)

clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.SetFrameProps(clip, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
clip.set_output()

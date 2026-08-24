# Audion VS Engine -- Precision palette
# Preset: archive_clean
# Stack:  DFTTest (mild) + neo_f3kdb (light), NO grain.
# Goal:   neutral archival master -- removes noise + banding without adding texture.
#         For long-term storage / broadcast deliverables / clean intermediate masters.
#
# Required:
#   AUDION_VS_INPUT       absolute path to source
# Optional:
#   AUDION_VS_DENOISE     "light" | "medium" | "strong"   default "light"
#                            DFTTest sigma: light=4, medium=8, strong=14
#   AUDION_VS_RANGE       neo_f3kdb range.                default 10
#
import os
import vapoursynth as vs
core = vs.core

INPUT   = os.environ["AUDION_VS_INPUT"]
DENOISE = os.environ.get("AUDION_VS_DENOISE", "light").lower()
SIGMA   = {"light": 4.0, "medium": 8.0, "strong": 14.0}.get(DENOISE, 4.0)
RANGE   = int(os.environ.get("AUDION_VS_RANGE", "10"))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


clip = _load(INPUT)

# Mild DFTTest denoise on all planes
clip = core.dfttest.DFTTest(clip, sigma=SIGMA, tbsize=3, planes=[0, 1, 2])

# Light deband (no grain)
clip = core.fmtc.bitdepth(clip, bits=16)
clip = core.neo_f3kdb.Deband(
    clip, range=RANGE,
    y=32, cb=24, cr=24,
    grainy=0, grainc=0,
    sample_mode=2,
)
clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.SetFrameProps(clip, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
clip.set_output()

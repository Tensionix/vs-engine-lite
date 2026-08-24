# Audion VS Engine -- Restoration palette
# Preset: tivtc_ivtc
# Stack:  TIVTC.TFM (field matching) -> TIVTC.TDecimate (drop duplicate frames)
# Goal:   Reference-quality inverse-telecine. Converts NTSC 29.97 fps interlaced
#         film source (3:2 pulldown -- "telecined") back into native 23.976 fps
#         progressive. This is what NTSC DVDs, broadcast prints, and digitized
#         film look like when they end up as 60i/30p; TFM matches the original
#         film fields back together, TDecimate drops the duplicated cadence
#         frame, and you get the original 24p film master back.
#
#         DaVinci Resolve has IVTC but it's a coarser pattern detector.
#         TIVTC is the reference implementation that Doom9 / encoder.community
#         uses for film masters.
#
# Required:
#   AUDION_VS_INPUT      absolute path to telecined NTSC source
# Optional:
#   AUDION_VS_PP         TFM post-processor mode 0..7. Default 6 (the most
#                        common; deinterlaces frames TFM cannot match cleanly).
#   AUDION_VS_CYCLE_R    int -- TDecimate cycle/r (drop r frames per cycle).
#                        Default "5/4" -- standard NTSC telecine.
#
import os
import vapoursynth as vs
core = vs.core

INPUT  = os.environ["AUDION_VS_INPUT"]
PP     = int(os.environ.get("AUDION_VS_PP", "6"))
CYCLE  = int(os.environ.get("AUDION_VS_CYCLE",  "5"))
RDROP  = int(os.environ.get("AUDION_VS_RDROP",  "1"))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)

# TFM expects YUV with proper field flags. Tag the source as TFF (NTSC default)
# if the upstream file did not -- safe choice for telecined NTSC.
src = core.std.SetFrameProps(src, _FieldBased=2)

# Field matching pass.
matched = core.tivtc.TFM(src, PP=PP)

# Decimation pass: drop the redundant 5th frame in each cycle of 5.
out = core.tivtc.TDecimate(matched, cycle=CYCLE, cycleR=RDROP)

out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1, _FieldBased=0)
out.set_output()

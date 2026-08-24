# Audion VS Engine -- Restoration palette
# Preset: deblock_h264_artefacts
# Stack:  havsfunc.Deblock_QED -- a deblocker tuned for H.264 / MPEG-2 / MPEG-4
#         block-DCT compression artifacts (8x8 boundaries, ringing around edges,
#         mosquito noise).
# Goal:   Salvage heavily compressed sources -- old YouTube rips, social-media
#         re-encodes (WhatsApp, Telegram), SD broadcast TS captures, low-bitrate
#         streaming dumps. NLEs typically just blur these or rely on temporal
#         denoise that softens motion; Deblock_QED is edge-aware: it smooths
#         block boundaries while preserving genuine edge detail by running a
#         quick edge-mask gate.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source media
# Optional:
#   AUDION_VS_QUANT1     int 16..32 -- base quant strength on block edges.
#                        Higher = stronger deblock.                      default 24.
#   AUDION_VS_QUANT2     int 16..32 -- secondary quant for inner block.  default 26.
#   AUDION_VS_AOFFSET    int 0..2  -- alpha offset (edge sensitivity).   default 1.
#   AUDION_VS_BOFFSET    int 0..2  -- beta offset  (intra sensitivity).  default 1.
#
import os
import vapoursynth as vs
core = vs.core

import havsfunc as haf

INPUT   = os.environ["AUDION_VS_INPUT"]
QUANT1  = max(16, min(32, int(os.environ.get("AUDION_VS_QUANT1", "24"))))
QUANT2  = max(16, min(32, int(os.environ.get("AUDION_VS_QUANT2", "26"))))
AOFFSET = max(0,  min(2,  int(os.environ.get("AUDION_VS_AOFFSET", "1"))))
BOFFSET = max(0,  min(2,  int(os.environ.get("AUDION_VS_BOFFSET", "1"))))


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)
clip = core.fmtc.bitdepth(src, bits=16)

out = haf.Deblock_QED(
    clip,
    quant1=QUANT1, quant2=QUANT2,
    aOff1=AOFFSET, aOff2=AOFFSET,
    bOff1=BOFFSET, bOff2=BOFFSET,
)

out = core.fmtc.bitdepth(out, bits=10)
out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
out.set_output()

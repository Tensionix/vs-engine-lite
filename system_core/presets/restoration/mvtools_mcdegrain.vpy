# Audion VS Engine -- Restoration palette
# Preset: mvtools_mcdegrain
# Stack:  MVTools motion estimation -> MDegrain temporal denoise
# Goal:   Motion-compensated temporal denoise that REMOVES NOISE WITHOUT
#         SOFTENING DETAIL. The trick: MVTools tracks every block of pixels
#         across past+future frames, then MDegrain averages each pixel with
#         its motion-aligned neighbors. Static texture stays sharp because
#         it's averaged with itself; moving texture stays sharp because
#         we average along its motion vector, not across it.
#
#         This is what Topaz Video Enhance AI and Neat Video do internally
#         to "denoise without losing texture". VapourSynth gives raw access
#         to the same machinery -- DaVinci's Temporal Noise Reduction is a
#         coarse implementation of the same idea; this one is the reference.
#
# Required:
#   AUDION_VS_INPUT      absolute path to source media
# Optional:
#   AUDION_VS_RADIUS     int 1..3 -- temporal radius (frames considered before
#                        and after current). Higher = stronger denoise + slower.
#                        default 2 (5-frame window).
#   AUDION_VS_THSAD      int 100..400 -- block-match SAD threshold; lower means
#                        only very confident motion matches contribute, higher
#                        means more aggressive averaging.            default 200.
#   AUDION_VS_BLKSIZE    int 8|16 -- motion search block size. 16 is faster
#                        and good for HD; 8 is slower and good for 4K.   default 16.
#
import os
import vapoursynth as vs
core = vs.core

INPUT   = os.environ["AUDION_VS_INPUT"]
RADIUS  = max(1, min(3, int(os.environ.get("AUDION_VS_RADIUS", "2"))))
THSAD   = max(100, min(400, int(os.environ.get("AUDION_VS_THSAD", "200"))))
BLKSIZE = int(os.environ.get("AUDION_VS_BLKSIZE", "16"))
if BLKSIZE not in (8, 16):
    BLKSIZE = 16


def _load(path: str):
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


src = _load(INPUT)

# MVTools needs the clip in YUV; ensure 16-bit int for clean motion math.
clip = core.fmtc.bitdepth(src, bits=16)

# 1. Build a "super" representation -- pyramid + padding for motion search.
sup = core.mv.Super(clip, pel=2, sharp=2, rfilter=4)

# 2. Estimate forward+backward vectors for each radius level.
mvbw = [core.mv.Analyse(sup, isb=True,  delta=i, blksize=BLKSIZE, overlap=BLKSIZE // 2)
        for i in range(1, RADIUS + 1)]
mvfw = [core.mv.Analyse(sup, isb=False, delta=i, blksize=BLKSIZE, overlap=BLKSIZE // 2)
        for i in range(1, RADIUS + 1)]

# 3. Apply MDegrain at the requested radius.
if RADIUS == 1:
    out = core.mv.Degrain1(clip, sup, mvbw[0], mvfw[0], thsad=THSAD)
elif RADIUS == 2:
    out = core.mv.Degrain2(clip, sup, mvbw[0], mvfw[0], mvbw[1], mvfw[1], thsad=THSAD)
else:  # 3
    out = core.mv.Degrain3(
        clip, sup,
        mvbw[0], mvfw[0], mvbw[1], mvfw[1], mvbw[2], mvfw[2],
        thsad=THSAD,
    )

# Convert back to 10-bit for our standard h264_crf18 / h265_main10 encoders.
out = core.fmtc.bitdepth(out, bits=10)
out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
out.set_output()

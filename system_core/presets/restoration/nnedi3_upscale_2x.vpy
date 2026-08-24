# Audion VS Engine Lite -- Restoration palette
# Preset: nnedi3_upscale_2x
# Stack:  nnedi3_resample + znedi3 -> deterministic non-ML 2x upscale
# Goal:   Clean 2x enlargement without hallucinated texture. This is the Lite
#         fallback for SD/soft-HD sources when MLRT is intentionally absent.
#
# Required:
#   AUDION_VS_INPUT       absolute path to source media
# Optional:
#   AUDION_VS_QUALITY     "fast" | "balanced" | "best"       default "balanced"
#   AUDION_VS_CHROMA      "spline36" | "nnedi3"              default "spline36"
#
import os

import vapoursynth as vs
core = vs.core

import audion_lib as al
import nnedi3_resample as nnrs


INPUT = os.environ["AUDION_VS_INPUT"]
QUALITY = os.environ.get("AUDION_VS_QUALITY", "balanced").lower()
CHROMA = os.environ.get("AUDION_VS_CHROMA", "spline36").lower()

QUALITY_TABLE = {
    "fast": {"nsize": 0, "nns": 1, "qual": 1},
    "balanced": {"nsize": 4, "nns": 2, "qual": 1},
    "best": {"nsize": 4, "nns": 4, "qual": 2},
}
params = QUALITY_TABLE.get(QUALITY, QUALITY_TABLE["balanced"])
chroma_kernel = "nnedi3" if CHROMA == "nnedi3" else "spline36"

src = al.load_source(INPUT)
src = al.tag_bt709(src)

out = nnrs.nnedi3_resample(
    src,
    target_width=src.width * 2,
    target_height=src.height * 2,
    csp=vs.YUV420P10,
    mats="709",
    matd="709",
    kernel="spline36",
    chromak_up=chroma_kernel,
    chromak_down="spline36",
    mode="znedi3",
    **params,
)

out = core.std.SetFrameProps(out, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)
out.set_output()

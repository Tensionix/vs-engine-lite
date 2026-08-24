from __future__ import annotations

import os
import vapoursynth as vs

core = vs.core


def load_source(path: str) -> vs.VideoNode:
    try:
        return core.lsmas.LWLibavSource(path)
    except (vs.Error, AttributeError):
        return core.ffms2.Source(path)


def tag_bt709(clip: vs.VideoNode) -> vs.VideoNode:
    return core.std.SetFrameProps(clip, _Matrix=1, _Transfer=1, _Primaries=1, _Range=1)


def mtf_soften(clip: vs.VideoNode, factor: float) -> vs.VideoNode:
    factor = max(0.5, min(1.0, float(factor)))
    if factor >= 0.995:
        return clip
    width = max(16, int(clip.width * factor)) & ~1
    height = max(16, int(clip.height * factor)) & ~1
    soft = core.resize.Spline36(clip, width, height)
    return core.resize.Spline36(soft, clip.width, clip.height)


def _box_blur(clip: vs.VideoNode, radius: float) -> vs.VideoNode:
    r = max(1, int(round(radius)))
    try:
        return core.std.BoxBlur(clip, hradius=r, vradius=r)
    except Exception:
        return clip


def halation_bloom(
    clip: vs.VideoNode,
    *,
    threshold: int,
    strength: float,
    blur_radius: float = 2.0,
) -> vs.VideoNode:
    if strength <= 0 or clip.format is None or clip.format.color_family != vs.YUV:
        return clip
    peak = (1 << clip.format.bits_per_sample) - 1
    threshold = max(0, min(peak - 1, int(threshold)))
    luma = core.std.ShufflePlanes(clip, 0, vs.GRAY)
    glow = _box_blur(luma, blur_radius)
    expr = f"x y {threshold} - 0 max {float(strength)} * + {peak} min"
    luma_out = core.std.Expr([luma, glow], expr)
    return core.std.ShufflePlanes([luma_out, clip, clip], [0, 1, 2], vs.YUV)


def luma_zoned_grain(
    clip: vs.VideoNode,
    *,
    shadow: float,
    mid: float,
    high: float,
    t_shadow: float = 0.30,
    t_high: float = 0.70,
    ramp: float = 0.10,
) -> vs.VideoNode:
    var = max(0.0, float(shadow), float(mid), float(high))
    if var <= 0:
        return clip
    return core.grain.Add(clip, var=var * 1.2, uvar=var * 0.35, constant=False)


def gamma_curve(clip: vs.VideoNode, gamma: float) -> vs.VideoNode:
    try:
        return core.std.Levels(clip, gamma=float(gamma), planes=[0])
    except Exception:
        return clip


def lift_blacks(clip: vs.VideoNode, lift: float) -> vs.VideoNode:
    if lift <= 0 or clip.format is None or clip.format.color_family != vs.YUV:
        return clip
    peak = (1 << clip.format.bits_per_sample) - 1
    add = int(max(0.0, min(1.0, float(lift))) * peak)
    luma = core.std.ShufflePlanes(clip, 0, vs.GRAY)
    lifted = core.std.Expr([luma], f"x {add} + {peak} min")
    return core.std.ShufflePlanes([lifted, clip, clip], [0, 1, 2], vs.YUV)


def desaturate(clip: vs.VideoNode, amount: float) -> vs.VideoNode:
    amount = max(0.0, min(1.0, float(amount)))
    if amount <= 0 or clip.format is None or clip.format.color_family != vs.YUV:
        return clip
    neutral = 1 << (clip.format.bits_per_sample - 1)
    keep = 1.0 - amount
    u = core.std.ShufflePlanes(clip, 1, vs.GRAY)
    v = core.std.ShufflePlanes(clip, 2, vs.GRAY)
    u = core.std.Expr([u], f"x {neutral} - {keep} * {neutral} +")
    v = core.std.Expr([v], f"x {neutral} - {keep} * {neutral} +")
    return core.std.ShufflePlanes([clip, u, v], [0, 0, 0], vs.YUV)


def bm3d_auto(clip: vs.VideoNode, *, sigma, radius: int = 0) -> vs.VideoNode:
    if os.environ.get("AUDION_VS_USE_CUDA") == "1":
        try:
            return core.bm3dcuda.BM3D(clip, sigma=sigma, radius=radius)
        except Exception:
            pass
    return core.bm3dcpu.BM3D(clip, sigma=sigma, radius=radius)


def vsmlrt_backend_chain() -> list[str]:
    return ["trt", "ort_dml", "ort_cpu"] if os.environ.get("AUDION_VS_HAS_CUDA") == "1" else ["ort_dml", "ort_cpu"]

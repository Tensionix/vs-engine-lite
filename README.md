# Audion VS Engine Lite

<!-- audion:release -->
<p align="center">
  <a href="https://audion.dev/downloads/vs-engine-lite"><img alt="Windows" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0b6db8?style=flat-square&logo=windows&logoColor=white"></a>
  <a href="https://github.com/Tensionix/vs-engine-lite/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Tensionix/vs-engine-lite?style=flat-square&label=release&color=e08a63"></a>
  <a href="https://github.com/Tensionix/vs-engine-lite/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Tensionix/vs-engine-lite/total?style=flat-square&label=downloads&color=5fd08a"></a>
  <a href="https://github.com/Tensionix/vs-engine-lite/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/Tensionix/vs-engine-lite?style=flat-square&color=5fd08a&logo=apache&logoColor=white&cacheSeconds=3600"></a>
</p>

**Version 2.0.2** · 2026-09-02 · 449.4 MB

- [Direct download](https://audion.dev/get/vs-engine-lite/2.0.2/Audion_VS_Engine_Lite_v2.0.2_Full.zip) — unmetered, no rate limits
- [Project page](https://audion.dev/downloads/vs-engine-lite) — every version and how to install

<p align="center"><img src="docs/screenshot.png" alt="The program window" width="560"></p>

`SHA-256: 2c1b57a1b8fd0f15cf8f9e14ddf7949ad5489537c888d3b182e8f9d80d568661`

---

An **Audion** tool, published by [Tensionix](https://github.com/Tensionix).
<!-- /audion:release -->


[Русский](README_RU.md) · [User Guide](USER_GUIDE_EN.md)

Technical video preparation and stylisation on VapourSynth and FFmpeg.
Twenty-two presets across four independent palettes, without the neural layer.

## Why It Exists

VapourSynth does what no editing suite offers out of the box: restoring film
material, deinterlacing with a good algorithm, denoising that treats the shadows
separately, neural upscaling. But using it means writing a Python script,
remembering plugin names, and assembling a pipeline by hand for every clip.

This program turns that into a set of ready presets. The script stays under the
hood: the engine assembles a `vspipe | ffmpeg` chain and runs it.

## Four Palettes

They are independent: you can take the technical processing alone and never touch
the stylisation, or the reverse.

| palette | presets | what it does |
|---|---|---|
| **Precision** | 8 | denoising, including shadow-targeted, debanding, controlled return of fine grain. The technical layer **before** the colourist |
| **Film** | 5 | film emulations: 35 mm Kodak, 16 mm, Super 8, bleach bypass, a general cinematic look |
| **Retro** | 2 | analogue character: VHS and CRT, a 1990s camcorder |
| **Restoration** | 7 | what editing suites lack: deinterlacing, inverse telecine, motion-compensated denoising, derainbow and deblocking, dehazing, plus non-neural upscaling |

**Order matters.** The precision palette is the technical layer that comes
*before* colour grading: fixing noise after the colourist has lifted the shadows
is too late.

## The Principle

The engine is a Python orchestrator over `vspipe | ffmpeg`. It neither rewrites
VapourSynth nor hides it: the assembled command is visible, and you can take it
and run it by hand.

The launchers are ordinary batch files with a quick picker and a fallback menu, in
Russian and English versions.

## Editions

| edition | presets | difference |
|---|---|---|
| full | 28 | with the neural layer: upscaling, frame doubling, neural denoising |
| **Lite** | 22 | classic VapourSynth plugins, no neural stack |

This edition is lighter and needs no graphics card: everything runs on classic
plugins.

## Next

* [User Guide](USER_GUIDE_EN.md) — installing the engine, first run, palettes,
  profiles, command line.

---

## Technical Reference

### Before the First Run

The VapourSynth engine and its plugins are installed separately — once. Until
that is done, the presets will not run.

### FFmpeg and the NVIDIA Driver

Every FFmpeg build is compiled against a particular version of the
hardware-encoding headers and demands its own minimum driver. The newest build on
an old driver does not accelerate anything — it breaks the hardware path. The
build is chosen to match the driver.

### Profiles

Saved combinations of presets and parameters — so the same chain need not be
assembled twice.

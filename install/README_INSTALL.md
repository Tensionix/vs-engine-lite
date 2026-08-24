# Audion Python Portable Template - install notes

## Main build paths

### Recommended
Run:

```bat
builder_main.cmd
```

or directly:

```bat
install\Build_Portable_Env_Build.cmd
```

This is the main CMD build script.

### Optional PowerShell route
Run:

```bat
install\Build_Portable_Env.cmd
```

This is a thin wrapper for the same-name `Build_Portable_Env.ps1`.

The wrapper looks for PowerShell in:

1. `system_core\powershell\pwsh.exe`
2. `pwsh.exe` in `PATH`
3. `powershell.exe` in `PATH`

## Portable flow

1. Create folders
2. Resolve and download latest Python Embedded `3.12.x` ZIP
3. Extract to `runtime\`
4. Enable `import site` and add the project root (`..`) in `python3<minor>._pth`
5. Download `get-pip.py`
6. Install packaging bootstrap (`setuptools`, `wheel`, `packaging`)
7. Rebuild local `wheelhouse\` as installable wheels (`.gitkeep` is preserved,
   stale wheels are removed first)
8. Install packages into portable runtime from local `wheelhouse\`
9. Verify orchestrator + GUI dependencies (`yaml`, `nicegui`, `pywebview`,
   `psutil`, `rich`) and run `system_core\ui_nicegui\app.py --smoke`
10. Optionally create a release ZIP in `release\`

Full stack verification is a separate later step:

```bat
install\verify_portable_env.cmd
```

Run it only after VapourSynth, VS plugins and FFmpeg are installed.

Portable PowerShell and FZF are reproducible tool payloads. Their installers
resolve latest upstream releases and replace only `system_core\powershell\` or
`system_core\fzf.exe`; they do not touch source/config/user data.

## Offline flow

If `runtime\` and `wheelhouse\` are already populated, run:

```bat
install\install_portable_offline.cmd
```

Then verify with:

```bat
install\verify_portable_env.cmd
```


## Release licensing

Third-party notices and license files are generated from the finalized staged release contents during `make_release_archive.cmd`. They are no longer generated during routine environment build/install steps.

---

## Current Builder Order And Dependency Hygiene

`builder_main.cmd` uses fixed numeric entries. Keep the bootstrap order stable: `[01] PYTHON ENV CMD`, `[02] PYTHON ENV PS`, `[03] FZF`, `[04] POWERSHELL`, then project-specific payload installers and one-time maintenance/diagnostic actions below.

Current builder install/maintenance map:

```text
[01] PYTHON ENV CMD
[02] PYTHON ENV PS
[03] FZF
[04] POWERSHELL
[09] PORTABLE OFFLINE
[10] VAPOURSYNTH
[11] VS PLUGINS
[12] FFMPEG
[70] CLEAN INSTALL CACHE
[71] VERIFY / DOCTOR
[74] COLLECT LICENSES
[75] PRUNE LICENSES
[76] DEDUP LICENSES
[77] MAKE RELEASE ARCHIVE
[90] PROJECT LAUNCHER
[95] OPEN install
[96] OPEN runtime
[97] OPEN wheelhouse
[98] OPEN licenses
[99] OPEN release
[00] EXIT
```

Project-specific payload entries before diagnostics:

[10] VAPOURSYNTH, [11] VS PLUGINS, [12] FFMPEG

Dependency hygiene rules:

- Python Embedded tracks the latest `3.12.x`; do not pin a concrete patch version in docs or scripts.
- Use the active embedded Python `_pth` file for path edits; do not hard-code a concrete filename.
- Bootstrap installs must include `setuptools`, `wheel`, and `packaging` before building or installing project wheels.
- `runtime\`, `wheelhouse\`, `system_core\powershell\`, `system_core\fzf.exe`, browser payloads, and external tool folders are reproducible payloads. Install/update scripts may cleanly replace only their owned targets.
- GPL or unknown-license external tools are explicit install/update payloads. Prefer GUI install buttons where the project exposes them, or fixed builder entries otherwise; do not silently bundle them as default source contents.
- Base VS plugins are declared in `install\vs_plugins.json`, shared with Full, and verified by real Python-module or VapourSynth-namespace probes. Maintained Python/wheel packages use PyPI; native filters and VS scripts use `vsrepo` through VS-host `python.exe`, not `Scripts\vsrepo.exe`. `nnedi3_resample` is installed with dependency resolution disabled because the canonical modern `znedi3` wheel is installed separately from PyPI.
- `install\Clean-Install-Cache.cmd` / `.ps1` is the general install-cache cleanup. It removes transient `install\download\` artifacts (preserving `.gitkeep`, `get-pip.py`, and `7z*-extra.7z`), exact installer staging dirs `system_core\_pwsh_tmp` / `system_core\_fzf_tmp`, and Python bytecode caches outside runtime, wheelhouse, and user-data zones.
- `cleanup_project.cmd` is a separate source/release cleanup tool. It can remove runtime payloads and user-output zones after explicit confirmation; do not describe it as the general install-cache cleaner and do not wire it into install flow.

Project-specific notes:

- Lite exposes GUI install buttons for VS host, VS plugins, and FFmpeg only. Lite has no MLRT install step; cache cleanup is `[70] CLEAN INSTALL CACHE`.



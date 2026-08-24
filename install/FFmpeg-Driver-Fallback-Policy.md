# FFmpeg NVIDIA stable driver policy

Default policy:

- NVIDIA driver 610.0 or newer: install the latest available BtbN or Gyan Stable release.
- NVIDIA driver 570.0-609.xx: install the latest FFmpeg 8.x Stable release (currently 8.1.x, NVENC SDK 13.0).
- NVIDIA driver 471.41-569.xx: install FFmpeg 7.1 Stable (NVENC SDK 11.1).
- NVIDIA GPU present but driver version unavailable: stop; compatibility cannot be verified safely.
- NVIDIA driver below 471.41: stop; no supported automatic NVENC branch is defined.
- No NVIDIA GPU: install the latest selected Stable release without an NVENC driver gate.

Master, nightly and autobuild assets are never selected.

BtbN is the primary provider. Its PowerShell helper returns exit code 20 only when the BtbN release asset cannot be resolved or downloaded. The BtbN CMD launcher catches that provider error and invokes Install-Portable-FFmpeg-Gyan.cmd without downgrading a compatible 570+ system.

The Gyan installer follows the same branch policy and performs a real one-frame H.264 NVENC smoke test after installation.

Manual Gyan version override:

    Install-Portable-FFmpeg-Gyan.cmd /VERSION 8.1.2
    Install-Portable-FFmpeg-Gyan.cmd /VERSION 7.1.1

Files must remain together in the same install script directory.

## Why the pinned release is not the newest one

The newer the FFmpeg build, the *narrower* its driver compatibility - each one
is compiled against newer NVENC headers that demand a newer driver:

| FFmpeg | NVENC headers | Minimum driver |
|---|---|---|
| 9.0.1 | ffnvcodec n13.1.15.0 | 610.0 |
| 8.1.x | ffnvcodec n13.1.x | 610.0 |
| 8.0.1 | ffnvcodec n13.0.19.0 | 570.0 |
| 7.1 | ffnvcodec n12.2.72.0 | 551.76 |

Most editing and encoding machines today sit roughly between drivers 571 and
609. The 610 branch is installed by very few of them. Pinning the newest build
would advertise NVIDIA hardware encoding and then deny it to the majority of
the people it was promised to.

So 8.0.1 is the deliberate default: it has everything these products use and it
runs on the drivers people actually have. Raise it when the 610 branch becomes
common - not when the next FFmpeg is released.

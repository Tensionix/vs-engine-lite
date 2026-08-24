<#
.SYNOPSIS
  Audion VS Engine - Repair pip-generated console_script .exe shims after a project move.

.DESCRIPTION
  pip wheels (incl. VapourSynth) install console_scripts as tiny launcher .exe files
  that EMBED an absolute shebang line `#!"<python.exe>"` between the launcher stub and
  the trailing zip payload. After moving the project to a different drive/path, that
  shebang points at a non-existent python.exe and the shim exits silently with code 1
  (no stdout, no stderr).

  This script rewrites the embedded shebang of every *.exe in -ScriptsDir to point at
  -PyExe, preserving the launcher stub head and the zip payload tail. Length of the
  shebang line may change freely - the zip parser scans from end-of-file.

.PARAMETER ScriptsDir
  Path to a directory containing pip-generated *.exe launchers (e.g.
  system_core\vapoursynth\Scripts).

.PARAMETER PyExe
  Absolute path to the python.exe these shims should call.

.PARAMETER WhatIf
  Report what would change without writing.
#>
param(
    [Parameter(Mandatory=$true)][string]$ScriptsDir,
    [Parameter(Mandatory=$true)][string]$PyExe,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ScriptsDir)) { throw "ScriptsDir not found: $ScriptsDir" }
if (-not (Test-Path $PyExe))      { throw "PyExe not found: $PyExe"           }

$PyExe = (Resolve-Path $PyExe).Path
$newShebang     = "#!`"$PyExe`"`r`n"
$newShebangBytes = [System.Text.Encoding]::ASCII.GetBytes($newShebang)

# Latin-1 gives 1:1 byte<->char mapping, safe for binary scanning via String.IndexOf.
$L1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')
$pkSig = [char]0x50 + [char]0x4B + [char]0x03 + [char]0x04   # PK\x03\x04

$patched = 0
$skipped = 0
$failed  = 0

Get-ChildItem -Path $ScriptsDir -Filter '*.exe' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $f = $_.FullName
    try {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $str   = $L1.GetString($bytes)

        $pkIdx = $str.IndexOf($pkSig, [System.StringComparison]::Ordinal)
        if ($pkIdx -lt 0) {
            Write-Host "      [SKIP]  $($_.Name)  (no zip payload, not a pip shim)"
            $script:skipped++
            return
        }

        # Find #! ordinal-binary, walking back from PK. Default LastIndexOf is
        # culture-aware and will spuriously match across arbitrary binary bytes.
        $shebangIdx = $str.LastIndexOf('#!', $pkIdx, [System.StringComparison]::Ordinal)
        if ($shebangIdx -lt 0) {
            Write-Host "      [SKIP]  $($_.Name)  (no shebang found)"
            $script:skipped++
            return
        }

        # End of shebang line = first \n at or after #! and before zip
        $lineEnd = $str.IndexOf("`n", $shebangIdx, [System.StringComparison]::Ordinal)
        if ($lineEnd -lt 0 -or $lineEnd -ge $pkIdx) {
            Write-Host "      [SKIP]  $($_.Name)  (malformed shebang line)"
            $script:skipped++
            return
        }
        $lineEnd += 1   # consume the \n

        # Read existing shebang for diff reporting
        $oldShebangLen = $lineEnd - $shebangIdx
        $oldShebangRaw = $str.Substring($shebangIdx, $oldShebangLen).TrimEnd("`r","`n")

        # Sanity: a real pip shim shebang is short, printable ASCII, and references python.
        # Without this guard, a #! pattern that happens to occur inside the launcher .exe
        # stub (e.g. a native non-pip launcher like uv-build.exe) would be "patched",
        # corrupting the binary.
        $isPlausible = ($oldShebangLen -lt 1024) `
                       -and ($oldShebangRaw -match '^#!\s*"?[^"\r\n]*python(\d|w)?\.exe"?\s*$')
        if (-not $isPlausible) {
            Write-Host "      [SKIP]  $($_.Name)  (no recognizable python shebang; not a pip shim)"
            $script:skipped++
            return
        }

        if ($oldShebangRaw -eq $newShebang.TrimEnd("`r","`n")) {
            Write-Host "      [OK]    $($_.Name)  (already points at $PyExe)"
            $script:skipped++
            return
        }

        if ($WhatIfOnly) {
            Write-Host "      [WOULD] $($_.Name)"
            Write-Host "              old: $oldShebangRaw"
            Write-Host "              new: #!`"$PyExe`""
            return
        }

        # Build new file = [head before shebang] + [new shebang] + [zip + everything after]
        $headLen = $shebangIdx
        $tailLen = $bytes.Length - $lineEnd
        $out = New-Object byte[] ($headLen + $newShebangBytes.Length + $tailLen)
        [Array]::Copy($bytes, 0,        $out, 0,                                   $headLen)
        [Array]::Copy($newShebangBytes, 0, $out, $headLen,                         $newShebangBytes.Length)
        [Array]::Copy($bytes, $lineEnd, $out, $headLen + $newShebangBytes.Length, $tailLen)

        [System.IO.File]::WriteAllBytes($f, $out)
        Write-Host "      [PATCH] $($_.Name)"
        $script:patched++
    }
    catch {
        Write-Host "      [FAIL]  $($_.Name)  ($($_.Exception.Message))"
        $script:failed++
    }
}

Write-Host ""
Write-Host "Repair-PipShims summary: patched=$patched skipped=$skipped failed=$failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }

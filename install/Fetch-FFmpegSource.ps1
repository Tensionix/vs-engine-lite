# Corresponding Source для установленного FFmpeg.
#
# Зачем. Сборка FFmpeg, которую мы кладём рядом с программой, собрана с
# --enable-gpl: это GPLv3, и распространять её можно, только обеспечив исходный
# код именно этой сборки. Ссылки на «FFmpeg вообще» недостаточно - между тэгом
# и сборкой бывают патчи.
#
# Откуда берётся версия. Не из кода: сборщик кладёт в архив README.txt, где
# записан точный коммит апстрима. Скрипт читает его оттуда, поэтому переход на
# любую будущую версию FFmpeg ничего здесь менять не требует.
#
# Что остаётся на диске:
#   Tools\ffmpeg-<версия>-source.tar.gz   исходники этой сборки
#   Tools\ffmpeg\ffmpeg-source.json       что это за сборка, машиночитаемо
#
# Второй файл читает Audion Build Licenses, когда собирает
# SOURCE_CODE_AVAILABILITY.txt - чтобы там стояли настоящие версия и коммит,
# а не заглушка.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [switch]$SkipDownload
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$toolsDir = Join-Path $ProjectRoot 'Tools'
$ffmpegDir = Join-Path $toolsDir 'ffmpeg'
$readme = Join-Path $ffmpegDir 'README.txt'

if (-not (Test-Path -LiteralPath $readme)) {
    Write-Warning "README.txt рядом с FFmpeg не найден: $readme"
    Write-Warning 'Сборка распакована не полностью - исходники не за что зацепить.'
    exit 2
}

$text = Get-Content -LiteralPath $readme -Raw -Encoding UTF8

$version = if ($text -match '(?m)^Version:\s*(\S+)') { $Matches[1] } else { '' }
$license = if ($text -match '(?m)^License:\s*(.+?)\s*$') { $Matches[1] } else { '' }
$commit = if ($text -match 'Source Code:\s*https://github\.com/FFmpeg/FFmpeg/commit/([0-9a-f]+)') {
    $Matches[1]
} else { '' }
# Строка конфигурации объясняет, почему лицензия именно такая: без
# --enable-gpl сборка была бы LGPL и этот скрипт был бы не нужен.
$configuration = ''
$ffmpegExe = Join-Path $ffmpegDir 'bin\ffmpeg.exe'
if (Test-Path -LiteralPath $ffmpegExe) {
    $versionLines = & $ffmpegExe -hide_banner -version 2>&1
    $configLine = $versionLines | Where-Object { $_ -match '^configuration:' } | Select-Object -First 1
    if ($configLine) { $configuration = ($configLine -replace '^configuration:\s*', '').Trim() }
}

if (-not $commit) {
    Write-Warning 'В README.txt нет ссылки на коммит исходников - нечего скачивать.'
    exit 3
}

Write-Host ("FFmpeg:  {0}" -f $(if ($version) { $version } else { '(версия не указана)' }))
Write-Host ("License: {0}" -f $(if ($license) { $license } else { '(не указана)' }))
Write-Host ("Commit:  {0}" -f $commit)

$shortVersion = if ($version -match '^([0-9]+(?:\.[0-9]+)*)') { $Matches[1] } else { 'unknown' }
$archiveName = "ffmpeg-$shortVersion-source.tar.gz"
$archivePath = Join-Path $toolsDir $archiveName
$sourceUrl = "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/$commit"

if ($SkipDownload) {
    Write-Host '[SKIP] Скачивание исходников отключено ключом -SkipDownload.'
} elseif (Test-Path -LiteralPath $archivePath) {
    Write-Host ("[OK] Исходники уже на месте: Tools\{0}" -f $archiveName)
} else {
    Write-Host ("Скачиваю исходники: {0}" -f $sourceUrl)
    $partPath = "$archivePath.part"
    try {
        Invoke-WebRequest -Uri $sourceUrl -OutFile $partPath -TimeoutSec 600 `
            -Headers @{ 'User-Agent' = 'Audion-FFmpeg-Source' }
        # Пустой или обрезанный файл хуже отсутствующего: он выглядит как
        # выполненное обязательство.
        $size = (Get-Item -LiteralPath $partPath).Length
        if ($size -lt 1MB) { throw "архив подозрительно мал: $size байт" }
        Move-Item -LiteralPath $partPath -Destination $archivePath -Force
        Write-Host ("[OK] Исходники: Tools\{0} ({1:N1} МБ)" -f $archiveName, ($size / 1MB))
    } catch {
        Remove-Item -LiteralPath $partPath -Force -ErrorAction SilentlyContinue
        Write-Warning ("Исходники скачать не удалось: {0}" -f $_.Exception.Message)
        Write-Warning 'Бинарник останется, но обязательство GPL закрыто только ссылкой.'
    }
}

$record = [ordered]@{
    component      = 'FFmpeg'
    version        = $version
    license        = $license
    upstream_commit = $commit
    upstream_url   = "https://github.com/FFmpeg/FFmpeg/commit/$commit"
    source_archive = if (Test-Path -LiteralPath $archivePath) { "Tools\$archiveName" } else { '' }
    source_url     = $sourceUrl
    configuration  = $configuration
    recorded_at    = (Get-Date).ToString('o')
}
$recordPath = Join-Path $ffmpegDir 'ffmpeg-source.json'
$record | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $recordPath -Encoding UTF8
Write-Host ("[OK] Запись для сборщика лицензий: Tools\ffmpeg\ffmpeg-source.json")

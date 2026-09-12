#requires -Version 7.0

$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($PSScriptRoot, '..')
)

$manifestPaths = @(
    'apps/lua/beamng-orbit-camera/manifest.ini'
    'extension/lua/chaser-camera/beamng-orbit/manifest.ini'
)

$versions = foreach ($manifestPath in $manifestPaths) {
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot $manifestPath) -Raw
    $versionMatch = [regex]::Match($manifest, '(?m)^VERSION\s*=\s*([^\r\n]+)')
    $version = $versionMatch.Groups[1].Value.Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$') {
        throw "Missing or invalid release version in $manifestPath"
    }
    $version
}

if ($versions[0] -ne $versions[1]) {
    throw "App and camera versions do not match: $($versions -join ', ')"
}

$distDirectory = Join-Path $projectRoot 'dist'
$archivePath = Join-Path $distDirectory "beamng-orbit-camera-$($versions[0]).zip"
$sourceDirectories = @(
    (Join-Path $projectRoot 'apps')
    (Join-Path $projectRoot 'extension')
)

New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null
Compress-Archive -LiteralPath $sourceDirectories -DestinationPath $archivePath -CompressionLevel Optimal -Force

Write-Host "Release archive created: $archivePath"

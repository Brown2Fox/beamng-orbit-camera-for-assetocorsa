#requires -Version 7.0

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:ASSETO_CORSA_HOME)) {
    throw 'The ASSETO_CORSA_HOME environment variable is not configured.'
}

$assettoCorsaHome = [System.IO.Path]::GetFullPath(
    $env:ASSETO_CORSA_HOME
)

if (-not (Test-Path -LiteralPath $assettoCorsaHome -PathType Container)) {
    throw "The Assetto Corsa directory does not exist: $assettoCorsaHome"
}

# The script is located in <project>\tools,
# so the project root is one directory above.
$projectRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($PSScriptRoot, '..')
)

$folders = @(
    'apps'
    'extension'
)

foreach ($folder in $folders) {
    $source = Join-Path $projectRoot $folder
    $destination = Join-Path $assettoCorsaHome $folder

    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "The source directory does not exist: $source"
    }

    New-Item `
        -ItemType Directory `
        -Path $destination `
        -Force |
        Out-Null

    Write-Host "Copying '$source' to '$destination'..."

    # Recursively copy the directory contents
    # and overwrite existing files.
    Copy-Item `
        -Path (Join-Path $source '*') `
        -Destination $destination `
        -Recurse `
        -Force
}

Write-Host 'Deployment completed successfully.'
# GameVault Game Compression Script
# Compresses pre-sorted, already-named game folders into .7z archives using
# maximum compression for GameVault ingestion. Folders are expected to already
# be named per GameVault conventions.

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Define source and destination directories
$gogSourceDir   = Join-Path $PSScriptRoot "GOG-Archive"
$steamSourceDir = Join-Path $PSScriptRoot "Steam-Archive"
$destinationDir = Join-Path $PSScriptRoot "GameVault-Ready"

# Locate 7-Zip: env override -> standard install paths -> PATH lookup.
function Find-SevenZip
{
    if ($env:SEVENZIP_PATH -and (Test-Path $env:SEVENZIP_PATH))
    {
        return $env:SEVENZIP_PATH
    }
    $candidates = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )
    foreach ($candidate in $candidates)
    {
        if (Test-Path $candidate) { return $candidate }
    }
    $onPath = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

# GameVault folder-name validator. Minimum requirement: ends with `(YYYY)`.
$script:GameVaultNameRegex = '\((\d{4})\)$'

$sevenZipPath = Find-SevenZip
if (-not $sevenZipPath)
{
    Write-Host "ERROR: 7-Zip not found. Install 7-Zip, set `$env:SEVENZIP_PATH, or add 7z.exe to PATH." -ForegroundColor Red
    exit 1
}
Write-Host "Using 7-Zip: $sevenZipPath" -ForegroundColor DarkGray

# Create destination directory if needed
if (!(Test-Path $destinationDir))
{
    New-Item -ItemType Directory -Path $destinationDir | Out-Null
    Write-Host "Created destination directory: $destinationDir" -ForegroundColor Green
}

# Collect games from both GOG and Steam sources
$allGames = @()

if (Test-Path $gogSourceDir)
{
    $gogFolders = Get-ChildItem -Path $gogSourceDir -Directory
    foreach ($folder in $gogFolders)
    {
        $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = "GOG" }
    }
    Write-Host "Found $($gogFolders.Count) GOG game folders" -ForegroundColor Green
} else
{
    Write-Host "GOG source directory not found: $gogSourceDir" -ForegroundColor Yellow
}

if (Test-Path $steamSourceDir)
{
    $steamFolders = Get-ChildItem -Path $steamSourceDir -Directory
    foreach ($folder in $steamFolders)
    {
        $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = "Steam" }
    }
    Write-Host "Found $($steamFolders.Count) Steam game folders" -ForegroundColor Green
} else
{
    Write-Host "Steam source directory not found: $steamSourceDir" -ForegroundColor Yellow
}

if ($allGames.Count -eq 0)
{
    Write-Host "No game folders found in GOG or Steam source directories." -ForegroundColor Yellow
    exit 0
}

# Pre-flight: validate folder names against GameVault format and report.
$valid   = @()
$invalid = @()
foreach ($game in $allGames)
{
    if ($game.Name -match $script:GameVaultNameRegex)
    {
        $valid += $game
    } else
    {
        $invalid += $game
    }
}

if ($invalid.Count -gt 0)
{
    Write-Host "`nWARNING: $($invalid.Count) folder(s) do not end with a 4-digit year in parentheses and will be SKIPPED:" -ForegroundColor Yellow
    foreach ($game in $invalid)
    {
        Write-Host "  [$($game.Source)] $($game.Name)" -ForegroundColor Yellow
    }
    Write-Host "Rename them per GameVault format (e.g. 'Title (W) (2020)') or use Prepare-GamesForGameVault.ps1." -ForegroundColor Yellow
}

if ($valid.Count -eq 0)
{
    Write-Host "`nNo validly-named folders to compress." -ForegroundColor Red
    exit 1
}

Write-Host "`nFound $($valid.Count) folder(s) to compress." -ForegroundColor Cyan
Write-Host "Output -> $destinationDir"
Write-Host "Compression: Maximum (-mx=9 -mfb=64 -md=32m -ms=on -mmt=on)`n"
Write-Host ("-" * 60)

$success = 0
$failed  = 0

foreach ($game in $valid)
{
    $archiveName = "$($game.Name).7z"
    $archivePath = Join-Path $destinationDir $archiveName

    Write-Host "[$($game.Source)] $($game.Name)" -ForegroundColor Cyan

    if (Test-Path $archivePath)
    {
        Write-Host "  SKIPPED - archive already exists: $archiveName" -ForegroundColor Yellow
        continue
    }

    & "$sevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$archivePath" "$($game.Path)\*" | Out-Null

    if ($LASTEXITCODE -eq 0)
    {
        Write-Host "  OK -> $archiveName" -ForegroundColor Green
        $success++
    } else
    {
        Write-Host "  FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ("-" * 60)
Write-Host "`nDone: $success compressed, $failed failed, $($invalid.Count) skipped (invalid name)." -ForegroundColor Cyan
Write-Host "GameVault-ready archives are in: $destinationDir" -ForegroundColor Green

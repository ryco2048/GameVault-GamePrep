# GameVault Game Compression Script
# Compresses pre-sorted, already-named game folders into .7z archives using
# maximum compression for GameVault ingestion. Folders are expected to already
# be named per GameVault conventions.

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GogSourceDir   = (Join-Path $PSScriptRoot "GOG-Archive"),
    [string]$SteamSourceDir = (Join-Path $PSScriptRoot "Steam-Archive"),
    [string]$DestinationDir = (Join-Path $PSScriptRoot "GameVault-Ready"),
    [string]$SevenZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

if (-not $SevenZipPath) { $SevenZipPath = Find-SevenZip }
if (-not $SevenZipPath -or -not (Test-Path $SevenZipPath))
{
    Write-Error "7-Zip not found. Install 7-Zip, set `$env:SEVENZIP_PATH, pass -SevenZipPath, or add 7z.exe to PATH."
    exit 1
}
Write-Verbose "Using 7-Zip: $SevenZipPath"

# Create destination directory if needed
if (!(Test-Path $DestinationDir))
{
    if ($PSCmdlet.ShouldProcess($DestinationDir, "Create directory"))
    {
        New-Item -ItemType Directory -Path $DestinationDir | Out-Null
        Write-Verbose "Created destination directory: $DestinationDir"
    }
}

# Collect games from both GOG and Steam sources
$allGames = @()

if (Test-Path $GogSourceDir)
{
    $gogFolders = Get-ChildItem -Path $GogSourceDir -Directory
    foreach ($folder in $gogFolders)
    {
        $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = "GOG" }
    }
    Write-Host "Found $($gogFolders.Count) GOG game folders" -ForegroundColor Green
} else
{
    Write-Warning "GOG source directory not found: $GogSourceDir"
}

if (Test-Path $SteamSourceDir)
{
    $steamFolders = Get-ChildItem -Path $SteamSourceDir -Directory
    foreach ($folder in $steamFolders)
    {
        $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = "Steam" }
    }
    Write-Host "Found $($steamFolders.Count) Steam game folders" -ForegroundColor Green
} else
{
    Write-Warning "Steam source directory not found: $SteamSourceDir"
}

if ($allGames.Count -eq 0)
{
    Write-Warning "No game folders found in GOG or Steam source directories."
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
    $invalidList = ($invalid | ForEach-Object { "  [$($_.Source)] $($_.Name)" }) -join "`n"
    Write-Warning "$($invalid.Count) folder(s) do not end with a 4-digit year in parentheses and will be SKIPPED:`n$invalidList`nRename them per GameVault format (e.g. 'Title (W) (2020)') or use Prepare-GamesForGameVault.ps1."
}

if ($valid.Count -eq 0)
{
    Write-Error "No validly-named folders to compress."
    exit 1
}

Write-Host "`nFound $($valid.Count) folder(s) to compress." -ForegroundColor Cyan
Write-Host "Output -> $DestinationDir"
Write-Host "Compression: Maximum (-mx=9 -mfb=64 -md=32m -ms=on -mmt=on)`n"
Write-Host ("-" * 60)

$success = 0
$failed  = 0

foreach ($game in $valid)
{
    $archiveName = "$($game.Name).7z"
    $archivePath = Join-Path $DestinationDir $archiveName

    Write-Host "[$($game.Source)] $($game.Name)" -ForegroundColor Cyan

    if (Test-Path $archivePath)
    {
        Write-Host "  SKIPPED (archive exists): $archiveName" -ForegroundColor Yellow
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($archivePath, "7-Zip compress from $($game.Path)"))
    {
        Write-Host "  SKIPPED (WhatIf): would compress to $archiveName" -ForegroundColor DarkGray
        continue
    }

    & "$SevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$archivePath" "$($game.Path)\*" | Out-Null

    if ($LASTEXITCODE -eq 0)
    {
        Write-Host "  OK -> $archiveName" -ForegroundColor Green
        $success++
    } else
    {
        Write-Host "  FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
        Write-Error "7-Zip failed for '$($game.Name)' with exit code $LASTEXITCODE" -ErrorAction Continue
        $failed++
    }
}

Write-Host ("-" * 60)
Write-Host "`nDone: $success compressed, $failed failed, $($invalid.Count) skipped (invalid name)." -ForegroundColor Cyan
Write-Host "GameVault-ready archives are in: $DestinationDir" -ForegroundColor Green

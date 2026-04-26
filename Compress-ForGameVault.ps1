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

# Sum of all file sizes inside a folder (recursive). Returns 0 on empty/missing.
function Get-FolderSize
{
    param([string]$Path)
    $sum = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return [int64]$sum
}

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

# Pre-flight: estimate source size and verify destination has enough free space.
# Estimate archive size at 70% of source (lz77 typical for game content).
Write-Verbose "Calculating source folder sizes for free-space check..."
$totalSourceBytes = 0
foreach ($game in $valid) { $totalSourceBytes += Get-FolderSize -Path $game.Path }
$estArchiveBytes = [int64]($totalSourceBytes * 0.7)
$destDrive = (Get-Item $DestinationDir).PSDrive
$freeBytes = $destDrive.Free
if ($freeBytes -lt $estArchiveBytes)
{
    $needGB = [math]::Round($estArchiveBytes / 1GB, 2)
    $haveGB = [math]::Round($freeBytes / 1GB, 2)
    Write-Error "Insufficient free space on $($destDrive.Name): need ~${needGB} GB, have ${haveGB} GB."
    exit 1
}

Write-Host "`nFound $($valid.Count) folder(s) to compress." -ForegroundColor Cyan
Write-Host "Output -> $DestinationDir"
Write-Host ("Source: {0:N2} GB  |  Free on {1}: {2:N2} GB  |  Est. archive: {3:N2} GB" -f ($totalSourceBytes/1GB), $destDrive.Name, ($freeBytes/1GB), ($estArchiveBytes/1GB))
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

    # Write to .tmp first; only rename to final name on success so partial
    # archives never end up in the GameVault-Ready directory.
    $tempArchive = "$archivePath.tmp"
    if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force }

    try
    {
        & "$SevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$tempArchive" "$($game.Path)\*" | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            throw "7-Zip exited $LASTEXITCODE"
        }
        Move-Item -LiteralPath $tempArchive -Destination $archivePath
        Write-Host "  OK -> $archiveName" -ForegroundColor Green
        $success++
    } catch
    {
        if (Test-Path $tempArchive) { Remove-Item -LiteralPath $tempArchive -Force -ErrorAction SilentlyContinue }
        Write-Host "  FAILED ($_)" -ForegroundColor Red
        Write-Error "7-Zip failed for '$($game.Name)': $_" -ErrorAction Continue
        $failed++
    }
}

Write-Host ("-" * 60)
Write-Host "`nDone: $success compressed, $failed failed, $($invalid.Count) skipped (invalid name)." -ForegroundColor Cyan
Write-Host "GameVault-ready archives are in: $DestinationDir" -ForegroundColor Green

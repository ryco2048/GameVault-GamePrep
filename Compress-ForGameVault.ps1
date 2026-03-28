# GameVault Game Compression Script
# This script compresses pre-sorted, already-named game folders into .7z archives
# using maximum compression settings for GameVault ingestion.
# Folders are expected to already be named per GameVault conventions.

# Define source and destination directories
$gogSourceDir   = Join-Path $PSScriptRoot "GOG-Archive"
$steamSourceDir = Join-Path $PSScriptRoot "Steam-Archive"
$destinationDir = Join-Path $PSScriptRoot "GameVault-Ready"
$sevenZipPath   = "C:\Program Files\7-Zip\7z.exe"    # Update this path if 7-Zip is installed elsewhere

# Check if 7-Zip is installed
if (!(Test-Path $sevenZipPath)) {
    Write-Host "ERROR: 7-Zip not found at '$sevenZipPath'. Update the path in the script." -ForegroundColor Red
    exit 1
}

# Create destination directory if needed
if (!(Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir | Out-Null
    Write-Host "Created destination directory: $destinationDir" -ForegroundColor Green
}

# Main processing loop
# Collect games from both GOG and Steam sources
$allGames = @()

# Check GOG directory
if (Test-Path $gogSourceDir) {
    $gogFolders = Get-ChildItem -Path $gogSourceDir -Directory
    foreach ($folder in $gogFolders) {
        $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = "GOG" }
    }
    Write-Host "Found $($gogFolders.Count) GOG game folders" -ForegroundColor Green
} else {
    Write-Host "GOG source directory not found: $gogSourceDir" -ForegroundColor Yellow
}

# Check Steam directory
if (Test-Path $steamSourceDir) {
    $steamFolders = Get-ChildItem -Path $steamSourceDir -Directory
    foreach ($folder in $steamFolders) {
        $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = "Steam" }
    }
    Write-Host "Found $($steamFolders.Count) Steam game folders" -ForegroundColor Green
} else {
    Write-Host "Steam source directory not found: $steamSourceDir" -ForegroundColor Yellow
}

if ($allGames.Count -eq 0) {
    Write-Host "No game folders found in GOG or Steam source directories." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nFound $($allGames.Count) total folders to compress." -ForegroundColor Cyan
Write-Host "Output -> $destinationDir"
Write-Host "Compression: Maximum (-mx=9 -mfb=64 -md=32m -ms=on)`n"
Write-Host ("-" * 60)

$success = 0
$failed  = 0

foreach ($game in $allGames) {
    $archiveName = "$($game.Name).7z"
    $archivePath = Join-Path $destinationDir $archiveName

    Write-Host "[$($game.Source)] $($game.Name)" -ForegroundColor Cyan

    if (Test-Path $archivePath) {
        Write-Host "  SKIPPED - archive already exists: $archiveName" -ForegroundColor Yellow
        continue
    }

    & "$sevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on "$archivePath" "$($game.Path)\*" | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK -> $archiveName" -ForegroundColor Green
        $success++
    } else {
        Write-Host "  FAILED (exit code $LASTEXITCODE)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ("-" * 60)
Write-Host "`nDone: $success compressed, $failed failed." -ForegroundColor Cyan
Write-Host "GameVault-ready archives are in: $destinationDir" -ForegroundColor Green

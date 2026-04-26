# GameVault Game Preparation Script
# Prepares both GOG and Steam games for GameVault by compressing and naming them
# according to GameVault standards via interactive prompts.

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

# Strip characters Windows forbids in filenames and trim whitespace/trailing dots.
function Format-SafeFileName
{
    param([string]$Name)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray())
    {
        if ($invalid -notcontains $ch) { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Trim().TrimEnd('.')
}

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
    Write-Host "Created destination directory: $destinationDir"
}

# Builds a GameVault-compliant archive filename from interactive user input.
function Build-GameVaultFileName
{
    param (
        [string]$gameFolderName,
        [string]$gameSource
    )

    Write-Host "`nPreparing game: $gameFolderName (Source: $gameSource)" -ForegroundColor Cyan

    $title = Read-Host "Enter game title (default: $gameFolderName)"
    if ([string]::IsNullOrWhiteSpace($title))
    { $title = $gameFolderName
    }
    $title = Format-SafeFileName -Name $title
    if ([string]::IsNullOrWhiteSpace($title))
    {
        throw "Title became empty after sanitization. Aborting."
    }

    $version = Read-Host "Enter game version (e.g., v1.2.3) (optional)"
    if ($version) { $version = Format-SafeFileName -Name $version }

    $earlyAccess = Read-Host "Is this an Early Access game? (y/n) (default: n)"
    $earlyAccessTag = if ($earlyAccess -eq "y")
    { "EA"
    } else
    { ""
    }

    $allowedTypes = @('W_S','W','L','M','A')
    $gameType = Read-Host "Enter game type (W_S, W, L, M, A) (default: W)"
    if ([string]::IsNullOrWhiteSpace($gameType))
    { $gameType = "W"
    }
    while ($gameType -notin $allowedTypes)
    {
        Write-Host "Invalid game type. Must be one of: $($allowedTypes -join ', ')" -ForegroundColor Yellow
        $gameType = Read-Host "Enter game type (W_S, W, L, M, A)"
        if ([string]::IsNullOrWhiteSpace($gameType)) { $gameType = "W" }
    }

    $noCache = Read-Host "Disable caching for this game? (y/n) (default: n)"
    $noCacheTag = if ($noCache -eq "y")
    { "NC"
    } else
    { ""
    }

    $minYear = 1970
    $maxYear = (Get-Date).Year + 1
    $releaseYear = Read-Host "Enter release year (e.g., 2023) (required, $minYear-$maxYear)"
    while ($true)
    {
        if ($releaseYear -match '^\d{4}$' -and [int]$releaseYear -ge $minYear -and [int]$releaseYear -le $maxYear)
        {
            break
        }
        Write-Host "Release year must be a 4-digit number between $minYear and $maxYear." -ForegroundColor Yellow
        $releaseYear = Read-Host "Enter release year (e.g., 2023)"
    }

    # Build filename according to GameVault naming convention
    $fileName = $title

    if (![string]::IsNullOrWhiteSpace($version))
    {
        $fileName += " ($version)"
    }

    if (![string]::IsNullOrWhiteSpace($earlyAccessTag))
    {
        $fileName += " ($earlyAccessTag)"
    }

    if (![string]::IsNullOrWhiteSpace($gameType))
    {
        $fileName += " ($gameType)"
    }

    if (![string]::IsNullOrWhiteSpace($noCacheTag))
    {
        $fileName += " ($noCacheTag)"
    }

    $fileName += " ($releaseYear).7z"

    return $fileName
}

# Function to compress a game folder
function Compress-Game
{
    param (
        [string]$sourcePath,
        [string]$destinationFile,
        [ValidateSet(1, 5, 9)]
        [int]$compressionLevel = 5
    )

    Write-Host "Compressing $sourcePath to $destinationFile..." -ForegroundColor Yellow

    # Compression command based on level
    switch ($compressionLevel)
    {
        1
        { # Fast (store only, no compression)
            & "$sevenZipPath" a -mx=0 -ms=off "$destinationFile" "$sourcePath\*"
        }
        5
        { # Balanced
            & "$sevenZipPath" a -mx=5 -mmt=on "$destinationFile" "$sourcePath\*"
        }
        9
        { # Maximum compression
            & "$sevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$destinationFile" "$sourcePath\*"
        }
    }

    if ($LASTEXITCODE -eq 0)
    {
        Write-Host "Compression completed successfully!" -ForegroundColor Green
        return $true
    } else
    {
        Write-Host "Compression failed with exit code $LASTEXITCODE" -ForegroundColor Red
        return $false
    }
}

# Main processing loop
# Collect games from both GOG and Steam sources
$allGames = @()

# Check GOG directory
if (Test-Path $gogSourceDir)
{
    $gogFolders = Get-ChildItem -Path $gogSourceDir -Directory
    foreach ($folder in $gogFolders)
    {
        $allGames += [PSCustomObject]@{
            Name = $folder.Name
            Path = $folder.FullName
            Source = "GOG"
        }
    }
    Write-Host "Found $($gogFolders.Count) GOG game folders" -ForegroundColor Green
} else
{
    Write-Host "GOG source directory not found: $gogSourceDir" -ForegroundColor Yellow
}

# Check Steam directory
if (Test-Path $steamSourceDir)
{
    $steamFolders = Get-ChildItem -Path $steamSourceDir -Directory
    foreach ($folder in $steamFolders)
    {
        $allGames += [PSCustomObject]@{
            Name = $folder.Name
            Path = $folder.FullName
            Source = "Steam"
        }
    }
    Write-Host "Found $($steamFolders.Count) Steam game folders" -ForegroundColor Green
} else
{
    Write-Host "Steam source directory not found: $steamSourceDir" -ForegroundColor Yellow
}

if ($allGames.Count -eq 0)
{
    Write-Host "No game folders found in either GOG or Steam directories" -ForegroundColor Red
    exit 1
}

Write-Host "`nTotal: $($allGames.Count) game folders to process" -ForegroundColor Green
Write-Host "-----------------------------------------"

foreach ($game in $allGames)
{
    $gameName = $game.Name
    $gamePath = $game.Path
    $gameSource = $game.Source

    $fileName = Build-GameVaultFileName -gameFolderName $gameName -gameSource $gameSource
    $destinationFile = Join-Path -Path $destinationDir -ChildPath $fileName

    Write-Host "`nProcessing: $gameName ($gameSource)" -ForegroundColor Cyan
    Write-Host "Target file: $fileName" -ForegroundColor Cyan

    $compressionChoice = Read-Host "Select compression level: 1 (Fast), 5 (Balanced), 9 (Maximum) (default: 5)"
    if ([string]::IsNullOrWhiteSpace($compressionChoice) -or !($compressionChoice -match '^[159]$'))
    {
        $compressionChoice = 5
    }

    $success = Compress-Game -sourcePath $gamePath -destinationFile $destinationFile -compressionLevel ([int]$compressionChoice)

    if ($success)
    {
        Write-Host "Successfully prepared $gameName for GameVault" -ForegroundColor Green
    } else
    {
        Write-Host "Failed to prepare $gameName" -ForegroundColor Red
    }

    Write-Host "-----------------------------------------"
}

Write-Host "`nAll games have been processed. GameVault-ready games are in: $destinationDir" -ForegroundColor Green
Write-Host "You can now copy these files to your GameVault server's /files directory." -ForegroundColor Green

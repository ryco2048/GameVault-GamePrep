# GameVault GOG Game Preparation Script
# This script prepares GOG games for GameVault by compressing and naming them according to GameVault standards

# Define source and destination directories
$sourceDir = "C:\Games\GOG-Archive"                # Update this path to your source folder
$destinationDir = "C:\Games\GameVault-Ready"       # Update this path to your destination folder
$tempDir = "C:\Games\Temp"                         # Update this path to your temp folded   
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"    # Update this path if 7-Zip is installed elsewhere

# Create destination and temp directories if they don't exist
if (!(Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir | Out-Null
    Write-Host "Created destination directory: $destinationDir"
}

if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    Write-Host "Created temporary directory: $tempDir"
}

# Check if 7-Zip is installed
if (!(Test-Path $sevenZipPath)) {
    Write-Host "7-Zip not found at $sevenZipPath. Please install 7-Zip or update the path in the script." -ForegroundColor Red
    exit
}

# Function to get game information from user
function Get-GameInfo {
    param (
        [string]$gameFolderName
    )

    Write-Host "`nPreparing game: $gameFolderName" -ForegroundColor Cyan

    $title = Read-Host "Enter game title (default: $gameFolderName)"
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $gameFolderName }

    $version = Read-Host "Enter game version (e.g., v1.2.3) (optional)"

    $earlyAccess = Read-Host "Is this an Early Access game? (y/n) (default: n)"
    $earlyAccessTag = if ($earlyAccess -eq "y") { "EA" } else { "" }

    $gameType = Read-Host "Enter game type (W_S, W, L, M, A) (default: W)"
    if ([string]::IsNullOrWhiteSpace($gameType)) { $gameType = "W" }

    $noCache = Read-Host "Disable caching for this game? (y/n) (default: n)"
    $noCacheTag = if ($noCache -eq "y") { "NC" } else { "" }

    $releaseYear = Read-Host "Enter release year (e.g., 2023) (required)"
    while ([string]::IsNullOrWhiteSpace($releaseYear) -or !($releaseYear -match '^\d{4}$')) {
        Write-Host "Release year is required and must be a 4-digit number." -ForegroundColor Yellow
        $releaseYear = Read-Host "Enter release year (e.g., 2023)"
    }

    # Build filename according to GameVault naming convention
    $fileName = $title

    if (![string]::IsNullOrWhiteSpace($version)) {
        $fileName += " ($version)"
    }

    if (![string]::IsNullOrWhiteSpace($earlyAccessTag)) {
        $fileName += " ($earlyAccessTag)"
    }

    if (![string]::IsNullOrWhiteSpace($gameType)) {
        $fileName += " ($gameType)"
    }

    if (![string]::IsNullOrWhiteSpace($noCacheTag)) {
        $fileName += " ($noCacheTag)"
    }

    $fileName += " ($releaseYear).7z"

    return $fileName
}

# Function to compress a game folder
function Compress-Game {
    param (
        [string]$sourcePath,
        [string]$destinationFile,
        [int]$compressionLevel = 5
    )

    Write-Host "Compressing $sourcePath to $destinationFile..." -ForegroundColor Yellow

    # Compression command based on level
    switch ($compressionLevel) {
        1 { # Fast compression
            & "$sevenZipPath" a -mx=0 -ms=off "$destinationFile" "$sourcePath\*"
        }
        9 { # Maximum compression
            & "$sevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on "$destinationFile" "$sourcePath\*"
        }
        default { # Balanced compression (default)
            & "$sevenZipPath" a -mx=5 "$destinationFile" "$sourcePath\*"
        }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Compression completed successfully!" -ForegroundColor Green
        return $true
    } else {
        Write-Host "Compression failed with exit code $LASTEXITCODE" -ForegroundColor Red
        return $false
    }
}

# Main processing loop
$gameFolders = Get-ChildItem -Path $sourceDir -Directory

if ($gameFolders.Count -eq 0) {
    Write-Host "No game folders found in $sourceDir" -ForegroundColor Yellow
    exit
}

Write-Host "Found $($gameFolders.Count) game folders to process" -ForegroundColor Green

foreach ($gameFolder in $gameFolders) {
    $gameName = $gameFolder.Name
    $gamePath = $gameFolder.FullName

    $fileName = Get-GameInfo -gameFolderName $gameName
    $destinationFile = Join-Path -Path $destinationDir -ChildPath $fileName

    Write-Host "`nProcessing: $gameName" -ForegroundColor Cyan
    Write-Host "Target file: $fileName" -ForegroundColor Cyan

    $compressionChoice = Read-Host "Select compression level: 1 (Fast), 5 (Balanced), 9 (Maximum) (default: 5)"
    if ([string]::IsNullOrWhiteSpace($compressionChoice) -or !($compressionChoice -match '^[159]$')) {
        $compressionChoice = 5
    }

    $success = Compress-Game -sourcePath $gamePath -destinationFile $destinationFile -compressionLevel ([int]$compressionChoice)

    if ($success) {
        Write-Host "Successfully prepared $gameName for GameVault" -ForegroundColor Green
    } else {
        Write-Host "Failed to prepare $gameName" -ForegroundColor Red
    }

    Write-Host "-----------------------------------------"
}

Write-Host "`nAll games have been processed. GameVault-ready games are in: $destinationDir" -ForegroundColor Green
Write-Host "You can now copy these files to your GameVault server's /files directory." -ForegroundColor Green

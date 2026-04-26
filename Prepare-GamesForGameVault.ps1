# GameVault Game Preparation Script
# Prepares both GOG and Steam games for GameVault by compressing and naming them
# according to GameVault standards via interactive prompts.

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GogSourceDir   = (Join-Path $PSScriptRoot "GOG-Archive"),
    [string]$SteamSourceDir = (Join-Path $PSScriptRoot "Steam-Archive"),
    [string]$DestinationDir = (Join-Path $PSScriptRoot "GameVault-Ready"),
    [string]$SevenZipPath,
    [switch]$EmitSha256
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

# Sum of all file sizes inside a folder (recursive). Returns 0 on empty/missing.
function Get-FolderSize
{
    param([string]$Path)
    $sum = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return [int64]$sum
}

# Append one row to manifest.csv describing a successful compression.
function Add-ManifestEntry
{
    param(
        [string]$ManifestPath,
        [string]$Name,
        [string]$Source,
        [string]$ArchivePath,
        [int64]$SourceBytes,
        [TimeSpan]$Duration,
        [switch]$IncludeHash
    )
    $archiveBytes = (Get-Item -LiteralPath $ArchivePath).Length
    $ratio = if ($SourceBytes -gt 0) { [math]::Round($archiveBytes / $SourceBytes, 4) } else { 0 }
    $hash  = if ($IncludeHash) { (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash } else { '' }
    $row = [PSCustomObject]@{
        CompletedAt      = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')
        Name             = $Name
        Source           = $Source
        SourceBytes      = $SourceBytes
        ArchiveBytes     = $archiveBytes
        CompressionRatio = $ratio
        DurationSeconds  = [math]::Round($Duration.TotalSeconds, 2)
        SHA256           = $hash
    }
    $row | Export-Csv -LiteralPath $ManifestPath -Append -NoTypeInformation -Encoding UTF8
}

# Parse an existing folder name into GameVault field defaults.
# Strips known tags from the end so the remaining string becomes the title.
function Get-FolderNameDefaults
{
    param([string]$FolderName)
    $d = @{ Title=$FolderName; Version=''; EarlyAccess='n'; GameType='W'; NoCache='n'; ReleaseYear='' }

    if ($FolderName -match '\((\d{4})\)$')
    {
        $d.ReleaseYear = $Matches[1]
        $FolderName = ($FolderName -replace '\s*\(\d{4}\)$', '').TrimEnd()
    }
    if ($FolderName -match '\((NC)\)')
    {
        $d.NoCache = 'y'
        $FolderName = ($FolderName -replace '\s*\(NC\)', '').TrimEnd()
    }
    if ($FolderName -match '\((W_S|W|L|M|A)\)')
    {
        $d.GameType = $Matches[1]
        $FolderName = ($FolderName -replace '\s*\((W_S|W|L|M|A)\)', '').TrimEnd()
    }
    if ($FolderName -match '\((EA)\)')
    {
        $d.EarlyAccess = 'y'
        $FolderName = ($FolderName -replace '\s*\(EA\)', '').TrimEnd()
    }
    if ($FolderName -match '\((v[^)]+)\)')
    {
        $d.Version = $Matches[1]
        $FolderName = ($FolderName -replace '\s*\(v[^)]+\)', '').TrimEnd()
    }
    $d.Title = $FolderName.Trim()
    return $d
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

# Builds a GameVault-compliant archive filename from interactive user input.
# $Defaults hashtable (from Get-FolderNameDefaults) pre-fills each prompt.
function Build-GameVaultFileName
{
    param (
        [string]$gameFolderName,
        [string]$gameSource,
        [hashtable]$Defaults = @{}
    )

    $defTitle  = if ($Defaults.Title)       { $Defaults.Title }       else { $gameFolderName }
    $defVer    = if ($Defaults.Version)     { $Defaults.Version }     else { '' }
    $defEA     = if ($Defaults.EarlyAccess) { $Defaults.EarlyAccess } else { 'n' }
    $defType   = if ($Defaults.GameType)    { $Defaults.GameType }    else { 'W' }
    $defNC     = if ($Defaults.NoCache)     { $Defaults.NoCache }     else { 'n' }
    $defYear   = if ($Defaults.ReleaseYear) { $Defaults.ReleaseYear } else { '' }

    Write-Host "`nPreparing game: $gameFolderName (Source: $gameSource)" -ForegroundColor Cyan

    $title = Read-Host "Enter game title (default: $defTitle)"
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $defTitle }
    $title = Format-SafeFileName -Name $title
    if ([string]::IsNullOrWhiteSpace($title))
    {
        throw "Title became empty after sanitization. Aborting."
    }

    $verPrompt = if ($defVer) { "(default: $defVer)" } else { "(optional)" }
    $version = Read-Host "Enter game version e.g. v1.2.3 $verPrompt"
    if ([string]::IsNullOrWhiteSpace($version)) { $version = $defVer }
    if ($version) { $version = Format-SafeFileName -Name $version }

    $earlyAccess = Read-Host "Is this an Early Access game? (y/n) (default: $defEA)"
    if ([string]::IsNullOrWhiteSpace($earlyAccess)) { $earlyAccess = $defEA }
    $earlyAccessTag = if ($earlyAccess -eq "y")
    { "EA"
    } else
    { ""
    }

    $allowedTypes = @('W_S','W','L','M','A')
    $gameType = Read-Host "Enter game type (W_S, W, L, M, A) (default: $defType)"
    if ([string]::IsNullOrWhiteSpace($gameType)) { $gameType = $defType }
    while ($gameType -notin $allowedTypes)
    {
        Write-Warning "Invalid game type. Must be one of: $($allowedTypes -join ', ')"
        $gameType = Read-Host "Enter game type (W_S, W, L, M, A)"
        if ([string]::IsNullOrWhiteSpace($gameType)) { $gameType = $defType }
    }

    $noCache = Read-Host "Disable caching for this game? (y/n) (default: $defNC)"
    if ([string]::IsNullOrWhiteSpace($noCache)) { $noCache = $defNC }
    $noCacheTag = if ($noCache -eq "y")
    { "NC"
    } else
    { ""
    }

    $minYear = 1970
    $maxYear = (Get-Date).Year + 1
    $yearPrompt = if ($defYear) { "required, $minYear-$maxYear, default: $defYear" } else { "required, $minYear-$maxYear" }
    $releaseYear = Read-Host "Enter release year ($yearPrompt)"
    if ([string]::IsNullOrWhiteSpace($releaseYear)) { $releaseYear = $defYear }
    while ($true)
    {
        if ($releaseYear -match '^\d{4}$' -and [int]$releaseYear -ge $minYear -and [int]$releaseYear -le $maxYear)
        {
            break
        }
        Write-Warning "Release year must be a 4-digit number between $minYear and $maxYear."
        $releaseYear = Read-Host "Enter release year (e.g., 2023)"
        if ([string]::IsNullOrWhiteSpace($releaseYear)) { $releaseYear = $defYear }
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

# Function to compress a game folder. Writes to <dest>.tmp first and only renames
# to the final path on success, so partial archives never end up in the output dir.
function Compress-Game
{
    param (
        [string]$sourcePath,
        [string]$destinationFile,
        [ValidateSet(1, 5, 9)]
        [int]$compressionLevel = 5
    )

    Write-Verbose "Compressing $sourcePath to $destinationFile..."

    $tempFile = "$destinationFile.tmp"
    if (Test-Path $tempFile) { Remove-Item -LiteralPath $tempFile -Force }

    try
    {
        switch ($compressionLevel)
        {
            1
            { # Fast (store only, no compression)
                & "$SevenZipPath" a -mx=0 -ms=off "$tempFile" "$sourcePath\*"
            }
            5
            { # Balanced
                & "$SevenZipPath" a -mx=5 -mmt=on "$tempFile" "$sourcePath\*"
            }
            9
            { # Maximum compression
                & "$SevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$tempFile" "$sourcePath\*"
            }
        }

        if ($LASTEXITCODE -ne 0)
        {
            throw "7-Zip exited $LASTEXITCODE"
        }
        Move-Item -LiteralPath $tempFile -Destination $destinationFile
        Write-Host "Compression completed successfully!" -ForegroundColor Green
        return $true
    } catch
    {
        if (Test-Path $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        Write-Error "Compression failed: $_" -ErrorAction Continue
        return $false
    }
}

# Main processing loop
# Collect games from both GOG and Steam sources
$allGames = @()

# Check GOG directory
if (Test-Path $GogSourceDir)
{
    $gogFolders = Get-ChildItem -Path $GogSourceDir -Directory
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
    Write-Warning "GOG source directory not found: $GogSourceDir"
}

# Check Steam directory
if (Test-Path $SteamSourceDir)
{
    $steamFolders = Get-ChildItem -Path $SteamSourceDir -Directory
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
    Write-Warning "Steam source directory not found: $SteamSourceDir"
}

if ($allGames.Count -eq 0)
{
    Write-Error "No game folders found in either GOG or Steam directories"
    exit 1
}

# Pre-flight: estimate source size and warn if destination is short on space.
Write-Verbose "Calculating source folder sizes for free-space check..."
$totalSourceBytes = 0
foreach ($g in $allGames) { $totalSourceBytes += Get-FolderSize -Path $g.Path }
$estArchiveBytes = [int64]($totalSourceBytes * 0.7)
$destDrive = (Get-Item $DestinationDir).PSDrive
$freeBytes = $destDrive.Free
if ($freeBytes -lt $estArchiveBytes)
{
    $needGB = [math]::Round($estArchiveBytes / 1GB, 2)
    $haveGB = [math]::Round($freeBytes / 1GB, 2)
    Write-Warning "Estimated archives will need ~${needGB} GB; only ${haveGB} GB free on $($destDrive.Name). You may run out partway through."
}

$manifestPath = Join-Path $DestinationDir "manifest.csv"

Write-Host "`nTotal: $($allGames.Count) game folders to process" -ForegroundColor Green
Write-Host "Manifest -> $manifestPath"
Write-Host ("Source: {0:N2} GB  |  Free on {1}: {2:N2} GB  |  Est. archives: {3:N2} GB" -f ($totalSourceBytes/1GB), $destDrive.Name, ($freeBytes/1GB), ($estArchiveBytes/1GB))
if ($EmitSha256) { Write-Host "SHA256 hashing: ON (slower)" -ForegroundColor DarkGray }
Write-Host "-----------------------------------------"

# P8: ask for session-wide default compression level once up front.
$sessionDefault = Read-Host "`nDefault compression level for all games: 1 (Fast), 5 (Balanced), 9 (Maximum) (default: 5)"
if ([string]::IsNullOrWhiteSpace($sessionDefault) -or !($sessionDefault -match '^[159]$'))
{
    $sessionDefault = '5'
}
Write-Host "Session default: level $sessionDefault (override per game)`n"
Write-Host "-----------------------------------------"

foreach ($game in $allGames)
{
    $gameName   = $game.Name
    $gamePath   = $game.Path
    $gameSource = $game.Source

    # P7: let user skip this game or quit the whole run before any prompts fire.
    Write-Host "`n[$gameSource] $gameName" -ForegroundColor Cyan
    $intent = Read-Host "  Enter=process  s=skip  q=quit"
    if ($intent -eq 'q')
    {
        Write-Host "Quitting. Games processed so far are in: $DestinationDir" -ForegroundColor Yellow
        break
    }
    if ($intent -eq 's')
    {
        Write-Host "  Skipped." -ForegroundColor DarkGray
        Write-Host "-----------------------------------------"
        continue
    }

    # P6: parse existing folder name to pre-fill prompts.
    $defaults = Get-FolderNameDefaults -FolderName $gameName
    $fileName = Build-GameVaultFileName -gameFolderName $gameName -gameSource $gameSource -Defaults $defaults
    $destinationFile = Join-Path -Path $DestinationDir -ChildPath $fileName

    Write-Host "Target file: $fileName" -ForegroundColor Cyan

    $compressionChoice = Read-Host "Select compression level: 1 (Fast), 5 (Balanced), 9 (Maximum) (default: $sessionDefault)"
    if ([string]::IsNullOrWhiteSpace($compressionChoice) -or !($compressionChoice -match '^[159]$'))
    {
        $compressionChoice = $sessionDefault
    }

    if (-not $PSCmdlet.ShouldProcess($destinationFile, "7-Zip compress from $gamePath"))
    {
        Write-Host "SKIPPED (WhatIf): would write $fileName" -ForegroundColor DarkGray
        Write-Host "-----------------------------------------"
        continue
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $success = Compress-Game -sourcePath $gamePath -destinationFile $destinationFile -compressionLevel ([int]$compressionChoice)
    $sw.Stop()

    if ($success)
    {
        Write-Host "Successfully prepared $gameName for GameVault" -ForegroundColor Green
        $sourceBytes = Get-FolderSize -Path $gamePath
        Add-ManifestEntry -ManifestPath $manifestPath -Name $fileName -Source $gameSource -ArchivePath $destinationFile -SourceBytes $sourceBytes -Duration $sw.Elapsed -IncludeHash:$EmitSha256
    } else
    {
        Write-Warning "Failed to prepare $gameName"
    }

    Write-Host "-----------------------------------------"
}

Write-Host "`nAll games have been processed. GameVault-ready games are in: $DestinationDir" -ForegroundColor Green
Write-Host "You can now copy these files to your GameVault server's /files directory." -ForegroundColor Green

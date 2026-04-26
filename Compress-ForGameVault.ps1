# GameVault Game Compression Script
# Compresses pre-sorted, already-named game folders into .7z archives using
# maximum compression for GameVault ingestion. Folders are expected to already
# be named per GameVault conventions.

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    # Map of source-label -> directory. Each top-level subfolder of every
    # directory is treated as a candidate game. Override to add Itch, Epic,
    # etc.: -Sources @{ GOG='D:\GOG'; Itch='E:\Itch' }
    [hashtable]$Sources = @{
        GOG   = (Join-Path $PSScriptRoot "GOG-Archive")
        Steam = (Join-Path $PSScriptRoot "Steam-Archive")
    },
    [string]$DestinationDir = (Join-Path $PSScriptRoot "GameVault-Ready"),
    [string]$SevenZipPath,
    [switch]$EmitSha256,
    # Re-archive folders whose .7z already exists in the destination.
    [switch]$Force,
    # Skip integrity verification (`7z t`) on existing archives before deciding
    # to skip them. By default existing archives that fail verification are
    # re-archived.
    [switch]$SkipIntegrityCheck
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

# Collect games from every configured source.
$allGames = @()

foreach ($entry in $Sources.GetEnumerator())
{
    $label = $entry.Key
    $path  = $entry.Value
    if (Test-Path $path)
    {
        $folders = Get-ChildItem -LiteralPath $path -Directory
        foreach ($folder in $folders)
        {
            $allGames += [PSCustomObject]@{ Name = $folder.Name; Path = $folder.FullName; Source = $label }
        }
        Write-Host "Found $($folders.Count) $label game folders" -ForegroundColor Green
    } else
    {
        Write-Warning "$label source directory not found: $path"
    }
}

if ($allGames.Count -eq 0)
{
    Write-Warning "No game folders found in any configured source directory."
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

$manifestPath = Join-Path $DestinationDir "manifest.csv"

Write-Host "`nFound $($valid.Count) folder(s) to compress." -ForegroundColor Cyan
Write-Host "Output -> $DestinationDir"
Write-Host "Manifest -> $manifestPath"
Write-Host ("Source: {0:N2} GB  |  Free on {1}: {2:N2} GB  |  Est. archive: {3:N2} GB" -f ($totalSourceBytes/1GB), $destDrive.Name, ($freeBytes/1GB), ($estArchiveBytes/1GB))
Write-Host "Compression: Maximum (-mx=9 -mfb=64 -md=32m -ms=on -mmt=on)"
if ($EmitSha256) { Write-Host "SHA256 hashing: ON (slower)" -ForegroundColor DarkGray }
Write-Host ""
Write-Host ("-" * 60)

$success = 0
$failed  = 0

foreach ($game in $valid)
{
    $archiveName = "$($game.Name).7z"
    $archivePath = Join-Path $DestinationDir $archiveName

    Write-Host "[$($game.Source)] $($game.Name)" -ForegroundColor Cyan

    if (Test-Path -LiteralPath $archivePath)
    {
        $skipExisting = $true
        if ($Force)
        {
            Write-Host "  -Force set: re-archiving existing $archiveName" -ForegroundColor DarkGray
            $skipExisting = $false
        } elseif (-not $SkipIntegrityCheck)
        {
            & "$SevenZipPath" t "$archivePath" | Out-Null
            if ($LASTEXITCODE -ne 0)
            {
                Write-Warning "  Existing archive failed integrity check; re-archiving: $archiveName"
                Remove-Item -LiteralPath $archivePath -Force
                $skipExisting = $false
            }
        }
        if ($skipExisting)
        {
            Write-Host "  SKIPPED (archive exists): $archiveName" -ForegroundColor Yellow
            continue
        }
    }

    if (-not $PSCmdlet.ShouldProcess($archivePath, "7-Zip compress from $($game.Path)"))
    {
        Write-Host "  SKIPPED (WhatIf): would compress to $archiveName" -ForegroundColor DarkGray
        continue
    }

    # Write to .tmp first; only rename to final name on success so partial
    # archives never end up in the GameVault-Ready directory.
    $tempArchive = "$archivePath.tmp"
    if (Test-Path -LiteralPath $tempArchive) { Remove-Item -LiteralPath $tempArchive -Force }

    # Push into the source folder so 7-Zip never sees special characters
    # ([, ], ?, etc.) in the source path that its wildcard parser would
    # otherwise interpret. Pop in finally so an error doesn't leave us in
    # the wrong working directory.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location -LiteralPath $game.Path
    try
    {
        & "$SevenZipPath" a -mx=9 -mfb=64 -md=32m -ms=on -mmt=on "$tempArchive" "*" | Out-Null
        if ($LASTEXITCODE -ne 0)
        {
            throw "7-Zip exited $LASTEXITCODE"
        }
        Move-Item -LiteralPath $tempArchive -Destination $archivePath
        $sw.Stop()
        Write-Host ("  OK -> $archiveName ({0:N1}s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
        $sourceBytes = Get-FolderSize -Path $game.Path
        Add-ManifestEntry -ManifestPath $manifestPath -Name $game.Name -Source $game.Source -ArchivePath $archivePath -SourceBytes $sourceBytes -Duration $sw.Elapsed -IncludeHash:$EmitSha256
        $success++
    } catch
    {
        $sw.Stop()
        if (Test-Path -LiteralPath $tempArchive) { Remove-Item -LiteralPath $tempArchive -Force -ErrorAction SilentlyContinue }
        Write-Host "  FAILED ($_)" -ForegroundColor Red
        Write-Error "7-Zip failed for '$($game.Name)': $_" -ErrorAction Continue
        $failed++
    } finally
    {
        Pop-Location
    }
}

Write-Host ("-" * 60)
Write-Host "`nDone: $success compressed, $failed failed, $($invalid.Count) skipped (invalid name)." -ForegroundColor Cyan
Write-Host "GameVault-ready archives are in: $DestinationDir" -ForegroundColor Green

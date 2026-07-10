# Steam Cleanup Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional Steam folder cleanup (remove redistributables, DRM DLLs, crash logs, etc.) to both scripts, plus default Steam game type to `W_P` in the interactive script.

**Architecture:** Three new functions shared between both scripts (`Get-SteamCleanupItems`, `Show-CleanupPreview`, `Invoke-SteamCleanup`) + one new param per script + integration into each script's main processing loop.

**Tech Stack:** PowerShell 5.1+, No dependencies beyond existing 7-Zip requirement.

---

### Task 1: Add Steam cleanup functions to Prepare-GamesForGameVault.ps1

**Files:**
- Modify: `Prepare-GamesForGameVault.ps1` (add functions after `Format-SafeFileName` and before the 7-Zip check)

- [ ] **Step 1: Add `Get-SteamCleanupItems` function**

Insert after line 124 (after `Format-SafeFileName` function closing brace).

```powershell
# Scans a folder for Steam-specific files that can be safely removed before
# repackaging as a portable game. Returns @{Items=@(); TotalBytes=[int64]}.
# Items is an array of PSCustomObjects with Name, Path, Type (File/Directory), Length.
function Get-SteamCleanupItems
{
    param([string]$Path)

    # Patterns always safe to remove.
    $filePatterns = @(
        'steam_api.dll', 'steam_api64.dll', 'steam_appid.txt',
        'UnityCrashHandler*.exe', 'CrashReporter*.exe', 'CrashSender*.exe',
        'CrashUploader*.exe', 'REDEngineErrorReporter.exe',
        'steam_monitor.exe', 'steamsysinfo.exe', 'steamerrorreporter*.exe',
        'WriteMiniDump.exe',
        '*.dmp', '*.mdmp', '*.crash',
        '*.log', 'output_log.txt', 'Player.log', 'Player-prev.log',
        'EULA.*', 'ThirdPartyLegalNotices.*',
        '*.pdb', '*.url', '*.nfo'
    )
    $dirPatterns = @(
        '_CommonRedist', '_CommonInstaller', '_Installer',
        'CrashReport*', 'Crashes', 'dumps', 'Logs', 'logs',
        'Recording', 'Screenshots',
        '_BackUpThisFolder_ButDontShipItWithYourGame',
        'BurstDebugInformation', 'Telemetry', 'diagnostics'
    )

    $items = @()

    foreach ($pat in $filePatterns)
    {
        Get-ChildItem -LiteralPath $Path -Filter $pat -File -ErrorAction SilentlyContinue |
            ForEach-Object { $items += $_ }
    }
    foreach ($pat in $dirPatterns)
    {
        Get-ChildItem -LiteralPath $Path -Filter $pat -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $items += $_ }
    }

    # Deduplicate and sort by length descending (show biggest first).
    $unique = $items | Sort-Object -Property FullName -Unique

    $totalBytes = ($unique | Where-Object { $_ -is [System.IO.FileInfo] } |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $totalBytes) { $totalBytes = 0L }

    $result = $unique | ForEach-Object {
        $isDir = $_ -is [System.IO.DirectoryInfo]
        [PSCustomObject]@{
            Name   = if ($isDir) { $_.Name + '/' } else { $_.Name }
            Path   = $_.FullName
            Type   = if ($isDir) { 'Directory' } else { 'File' }
            Length = if ($isDir) { 0 } else { $_.Length }
        }
    }

    return @{ Items = $result; TotalBytes = $totalBytes }
}
```

- [ ] **Step 2: Add `Show-CleanupPreview` function**

Insert after the new `Get-SteamCleanupItems` function.

```powershell
# Displays a preview table of removable Steam files and asks for confirmation.
# Returns $true if the user wants to proceed with cleanup.
function Show-CleanupPreview
{
    param(
        [array]$Items,
        [int64]$TotalBytes,
        [string]$GameName
    )

    if ($Items.Count -eq 0)
    {
        return $false
    }

    $sizeStr = if ($TotalBytes -gt 1GB) { '{0:N2} GB' -f ($TotalBytes / 1GB) }
               elseif ($TotalBytes -gt 1MB) { '{0:N2} MB' -f ($TotalBytes / 1MB) }
               else { '{0:N2} KB' -f ($TotalBytes / 1KB) }

    Write-Host "`n[Steam Cleanup] $GameName" -ForegroundColor Cyan
    Write-Host "Found $($Items.Count) item(s) totalling ~$sizeStr that can be safely removed:" -ForegroundColor DarkGray

    # Show top offenders (anything > 10MB) individually, then summary.
    $bigItems = $Items | Where-Object { $_.Length -gt 10MB } | Sort-Object Length -Descending
    if ($bigItems.Count -gt 0)
    {
        Write-Host "  Large items:" -ForegroundColor Yellow
        foreach ($item in $bigItems)
        {
            $sz = if ($item.Length -gt 1GB) { '{0:N2} GB' -f ($item.Length / 1GB) }
                  else { '{0:N2} MB' -f ($item.Length / 1MB) }
            Write-Host "    $sz  $($item.Name)"
        }
    }

    $smallCount = $Items.Count - $bigItems.Count
    if ($smallCount -gt 0)
    {
        Write-Host "  ...and $smallCount smaller file(s)" -ForegroundColor DarkGray
    }

    $response = Read-Host "Remove these files before compression? (y/n/detail) [y]"
    if ($response -eq 'd')
    {
        Write-Host "`nFull item list:" -ForegroundColor Cyan
        $Items | Sort-Object Name | ForEach-Object {
            Write-Host "  $($_.Type)  $($_.Name)"
        }
        $response = Read-Host "`nRemove these files? (y/n) [y]"
    }
    if ([string]::IsNullOrWhiteSpace($response)) { $response = 'y' }

    return $response -eq 'y'
}
```

- [ ] **Step 3: Add `Invoke-SteamCleanup` function**

Insert after `Show-CleanupPreview`.

```powershell
# Removes the items returned by Get-SteamCleanupItems.
function Invoke-SteamCleanup
{
    param(
        [array]$Items,
        [switch]$WhatIf
    )

    $count = 0
    foreach ($item in $Items)
    {
        if ($WhatIf)
        {
            Write-Host "  WhatIf: would remove $($item.Path)" -ForegroundColor DarkGray
            $count++
            continue
        }
        try
        {
            if ($item.Type -eq 'Directory')
            {
                Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction Stop
            } else
            {
                Remove-Item -LiteralPath $item.Path -Force -ErrorAction Stop
            }
            $count++
        } catch
        {
            Write-Warning "Could not remove $($item.Path): $_"
        }
    }
    Write-Host "  Cleanup: removed $count item(s)" -ForegroundColor Green
}
```

- [ ] **Step 4: Add `-SkipSteamCleanup` parameter**

In the `param()` block at line 8-14, add after `[switch]$EmitSha256`:

```powershell
    [switch]$SkipSteamCleanup
```

- [ ] **Step 5: Integrate Steam cleanup into the main processing loop**

In the main loop at line 373 (`foreach ($game in $allGames)`), after the skip/quit handling (after line 391) and before `$defaults = Get-FolderNameDefaults...` at line 395, add:

```powershell
    # Steam-specific: clean junk files before compression.
    if ($game.Source -eq 'Steam' -and -not $SkipSteamCleanup)
    {
        $cleanup = Get-SteamCleanupItems -Path $gamePath
        if (Show-CleanupPreview -Items $cleanup.Items -TotalBytes $cleanup.TotalBytes -GameName $gameName)
        {
            Invoke-SteamCleanup -Items $cleanup.Items
        }
    }
```

- [ ] **Step 6: Default GameType to W_P for Steam games**

In the main processing loop, change the variable initialization just before the game-type prompt. The relevant block is where `$defaults` is fetched and `Build-GameVaultFileName` is called.

Currently at line 395-396:
```powershell
    $defaults = Get-FolderNameDefaults -FolderName $gameName
    $fileName = Build-GameVaultFileName -gameFolderName $gameName -gameSource $gameSource -Defaults $defaults
```

There is no change needed in `Build-GameVaultFileName` because the defaults only inform the prompts. Instead, after `$defaults = Get-FolderNameDefaults -FolderName $gameName`, override the GameType default for Steam:

```powershell
    $defaults = Get-FolderNameDefaults -FolderName $gameName
    if ($gameSource -eq 'Steam' -and [string]::IsNullOrWhiteSpace($defaults.GameType))
    {
        $defaults.GameType = 'W_P'
    }
    $fileName = Build-GameVaultFileName -gameFolderName $gameName -gameSource $gameSource -Defaults $defaults
```

---

### Task 2: Add Steam cleanup to Compress-ForGameVault.ps1

**Files:**
- Modify: `Compress-ForGameVault.ps1`

- [ ] **Step 1: Add same three cleanup functions**

Copy the functions `Get-SteamCleanupItems`, `Show-CleanupPreview`, and `Invoke-SteamCleanup` (from Task 1 Steps 1-3) into `Compress-ForGameVault.ps1`.

Insert them after the `Add-ManifestEntry` function (after line 95) and before the 7-Zip existence check (line 97).

- [ ] **Step 2: Add `-Cleanup` parameter**

In the `param()` block (lines 8-31), add after `[switch]$EmitSha256` (line 19):

```powershell
    # Enable Steam folder cleanup (remove redist, DRM DLLs, logs, etc.)
    [switch]$Cleanup
```

- [ ] **Step 3: Integrate cleanup into the serial compression loop**

In the serial (`else`) branch, inside the `foreach ($game in $valid)` loop (line 312), at the top of the loop body, add after the `Write-Host "[$($game.Source)]..."` line (line 317):

```powershell
        # Steam-specific cleanup
        if ($Cleanup -and $game.Source -eq 'Steam')
        {
            $cleanupItems = Get-SteamCleanupItems -Path $game.Path
            if (Show-CleanupPreview -Items $cleanupItems.Items -TotalBytes $cleanupItems.TotalBytes -GameName $game.Name)
            {
                Invoke-SteamCleanup -Items $cleanupItems.Items
            }
        }
```

- [ ] **Step 4: Integrate cleanup into the parallel branch**

In the parallel branch (line 199), the cleanup must happen in the main thread before spawning runspaces (functions are not serializable). Add after the `$p_*` variable captures (after line 215) and before the `$results = ...` line (line 217):

```powershell
    # Steam cleanup happens on the main thread before parallel dispatch.
    if ($Cleanup)
    {
        $valid = $valid | ForEach-Object {
            $g = $_
            if ($g.Source -eq 'Steam')
            {
                $ci = Get-SteamCleanupItems -Path $g.Path
                if (Show-CleanupPreview -Items $ci.Items -TotalBytes $ci.TotalBytes -GameName $g.Name)
                {
                    Invoke-SteamCleanup -Items $ci.Items
                }
            }
            $g
        }
    }
```

---

### Task 3: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README.md**

a) In the Features section (line 21 area), add a bullet after the source support line:
```markdown
- Steam cleanup mode automatically removes DRM DLLs, redistributables, crash logs, and other junk from Steam game folders before compression, with a preview and confirmation prompt
```

b) In the `Prepare-GamesForGameVault.ps1` Usage section (line 72 area), add a bullet describing Steam behavior:
```markdown
- For Steam game sources, the script scans for and offers to remove Steam-specific files (DRM DLLs, redistributables, crash logs, etc.) before compressing. Steam games default to `W_P` (Windows Portable) game type. Pass `-SkipSteamCleanup` to disable this behavior.
```

c) In the `Compress-ForGameVault.ps1` Usage section (line 91 area), add:
```markdown
- Steam sources: pass `-Cleanup` to automatically scan and remove known junk files (DRM DLLs, redistributables, logs, crash dumps, engine build artifacts) before compression, with a preview and confirmation prompt. This is off by default to preserve backward compatibility.
```

d) Add a new parameter row to `Compress-ForGameVault.ps1` param table (after line 169), inserting `-Cleanup` and `-SkipSteamCleanup`:

In the Compress-ForGameVault parameters table, add after the `-ThrottleLimit` row:
```markdown
| `-Cleanup` | `switch` | off | For Steam sources: scan and remove junk (DRM DLLs, redist, logs) before compressing. Shows preview and asks for confirmation per game. |
```

In the Prepare-GamesForGameVault.ps1 parameters table, add after the `-EmitSha256` row:
```markdown
| `-SkipSteamCleanup` | `switch` | off | Skip the Steam folder cleanup step. Compress raw Steam folders as-is. |
```

e) Add a Steam cleanup notes section after the Compression Options section:

```markdown
## Steam Cleanup Notes

When enabled, the scripts scan Steam game folders for files that are safe to remove:

- **Steam DRM DLLs:** `steam_api.dll`, `steam_api64.dll`, `steam_appid.txt`
- **Redistributable installers:** `_CommonRedist/`, `_CommonInstaller/`, standalone `.exe` installers
- **Crash reports and logs:** `*.dmp`, `*.mdmp`, `*.crash`, `*.log`, `UnityCrashHandler*.exe`, `CrashReporter*.exe`
- **Build artifacts:** `_BackUpThisFolder_ButDontShipItWithYourGame/`, `BurstDebugInformation/`, `*.pdb`
- **Telemetry and recordings:** `Recording/`, `Screenshots/`, `Telemetry/`
- **Legal/license files:** `EULA.*`, `ThirdPartyLegalNotices.*`

**Note on steam_api.dll:** Removing these files means the game will run without the Steam client. Some games that hard-depend on Steamworks may crash without these DLLs. For those games, you may need a Steamworks stub/emulator (such as Goldberg Emulator). The cleanup preview shows these files so you can review before confirming.
```

- [ ] **Step 2: Update CLAUDE.md**

Update the Folder Naming Convention section to mention Steam cleanup. After the "Both scripts validate..." text (line 37-39 area), add:

```markdown
- Steam cleanup: `-SkipSteamCleanup` (Prepare) / `-Cleanup` (Compress) controls removal of junk files before archiving
```

---

### Task 4: Commit

- [ ] **Step 1: Stage and commit**

```bash
git add -A
git commit -m "feat: add Steam folder cleanup and portable game type support"
```
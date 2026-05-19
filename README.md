# GameVault Game Preparation Scripts

PowerShell scripts that automate preparing GOG and Steam games for [GameVault](https://gamevau.lt/) by compressing them into `.7z` archives that follow GameVault's required naming format.

## Scripts

### `Prepare-GamesForGameVault.ps1`
Interactive script that prompts you for game metadata (title, version, release year, game type, etc.) and compresses each game folder into a properly named `.7z` archive. Use this when your source folders are not yet named per GameVault conventions.

### `Compress-ForGameVault.ps1`
Batch compression script for game folders that are **already** named per GameVault conventions. Compresses every validly-named folder using maximum compression with no prompts. Runs an integrity check (`7z t`) on existing archives before skipping them; corrupt archives are automatically rebuilt. Supports parallel compression via `-Parallel` for multi-drive setups.

## Features

- Supports both GOG and Steam game sources
- Compresses game folders using 7-Zip
- Follows GameVault's naming convention requirements
- Supports all GameVault metadata tags (Early Access, Game Type, No Cache)
- Automatically creates destination directories if needed
- Resolves all paths relative to the script (`$PSScriptRoot`), so the repo can live anywhere
- Auto-detects 7-Zip in standard install locations and on `PATH`; supports a `SEVENZIP_PATH` env-var override
- Compresses with multithreading enabled (`-mmt=on`) for faster runs on multi-core CPUs
- `Compress-ForGameVault.ps1` pre-flights folder names against GameVault format; invalid names are reported and skipped before compression starts
- `Compress-ForGameVault.ps1` integrity-tests existing archives with `7z t` before skipping; corrupt archives are rebuilt automatically
- `Compress-ForGameVault.ps1` supports configurable source directories via `-Sources` hashtable (add Itch, Epic, etc. without forking)
- `Compress-ForGameVault.ps1` supports optional parallel compression (`-Parallel`, PS 7+ only)
- `Prepare-GamesForGameVault.ps1` sanitizes user-typed titles to strip characters Windows forbids in filenames
- `Prepare-GamesForGameVault.ps1` parses existing folder names to pre-fill all metadata prompts — just press Enter to accept
- Both scripts emit `GameVault-Ready\manifest.csv` (name, source, sizes, compression ratio, duration, optional SHA-256)
- Both scripts support `-WhatIf` for dry-run and accept `-SevenZipPath`, `-DestinationDir`, and other path overrides as parameters

## Requirements

- Windows with PowerShell 5.1+ (or PowerShell 7+)
- [7-Zip](https://www.7-zip.org/) — keep on the latest stable release for security fixes
- GOG and/or Steam games in source directories
- For GOG offline installers: ensure all installer files for a given game live inside a folder named after the game (e.g. `Fallout 2`, **not** `FALLOUT_2-1998`)

## Installation

1. Clone this repository or download the scripts
2. Install 7-Zip. The scripts auto-discover it in this order:
   1. `$env:SEVENZIP_PATH` if set
   2. `C:\Program Files\7-Zip\7z.exe`
   3. `C:\Program Files (x86)\7-Zip\7z.exe`
   4. `7z.exe` on `PATH`

   If 7-Zip lives somewhere non-standard, set the override before running:
   ```powershell
   $env:SEVENZIP_PATH = "D:\Tools\7-Zip\7z.exe"
   ```
3. Place your game folders in the appropriate source directories alongside the scripts:
   - `GOG-Archive\` — GOG game folders
   - `Steam-Archive\` — Steam game folders

### Expected layout

```
GameVault-GamePrep\
├── Prepare-GamesForGameVault.ps1
├── Compress-ForGameVault.ps1
├── GOG-Archive\
│   └── Fallout 2\
│       └── ...installer files...
├── Steam-Archive\
│   └── Half-Life 2\
│       └── ...game files...
└── GameVault-Ready\           # created automatically
    └── Fallout 2 (W) (1998).7z
```

## Usage

### Interactive preparation (`Prepare-GamesForGameVault.ps1`)

Use this when your folders are not yet named per GameVault conventions.

1. Open PowerShell
2. Navigate to the script directory
3. Run the script:

```powershell
.\Prepare-GamesForGameVault.ps1
```

4. Choose a session-wide default compression level (can override per game)
5. For each game: press **Enter** to process, **s** to skip, or **q** to quit. If the folder name already follows GameVault conventions, all metadata prompts are pre-filled — just press Enter to accept
6. Title input is sanitized automatically. Game-type is validated; invalid values reprompt. Year is validated against the range 1970–(current year + 1)
7. Compressed archives are saved to `GameVault-Ready\`; a row is appended to `GameVault-Ready\manifest.csv` after each success

### Batch compression (`Compress-ForGameVault.ps1`)

Use this when your folders are already named per GameVault conventions. Each archive is named `<FolderName>.7z` verbatim, so the source folder name **must** end with a 4-digit year in parentheses (e.g. `Fallout 2 (W) (1998)`). Folders that don't match this format are reported and skipped before any compression begins.

1. Open PowerShell
2. Navigate to the script directory
3. Run the script:

```powershell
.\Compress-ForGameVault.ps1
```

4. All validly-named folders in the source directories are compressed to `GameVault-Ready\` using maximum compression; a row is appended to `GameVault-Ready\manifest.csv` after each success
5. Folders whose archive already exists are integrity-tested with `7z t` before being skipped. Corrupt archives are deleted and rebuilt. Pass `-SkipIntegrityCheck` to skip the test, or `-Force` to always re-archive
6. Folders missing the required `(YYYY)` suffix are reported and skipped — rename them or run `Prepare-GamesForGameVault.ps1` to handle them interactively

## GameVault Naming Convention

`Prepare-GamesForGameVault.ps1` builds filenames following GameVault's required format:

```
Title (Version) (EarlyAccess) (GameType) (NoCache) (ReleaseYear).7z
```

Where:
- **Title** — name of the game
- **Version** — optional version number (e.g. `v1.2.3`)
- **EarlyAccess** — `EA` tag for early access games
- **GameType** — game platform type:
  - `W_S` — Windows Store
  - `W` — Windows
  - `L` — Linux
  - `M` — Mac
  - `A` — Android
- **NoCache** — `NC` tag to disable caching
- **ReleaseYear** — required 4-digit year of release

Example: `Hades (v1.38209) (W) (2020).7z`

For full details, see the [GameVault file naming docs](https://gamevau.lt/docs/server-docs/game-files-and-metadata).

## Compression Options

`Prepare-GamesForGameVault.ps1` offers three compression levels:

| Choice | 7-Zip flags | Notes |
|--------|-------------|-------|
| `1` Fast | `-mx=0 -ms=off` | Store only (no compression). Fastest, largest output. |
| `5` Balanced | `-mx=5 -mmt=on` | Default. Good balance of size vs. speed. |
| `9` Maximum | `-mx=9 -mfb=64 -md=32m -ms=on -mmt=on` | Smallest output, slowest. |

`Compress-ForGameVault.ps1` always uses maximum compression (`-mx=9 -mfb=64 -md=32m -ms=on -mmt=on`).

## Output

Final archives land in `GameVault-Ready\`. Copy them to your GameVault server's `/files` directory (or your configured ingest path) for import.

Each successful compression appends a row to `GameVault-Ready\manifest.csv`:

| Column | Description |
|--------|-------------|
| `CompletedAt` | ISO-8601 timestamp |
| `Name` | Archive filename (without `.7z`) |
| `Source` | Source label (e.g. `GOG`, `Steam`) |
| `SourceBytes` | Uncompressed folder size |
| `ArchiveBytes` | Final archive size |
| `CompressionRatio` | `ArchiveBytes / SourceBytes` |
| `DurationSeconds` | Elapsed compression time |
| `SHA256` | SHA-256 of archive, or empty if `-EmitSha256` not passed |

## Parameters

Both scripts accept these parameters (all have sensible defaults):

### `Compress-ForGameVault.ps1`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Sources` | `hashtable` | `@{ GOG=…; Steam=… }` | Map of `Label → SourceDir`. Add any number of sources without forking. |
| `-DestinationDir` | `string` | `.\GameVault-Ready` | Output directory for archives and manifest. |
| `-SevenZipPath` | `string` | auto-detected | Path to `7z.exe`. Overrides `$env:SEVENZIP_PATH`. |
| `-Force` | `switch` | off | Re-archive even when a `.7z` already exists. |
| `-SkipIntegrityCheck` | `switch` | off | Skip `7z t` test on existing archives before deciding to skip. |
| `-Parallel` | `switch` | off | Fan out compressions across runspaces (PS 7+ only). |
| `-ThrottleLimit` | `int` | `2` | Max concurrent jobs when `-Parallel` is set. |
| `-EmitSha256` | `switch` | off | Compute and record SHA-256 of each archive in the manifest. |
| `-WhatIf` | `switch` | off | Dry-run: report what would be compressed without writing. |

```powershell
# Example: custom sources, parallel, 3 threads
.\Compress-ForGameVault.ps1 -Sources @{ GOG='D:\GOG'; Itch='E:\Itch' } -Parallel -ThrottleLimit 3
```

### `Prepare-GamesForGameVault.ps1`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-GogSourceDir` | `string` | `.\GOG-Archive` | Path to GOG game folders. |
| `-SteamSourceDir` | `string` | `.\Steam-Archive` | Path to Steam game folders. |
| `-DestinationDir` | `string` | `.\GameVault-Ready` | Output directory for archives and manifest. |
| `-SevenZipPath` | `string` | auto-detected | Path to `7z.exe`. Overrides `$env:SEVENZIP_PATH`. |
| `-EmitSha256` | `switch` | off | Compute and record SHA-256 of each archive in the manifest. |
| `-WhatIf` | `switch` | off | Dry-run: report what would be compressed without writing. |

## Security Note

Keep 7-Zip on the latest stable release. Older builds have known CVEs; check [7-zip.org](https://www.7-zip.org/) for the current version.

### Secret scanning (gitleaks)

This repo ships a [gitleaks](https://github.com/gitleaks/gitleaks) pre-commit hook that blocks commits containing leaked credentials.

**One-time setup after cloning:**

1. Install gitleaks:
   ```bash
   # macOS
   brew install gitleaks

   # Linux / Windows — see https://github.com/gitleaks/gitleaks#installing
   ```
2. Wire up the tracked hooks:
   ```bash
   bash scripts/install-hooks.sh
   ```

The hook runs `gitleaks protect --staged` on every commit. Configuration lives in `.gitleaks.toml`. To bypass for a known false positive: `git commit --no-verify`.

To scan the full history manually:

```bash
gitleaks detect --source . --verbose --redact
```

## License

Released under the [MIT License](LICENSE).

## Contributing

Issues and pull requests welcome. For larger changes, open an issue first to discuss the approach.

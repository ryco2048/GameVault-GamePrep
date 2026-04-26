# GameVault Game Preparation Scripts

PowerShell scripts that automate preparing GOG and Steam games for [GameVault](https://gamevau.lt/) by compressing them into `.7z` archives that follow GameVault's required naming format.

## Scripts

### `Prepare-GamesForGameVault.ps1`
Interactive script that prompts you for game metadata (title, version, release year, game type, etc.) and compresses each game folder into a properly named `.7z` archive. Use this when your source folders are not yet named per GameVault conventions.

### `Compress-ForGameVault.ps1`
Batch compression script for game folders that are **already** named per GameVault conventions. Compresses every folder in the source directories using maximum compression with no prompts. Skips any game that already has an archive in the destination.

## Features

- Supports both GOG and Steam game sources
- Compresses game folders using 7-Zip
- Follows GameVault's naming convention requirements
- Supports all GameVault metadata tags (Early Access, Game Type, No Cache)
- Automatically creates destination directories if needed
- Resolves all paths relative to the script (`$PSScriptRoot`), so the repo can live anywhere
- Auto-detects 7-Zip in standard install locations and on `PATH`; supports a `SEVENZIP_PATH` env-var override
- Compresses with multithreading enabled (`-mmt=on`) for faster runs on multi-core CPUs
- `Compress-ForGameVault.ps1` pre-flights folder names against the GameVault format and skips invalid ones before any compression starts
- `Prepare-GamesForGameVault.ps1` sanitizes user-typed titles to remove characters Windows forbids in filenames

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

4. Follow the prompts for each game found. Title input is sanitized — characters Windows forbids in filenames (`<>:"/\|?*` plus controls) are stripped automatically. Game-type input is validated against the allowed set; invalid values reprompt
5. Compressed archives are saved to `GameVault-Ready\`

### Batch compression (`Compress-ForGameVault.ps1`)

Use this when your folders are already named per GameVault conventions. Each archive is named `<FolderName>.7z` verbatim, so the source folder name **must** end with a 4-digit year in parentheses (e.g. `Fallout 2 (W) (1998)`). Folders that don't match this format are reported and skipped before any compression begins.

1. Open PowerShell
2. Navigate to the script directory
3. Run the script:

```powershell
.\Compress-ForGameVault.ps1
```

4. All validly-named folders in `GOG-Archive\` and `Steam-Archive\` are compressed to `GameVault-Ready\` using maximum compression
5. Folders whose archive already exists in the destination are skipped automatically
6. Folders missing the required `(YYYY)` suffix are listed in the warning summary and skipped — rename them or run `Prepare-GamesForGameVault.ps1` to handle them interactively

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

## Security Note

Keep 7-Zip on the latest stable release. Older builds have known CVEs; check [7-zip.org](https://www.7-zip.org/) for the current version.

## License

Released under the [MIT License](LICENSE).

## Contributing

Issues and pull requests welcome. For larger changes, open an issue first to discuss the approach.

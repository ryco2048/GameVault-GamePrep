# GameVault Game Preparation Scripts

These PowerShell scripts automate the process of preparing your GOG and Steam games for use with GameVault by compressing them according to GameVault's required format and naming conventions.

## Scripts

### `Prepare-GamesForGameVault.ps1`
Interactive script that prompts you for game metadata (title, version, release year, game type, etc.) and compresses each game folder into a properly named `.7z` archive. Use this when your source folders are not yet named per GameVault conventions.

### `Compress-ForGameVault.ps1`
Batch compression script for game folders that are already named per GameVault conventions. Compresses all folders in the source directories using maximum compression settings with no prompts. Skips any game that already has an archive in the destination.

## Features

- Supports both GOG and Steam game sources
- Compresses game folders using 7-Zip
- Follows GameVault's naming convention requirements
- Supports all GameVault metadata tags (Early Access, Game Type, No Cache)
- Automatically creates destination directories if needed

## Requirements

- Windows with PowerShell
- 7-Zip (latest version 24.09 recommended for security)
- GOG and/or Steam games in source directories
- If games are GOG offline installers, make sure all install files are included in a folder of the game's proper name (e.g., "Fallout 2" and NOT "FALLOUT_2-1998")

## Installation

1. Clone this repository or download the scripts
2. Ensure 7-Zip is installed (the scripts assume it's at `C:\Program Files\7-Zip\7z.exe`)
3. Place your game folders in the appropriate source directories:
   - `GOG-Archive\`: GOG game folders
   - `Steam-Archive\`: Steam game folders
4. If 7-Zip is installed to a different path, update `$sevenZipPath` in whichever script you are using

## Usage

### Interactive preparation (`Prepare-GamesForGameVault.ps1`)

Use this when your folders are not yet named per GameVault conventions.

1. Open PowerShell as Admin
2. Navigate to the script directory
3. Run the script:

```powershell
.\Prepare-GamesForGameVault.ps1
```

4. Follow the interactive prompts for each game found
5. Compressed games will be saved to `GameVault-Ready\`

### Batch compression (`Compress-ForGameVault.ps1`)

Use this when your folders are already named per GameVault conventions.

1. Open PowerShell as Admin
2. Navigate to the script directory
3. Run the script:

```powershell
.\Compress-ForGameVault.ps1
```

4. All game folders in `GOG-Archive\` and `Steam-Archive\` will be compressed to `GameVault-Ready\` using maximum compression
5. Folders with an existing archive in the destination are skipped automatically

## GameVault Naming Convention

`Prepare-GamesForGameVault.ps1` builds filenames following GameVault's required naming format:
```
Title (Version) (EarlyAccess) (GameType) (NoCache) (ReleaseYear).7z
```

Where:
- **Title**: The name of the game
- **Version**: Optional version number (e.g., v1.2.3)
- **EarlyAccess**: "EA" tag for early access games
- **GameType**: Game platform type:
  - W_S: Windows Store
  - W: Windows
  - L: Linux
  - M: Mac
  - A: Android
- **NoCache**: "NC" tag to disable caching
- **ReleaseYear**: Required 4-digit year of release

## Compression Options

`Prepare-GamesForGameVault.ps1` offers three compression levels:
1. **Fast** (Level 1): Minimal compression, fastest processing
2. **Balanced** (Level 5): Default, good balance of size and speed
3. **Maximum** (Level 9): Highest compression, slowest processing

`Compress-ForGameVault.ps1` always uses maximum compression (`-mx=9 -mfb=64 -md=32m -ms=on`).

## Security Note

Always keep 7-Zip updated to the latest version (currently 24.09) to avoid security vulnerabilities in older versions.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.


# GameVault Game Preparation Script

This PowerShell script automates the process of preparing your GOG and Steam games for use with GameVault by compressing them according to GameVault's required format and naming conventions.

## Features

- Supports both GOG and Steam game sources
- Compresses game folders using 7-Zip with customizable compression levels
- Follows GameVault's naming convention requirements
- Supports all GameVault metadata tags (Early Access, Game Type, No Cache)
- Interactive prompts for game information
- Creates properly formatted 7z archives ready for GameVault
- Automatically creates destination and temporary directories if needed

## Requirements

- Windows with PowerShell
- 7-Zip (latest version 24.09 recommended for security)
- GOG and/or Steam games in source directories
- If games are GOG offline installers, make sure all install files are included in a folder of the game's proper name (e.g., "Fallout 2" and NOT "FALLOUT_2-1998")

## Installation

1. Clone this repository or download the script
2. Ensure 7-Zip is installed (the script assumes it's at `C:\Program Files\7-Zip\7z.exe`)
3. Edit the script to configure your directory paths:
   - `$gogSourceDir`: Path to your GOG games folder
   - `$steamSourceDir`: Path to your Steam games folder
   - `$destinationDir`: Path where GameVault-ready files will be saved
   - `$tempDir`: Path for temporary processing files
   - `$sevenZipPath`: Path to 7-Zip executable (if different from default)

## Usage

1. Open PowerShell as Admin
2. Navigate to the script directory
3. Run the script:

```powershell
.\Prepare-GamesForGameVault.ps1
```

4. The script will scan both GOG and Steam source directories
5. Follow the interactive prompts for each game found
6. Compressed games will be saved to the destination directory

## GameVault Naming Convention

The script follows GameVault's required naming format:
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

The script offers three compression levels:
1. **Fast** (Level 1): Minimal compression, fastest processing
2. **Balanced** (Level 5): Default, good balance of size and speed
3. **Maximum** (Level 9): Highest compression, slowest processing

## Security Note

Always keep 7-Zip updated to the latest version (currently 24.09) to avoid security vulnerabilities in older versions. 

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.


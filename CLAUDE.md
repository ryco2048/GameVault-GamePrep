# GameVault-GamePrep

PowerShell scripts that compress GOG/Steam game folders into `.7z` archives for [GameVault](https://gamevau.lt/).

## Project Context

- **Target platform:** Windows (PS 5.1+ or 7+); repo is edited on macOS
- **Two scripts:** `Prepare-GamesForGameVault.ps1` (interactive, prompts for metadata) · `Compress-ForGameVault.ps1` (batch, folders pre-named)
- **No automated tests** — scripts are validated manually on Windows
- **Large game directories are gitignored:** `GOG-Archive/`, `Steam-Archive/`, `GameVault-Ready/`

## Prerequisites

- Windows: 7-Zip installed (`C:\Program Files\7-Zip\7z.exe`) or set `$env:SEVENZIP_PATH`
- macOS (dev): `brew install gitleaks`

## Setup (after clone)

```bash
bash scripts/install-hooks.sh   # sets core.hooksPath → scripts/hooks
```

## Script Usage

```powershell
# Prepare-GamesForGameVault.ps1 — interactive; prompts for title, year, source
.\Prepare-GamesForGameVault.ps1 [-SkipSteamCleanup] [-EmitSha256]

# Compress-ForGameVault.ps1 — batch; folders must already be named correctly
.\Compress-ForGameVault.ps1 [-Force] [-SkipIntegrityCheck] [-Parallel] [-Cleanup] [-EmitSha256]
# -Parallel only helps when source and dest are on different physical drives
# Custom sources: -Sources @{ GOG='D:\GOG'; Itch='E:\Itch' }
# Steam cleanup: -Cleanup removes DRM DLLs, redist, logs, crash dumps
```

## Folder Naming Convention

GameVault requires: `Game Title (YYYY)` — must end with `(4-digit year)`.
`Prepare-GamesForGameVault.ps1` enforces this interactively.
`Compress-ForGameVault.ps1` validates and skips non-conforming folders.
- Steam cleanup: `-SkipSteamCleanup` (Prepare) / `-Cleanup` (Compress) controls removal of junk files before archiving

**Game-type tags:** `W_S` (Win Store), `W_P` (Win Portable, Steam default), `W` (Windows), `L`, `M`, `A`.
Gotcha: in game-type alternation regexes, order longer prefixes first (`W_S|W_P|W|…`) — bare `W` otherwise steals `W_P`/`W_S` matches.

## Outputs

- `.7z` archives → `GameVault-Ready/` (gitignored)
- `manifest.csv` in destination — one row per successful compression
- Existing archives are integrity-checked (`7z t`) before skipping; use `-SkipIntegrityCheck` to bypass

## Security

- Pre-commit hook: `gitleaks protect --staged` — runs on every commit
- CI: `gitleaks` GitHub Action on every push/PR
- GitHub Actions are pinned to commit SHAs (not tags) — keep this when adding/updating actions
- `GITHUB_TOKEN` permissions are scoped per-job — don't widen without reason

## Code Review

CodeRabbit is configured (`.coderabbit.yaml`) — auto-reviews PRs, chill profile.

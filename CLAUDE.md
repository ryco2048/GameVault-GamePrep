# GameVault-GamePrep

PowerShell scripts that compress GOG/Steam game folders into `.7z` archives for [GameVault](https://gamevau.lt/).

## Project Context

- **Target platform:** Windows (PS 5.1+ or 7+); repo is edited on macOS
- **Two scripts:** `Prepare-GamesForGameVault.ps1` (interactive, prompts for metadata) · `Compress-ForGameVault.ps1` (batch, folders pre-named)
- **No automated tests** — scripts are validated manually on Windows
- **Large game directories are gitignored:** `GOG-Archive/`, `Steam-Archive/`, `GameVault-Ready/`

## Setup (after clone)

```bash
bash scripts/install-hooks.sh   # sets core.hooksPath → scripts/hooks
```

Requires `gitleaks` installed (`brew install gitleaks`) for pre-commit secret scanning.

## Security

- Pre-commit hook: `gitleaks protect --staged` — runs on every commit
- CI: `gitleaks` GitHub Action on every push/PR
- GitHub Actions are pinned to commit SHAs (not tags) — keep this when adding/updating actions
- `GITHUB_TOKEN` permissions are scoped per-job — don't widen without reason

## Code Review

CodeRabbit is configured (`.coderabbit.yaml`) — auto-reviews PRs, chill profile.

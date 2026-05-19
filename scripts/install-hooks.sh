#!/usr/bin/env bash
#
# Wire up tracked git hooks for this repo. Run once after cloning.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git config core.hooksPath scripts/hooks
chmod +x scripts/hooks/*

echo "Git hooks installed: core.hooksPath -> scripts/hooks"
echo "Hooks active:"
ls -1 scripts/hooks

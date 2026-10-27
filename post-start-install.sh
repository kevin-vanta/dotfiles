#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /workspaces/obsidian/git-hooks/local-hooks/check-maintainers ]]; then
    python3 "$script_dir/obsidian-hooks/hooks.py" install /workspaces/obsidian
fi

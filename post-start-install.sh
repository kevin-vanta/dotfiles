#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install -d "$HOME/bin"
install -m 755 "$script_dir/bin/codex" "$HOME/bin/codex"
if [[ -f /workspaces/obsidian/git-hooks/local-hooks/check-maintainers ]]; then
    python3 "$script_dir/obsidian-hooks/hooks.py" install /workspaces/obsidian
fi

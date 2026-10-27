# Personal ownership hook adapter

This adapter keeps the maintainer check enabled when libgit2 repository discovery
fails on a nested `.git` directory on another filesystem, as seen in Codex
worktrees. It does not remove or modify that directory.

## Install

Keep this dotfiles checkout on the persistent home volume, then run:

```sh
python3 ~/dotfiles/obsidian-hooks/hooks.py install /workspaces/obsidian
```

`post-start-install.sh` repeats installation after the development environment's
standard setup resets its hooks. Installation changes only the repository's local
`core.hooksPath`. Linked worktrees share this configuration unless they have their
own override. Other clones need their own install command.

The adapter delegates every Git hook to the active checkout's `git-hooks` script.
During `pre-push`, a temporary prek configuration substitutes the maintainer entry
with the personal runner. All other hook configuration, arguments, push refs,
input, and failures pass through. No hook is automatically skipped. Direct
`prek run` invocations outside the push hook still use the original configuration;
to run the repaired maintainer check directly:

```sh
python3 ~/dotfiles/obsidian-hooks/hooks.py maintainers
```

The runner snapshots the active checkout's Rust workspace into
`~/.local/share/obsidian-hooks`, replaces the two `Repository::discover` calls with
`Repository::open_ext` using `CROSS_FS`, and builds with the checkout's lockfile
and pinned toolchain. It uses offline Cargo dependencies. Standard development
setup must already have populated the Rust dependency cache and toolchain.

The binary cache is keyed by the Rust sources, manifests, lockfile, toolchain
file, adapter implementation, OS, and CPU architecture. Concurrent builds share
a file lock. Each cached binary belongs to that exact source snapshot. Branch
changes and source edits rebuild as needed. No source patch or binary is written
into the product checkout. Generated maintainer artifacts are refreshed before
running the same `check` command used by the repository hook.

The runner checks hashes of the three original ownership shell scripts before
substituting their commands, so upstream additions to validation cannot silently
be omitted. Changes to those scripts, discovery syntax, workspace membership,
hook configuration, or build failures stop the push with an error. Update the adapter when these interfaces
change. Genuine ownership failures still block pushing. Semgrep findings are
unaffected; this adapter does not suppress or change their scope.

## Verify

From an Obsidian checkout:

```sh
OWNERSHIP_TEST_BINARY="$(python3 ~/dotfiles/obsidian-hooks/hooks.py build)" \
  OWNERSHIP_TEST_REPO="$PWD" python3 ~/dotfiles/obsidian-hooks/test_hooks.py -v
```

The tests cover filesystem-boundary discovery in ordinary and linked worktrees,
worktree-specific indexes, real ownership failures, configuration preservation,
and an actual push to a temporary local remote. The push test also verifies that
a failing unrelated hook blocks the remote update and that commit hooks delegate.
Only the adapter and tests are committed to dotfiles. Product sources, cached
binaries, and validation output remain local.

## Disable

```sh
git -C /workspaces/obsidian config --local core.hooksPath git-hooks
```

This restores the tracked hooks immediately. Also remove the adapter invocation
from `post-start-install.sh` if it should remain disabled after restart.

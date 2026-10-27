"""Run with OWNERSHIP_TEST_BINARY set to the result of hooks.py build."""

import importlib.util
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("hooks", HERE / "hooks.py")
hooks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hooks)


class AdapterTests(unittest.TestCase):
    def test_config_preserves_other_hooks_and_attributes(self):
        original = (
            "repos:\n- repo: local\n  hooks:\n"
            "  - id: check-maintainers\n    language: script\n"
            "    entry: git-hooks/local-hooks/check-maintainers\n"
            "    always_run: true\n  - id: semgrep\n    entry: semgrep --error\n"
        )
        result = hooks.adapt_config(original)
        self.assertEqual(result.splitlines()[:5], original.splitlines()[:5])
        self.assertEqual(result.splitlines()[6:], original.splitlines()[6:])
        self.assertIn("maintainers", result.splitlines()[5])
        for text in (
            original.replace(hooks.ENTRY, "different-command"),
            original + original,
        ):
            with self.assertRaises(RuntimeError):
                hooks.adapt_config(text)

    def test_changed_hook_script_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "git-hooks/local-hooks").mkdir(parents=True)
            (root / hooks.ENTRY).write_text("new validation step")
            with self.assertRaisesRegex(RuntimeError, "new checks are preserved"):
                hooks.validate_scripts(root)

    def test_unknown_discovery_source_fails_closed(self):
        for source in (
            "",
            "Repository::discover(path)",
            "Repository::discover(f())" * 2,
        ):
            with self.assertRaises(RuntimeError):
                hooks.patched_source(source)


@unittest.skipUnless(os.environ.get("OWNERSHIP_TEST_BINARY"), "build the binary first")
class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ownership-regression-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.binary = os.environ["OWNERSHIP_TEST_BINARY"]
        self.run_git("init", "-q")
        (self.repo / "CODEOWNERS").write_text("* @VantaInc/test\n")
        (self.repo / "MAINTAINERS").write_text("* @VantaInc/test\n")
        self.run_git("add", "CODEOWNERS", "MAINTAINERS")
        self.run_git(
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "-qm",
            "fixture",
        )

    def run_git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.repo), *args], text=True
        ).strip()

    def audit(self, root):
        result = subprocess.run(
            [self.binary, "audit", "-c", str(root / "CODEOWNERS")],
            cwd=root,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return {line.split()[0] for line in result.stdout.splitlines()}

    def test_nested_mount_boundary_and_worktree_index(self):
        expected = {"CODEOWNERS", "MAINTAINERS"}
        self.assertEqual(self.audit(self.repo), expected)
        if os.stat("/proc").st_dev == self.repo.stat().st_dev:
            self.skipTest("requires /proc on another filesystem")
        (self.repo / ".git/.git").symlink_to("/proc", target_is_directory=True)
        self.assertEqual(self.audit(self.repo), expected)
        worktree = Path(self.temp.name) / "worktree"
        self.run_git("worktree", "add", "--detach", "-q", str(worktree))
        private = Path(
            subprocess.check_output(
                ["git", "-C", str(worktree), "rev-parse", "--absolute-git-dir"],
                text=True,
            ).strip()
        )
        (private / ".git").symlink_to("/proc", target_is_directory=True)
        (worktree / "worktree-only.txt").write_text("tracked only in this index\n")
        subprocess.run(
            ["git", "-C", str(worktree), "add", "worktree-only.txt"], check=True
        )
        self.assertEqual(self.audit(worktree), expected | {"worktree-only.txt"})
        self.assertEqual(self.audit(self.repo), expected)

    def test_real_ownership_failure_still_fails(self):
        (self.repo / "MAINTAINERS").write_text("* @VantaInc/different-team\n")
        (self.repo / ".git/.git").symlink_to("/proc", target_is_directory=True)
        result = subprocess.run(
            [
                self.binary,
                "check",
                "--codeowners",
                "CODEOWNERS",
                "--maintainers",
                "MAINTAINERS",
            ],
            cwd=self.repo,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Team Mismatch", result.stdout + result.stderr)


@unittest.skipUnless(
    os.environ.get("OWNERSHIP_TEST_REPO"), "set the source checkout for push tests"
)
class PushTests(unittest.TestCase):
    setUp = DiscoveryTests.setUp
    run_git = DiscoveryTests.run_git

    def test_git_push_and_other_hooks(self):
        source = Path(os.environ["OWNERSHIP_TEST_REPO"])
        for name in ("Cargo.toml", "Cargo.lock", "rust-toolchain.toml"):
            shutil.copy2(source / name, self.repo / name)
        for crate in hooks.CRATES:
            dest = self.repo / "packages" / crate
            dest.mkdir(parents=True)
            shutil.copy2(
                source / "packages" / crate / "Cargo.toml", dest / "Cargo.toml"
            )
            shutil.copytree(source / "packages" / crate / "src", dest / "src")
        tracked_hooks = self.repo / "git-hooks"
        (tracked_hooks / "local-hooks").mkdir(parents=True)
        for name in hooks.SCRIPT_DIGESTS:
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / name, target)
        prepush = tracked_hooks / "pre-push"
        prepush.write_text(
            "#!/bin/sh\nexec prek hook-impl --hook-type=pre-push --script-version=4 "
            '--config=.pre-commit-config.yaml --hook-dir git-hooks -- "$@"\n'
        )
        prepush.chmod(0o755)
        precommit = tracked_hooks / "pre-commit"
        precommit.write_text("#!/bin/sh\nprintf delegated > hook-was-called\n")
        precommit.chmod(0o755)
        config = self.repo / ".pre-commit-config.yaml"
        config.write_text(
            "repos:\n- repo: local\n  hooks:\n"
            "  - id: check-maintainers\n    name: Check MAINTAINERS coverage\n"
            "    language: script\n    entry: git-hooks/local-hooks/check-maintainers\n"
            "    always_run: true\n    pass_filenames: false\n    stages: [pre-push]\n"
            "  - id: other-hook\n    name: Other validation\n    language: system\n"
            "    entry: /bin/true\n    always_run: true\n"
            "    pass_filenames: false\n    stages: [pre-push]\n"
        )
        remote = Path(self.temp.name) / "remote.git"
        subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
        self.run_git("config", "core.hooksPath", "git-hooks")
        # Isolate installation state while reusing the previously built binary cache.
        hooks.STATE = Path(self.temp.name) / "adapter"
        hooks.install(self.repo)
        self.run_git("add", ".pre-commit-config.yaml")
        self.run_git(
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "-qm",
            "hook config",
        )
        self.assertEqual((self.repo / "hook-was-called").read_text(), "delegated")
        (self.repo / ".git/.git").symlink_to("/proc", target_is_directory=True)
        result = subprocess.run(
            ["git", "-C", str(self.repo), "push", str(remote), "HEAD:smoke"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Passed", result.stdout + result.stderr)
        original_head = subprocess.check_output(
            ["git", "--git-dir", str(remote), "rev-parse", "refs/heads/smoke"],
            text=True,
        ).strip()
        config.write_text(
            config.read_text().replace("entry: /bin/true", "entry: /bin/false")
        )
        self.run_git("add", ".pre-commit-config.yaml")
        self.run_git(
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "-qm",
            "other hook fails",
        )
        result = subprocess.run(
            ["git", "-C", str(self.repo), "push", str(remote), "HEAD:smoke"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Other validation", result.stdout + result.stderr)
        self.assertEqual(
            subprocess.check_output(
                ["git", "--git-dir", str(remote), "rev-parse", "refs/heads/smoke"],
                text=True,
            ).strip(),
            original_head,
        )


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Personal hook adapter; builds ownership validation from the active checkout."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import tomllib

HERE = Path(__file__).resolve().parent
STATE = Path.home() / ".local/share/obsidian-hooks"
CRATES = ("code-ownership", "codeowners-engine-rs")
HOOKS = (
    "applypatch-msg",
    "pre-applypatch",
    "post-applypatch",
    "pre-commit",
    "pre-merge-commit",
    "prepare-commit-msg",
    "commit-msg",
    "post-commit",
    "pre-rebase",
    "post-checkout",
    "post-merge",
    "pre-push",
    "post-rewrite",
    "sendemail-validate",
    "fsmonitor-watchman",
    "post-index-change",
)
ENTRY = "git-hooks/local-hooks/check-maintainers"
SCRIPT_DIGESTS = {
    ENTRY: "9373fd1d385d588798de7ca2e1dd9dc44b548866e7d6b018e25c7f02b0f12e68",
    "scripts/ownership/generate-maintainers.sh": "ea7b3d4d30d166f27b0946bac7792ec3a8182617659d33c1d5a077375902c22a",
    "scripts/ownership/check-maintainers.sh": "45f55f82c78bbcfe3d0034adb9af5aa805f328416efb725c54f3b444beec420e",
}


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def root_dir():
    return Path(git(Path.cwd(), "rev-parse", "--show-toplevel"))


def patched_source(source):
    count = source.count("Repository::discover(")
    if count != 2:
        raise RuntimeError(
            f"Expected two discovery calls, found {count}; review the adapter for this checkout"
        )
    patched, replaced = re.subn(
        r"Repository::discover\(([^()]+)\)",
        r"Repository::open_ext(\1, git2::RepositoryOpenFlags::CROSS_FS, std::iter::empty::<&Path>())",
        source,
    )
    if replaced != 2:
        raise RuntimeError("Discovery call syntax changed; review the adapter")
    return patched


def build(root):
    files = [Path("Cargo.toml"), Path("Cargo.lock"), Path("rust-toolchain.toml")]
    manifest = tomllib.loads((root / "Cargo.toml").read_text())
    if set(manifest["workspace"]["members"]) != {f"packages/{name}" for name in CRATES}:
        raise RuntimeError(
            "Rust workspace membership changed; review the adapter before building"
        )
    for name in CRATES:
        crate = Path("packages") / name
        files.append(crate / "Cargo.toml")
        files.extend(
            p.relative_to(root)
            for p in (root / crate / "src").rglob("*")
            if p.is_file()
        )
        if (root / crate / "build.rs").exists():
            raise RuntimeError("A crate now has a build script; review snapshot inputs")
    snapshot = {p: (root / p).read_bytes() for p in sorted(files)}
    cli = Path("packages/code-ownership/src/bin/code-ownership.rs")
    snapshot[cli] = patched_source(snapshot[cli].decode()).encode()
    digest = hashlib.sha256(HERE.joinpath("hooks.py").read_bytes())
    digest.update(f"{platform.system()}:{platform.machine()}".encode())
    for path, data in snapshot.items():
        digest.update(str(path).encode() + b"\0" + data + b"\0")
    cache = STATE / "builds" / digest.hexdigest()
    binary = cache / "code-ownership"
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / "build.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if binary.is_file():
            return binary
        source = cache / "source"
        for path, data in snapshot.items():
            dest = source / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        print(
            "Building personal ownership discovery fix (cached by source contents)...",
            file=sys.stderr,
        )
        target = STATE / "target"
        subprocess.run(
            [
                "cargo",
                "build",
                "--release",
                "--locked",
                "--offline",
                "-p",
                "code-ownership",
                "--target-dir",
                str(target),
            ],
            cwd=source,
            check=True,
            stdout=sys.stderr,
        )
        staged = cache / "code-ownership.new"
        shutil.copy2(target / "release/code-ownership", staged)
        staged.replace(binary)
    return binary


def validate_scripts(root):
    for name, expected in SCRIPT_DIGESTS.items():
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise RuntimeError(
                f"{name} changed; review the adapter so new checks are preserved"
            )


def maintainers():
    root = root_dir()
    validate_scripts(root)
    binary = build(root)
    folder = root / "scripts/ownership/__generated__"
    folder.mkdir(parents=True, exist_ok=True)
    for command, name in [
        ("combine", "COMBINED_MAINTAINERS"),
        ("sources", "MAINTAINERS_SOURCES"),
    ]:
        with tempfile.NamedTemporaryFile(dir=folder, delete=False) as output:
            temporary = Path(output.name)
            try:
                subprocess.run(
                    [str(binary), "maintainers", command],
                    cwd=root,
                    stdout=output,
                    check=True,
                )
                temporary.replace(folder / name)
            finally:
                temporary.unlink(missing_ok=True)
    return subprocess.call(
        [
            str(binary),
            "check",
            "--codeowners",
            "CODEOWNERS",
            "--maintainers",
            str(folder / "COMBINED_MAINTAINERS"),
        ],
        cwd=root,
    )


def adapt_config(text):
    matches = list(
        re.finditer(
            r"(?m)^([ \t]*)entry: git-hooks/local-hooks/check-maintainers[ \t]*$", text
        )
    )
    if len(matches) != 1:
        raise RuntimeError(
            "Maintainer hook entry changed; review the adapter instead of skipping validation"
        )
    match = matches[0]
    command = shlex.join([sys.executable, str(HERE / "hooks.py"), "maintainers"])
    return (
        text[: match.start()]
        + match[1]
        + "entry: "
        + json.dumps(command)
        + text[match.end() :]
    )


def prek(args):
    real = os.environ["OBSIDIAN_REAL_PREK"]
    if not args or args[0] != "hook-impl":
        os.execv(real, [real, *args])
    args = list(args)
    config_index = next(
        (i for i, arg in enumerate(args) if arg.startswith("--config=")), None
    )
    if config_index is None:
        raise RuntimeError("Unexpected prek hook invocation: missing --config=")
    original = Path(args[config_index].split("=", 1)[1])
    with tempfile.TemporaryDirectory(prefix="obsidian-hooks-") as temporary:
        config = Path(temporary) / ".pre-commit-config.yaml"
        config.write_text(adapt_config(original.read_text()))
        args[config_index] = f"--config={config}"
        return subprocess.call([real, *args])


def dispatch(name, args):
    root = root_dir()
    original = root / "git-hooks" / name
    if not original.is_file() or not os.access(original, os.X_OK):
        return 0
    if name == "pre-push":
        real = shutil.which("prek")
        if real is None or Path(real).resolve() == (HERE / "bin/prek").resolve():
            raise RuntimeError("Cannot locate the original prek executable")
        os.environ["OBSIDIAN_REAL_PREK"] = real
        os.environ["PATH"] = str(HERE / "bin") + os.pathsep + os.environ.get("PATH", "")
    os.execv(str(original), [str(original), *args])


def install(root):
    root = Path(git(root, "rev-parse", "--show-toplevel"))
    if not (root / ENTRY).is_file():
        raise RuntimeError(f"{root} does not have the expected ownership hook")
    hook_dir = STATE / "hooks"
    current = subprocess.run(
        ["git", "-C", str(root), "config", "--get", "core.hooksPath"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    if current not in ("git-hooks", str(hook_dir)):
        raise RuntimeError(f"Refusing to replace unfamiliar hooksPath: {current!r}")
    hook_dir.mkdir(parents=True, exist_ok=True)
    for name in HOOKS:
        path = hook_dir / name
        path.write_text(
            "#!/usr/bin/env bash\nexec python3 "
            + shlex.quote(str(HERE / "hooks.py"))
            + " hook "
            + shlex.quote(name)
            + ' "$@"\n'
        )
        path.chmod(0o755)
    subprocess.run(
        ["git", "-C", str(root), "config", "--local", "core.hooksPath", str(hook_dir)],
        check=True,
    )
    print(f"Installed personal ownership adapter for {root}")


def main():
    command, *args = sys.argv[1:]
    if command == "install":
        install(Path(args[0]) if args else Path("/workspaces/obsidian"))
    elif command == "hook":
        return dispatch(args[0], args[1:])
    elif command == "prek":
        return prek(args)
    elif command == "maintainers":
        return maintainers()
    elif command == "build":
        print(build(root_dir()))
    else:
        raise RuntimeError(f"Unknown command: {command}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Personal ownership adapter failed: {error}", file=sys.stderr)
        sys.exit(1)

#!/usr/bin/env python3
"""Install or verify the pinned Isabelle sources; never change existing HEADs."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
PROFILE = json.loads((HERE / "profile.json").read_text())
PINS = json.loads((HERE / "pins.json").read_text())


def run(*args, cwd=None, capture=False, check=True):
    return subprocess.run(args, cwd=cwd, check=check, text=True,
                          capture_output=capture)


def sources(install):
    if not shutil.which("git"):
        raise SystemExit("Isabelle setup needs Git. Install Git first (on macOS: xcode-select --install).")
    for key, pin in PINS.items():
        path = Path(PROFILE[key]).expanduser()
        if not path.exists() and not install:
            raise SystemExit(f"Missing Isabelle dependency: {path}.\nRun: python3 {HERE / 'setup.py'} --install")
        if not path.exists() and install:
            path.mkdir(parents=True)
            run("git", "init", str(path))
            run("git", "remote", "add", "origin", pin["url"], cwd=path)
            run("git", "fetch", "--depth", "1", "origin", pin["revision"], cwd=path)
            run("git", "checkout", "--detach", "FETCH_HEAD", cwd=path)
        if not (path / ".git").exists():
            raise SystemExit(f"Not an Isabelle Git checkout: {path}. Refusing to overwrite it; check profile.json.")
        head = run("git", "rev-parse", "HEAD", cwd=path, capture=True).stdout.strip()
        if head != pin["revision"]:
            raise SystemExit(f"Refusing to change {path}: unexpected HEAD {head}")
        if patch := pin.get("patch"):
            patch = str(HERE / patch)
            applied = run("git", "apply", "--reverse", "--check", patch,
                          cwd=path, capture=True, check=False).returncode == 0
            if not applied:
                if not install:
                    raise SystemExit(f"Required patch missing: {patch}")
                run("git", "apply", "--check", patch, cwd=path)
                run("git", "apply", patch, cwd=path)
        print(f"Verified {path.name}: {head}", flush=True)


def install_components():
    if not shutil.which("curl"):
        raise SystemExit("Isabelle component downloads need curl. Install curl and rerun setup.py --install.")
    home = Path(PROFILE["isabelle_home"]).expanduser()
    binary = str(home / "bin/isabelle")
    settings_dir = Path.home() / ".isabelle/Isabelle2025-2-vsce/etc"
    settings_dir.mkdir(parents=True, exist_ok=True)
    target = settings_dir / "settings"
    expected = (HERE / "settings").read_text()
    if not target.exists() or target.read_text() != expected:
        if target.exists():
            backup = target.with_name("settings.before-isabelle-" +
                                      datetime.now().strftime("%Y%m%d-%H%M%S"))
            shutil.copy2(target, backup)
            print(f"Backed up user settings to {backup}", flush=True)
        target.write_text(expected)
    # Identically versioned components can be reused, without touching the app.
    base = Path.home() / ".isabelle/contrib"
    base.mkdir(parents=True, exist_ok=True)
    for name in (home / "Admin/components/main").read_text().splitlines():
        if not name or name.startswith("#"):
            continue
        candidates = sorted(Path("/Applications").glob(
            f"Isabelle*.app/Contents/Resources/contrib/{name}"))
        if candidates and not (base / name).exists():
            (base / name).symlink_to(candidates[-1], target_is_directory=True)
    run(binary, "components", "-a")
    run(binary, "components", "-u", str(Path(PROFILE["mcp_home"]).expanduser()))
    print("Sources ready. Run isabelle-dev build to build/check the smoke session.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--verify", action="store_true")
    action.add_argument("--install", action="store_true")
    args = parser.parse_args()
    sources(args.install)
    if args.install:
        install_components()

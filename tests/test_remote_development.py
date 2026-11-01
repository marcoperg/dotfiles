import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RemoteDevelopmentConfigTests(unittest.TestCase):
    def read(self, relative_path):
        return (ROOT / relative_path).read_text()

    def test_ghostty_enables_remote_capabilities(self):
        config = self.read("dotfiles/ghostty/config")
        self.assertIn("shell-integration-features = ssh-env,ssh-terminfo", config)
        self.assertIn("clipboard-write = allow", config)
        self.assertIn("clipboard-read = allow", config)
        self.assertIn("font-family = Menlo", config)

    def test_shell_does_not_downgrade_term(self):
        self.assertNotIn("TERM=xterm-256color", self.read("dotfiles/.zshrc"))

    def test_ssh_uses_persistent_connections_and_forwards_ghostty_env(self):
        config = self.read("dotfiles/ssh/config")
        self.assertIn("ControlMaster auto", config)
        self.assertIn("ControlPersist 10m", config)
        self.assertIn(
            "SendEnv COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION", config
        )

    def test_emacs_service_is_not_snap_specific(self):
        service = self.read("dotfiles/emacs/emacs.service")
        self.assertNotIn("ExecStart=/snap/", service)
        self.assertIn("ExecStart=/usr/bin/env emacs --fg-daemon", service)

    def test_daemon_services_receive_development_path(self):
        required_paths = (
            "%h/.local/bin",
            "%h/clip/Systems/ciao-devel/build/bin",
        )
        for service_path in (
            "dotfiles/emacs/emacs.service",
        ):
            service = self.read(service_path)
            for path in required_paths:
                self.assertIn(path, service)

    def test_terminal_client_self_starts_daemon(self):
        launcher = self.read("dotfiles/bin/e")
        self.assertIn('emacsclient -a "" -t "$@"', launcher)

    def test_default_opencode_is_v2_and_legacy_service_is_not_installed(self):
        init = self.read("dotfiles/emacs/init.el")
        bootstrap = self.read("create-links.sh")

        self.assertIn('(my/opencode-start-direct "~/.local/bin/opencode" "")', init)
        self.assertNotIn('"attach" "http://localhost:4096"', init)
        self.assertNotIn("~/.opencode/bin", init)
        self.assertNotIn("(defun my/opencode1 ()", init)
        self.assertNotIn("opencode.service", bootstrap)
        self.assertNotIn("install_opencode_state_defaults", bootstrap)
        self.assertFalse((ROOT / "dotfiles/opencode").exists())

    @unittest.skipUnless(os.uname().sysname == "Linux", "Linux binary discovery")
    def test_launcher_prefers_standalone_v2_and_ignores_v1(self):
        with tempfile.TemporaryDirectory() as home:
            launcher = Path(home) / ".opencode/bin/opencode"
            launcher.parent.mkdir(parents=True)
            fallback = Path(home) / ".local/opt/opencode-v2/bin/opencode"
            fallback.parent.mkdir(parents=True)
            fallback.write_text('#!/bin/sh\nprintf "fallback\\n"\n')
            fallback.chmod(0o755)
            env = os.environ.copy()
            env["HOME"] = home
            env.pop("OPENCODE_BIN", None)
            for version in ("2.2.5", "1.0.0"):
                launcher.write_text(
                    '#!/bin/sh\nif [ "$1" = --version ]; then\n'
                    f'  echo "opencode v{version}"\n'
                    'else\n  printf "%s\\n" "$@"\nfi\n'
                )
                launcher.chmod(0o755)
                result = subprocess.run(
                    [str(ROOT / "dotfiles/bin/opencode"), "run", "hello world"],
                    capture_output=True, env=env, text=True, check=True,
                )
                expected = (["run", "--standalone", "hello world"]
                            if version.startswith("2.") else ["fallback"])
                self.assertEqual(result.stdout.splitlines(), expected)

    def test_opencode_isolates_profile_and_preserves_command_arguments(self):
        with tempfile.TemporaryDirectory() as home:
            executable = Path(home) / "v2 executable"
            executable.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$XDG_CONFIG_HOME\" \"$XDG_DATA_HOME\" "
                "\"$XDG_STATE_HOME\" \"$XDG_CACHE_HOME\" "
                "\"${OPENCODE_CONFIG-unset}\" \"${OPENCODE_DB-unset}\" \"$@\"\n"
            )
            executable.chmod(0o755)
            env = os.environ.copy()
            env.update({
                "HOME": home,
                "OPENCODE_BIN": str(executable),
                "OPENCODE_CONFIG": "/v1/config.json",
                "OPENCODE_DB": "/v1/opencode.db",
                "XDG_CONFIG_HOME": "/v1/config",
                "XDG_DATA_HOME": "/v1/data",
                "XDG_STATE_HOME": "/v1/state",
                "XDG_CACHE_HOME": "/v1/cache",
            })
            cases = [
                ([], ["--standalone"]),
                (["project with spaces"], ["--standalone", "project with spaces"]),
                (["run", "hello world"], ["run", "--standalone", "hello world"]),
                (["mini"], ["mini", "--standalone"]),
                (["debug", "paths"], ["debug", "paths"]),
                (["mcp", "list"], ["mcp", "list"]),
                (["upgrade", "--method", "curl"], ["upgrade", "--method", "curl"]),
            ]
            for arguments, forwarded in cases:
                with self.subTest(arguments=arguments):
                    result = subprocess.run(
                        [str(ROOT / "dotfiles/bin/opencode"), *arguments],
                        capture_output=True, env=env, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.splitlines(), [
                        f"{home}/.config/opencode-v2",
                        f"{home}/.local/share/opencode-v2",
                        f"{home}/.local/state/opencode-v2",
                        f"{home}/.cache/opencode-v2",
                        "unset", "unset", *forwarded,
                    ])

    def test_opencode_discovers_private_knowledge_skill_portably(self):
        config = json.loads(self.read("dotfiles/opencode-v2/opencode.jsonc"))

        self.assertIn(
            "~/knowledge/praxis/skills", config["skills"]
        )
        self.assertEqual(
            [rule["effect"] for rule in config["permissions"]
             if rule["action"] == "skill" and rule["resource"] == "knowledge-ecosystem"],
            ["ask"]
        )
        self.assertNotIn("/Users/", str(config))

    def test_managed_bootstrap_links_remote_development_files(self):
        with tempfile.TemporaryDirectory() as home:
            env = os.environ.copy()
            env["HOME"] = home
            env["DOTFILES_SKIP_SERVICES"] = "1"
            result = subprocess.run(
                ["bash", str(ROOT / "create-links.sh"), "--managed"],
                capture_output=True,
                env=env,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = [
                ".local/bin/e",
                ".local/bin/opencode",
                ".ssh/config",
                ".config/opencode-v2/opencode/opencode.jsonc",
                ".config/opencode-v2/opencode/cli.json",
                ".config/opencode-v2/opencode/plugins/chatgpt-compat.ts",
            ]
            if os.uname().sysname == "Darwin":
                expected.append(
                    "Library/Application Support/com.mitchellh.ghostty/config.ghostty"
                )
            for relative_path in expected:
                self.assertTrue((Path(home) / relative_path).is_symlink())
            self.assertTrue(os.access(Path(home) / ".local/bin/e", os.X_OK))
            self.assertTrue(os.access(Path(home) / ".local/bin/opencode", os.X_OK))
            self.assertFalse((Path(home) / ".local/bin/opencode2").is_symlink())
            self.assertFalse((Path(home) / ".config/opencode").exists())
            self.assertFalse((Path(home) / ".local/state/opencode").exists())

    def test_opencode_only_bootstrap_backs_up_local_cli_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as home:
            cli = Path(home) / ".config/opencode-v2/opencode/cli.json"
            cli.parent.mkdir(parents=True)
            local_settings = '{"session":{"sidebar":"hide"}}\n'
            cli.write_text(local_settings)
            env = os.environ.copy()
            env["HOME"] = home
            for _ in range(2):
                subprocess.run(
                    ["bash", str(ROOT / "create-links.sh"), "--opencode"],
                    capture_output=True, env=env, text=True, check=True,
                )
            self.assertTrue(cli.is_symlink())
            backup = Path(home) / ".dotfiles.backups/.config/opencode-v2/opencode/cli.json"
            self.assertEqual(backup.read_text(), local_settings)
            self.assertFalse(backup.with_name("cli.json.1").exists())
            self.assertFalse((Path(home) / ".ssh").exists())
            self.assertFalse((Path(home) / ".config/systemd").exists())
            self.assertFalse((Path(home) / ".local/share").exists())

    def test_bootstrap_removes_only_owned_retired_launcher(self):
        with tempfile.TemporaryDirectory() as home:
            retired = Path(home) / ".local/bin/opencode2"
            retired.parent.mkdir(parents=True)
            retired.symlink_to(ROOT / "dotfiles/bin/opencode2")
            env = dict(os.environ, HOME=home)
            subprocess.run(
                ["bash", str(ROOT / "create-links.sh"), "--opencode"],
                capture_output=True, env=env, check=True,
            )
            self.assertFalse(retired.is_symlink())
            retired.write_text("user-owned launcher\n")
            subprocess.run(
                ["bash", str(ROOT / "create-links.sh"), "--opencode"],
                capture_output=True, env=env, check=True,
            )
            self.assertEqual(retired.read_text(), "user-owned launcher\n")


if __name__ == "__main__":
    unittest.main()

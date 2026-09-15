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
            "%h/.opencode/bin",
            "%h/clip/Systems/ciao-devel/build/bin",
        )
        for service_path in (
            "dotfiles/emacs/emacs.service",
            "dotfiles/opencode/opencode.service",
        ):
            service = self.read(service_path)
            for path in required_paths:
                self.assertIn(path, service)

    def test_terminal_client_self_starts_daemon(self):
        launcher = self.read("dotfiles/bin/e")
        self.assertIn('emacsclient -a "" -t "$@"', launcher)

    def test_opencode_discovers_private_knowledge_skill_portably(self):
        config = json.loads(self.read("dotfiles/opencode/opencode.jsonc"))

        self.assertIn(
            "~/knowledge/praxis/skills", config["skills"]["paths"]
        )
        self.assertEqual(
            config["permission"]["skill"]["knowledge-ecosystem"], "ask"
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
                ".ssh/config",
                ".config/opencode/opencode.jsonc",
                ".config/opencode/tui.jsonc",
            ]
            if os.uname().sysname == "Darwin":
                expected.append(
                    "Library/Application Support/com.mitchellh.ghostty/config.ghostty"
                )
            for relative_path in expected:
                self.assertTrue((Path(home) / relative_path).is_symlink())
            self.assertTrue(os.access(Path(home) / ".local/bin/e", os.X_OK))


if __name__ == "__main__":
    unittest.main()

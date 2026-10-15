# Dotfiles

Personal workstation configuration and bootstrap scripts. `create-links.sh`
links the tracked files into their expected locations; system package changes
remain an explicit, separate step.

Bootstrap `~/knowledge` before running Emacs: the init file intentionally loads
Lisp packages from the Episteme and Praxis repositories. Ciao is not installed
by `install-system-deps.sh`; install it separately when reverse source navigation
is required.

## Mail

The mail configuration needs a `.authinfo.gpg` file containing

```
machine imap.domain.tld login [USER] password [PASS] port 993
machine smtp.domain.tld login [USER] password [PASS] port 587
```

for each mail address.

## AI Tool Configuration

`create-links.sh --managed` manages these configuration files individually,
leaving their runtime state directories intact and moving replaced files into
`~/.dotfiles.backups`:

- `~/.zshenv`
- `~/.local/bin/opencode`
- `~/.local/bin/opencode-blueprofit`
- `~/.local/bin/opencode2`
- `~/.claude/settings.json`
- `~/.claude/keybindings.json`
- `~/.config/opencode-v2/opencode/opencode.jsonc`
- `~/.config/opencode-v2/opencode/cli.json`

OpenCode V2 is the default. The `opencode` command delegates to the established
`opencode2` launcher, preserving the working V2 profile without moving credentials
or sessions. V1 configuration under `dotfiles/opencode/` is retained for reference
only: bootstrap no longer links it, merges its state, or installs its service.
On Linux, bootstrap still installs and starts the Emacs daemon when available.
Run `./create-links.sh --managed` to apply managed settings.
Use `./create-links.sh --opencode` to apply only the OpenCode launchers and
configuration, without touching other managed files or services. Existing local
CLI settings are backed up before linking the tracked file.

`opencode-blueprofit` launches the same OpenCode executable with the same
configuration, TUI settings, plugins, skills, and MCP servers as `opencode`, but
with separate authentication, sessions, logs, repositories, and mutable state.
Authenticate the account through OpenCode on first use. Its runtime files live
under `~/.local/share/opencode-blueprofit-v2/opencode/` and
`~/.local/state/opencode-blueprofit-v2/opencode/`, with a separate cache under
`~/.cache/opencode-blueprofit-v2/`. This is a new V2 account profile: authenticate
again with `/connect`; the old V1 BlueProfit data is not reused or modified.
Neither profile is tracked or backed up.
From Emacs, `M-x my/opencode-blueprofit` opens it in the current buffer's
directory. Buffers include the directory name and Emacs adds numeric suffixes
when more than one instance is open. The command intentionally has no global
keybinding.

The OpenCode configuration discovers reusable Ciao guidance from
`~/clip/Systems/ciao-skills/skills` and the private `knowledge-ecosystem` skill
from `~/knowledge/praxis/skills`. Bootstrap the knowledge repositories before
linking dotfiles so that the latter exists. Loading `knowledge-ecosystem`
requires an OpenCode permission prompt; its private content remains in Praxis
and is not copied into this public repository.

### OpenCode V2

Install V2 with Homebrew; the managed launcher owns the default command:

```sh
brew install anomalyco/tap/opencode-v2
brew unlink opencode-v2
./create-links.sh --managed
opencode --version
opencode2 --version
opencode2 debug paths
```

`opencode2` uses the Homebrew `opt/opencode-v2/bin/opencode` executable on
Apple Silicon, Intel macOS, or Linuxbrew. For another installation, set
`OPENCODE2_BIN` to the absolute path of the v2 executable. Do not use the v2 curl
installer during side-by-side testing: it replaces `~/.opencode/bin/opencode`.

The launcher keeps all four XDG roots under directories named `opencode-v2`:
configuration in `~/.config`, data in `~/.local/share`, state in `~/.local/state`,
and cache in `~/.cache`. OpenCode appends `opencode/` to each root. Inherited
explicit OpenCode config/database overrides are cleared. Project configuration
is still loaded normally and must use a format compatible with v2.

Interactive launches, `opencode run`, and `opencode mini` use private servers
with `--standalone`. Management commands pass through normally; commands that
start a shared server use the isolated v2 profile. Authenticate with `/connect`
on first use. No legacy server is required. The old binary and V1 runtime data
can remain on disk, but are not used by the default entry points.

From Emacs, `M-x my/opencode` (`C-c a o`) opens V2 directly in a fresh vterm in
the current project root, or the current directory outside a project, on every
host. `M-x my/opencode2` (`C-c a 2`) remains an equivalent explicit entry point.
The V1 command and `C-c a 1` binding are retired. Restart Emacs or evaluate the
updated definitions and keybindings to apply the change to a running instance.

Disable any previously installed V1 server once on each existing host:

```sh
# macOS (if the legacy LaunchAgent was installed)
launchctl disable "gui/$(id -u)/local.opencode.server"
launchctl bootout "gui/$(id -u)/local.opencode.server"
# Linux (if the legacy user service was installed)
systemctl --user disable --now opencode.service
```

Do not remove credentials or session databases. Put `~/.local/bin` ahead of
`~/.opencode/bin` in local shell customizations; the tracked shell configuration
already prefers the managed launcher.

`dotfiles/opencode-v2/` owns the active skills, skill permissions,
Ciao MCP connection, and CLI settings. Ciao tools are exposed directly with
`codemode: false`. `Alt+o` / leader-`o` cycle v2 transcript verbosity. The v1
`shell-env.ts` plugin is not loaded by v2; v2 inherits the launcher's shell
environment. Restart OpenCode after editing managed configuration.

The v2 `chatgpt-compat.ts` plugin removes outgoing OpenAI reasoning-effort update
markers. GPT-6 normally lowers these to `configuration_update` input items,
which ChatGPT subscription sharing rejects. The selected reasoning level still
applies to the request; stored history is preserved.

V2's own update checks are disabled; update the binary explicitly with
`brew upgrade anomalyco/tap/opencode-v2`, then `brew unlink opencode-v2` again
and restart V2. To uninstall the binary, use `brew uninstall opencode-v2`.
Runtime data and credentials remain local and are not tracked or backed up.

### Other managed configuration

The managed configuration also installs:

- `~/.local/bin/e`, which attaches a terminal frame and self-starts an Emacs
  daemon if necessary
- `~/.ssh/config`, with a local untracked override at `~/.ssh/config.local`
- the native macOS Ghostty configuration, including Ghostty SSH environment and
  terminfo integration

On a remote development host, install Emacs and OpenCode first, clone the
knowledge and Ciao repositories at the paths used below, run
`./install-system-deps.sh`, and then run `./create-links.sh`. The Linux bootstrap
only starts services whose executables are present.

The `marco` user must have lingering enabled for these services to start at
boot without an interactive login:

```sh
sudo loginctl enable-linger marco
loginctl show-user marco -p Linger
```

Do not add `~/.claude.json`, `~/.claude/` runtime state, or
`~/.config/opencode/node_modules/`; they contain account data, sessions, and
generated dependencies.

Do not back up or track `~/.opencode`, `~/.local/share/opencode`,
`~/.local/share/opencode-blueprofit`, or the corresponding directories under
`~/.local/state`, or the `opencode-v2` and `opencode-blueprofit-v2` runtime/cache directories. They
contain authentication, sessions, logs, and generated state. Reinstall OpenCode
and authenticate again on a rebuilt host.

The Ghostty configuration allows OSC 52 clipboard reads and writes so remote
Emacs can integrate with the Mac clipboard. Treat processes on SSH hosts as able
to request clipboard contents; change `clipboard-read` back to `ask` when that
trust is not appropriate.

## System Dependencies

Emacs packages listed in `dotfiles/emacs/init.el` install automatically on
first startup. Install system-backed integrations such as mu4e, mail
synchronization, vterm, PDF Tools, spelling, and LaTeX with:

```sh
./install-system-deps.sh
```

The script supports Ubuntu/Debian (`apt-get`), Arch Linux (`pacman`, plus
`paru` or `yay` for the AUR `mu` package), and macOS or Linux with Homebrew.
LaTeX is included on apt, Arch, and macOS; a Linuxbrew installation requires a
separate TeX distribution.
It also installs the remote-development shell, compiler/LSP, Node, search, and
terminal tools, including `clangd`, TypeScript Language Server, `jq`, Neovim,
ripgrep, rlwrap, tmux, and Zsh. It installs Clingo where the package manager
provides it and reports when apt requires a separate installation. Emacs, Ciao,
and OpenCode remain explicit installations because their required versions and
source trees are selected separately. Native `ciao_asp` sessions require both
the Clingo executable and matching `clingo.h` and libclingo files.
The pinned TypeScript tooling requires Node.js 18 or newer; on distributions
whose package repository provides an older Node, install an approved current
Node release before running this script.
When the `apt-get` version of mu is too old for current Emacs releases, the
script builds a pinned mu release under `~/.local` and verifies its checksum.
It does not run from `create-links.sh`, so linking dotfiles never changes
system packages unexpectedly.

## Knowledge System Integration

The Emacs configuration expects the sibling repositories under `~/knowledge`:

- `episteme` for authored knowledge and its Ciao relation query layer
- `bibliotheca` for the Better BibTeX bibliography and generated catalogue
- `praxis` for practical-note utilities

Domain behavior is versioned with the repository that owns it. The init file
loads `episteme/lisp/episteme-citations.el` and
`praxis/lisp/praxis-utils.el`; dotfiles only owns package configuration and key
choices. This prevents the Emacs parser for relation-query output from drifting
away from the Episteme CLI that produces it.

The citation workflow uses:

- `C-c b` to insert or edit an Org citation through Citar
- `C-c B` on an Episteme citation to open its Bibliotheca item
- `C-c B` in a Bibliotheca item to choose an Episteme citation or
  `informed-by` occurrence. Citation jumps have exact line and column positions;
  relation-drawer assertions have an exact line and a synthetic column of 1.

Reverse navigation requires `python3`, `ciao-shell`, and an executable
`~/knowledge/episteme/bin/query-relations`. The query wrapper rebuilds its
ignored Ciao facts before use, so no generated relation database is tracked in
dotfiles or Git.

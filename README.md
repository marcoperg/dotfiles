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
- `~/.local/bin/opencode-blueprofit`
- `~/.local/bin/opencode2`
- `~/.claude/settings.json`
- `~/.claude/keybindings.json`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/tui.jsonc`
- `~/.config/opencode-v2/opencode/opencode.jsonc`
- `~/.config/opencode-v2/opencode/cli.json`

It also merges `dotfiles/opencode/state-defaults.json` into OpenCode's mutable
`~/.local/state/opencode/kv.json`. This keeps preferences such as disabled TUI
animations reproducible without symlinking or tracking the rest of the runtime
state. On Linux, it also installs and starts user services for the Emacs daemon
and the local OpenCode server used by the Emacs `C-c a o` command. Perseo is the
exception: its OpenCode service is installed but not enabled, and `C-c a o`
launches OpenCode directly inside the persistent Emacs daemon. Run
`./create-links.sh --managed` to apply these managed settings.

`opencode-blueprofit` launches the same OpenCode executable with the same
configuration, TUI settings, plugins, skills, and MCP servers as `opencode`, but
with separate authentication, sessions, logs, repositories, and mutable state.
Authenticate the account through OpenCode on first use. Its runtime files live
under `~/.local/share/opencode-blueprofit/opencode/` and
`~/.local/state/opencode-blueprofit/opencode/`; neither directory is tracked or
backed up. The normal `opencode` command and its user service are unchanged.
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

### OpenCode v2 testing

Keep v1 at `~/.opencode/bin/opencode` and install v2 separately with Homebrew:

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

The launcher isolates all four XDG roots under directories named `opencode-v2`:
configuration in `~/.config`, data in `~/.local/share`, state in `~/.local/state`,
and cache in `~/.cache`. OpenCode appends `opencode/` to each root. Inherited
explicit OpenCode config/database overrides are cleared. Project configuration
is still loaded normally and must use a format compatible with v2.

Interactive launches, `opencode2 run`, and `opencode2 mini` use private servers
with `--standalone`. Management commands pass through normally; commands that
start a shared server use the isolated v2 profile. Authenticate with `/connect`
on first use. Existing v1 Emacs commands and server definitions keep using v1.

From Emacs, `M-x my/opencode1` (`C-c a 1`) and `M-x my/opencode2` (`C-c a 2`)
each open a fresh vterm in the current project root, or the current directory
outside a project. Both launch directly; v2 uses the isolated `opencode2`
launcher. Buffers are named `*opencode1:project*` and `*opencode2:project*`, with
numeric suffixes for additional instances. The existing `C-c a o` command keeps
its host-specific behavior. Restart Emacs or evaluate the new definitions and
keybindings to make them available in a running instance.

`dotfiles/opencode-v2/` owns the separately translated skills, skill permissions,
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
and restart v2. To remove the trial binary, use `brew uninstall opencode-v2`.
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
`~/.local/state`, or the isolated `opencode-v2` runtime/cache directories. They
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

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
- `~/.claude/settings.json`
- `~/.claude/keybindings.json`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/tui.jsonc`

It also merges `dotfiles/opencode/state-defaults.json` into OpenCode's mutable
`~/.local/state/opencode/kv.json`. This keeps preferences such as disabled TUI
animations reproducible without symlinking or tracking the rest of the runtime
state. On Linux, it also installs and starts user services for the Emacs daemon
and the local OpenCode server used by the Emacs `C-c a o` command. Perseo is the
exception: its OpenCode service is installed but not enabled, and `C-c a o`
launches OpenCode directly inside the persistent Emacs daemon. Run
`./create-links.sh --managed` to apply these managed settings.

The OpenCode configuration discovers reusable Ciao guidance from
`~/clip/Systems/ciao-skills/skills` and the private `knowledge-ecosystem` skill
from `~/knowledge/praxis/skills`. Bootstrap the knowledge repositories before
linking dotfiles so that the latter exists. Loading `knowledge-ecosystem`
requires an OpenCode permission prompt; its private content remains in Praxis
and is not copied into this public repository.

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

Do not back up or track `~/.opencode`, `~/.local/share/opencode`, or the rest of
`~/.local/state/opencode`. They contain authentication, sessions, logs, and
generated state. Reinstall OpenCode and authenticate again on a rebuilt host.

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

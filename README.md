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
and the local OpenCode server used by the Emacs `C-c a o` command. Run
`./create-links.sh --managed` to apply these managed settings.

The `marco` user must have lingering enabled for these services to start at
boot without an interactive login:

```sh
sudo loginctl enable-linger marco
loginctl show-user marco -p Linger
```

Do not add `~/.claude.json`, `~/.claude/` runtime state, or
`~/.config/opencode/node_modules/`; they contain account data, sessions, and
generated dependencies.

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

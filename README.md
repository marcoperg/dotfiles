The mail configuration needs a `.authinfo.gpg` file containing

```
machine imap.domain.tld login [USER] password [PASS] port 993
machine stmp.domain.tld login [USER] password [PASS] port 587
```

for each mail address.

## AI Tool Configuration

`create-links.sh` manages these configuration files individually, leaving their
runtime state directories intact:

- `~/.claude/settings.json`
- `~/.claude/keybindings.json`
- `~/.config/opencode/opencode.jsonc`

It also merges `dotfiles/opencode/state-defaults.json` into OpenCode's mutable
`~/.local/state/opencode/kv.json`. This keeps preferences such as disabled TUI
animations reproducible without symlinking or tracking the rest of the runtime
state. Run `./create-links.sh --managed` to apply these managed settings.

Do not add `~/.claude.json`, `~/.claude/` runtime state, or
`~/.config/opencode/node_modules/`; they contain account data, sessions, and
generated dependencies.

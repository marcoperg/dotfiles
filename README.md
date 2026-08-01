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

Run `./create-links.sh --managed` to install just these links.

Do not add `~/.claude.json`, `~/.claude/` runtime state, or
`~/.config/opencode/node_modules/`; they contain account data, sessions, and
generated dependencies.

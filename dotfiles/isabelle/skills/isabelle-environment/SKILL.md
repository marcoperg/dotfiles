---
name: isabelle-environment
description: Local pinned Isabelle environment, session options, editor synchronization, and independent checking. Use before starting a PIDE MCP session here.
---

# Local Isabelle environment

Use `~/dotfiles/dotfiles/isabelle/profile.json` as the authority for the selected
Isabelle, logic, and session directories. All three entry points use the same
pinned Isabelle fork, not `/Applications/Isabelle2026.app`.

- `~/dotfiles/dotfiles/bin/isabelle-dev mcp-session-options` prints JSON arguments
  to pass to MCP `start_session`: `logic` HOL, profile `dirs`, and `options`
  `quick_and_dirty=false`, and two threads. MCP starts with no eager session.
- For other projects, add their session directory to the profile and use matching
  directories in `start_session`. Restart the Emacs LSP workspace after changes.
- Load the matching upstream `pide-mcp`, `isabelle-formalization`, and
  `isabelle-proof-development` skills when appropriate.
- Emacs LSP and MCP have **separate prover sessions**. Exchange changes through
  saved files. Do not edit a theory while its user has unsaved edits. Emacs
  automatically reloads unmodified files, but protects unsaved edits.
- Finish work with `~/dotfiles/dotfiles/bin/isabelle-dev build` for the smoke
  session. Use `~/dotfiles/dotfiles/bin/isabelle-dev check -D PROJECT_DIR` for
  another project's sessions. Both set `quick_and_dirty=false`; report the
  actual command and outcome.

Never treat an interactive success, MCP result, `sorry`, or a
`quick_and_dirty=true` run as independent final verification.

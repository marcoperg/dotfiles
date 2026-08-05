[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# OpenCode runs commands through non-interactive zsh, which does not read .zshrc.
if [[ -n "${OPENCODE:-}" && -z "${OPENCODE_ZSHRC_LOADED:-}" ]]; then
  export OPENCODE_ZSHRC_LOADED=1
  source "$HOME/.zshrc"
fi

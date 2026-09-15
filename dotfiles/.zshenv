[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

export PATH="$HOME/.local/bin:$PATH"
[[ ! -d /home/linuxbrew/.linuxbrew/opt/llvm/bin ]] \
  || export PATH="/home/linuxbrew/.linuxbrew/opt/llvm/bin:$PATH"
[[ ! -d /opt/homebrew/opt/llvm/bin ]] \
  || export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

# OpenCode runs commands through non-interactive zsh, which does not read .zshrc.
if [[ -n "${OPENCODE:-}" && -z "${OPENCODE_ZSHRC_LOADED:-}" ]]; then
  export OPENCODE_ZSHRC_LOADED=1
  source "$HOME/.zshrc"
fi

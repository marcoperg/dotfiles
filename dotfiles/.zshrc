export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="bira"
POWERLEVEL9K_MODE="nerdfont-complete"

POWERLEVEL9K_RAM_ELEMENTS="both"


CASE_SENSITIVE="true"

# DISABLE_LS_COLORS="true"

# ENABLE_CORRECTION="true"

plugins=(
    git
    zsh-navigation-tools
   )

source $ZSH/oh-my-zsh.sh

# Example aliases
# alias zshconfig="mate $HOME/.zshrc"
# alias ohmyzsh="mate $HOME/.oh-my-zsh"

source $HOME/.zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

[ -f $HOME/.fzf.zsh ] && source ~/.fzf.zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('$HOME/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
conda activate base
# <<< conda initialize <<<


# https://github.com/nvbn/thefuck
# pip3 install thefuck
eval $(thefuck --alias)

export LD_LIBRARY_PATH=/usr/local/cuda-11.2/lib64:/usr/local/TensorRT-6.0.1.5/lib:/usr/local/cuda-11.2/extras/CUPTI/lib64
export PATH=$PATH:/usr/local/go/bin
fpath+=${ZDOTDIR:-~}/.zsh_functions

# Autostart tmux
if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
    tmux attach -t default || tmux new -s default
fi

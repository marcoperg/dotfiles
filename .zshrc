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
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

source ~/.zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('~/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "~/anaconda3/etc/profile.d/conda.sh" ]; then
        . "~/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="~/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

export LD_LIBRARY_PATH=/usr/local/cuda-10.1/lib64:/usr/local/TensorRT-6.0.1.5/lib:/usr/local/cuda-10.1/extras/CUPTI/lib64

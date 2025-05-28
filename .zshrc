alias hg="history | grep"

export ZSH="$HOME/.oh-my-zsh"
plugins=(
    git 
    zsh-autosuggestions 
    zsh-syntax-highlighting 
    fast-syntax-highlighting 
    zsh-autocomplete
)
ZSH_THEME="robbyrussell"
source $ZSH/oh-my-zsh.sh

alias gc="git commit -m"
alias ga="git add"
alias gpo="git push origin HEAD"
alias gcm="git checkout main"
alias gst="git status"
alias gco="git checkout"
alias gcb="git checkout -b"

alias tmux-claude="tmux new-session -s claude"
alias tma="tmux -a"
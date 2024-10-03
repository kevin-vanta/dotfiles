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
alias gpo="git push origin"
alias gst="git status"
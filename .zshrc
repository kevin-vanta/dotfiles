alias hg="history | grep"

export ZSH="$HOME/.oh-my-zsh"
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)
ZSH_THEME="robbyrussell"

# Catppuccin theme for zsh-syntax-highlighting (must be before oh-my-zsh)
source ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh

source $ZSH/oh-my-zsh.sh

alias gc="git commit -m"
alias ga="git add"
alias gpo="git push origin HEAD"
alias gcm="git checkout main"
alias gst="git status"
alias gco="git checkout"
alias gcb="git checkout -b"

# Git stash aliases
alias gstp="git stash push -m"
alias gstl="git stash list"
alias gstpop="git stash pop"

alias squash="git fetch origin main && git reset --soft origin/main && git commit -m";

alias cc='claude --allowedTools "Bash(*)" "Git(*)" "Read" "Edit" "Write"'
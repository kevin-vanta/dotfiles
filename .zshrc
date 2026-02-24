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

export GITHUB_USER="kevin-vanta"

# Start claude code in a new tmux session
tcc() {
  local session_name="claude-$(openssl rand -hex 3)"
  tmux new-session -d -s "$session_name"
  tmux send-keys -t "$session_name" 'claude' Enter
  tmux attach-session -t "$session_name"
}

# Attach to an existing claude tmux session
tca() {
  local sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^claude-')"})

  if [[ ${#sessions[@]} -eq 0 ]]; then
    echo "No claude sessions found."
    return 1
  elif [[ ${#sessions[@]} -eq 1 ]]; then
    if [[ -n "$TMUX" ]]; then
      tmux switch-client -t "$sessions[1]"
    else
      tmux attach-session -t "$sessions[1]"
    fi
  else
    echo "Select a claude session:"
    select session in "${sessions[@]}"; do
      if [[ -n "$session" ]]; then
        if [[ -n "$TMUX" ]]; then
          tmux switch-client -t "$session"
        else
          tmux attach-session -t "$session"
        fi
        break
      fi
    done
  fi
}
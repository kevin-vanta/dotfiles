alias hg="history | grep"

# Ona secrets (added to zshrc since Ona only sources in bashrc by default)
[ -f /etc/profile.d/ona-secrets.sh ] && . /etc/profile.d/ona-secrets.sh

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

# Create a herdr worktree branched off the latest origin/main
herdr-new() {
  git fetch origin main && herdr worktree create --branch "$1" --base origin/main
}

herdr-rm() {
  if (( $# != 1 )); then
    print -u2 -r -- "Usage: herdr-rm <branch-name>"
    return 2
  fi

  local branch="$1"
  local worktrees
  local matches
  local match_count
  local workspace_id
  local worktree_path
  local reply

  worktrees=$(herdr worktree list) || return
  matches=$(jq -c --arg branch "$branch" \
    '[.result.worktrees[] | select(.branch == $branch and .is_linked_worktree == true)]' \
    <<< "$worktrees") || return
  match_count=$(jq 'length' <<< "$matches") || return

  if (( match_count == 0 )); then
    print -u2 -r -- "No linked herdr worktree found for branch: $branch"
    return 1
  fi

  if (( match_count > 1 )); then
    print -u2 -r -- "Multiple linked herdr worktrees found for branch: $branch"
    jq -r '.[] | "  \(.open_workspace_id // "-")  \(.path)"' <<< "$matches" >&2
    return 1
  fi

  workspace_id=$(jq -r '.[0].open_workspace_id // empty' <<< "$matches") || return
  worktree_path=$(jq -r '.[0].path' <<< "$matches") || return

  if [[ -z "$workspace_id" ]]; then
    print -u2 -r -- "The worktree for branch $branch has no workspace ID and cannot be removed with herdr."
    return 1
  fi

  read -r "reply?Remove $branch ($workspace_id) at $worktree_path? [y/N] "
  case "$reply" in
    y|Y|yes|YES|Yes)
      herdr worktree remove --workspace "$workspace_id"
      ;;
    *)
      print -r -- "Cancelled."
      return 1
      ;;
  esac
}

codex() {
  local git_dir common_dir filesystem_override

  if ! git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null); then
    command codex "$@"
    return
  fi

  common_dir=$(git rev-parse --path-format=absolute --git-common-dir) || return
  if [[ "$git_dir" == "$common_dir" ]]; then
    filesystem_override="{\"$git_dir\"=\"write\"}"
  else
    filesystem_override="{\"$common_dir\"=\"write\",\"$git_dir\"=\"write\"}"
  fi

  command codex -c "permissions.repo-git.filesystem=$filesystem_override" "$@"
}

alias web="NON_LOCAL_IMPERSONATION_ENABLED=true just dev-start-web"

# Start claude code in a new tmux session
tcc() {
  local session_name="claude-$(openssl rand -hex 3)"
  tmux new-session -d -s "$session_name"
  tmux send-keys -t "$session_name" 'claude' Enter
  tmux attach-session -t "$session_name"
}

export GITHUB_USER="kevin-vanta"

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
export PATH="$HOME/bin:$PATH"
export CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=true

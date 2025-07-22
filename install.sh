#!/bin/bash

create_symlinks() {
    # Get the directory in which this script lives.
    script_dir=$(dirname "$(readlink -f "$0")")

    # Get a list of all files in this directory that start with a dot.
    files=$(find -maxdepth 1 -type f -name ".*")

    # Create a symbolic link to each file in the home directory.
    for file in $files; do
        name=$(basename $file)
        echo "Creating symlink to $name in home directory."
        rm -rf ~/$name
        ln -s $script_dir/$name ~/$name
    done
}

echo "Creating symlinks..."
create_symlinks

echo "Installing tmux..."
if ! command -v tmux &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y tmux
else
    echo "tmux is already installed"
fi

echo "Installing Python dependencies..."
if ! command -v python3 &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y python3 python3-pip
else
    echo "Python3 is already installed"
fi

echo "Installing uv package manager..."
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source $HOME/.cargo/env
else
    echo "uv is already installed"
fi

echo "Installing SuperClaude Framework..."
# Ensure uv is in PATH for the current session
if [ -f "$HOME/.cargo/env" ]; then
    source $HOME/.cargo/env
fi

uv add SuperClaude
python3 -m SuperClaude install --quick

echo "SuperClaude Framework installed successfully!"

echo "Installing Zsh..."
sudo apt-get update && sudo apt-get install -y zsh

echo "Installing Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "Oh My Zsh is already installed"
fi

echo "Installing Zsh plugins..."
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting
git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete

echo "Installing Tmux Plugin Manager..."
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "Setting Zsh as default shell..."
# Check if we're in a container/codespace environment
if [ -f /.dockerenv ] || [ -n "$CODESPACES" ]; then
    echo "Running in container/codespace - updating shell in /etc/passwd"
    sudo usermod -s $(which zsh) $(whoami)
else
    echo "Running on regular system - using chsh"
    chsh -s $(which zsh)
fi
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a personal dotfiles repository for managing shell configuration and development environment setup. The repository contains:

- `.zshrc` - Zsh configuration with aliases and Oh My Zsh setup
- `.tmux.conf` - Tmux configuration with mouse support and plugins
- `install.sh` - Installation script that creates symlinks and sets up Zsh/tmux environment

## Key Commands

- `./install.sh` - Run the full installation process (creates symlinks, installs tmux, Zsh, Oh My Zsh, and plugins)
- `prefix + I` (in tmux) - Install tmux plugins after initial setup
- No build, lint, or test commands - this is a simple configuration repository

## Architecture

The repository follows a simple dotfiles pattern:
- Dotfiles (files starting with `.`) are stored in the repository root
- `install.sh` creates symlinks from the home directory to these dotfiles
- The installation script also handles Zsh and plugin installation via package managers and git clones

## Git Aliases Defined

The `.zshrc` includes several git aliases that are commonly used:
- `gc` - git commit -m
- `ga` - git add  
- `gpo` - git push origin HEAD
- `gcm` - git checkout main
- `gst` - git status
- `gco` - git checkout
- `gcb` - git checkout -b

## Tmux Integration

- `tmux-claude` - creates a new tmux session named "claude"
- `tma` - attaches to existing tmux session
- Mouse support enabled by default
- Includes tmux-continuum plugin for automatic session saving/restoration
- Tmux Plugin Manager (TPM) installed for plugin management
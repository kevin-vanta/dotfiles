#!/bin/bash
# install-lumen.sh - Complete installation script for lumen (git commit AI tool)
# https://github.com/jnsahaj/lumen

set -e

# Parse arguments
INTERACTIVE=false
SKIP_OPTIONAL=false
PROVIDER=""
MODEL=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        --skip-optional)
            SKIP_OPTIONAL=true
            shift
            ;;
        --provider)
            PROVIDER="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -i, --interactive    Enable interactive prompts (default: auto-confirm)"
            echo "  --skip-optional      Skip optional dependencies (fzf, mdcat)"
            echo "  --provider <name>    Set AI provider (openai, claude, groq, ollama, etc.)"
            echo "  --model <name>       Set model name (e.g., claude-3-5-haiku-latest)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Environment variables for API keys:"
            echo "  ANTHROPIC_API_KEY    Used when provider is 'claude'"
            echo "  OPENAI_API_KEY       Used when provider is 'openai'"
            echo "  LUMEN_API_KEY        Used for any provider (fallback)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper for prompts - returns 0 (yes) or 1 (no)
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"  # default to yes

    # Auto-confirm unless interactive mode
    if [ "$INTERACTIVE" != true ]; then
        return 0
    fi

    # Check if stdin is a terminal
    if [ ! -t 0 ]; then
        # Non-interactive, use default
        [ "$default" = "y" ] && return 0 || return 1
    fi

    read -p "$prompt " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

echo "========================================"
echo "  Lumen Installation Script for Linux"
echo "========================================"
echo ""

# Step 0: Install build dependencies
info "Checking build dependencies..."

install_build_deps() {
    if command_exists apt-get; then
        info "Installing build dependencies via apt..."
        sudo apt-get update
        sudo apt-get install -y pkg-config libssl-dev build-essential
    elif command_exists dnf; then
        info "Installing build dependencies via dnf..."
        sudo dnf install -y pkg-config openssl-devel gcc
    elif command_exists pacman; then
        info "Installing build dependencies via pacman..."
        sudo pacman -S --noconfirm pkg-config openssl base-devel
    elif command_exists apk; then
        info "Installing build dependencies via apk..."
        sudo apk add pkgconfig openssl-dev build-base
    else
        warn "Could not detect package manager. You may need to manually install:"
        echo "  - pkg-config"
        echo "  - OpenSSL development headers (libssl-dev / openssl-devel)"
        echo "  - C compiler (gcc/build-essential)"
    fi
}

# Check if pkg-config and OpenSSL dev headers are available
if ! command_exists pkg-config || ! pkg-config --exists openssl 2>/dev/null; then
    warn "Missing build dependencies (pkg-config and/or OpenSSL dev headers)"
    install_build_deps
    success "Build dependencies installed"
else
    success "Build dependencies already present"
fi

# Step 1: Ensure cargo is in PATH and install Rust if needed
info "Checking for Rust/Cargo..."

# Always ensure cargo bin is in PATH for this session
if [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Source cargo env if it exists
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

if command_exists cargo; then
    CARGO_VERSION=$(cargo --version)
    success "Cargo is already installed: $CARGO_VERSION"
else
    info "Cargo not found. Installing Rust via rustup..."

    info "Downloading and running rustup installer..."
    # Use --no-modify-path to avoid permission issues with shell profiles
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

    # Add cargo to PATH for this session
    export PATH="$HOME/.cargo/bin:$PATH"

    # Source cargo environment if it exists
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi

    if command_exists cargo; then
        success "Rust installed successfully: $(cargo --version)"
    else
        error "Failed to install Rust. Please install manually from https://rustup.rs"
    fi
fi

# Step 1.5: Ensure cargo PATH is in shell profile
setup_shell_path() {
    local CARGO_PATH_LINE='export PATH="$HOME/.cargo/bin:$PATH"'
    local shell_profile=""

    # Determine shell profile
    if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "$(which zsh)" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ] || [ "$SHELL" = "$(which bash)" ]; then
        shell_profile="$HOME/.bashrc"
    fi

    if [ -n "$shell_profile" ] && [ -f "$shell_profile" ]; then
        # Check if cargo path is already in profile
        if ! grep -q '.cargo/bin' "$shell_profile" 2>/dev/null; then
            info "Adding cargo to PATH in $shell_profile"
            echo "" >> "$shell_profile"
            echo "# Rust/Cargo" >> "$shell_profile"
            echo "$CARGO_PATH_LINE" >> "$shell_profile"
            success "Added cargo to $shell_profile"
        else
            success "Cargo PATH already configured in $shell_profile"
        fi
    else
        warn "Could not detect shell profile. Add this to your shell config:"
        echo "  $CARGO_PATH_LINE"
    fi
}

setup_shell_path

# Step 2: Install lumen
info "Installing lumen via cargo..."

if command_exists lumen; then
    CURRENT_VERSION=$(lumen --version 2>/dev/null || echo "unknown")
    warn "lumen is already installed: $CURRENT_VERSION"
    if prompt_yes_no "Do you want to reinstall/upgrade? [y/N]"; then
        cargo install lumen --force
        success "lumen reinstalled successfully"
    else
        info "Skipping lumen installation"
    fi
else
    cargo install lumen
    success "lumen installed successfully: $(lumen --version)"
fi

# Step 3: Install optional dependencies
echo ""
info "Checking optional dependencies..."

# Check for fzf
if [ "$SKIP_OPTIONAL" = true ]; then
    info "Skipping optional dependencies (--skip-optional)"
else
    if command_exists fzf; then
        success "fzf is already installed (for 'lumen explain --list')"
    else
        warn "fzf not found (optional - enables 'lumen explain --list')"
        if prompt_yes_no "Install fzf? [y/N]"; then
            if command_exists apt-get; then
                sudo apt-get update && sudo apt-get install -y fzf
            elif command_exists dnf; then
                sudo dnf install -y fzf
            elif command_exists pacman; then
                sudo pacman -S --noconfirm fzf
            elif command_exists brew; then
                brew install fzf
            else
                warn "Could not detect package manager. Install fzf manually."
            fi
        fi
    fi

    # Check for mdcat (optional for markdown rendering)
    if command_exists mdcat; then
        success "mdcat is already installed (for formatted markdown output)"
    else
        warn "mdcat not found (optional - enables formatted markdown output)"
        if prompt_yes_no "Install mdcat? [y/N]"; then
            cargo install mdcat
            success "mdcat installed successfully"
        fi
    fi
fi

# Step 4: Configuration
echo ""
info "Configuration options..."

CONFIG_DIR="$HOME/.config/lumen"
CONFIG_FILE="$CONFIG_DIR/lumen.config.json"

# Function to write config file
write_config() {
    local provider="$1"
    local model="$2"
    local api_key="$3"

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
{
  "provider": "$provider",
  "model": "$model",
  "api_key": "$api_key"
}
EOF
    success "Configuration written to $CONFIG_FILE"
}

# Function to get API key based on provider
get_api_key() {
    local provider="$1"
    local key=""

    # Check provider-specific env vars first
    case "$provider" in
        claude)
            key="${ANTHROPIC_API_KEY:-}"
            ;;
        openai)
            key="${OPENAI_API_KEY:-}"
            ;;
        groq)
            key="${GROQ_API_KEY:-}"
            ;;
        gemini)
            key="${GOOGLE_API_KEY:-${GEMINI_API_KEY:-}}"
            ;;
    esac

    # Fall back to LUMEN_API_KEY
    if [ -z "$key" ]; then
        key="${LUMEN_API_KEY:-}"
    fi

    echo "$key"
}

# If provider and model are specified, write config directly
if [ -n "$PROVIDER" ] && [ -n "$MODEL" ]; then
    API_KEY=$(get_api_key "$PROVIDER")
    if [ -z "$API_KEY" ]; then
        warn "No API key found for provider '$PROVIDER'"
        echo "Set one of these environment variables:"
        case "$PROVIDER" in
            claude)
                echo "  export ANTHROPIC_API_KEY=\"your-key\""
                ;;
            openai)
                echo "  export OPENAI_API_KEY=\"your-key\""
                ;;
            *)
                echo "  export LUMEN_API_KEY=\"your-key\""
                ;;
        esac
        # Still write config without API key - user can add it later
        write_config "$PROVIDER" "$MODEL" ""
    else
        write_config "$PROVIDER" "$MODEL" "$API_KEY"
    fi
elif [ "$INTERACTIVE" = true ]; then
    if [ -f "$CONFIG_FILE" ]; then
        success "Existing configuration found at $CONFIG_FILE"
        if prompt_yes_no "Do you want to reconfigure? [y/N]" "n"; then
            lumen configure
        fi
    else
        echo ""
        echo "lumen requires an AI provider for commit generation features."
        echo ""
        echo "Supported providers:"
        echo "  - OpenAI (gpt-4o, gpt-4o-mini, etc.)"
        echo "  - Anthropic (claude-3-5-sonnet, etc.)"
        echo "  - Ollama (local models)"
        echo "  - Google Gemini"
        echo "  - And more..."
        echo ""

        if prompt_yes_no "Configure lumen now? [Y/n]" "y"; then
            lumen configure
        else
            info "You can configure later with: lumen configure"
        fi
    fi
else
    info "Skipping configuration (use --provider and --model, or --interactive)"
    info "Configure later with: lumen configure"
fi

# Step 5: Verify installation
echo ""
echo "========================================"
info "Verifying installation..."
echo "========================================"

if command_exists lumen; then
    echo ""
    success "lumen is ready to use!"
    echo ""
    echo "Quick commands:"
    echo "  lumen draft           - Generate commit message from staged changes"
    echo "  lumen draft -c \"...\"  - Generate with context"
    echo "  lumen explain         - Explain recent changes"
    echo "  lumen diff            - Visual diff viewer"
    echo "  lumen operate \"...\"   - Get git commands from description"
    echo ""
    echo "For more info: https://github.com/jnsahaj/lumen"
else
    error "lumen installation verification failed"
fi
echo "========================================"
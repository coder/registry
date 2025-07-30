#!/usr/bin/env bash

BOLD='\033[0;1m'

# Convert templated variables to shell variables
SAVE_INTERVAL="${SAVE_INTERVAL}"
TMUX_CONFIG="${TMUX_CONFIG}"

# Function to install tmux
install_tmux() {
    printf "Checking for tmux installation\n"

    if command -v tmux &> /dev/null; then
        printf "tmux is already installed \n\n"
        return 0
    fi

    printf "Installing tmux \n\n"

    # Detect package manager and install tmux
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y tmux
    elif command -v yum &> /dev/null; then
        sudo yum install -y tmux
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y tmux
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y tmux
    elif command -v apk &> /dev/null; then
        sudo apk add tmux
    elif command -v brew &> /dev/null; then
        brew install tmux
    else
        printf "No supported package manager found. Please install tmux manually. \n"
        exit 1
    fi

    printf "tmux installed successfully \n"
}

# Function to install Tmux Plugin Manager (TPM)
install_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"

    if [ -d "$tpm_dir" ]; then
        printf "TPM is already installed"
        return 0
    fi

    printf "Installing Tmux Plugin Manager (TPM) \n"

    # Create plugins directory
    mkdir -p "$HOME/.tmux/plugins"

    # Clone TPM repository
    if command -v git &> /dev/null; then
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
        printf "TPM installed successfully"
    else
        printf "Git is not installed. Please install git to use tmux plugins. \n"
        exit 1
    fi
}

# Function to create tmux configuration
setup_tmux_config() {
    printf "Setting up tmux configuration \n"

    local config_dir="$HOME/.tmux"
    local config_file="$HOME/.tmux.conf"

    mkdir -p "$config_dir"

    if [ -n "$TMUX_CONFIG" ]; then
        printf "$TMUX_CONFIG" > "$config_file"
        printf "$${BOLD}Custom tmux configuration applied at {$config_file} \n\n"
    else
        cat > "$config_file" << EOF
# Tmux Configuration File

# =============================================================================
# PLUGIN CONFIGURATION
# =============================================================================

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# tmux-continuum configuration
set -g @continuum-restore 'on'
set -g @continuum-save-interval '$${SAVE_INTERVAL}'
set -g @continuum-boot 'on'
set -g status-right 'Continuum status: #{continuum_status}'

# =============================================================================
# KEY BINDINGS FOR SESSION MANAGEMENT
# =============================================================================

# Quick session save and restore
bind C-s run-shell "~/.tmux/plugins/tmux-resurrect/scripts/save.sh"
bind C-r run-shell "~/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
EOF
        printf "tmux configuration created at {$config_file} \n\n"
    fi
}

# Function to install tmux plugins
install_plugins() {
    printf "Installing tmux plugins"

    # Check if TPM is installed
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        printf "TPM is not installed. Cannot install plugins. \n"
        return 1
    fi

    # Install plugins using TPM
    "$HOME/.tmux/plugins/tpm/bin/install_plugins"

    printf "tmux plugins installed successfully \n"
}

# Main execution
main() {
    printf "$${BOLD} 🛠️Setting up tmux with session persistence! \n\n"
    printf ""

    # Install dependencies
    install_tmux
    install_tpm

    # Setup tmux configuration
    setup_tmux_config

    # Install plugins
    install_plugins

    printf "$${BOLD}✅ tmux setup complete! \n\n"

    printf "$${BOLD} Attempting to restore sessions\n"
    tmux new-session -d \; source-file ~/.tmux.conf \; run-shell '~/.tmux/plugins/tmux-resurrect/scripts/restore.sh'
    printf "$${BOLD} Sessions restored: -> %s\n" "$(tmux ls)"

}

# Run main function
main
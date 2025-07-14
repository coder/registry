#!/usr/bin/env bash

# Convert templated variables to shell variables
SESSION_NAME="${SESSION_NAME}"
STARTUP_COMMAND="${STARTUP_COMMAND}"
SAVE_INTERVAL="${SAVE_INTERVAL}"
TMUX_CONFIG="${TMUX_CONFIG}"

# Function to install tmux
install_tmux() {
    print_info "Checking for tmux installation..."

    if command -v tmux &> /dev/null; then
        print_info "tmux is already installed"
        return 0
    fi

    print_info "Installing tmux..."

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
        print_error "No supported package manager found. Please install tmux manually."
        exit 1
    fi

    print_info "tmux installed successfully"
}

# Function to install Tmux Plugin Manager (TPM)
install_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"

    if [ -d "$tpm_dir" ]; then
        print_info "TPM is already installed"
        return 0
    fi

    print_info "Installing Tmux Plugin Manager (TPM)..."

    # Create plugins directory
    mkdir -p "$HOME/.tmux/plugins"

    # Clone TPM repository
    if command -v git &> /dev/null; then
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
        print_info "TPM installed successfully"
    else
        print_error "Git is not installed. Please install git to use tmux plugins."
        exit 1
    fi
}

# Function to create tmux configuration
setup_tmux_config() {
    print_info "Setting up tmux configuration..."

    local config_dir="$HOME/.tmux"
    local config_file="$HOME/.tmux.conf"

    mkdir -p "$config_dir"

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

    print_info "tmux configuration created at $config_file"
}

# Function to install tmux plugins
install_plugins() {
    print_info "Installing tmux plugins..."

    # Check if TPM is installed
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        print_error "TPM is not installed. Cannot install plugins."
        return 1
    fi

    # Install plugins using TPM
    "$HOME/.tmux/plugins/tpm/bin/install_plugins"

    print_info "tmux plugins installed successfully"
}

# Function to start tmux session
start_tmux_session() {
    print_info "Setting up tmux session..."

    # Check if session already exists
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        print_warning "Session '$SESSION_NAME' already exists"
        return 0
    fi

    # Create new session
    if [ -n "$STARTUP_COMMAND" ]; then
        print_info "Creating tmux session '$SESSION_NAME' with startup command"
        tmux new-session -d -s "$SESSION_NAME" "$STARTUP_COMMAND"
    else
        print_info "Creating tmux session '$SESSION_NAME'"
        tmux new-session -d -s "$SESSION_NAME"
    fi

    print_info "tmux session '$SESSION_NAME' created successfully"
}

# Function to display usage information
show_usage_info() {
    echo -e "$${BOLD}✅ tmux setup complete!$${RESET}"
    echo ""
    echo -e "$${BOLD}📋 Quick reference:$${RESET}"
    echo "  • Attach to session: tmux attach -t $${SESSION_NAME}"
    echo "  • Detach from session: Ctrl+a, then d"
    echo "  • List sessions: tmux list-sessions"
    echo "  • Kill session: tmux kill-session -t $${SESSION_NAME}"
    echo ""
    echo -e "$${BOLD}🔄 Session persistence:$${RESET}"
    echo "  • Auto-save interval: every $${SAVE_INTERVAL} minutes"
    echo "  • Manual save: Ctrl+a, then Ctrl+s"
    echo "  • Manual restore: Ctrl+a, then Ctrl+r"
    echo "  • Sessions automatically restore on boot"
    echo ""
    echo -e "$${BOLD}🔌 Plugin management:$${RESET}"
    echo "  • Install plugins: Ctrl+a, then I"
    echo "  • Update plugins: Ctrl+a, then U"
    echo "  • Uninstall plugins: Ctrl+a, then alt+u"
    echo ""
}

# Main execution
main() {
    echo -e "$${BOLD}Setting up tmux with session persistence...$${RESET}"
    echo ""

    # Install dependencies
    install_tmux
    install_tpm

    # Setup tmux configuration
    setup_tmux_config

    # Install plugins
    install_plugins

    # Start tmux session
    start_tmux_session

    # Show usage information
    show_usage_info
}

# Run main function
main
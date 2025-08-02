#!/usr/bin/env bash

set -euo pipefail

# Template variables from Terraform
TOOLS=(${join(" ", TOOLS)})
LOG_PATH="${LOG_PATH}"
USER="${USER}"

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Function to log with timestamp
log() {
    echo "[$$(date '+%Y-%m-%d %H:%M:%S')] $$1" | tee -a "$$LOG_PATH"
}

# Function to install a tool
install_tool() {
    local tool="$$1"
    
    echo -e "$${BOLD}🔧 Installing $$tool...$${RESET}"
    log "Starting installation of $$tool"
    
    case "$$tool" in
        "git")
            if command -v git >/dev/null 2>&1; then
                echo -e "  $${GREEN}✅ Git already installed: $$(git --version)$${RESET}"
                log "Git already installed: $$(git --version)"
            else
                sudo apt-get update -qq
                sudo apt-get install -y git
                # Add git completion
                curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash > "/home/$$USER/.git-completion.bash" || true
                echo 'source ~/.git-completion.bash' >> "/home/$$USER/.bashrc" || true
                echo -e "  $${GREEN}✅ Git installed successfully$${RESET}"
                log "Git installed successfully"
            fi
            ;;
        "docker")
            if command -v docker >/dev/null 2>&1; then
                echo -e "  $${GREEN}✅ Docker already installed: $$(docker --version)$${RESET}"
                log "Docker already installed: $$(docker --version)"
            else
                curl -fsSL https://get.docker.com | sh
                sudo usermod -aG docker "$$USER"
                echo -e "  $${GREEN}✅ Docker installed successfully$${RESET}"
                echo -e "  $${YELLOW}⚠️  Please restart your workspace for Docker group membership to take effect$${RESET}"
                log "Docker installed successfully"
            fi
            ;;
        "nodejs")
            if command -v node >/dev/null 2>&1; then
                echo -e "  $${GREEN}✅ Node.js already installed: $$(node --version)$${RESET}"
                log "Node.js already installed: $$(node --version)"
            else
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                sudo apt-get install -y nodejs
                echo -e "  $${GREEN}✅ Node.js installed successfully: $$(node --version)$${RESET}"
                log "Node.js installed successfully: $$(node --version)"
            fi
            ;;
        "python")
            if command -v python3 >/dev/null 2>&1; then
                echo -e "  $${GREEN}✅ Python already installed: $$(python3 --version)$${RESET}"
                log "Python already installed: $$(python3 --version)"
            else
                sudo apt-get update -qq
                sudo apt-get install -y python3 python3-pip python3-venv python3-dev
                echo -e "  $${GREEN}✅ Python installed successfully: $$(python3 --version)$${RESET}"
                log "Python installed successfully: $$(python3 --version)"
            fi
            ;;
        "golang")
            if command -v go >/dev/null 2>&1; then
                echo -e "  $${GREEN}✅ Go already installed: $$(go version)$${RESET}"
                log "Go already installed: $$(go version)"
            else
                # Install Go via official method
                GO_VERSION="$$(curl -s https://go.dev/VERSION?m=text)"
                cd /tmp
                wget -q "https://go.dev/dl/$${GO_VERSION}.linux-amd64.tar.gz"
                sudo rm -rf /usr/local/go
                sudo tar -C /usr/local -xzf "$${GO_VERSION}.linux-amd64.tar.gz"
                echo 'export PATH=$$PATH:/usr/local/go/bin' >> "/home/$$USER/.bashrc"
                export PATH=$$PATH:/usr/local/go/bin
                echo -e "  $${GREEN}✅ Go installed successfully: $$(/usr/local/go/bin/go version)$${RESET}"
                log "Go installed successfully: $$(/usr/local/go/bin/go version)"
            fi
            ;;
        *)
            echo -e "  $${YELLOW}⚠️  Unknown tool: $$tool$${RESET}"
            log "Unknown tool: $$tool"
            ;;
    esac
    echo
}

# Main installation process
echo -e "$${BOLD}🚀 Development Tools Installation$${RESET}"
echo -e "Installing tools: $${TOOLS[*]}"
echo -e "Log file: $${BLUE}$$LOG_PATH$${RESET}"
echo

log "Starting development tools installation"
log "Tools to install: $${TOOLS[*]}"
log "User: $$USER"

# Update package list once
echo -e "$${BOLD}📦 Updating package list...$${RESET}"
sudo apt-get update -qq

# Install each tool
for tool in "$${TOOLS[@]}"; do
    install_tool "$$tool"
done

echo -e "$${GREEN}✨ All development tools installation complete!$${RESET}"
echo -e "$${BLUE}📋 Installed tools summary:$${RESET}"

# Show installed versions
for tool in "$${TOOLS[@]}"; do
    case "$$tool" in
        "git")
            command -v git >/dev/null 2>&1 && echo -e "  • Git: $$(git --version)" || echo -e "  • Git: Not installed"
            ;;
        "docker")
            command -v docker >/dev/null 2>&1 && echo -e "  • Docker: $$(docker --version)" || echo -e "  • Docker: Not installed"
            ;;
        "nodejs")
            command -v node >/dev/null 2>&1 && echo -e "  • Node.js: $$(node --version)" || echo -e "  • Node.js: Not installed"
            command -v npm >/dev/null 2>&1 && echo -e "  • npm: $$(npm --version)" || echo -e "  • npm: Not installed"
            ;;
        "python")
            command -v python3 >/dev/null 2>&1 && echo -e "  • Python: $$(python3 --version)" || echo -e "  • Python: Not installed"
            command -v pip3 >/dev/null 2>&1 && echo -e "  • pip: $$(pip3 --version)" || echo -e "  • pip: Not installed"
            ;;
        "golang")
            command -v go >/dev/null 2>&1 && echo -e "  • Go: $$(go version)" || echo -e "  • Go: Not installed"
            ;;
    esac
done

echo
echo -e "$${YELLOW}📄 Installation log: $$LOG_PATH$${RESET}"
log "Development tools installation completed successfully"
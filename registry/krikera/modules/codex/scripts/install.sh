#!/bin/bash
set -o errexit
set -o pipefail

# Template variables
CODEX_VERSION="${CODEX_VERSION}"
INSTALL_CODEX="${INSTALL_CODEX}"

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "$${BOLD}🦀 Installing Rust-based OpenAI Codex CLI...\n\n$${NC}"

# Skip installation if not requested
if [ "$INSTALL_CODEX" != "true" ]; then
    printf "$${YELLOW}⚠️  Codex installation skipped (install_codex = false)$${NC}\n"
    exit 0
fi

# For testing purposes, check if we should use a mock CLI
if [ -n "$CODEX_TEST_MODE" ] && [ "$CODEX_TEST_MODE" = "true" ]; then
    printf "$${YELLOW}🧪 Test mode detected, using mock Codex CLI$${NC}\n"
    
    # Create mock codex-cli
    mkdir -p "$HOME/.local/bin"
    
    # Use the mock script from testdata if available
    if [ -f "$(dirname "$0")/../testdata/mock-codex-cli.sh" ]; then
        cp "$(dirname "$0")/../testdata/mock-codex-cli.sh" "$HOME/.local/bin/codex-cli"
    else
        # Fallback mock script
        cat > "$HOME/.local/bin/codex-cli" << 'MOCK_EOF'
#!/bin/bash
case "$1" in
    --version) echo "codex-cli version 1.0.0 (mock)"; exit 0 ;;
    *) echo "Mock Codex CLI: $*"; exit 0 ;;
esac
MOCK_EOF
    fi
    
    chmod +x "$HOME/.local/bin/codex-cli"
    
    # Make sure ~/.local/bin is in PATH
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    printf "$${GREEN}✅ Mock Codex CLI installed successfully!$${NC}\n"
    printf "$${GREEN}🎉 Test mode installation complete!$${NC}\n"
    exit 0
fi

# Check if Rust is installed, install if not
if ! command -v rustc &> /dev/null; then
    printf "$${YELLOW}📦 Rust not found, installing Rust...$${NC}\n"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    printf "$${GREEN}✅ Rust installed successfully$${NC}\n\n"
else
    printf "$${GREEN}✅ Rust already installed$${NC}\n\n"
fi

# Ensure we have the latest stable Rust
rustup update stable
rustup default stable

# Install required system dependencies
printf "$${BOLD}📦 Installing system dependencies...$${NC}\n"
if command -v apt-get &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        build-essential \
        pkg-config \
        libssl-dev \
        libclang-dev \
        curl \
        git \
        ca-certificates
elif command -v yum &> /dev/null; then
    sudo yum install -y \
        gcc \
        gcc-c++ \
        make \
        pkgconfig \
        openssl-devel \
        clang-devel \
        curl \
        git \
        ca-certificates
elif command -v apk &> /dev/null; then
    sudo apk add --no-cache \
        build-base \
        pkgconfig \
        openssl-dev \
        clang-dev \
        curl \
        git \
        ca-certificates
else
    printf "$${RED}❌ Unsupported package manager. Please install build dependencies manually.$${NC}\n"
    exit 1
fi

printf "$${GREEN}✅ System dependencies installed$${NC}\n\n"

# Create codex directory
CODEX_DIR="$HOME/.local/share/codex"
mkdir -p "$CODEX_DIR"
cd "$CODEX_DIR"

# Clone or update the Codex CLI repository
CODEX_REPO="https://github.com/krikera/codex-cli.git"
if [ -d "codex-cli" ]; then
    printf "$${BOLD}🔄 Updating existing Codex CLI...$${NC}\n"
    cd codex-cli
    git fetch origin
    if [ "$CODEX_VERSION" = "latest" ]; then
        git checkout main
        git pull origin main
    else
        git checkout "v$CODEX_VERSION"
    fi
else
    printf "$${BOLD}📥 Cloning Codex CLI repository...$${NC}\n"
    if [ "$CODEX_VERSION" = "latest" ]; then
        git clone "$CODEX_REPO" codex-cli
    else
        git clone --branch "v$CODEX_VERSION" "$CODEX_REPO" codex-cli
    fi
    cd codex-cli
fi

# Build the Rust project
printf "$${BOLD}🔨 Building Codex CLI (this may take a few minutes)...$${NC}\n"
cargo build --release

# Install the binary
printf "$${BOLD}📦 Installing Codex CLI...$${NC}\n"
mkdir -p "$HOME/.local/bin"
cp target/release/codex-cli "$HOME/.local/bin/"

# Make sure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
fi

# Create configuration directory
mkdir -p "$HOME/.config/codex"

# Create default configuration file
cat > "$HOME/.config/codex/config.toml" << EOF
[openai]
model = "gpt-4"
temperature = 0.2
max_tokens = 2048

[codex]
auto_save = true
show_thinking = true
verbose = false

[ui]
theme = "dark"
highlight_syntax = true
EOF

printf "$${GREEN}✅ Codex CLI installed successfully!$${NC}\n\n"

# Verify installation
if command -v codex-cli &> /dev/null; then
    printf "$${GREEN}🎉 Installation verification successful!$${NC}\n"
    printf "$${BOLD}📍 Codex CLI version: $${NC}"
    codex-cli --version
    printf "\n$${BOLD}📁 Configuration directory: $${NC}$HOME/.config/codex\n"
    printf "$${BOLD}🔧 Binary location: $${NC}$HOME/.local/bin/codex-cli\n\n"
else
    printf "$${RED}❌ Installation verification failed. Please check the installation.$${NC}\n"
    exit 1
fi

printf "$${GREEN}🚀 Codex CLI is ready to use!$${NC}\n"
printf "$${BOLD}💡 Usage examples:$${NC}\n"
printf "  • $${YELLOW}codex-cli generate 'create a fibonacci function in Python'$${NC}\n"
printf "  • $${YELLOW}codex-cli complete 'def fibonacci(n):'$${NC}\n"
printf "  • $${YELLOW}codex-cli explain 'explain this code: def fib(n): return n if n <= 1 else fib(n-1) + fib(n-2)'$${NC}\n"
printf "  • $${YELLOW}codex-cli interactive$${NC}\n\n"

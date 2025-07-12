#!/usr/bin/env bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Convert templated variables to shell variables
INSTALLATION_METHOD=${INSTALLATION_METHOD}
ENABLE_HARDWARE_ACCELERATION=${ENABLE_HARDWARE_ACCELERATION}

# Colors for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root for security reasons"
    exit 1
fi

# Check if Parsec is already installed
if command -v parsec &> /dev/null; then
    log_info "Parsec is already installed, skipping installation"
    exit 0
fi

printf "${BOLD}🎮 Installing Parsec for Low-Latency Remote Desktop Access...${NC}\n\n"

# Function to detect the Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Function to install system dependencies
install_dependencies() {
    local distro=$1
    
    case $distro in
        ubuntu|debian|kali)
            log_info "Installing dependencies for Ubuntu/Debian..."
            if ! command -v sudo &> /dev/null; then
                log_error "sudo is required but not installed"
                exit 1
            fi
            
            # Update package lists
            sudo apt-get update -qq
            
            # Install basic dependencies
            sudo apt-get install -y curl wget ca-certificates
            
            # Install multimedia dependencies
            if [[ "$ENABLE_HARDWARE_ACCELERATION" == "true" ]]; then
                log_info "Installing hardware acceleration dependencies..."
                sudo apt-get install -y \
                    libva2 \
                    libva-drm2 \
                    libva-x11-2 \
                    libvdpau1 \
                    mesa-va-drivers \
                    mesa-vdpau-drivers \
                    intel-media-va-driver-non-free 2>/dev/null || \
                    sudo apt-get install -y intel-media-va-driver || true
            fi
            
            # Install audio dependencies
            sudo apt-get install -y \
                pulseaudio \
                pulseaudio-utils \
                alsa-utils \
                libasound2-dev || true
            ;;
        arch|manjaro)
            log_info "Installing dependencies for Arch Linux..."
            if command -v pacman &> /dev/null; then
                sudo pacman -Syu --noconfirm
                sudo pacman -S --noconfirm curl wget ca-certificates
                
                if [[ "$ENABLE_HARDWARE_ACCELERATION" == "true" ]]; then
                    log_info "Installing hardware acceleration dependencies..."
                    sudo pacman -S --noconfirm \
                        libva \
                        libva-mesa-driver \
                        libvdpau \
                        mesa-vdpau \
                        intel-media-driver || true
                fi
                
                # Install audio dependencies
                sudo pacman -S --noconfirm \
                    pulseaudio \
                    pulseaudio-alsa \
                    alsa-utils || true
            fi
            ;;
        fedora|rhel|centos)
            log_info "Installing dependencies for Red Hat/Fedora..."
            if command -v dnf &> /dev/null; then
                sudo dnf update -y
                sudo dnf install -y curl wget ca-certificates
                
                if [[ "$ENABLE_HARDWARE_ACCELERATION" == "true" ]]; then
                    log_info "Installing hardware acceleration dependencies..."
                    sudo dnf install -y \
                        libva \
                        libva-utils \
                        libvdpau \
                        mesa-va-drivers \
                        mesa-vdpau-drivers || true
                fi
                
                # Install audio dependencies
                sudo dnf install -y \
                    pulseaudio \
                    pulseaudio-utils \
                    alsa-utils || true
            fi
            ;;
        *)
            log_warn "Unknown distribution: $distro. Attempting generic installation..."
            ;;
    esac
}

# Function to install Parsec via DEB package
install_parsec_deb() {
    log_info "Installing Parsec via DEB package..."
    
    local temp_dir=$(mktemp -d)
    local deb_file="$temp_dir/parsec-linux.deb"
    
    # Download the DEB package
    log_info "Downloading Parsec DEB package..."
    if ! curl -L "https://builds.parsec.app/package/parsec-linux.deb" -o "$deb_file"; then
        log_error "Failed to download Parsec DEB package"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Install the DEB package
    log_info "Installing Parsec DEB package..."
    if ! sudo dpkg -i "$deb_file"; then
        log_info "Fixing broken dependencies..."
        sudo apt-get install -f -y
        sudo dpkg -i "$deb_file"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    return 0
}

# Function to install Parsec via AppImage
install_parsec_appimage() {
    log_info "Installing Parsec via AppImage..."
    
    local app_dir="$HOME/.local/share/parsec"
    local app_file="$app_dir/Parsec.AppImage"
    
    # Create application directory
    mkdir -p "$app_dir"
    
    # Download the AppImage
    log_info "Downloading Parsec AppImage..."
    if ! curl -L "https://builds.parsec.app/package/parsec-linux.AppImage" -o "$app_file"; then
        log_error "Failed to download Parsec AppImage"
        return 1
    fi
    
    # Make it executable
    chmod +x "$app_file"
    
    # Create a wrapper script in PATH
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    
    cat > "$bin_dir/parsec" << 'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/share/parsec/Parsec.AppImage" "$@"
EOF
    
    chmod +x "$bin_dir/parsec"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
    fi
    
    return 0
}

# Function to install Parsec via AUR (Arch Linux)
install_parsec_aur() {
    log_info "Installing Parsec via AUR..."
    
    # Check if an AUR helper is available
    if command -v yay &> /dev/null; then
        yay -S --noconfirm parsec-bin
    elif command -v paru &> /dev/null; then
        paru -S --noconfirm parsec-bin
    else
        log_warn "No AUR helper found. Falling back to AppImage installation..."
        install_parsec_appimage
    fi
}

# Main installation logic
main() {
    local distro=$(detect_distro)
    log_info "Detected distribution: $distro"
    
    # Install system dependencies
    install_dependencies "$distro"
    
    # Determine installation method
    local method="$INSTALLATION_METHOD"
    if [[ "$method" == "auto" ]]; then
        case $distro in
            ubuntu|debian|kali)
                method="deb"
                ;;
            arch|manjaro)
                method="aur"
                ;;
            *)
                method="appimage"
                ;;
        esac
    fi
    
    log_info "Using installation method: $method"
    
    # Install Parsec
    case $method in
        deb)
            install_parsec_deb
            ;;
        appimage)
            install_parsec_appimage
            ;;
        aur)
            install_parsec_aur
            ;;
        *)
            log_error "Unknown installation method: $method"
            exit 1
            ;;
    esac
    
    # Verify installation
    if command -v parsec &> /dev/null; then
        log_info "✅ Parsec installed successfully!"
        log_info "🎯 You can now use Parsec for low-latency remote desktop access"
        log_info "🔧 To get started, run 'parsec' or look for Parsec in your applications menu"
        
        if [[ "$ENABLE_HARDWARE_ACCELERATION" == "true" ]]; then
            log_info "🚀 Hardware acceleration is enabled for optimal performance"
        fi
    else
        log_error "❌ Parsec installation verification failed"
        exit 1
    fi
}

# Run main function
main "$@"

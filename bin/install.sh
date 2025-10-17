#!/usr/bin/env bash

set -e

# mqv installation script

readonly MQV_REPO="harehare/mqv"
readonly MQV_INSTALL_DIR="$HOME/.mqv"
readonly MQV_BIN_DIR="$MQV_INSTALL_DIR/bin"


# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Utility functions
log() {
    echo -e "${GREEN}ℹ${NC}  $*" >&2
}

warn() {
    echo -e "${YELLOW}⚠${NC}  $*" >&2
}

error() {
    echo -e "${RED}✗${NC}  $*" >&2
    exit 1
}

# Display the mqv logo
show_logo() {
    cat << 'EOF'

    ███╗   ███╗ ██████╗  ██╗   ██╗
    ████╗ ████║██╔═══██╗ ██║   ██║
    ██╔████╔██║██║   ██║ ██║   ██║
    ██║╚██╔╝██║██║▄▄ ██║ ╚██╗ ██╔╝
    ██║ ╚═╝ ██║╚██████╔╝  ╚████╔╝
    ╚═╝     ╚═╝ ╚══▀▀═╝    ╚═══╝

EOF
    echo -e "${BOLD}${CYAN}  Markdown Renderer with Syntax Highlighting${NC}"
    echo -e "${BLUE}  mqv renders Markdown with rich text formatting${NC}"
    echo -e "${BLUE}  and tree-sitter powered syntax highlighting${NC}"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Detect the operating system
detect_os() {
    case "$(uname -s)" in
        Linux*)
            echo "linux"
            ;;
        Darwin*)
            echo "darwin"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

# Detect the architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            ;;
    esac
}

# Get the latest release version from GitHub
get_latest_version() {
    local version
    version=$(curl -s "https://api.github.com/repos/$MQV_REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$version" ]]; then
        error "Failed to get the latest version"
    fi

    echo "$version"
}

# Construct the download URL for the binary
get_download_url() {
    local version="$1"
    local os="$2"
    local arch="$3"
    local ext=""

    if [[ "$os" == "windows" ]]; then
        ext=".exe"
        target="${arch}-pc-windows-msvc"
    elif [[ "$os" == "darwin" ]]; then
        target="${arch}-apple-darwin"
    else
        target="${arch}-unknown-linux-gnu"
    fi

    echo "https://github.com/$MQV_REPO/releases/download/$version/mqv-${target}${ext}"
}

# Download checksums file
download_checksums() {
    local version="$1"
    local checksums_url="https://github.com/$MQV_REPO/releases/download/$version/checksums.txt"
    local checksums_file
    checksums_file=$(mktemp)

    log "Downloading checksums file..."
    if ! curl -L --progress-bar "$checksums_url" -o "$checksums_file"; then
        warn "Failed to download checksums file, skipping verification"
        return 1
    fi

    echo "$checksums_file"
}

# Verify binary checksum
verify_checksum() {
    local binary_file="$1"
    local checksums_file="$2"
    local binary_name="$3"

    if [[ ! -f "$checksums_file" ]]; then
        warn "Checksums file not available"
        return 1
    fi

    log "Verifying checksum for $binary_name..."

    # Calculate the SHA256 of the downloaded binary
    local calculated_checksum
    if command -v sha256sum &> /dev/null; then
        calculated_checksum=$(sha256sum "$binary_file" | cut -d' ' -f1)
    elif command -v shasum &> /dev/null; then
        calculated_checksum=$(shasum -a 256 "$binary_file" | cut -d' ' -f1)
    else
        warn "No SHA256 utility found"
        return 1
    fi

    # Find the expected checksum from the checksums file
    local expected_checksum
    expected_checksum=$(grep "$binary_name/$binary_name" "$checksums_file" | cut -d' ' -f1)

    if [[ -z "$expected_checksum" ]]; then
        warn "No checksum found for $binary_name"
        return 1
    fi

    # Compare checksums
    if [[ "$calculated_checksum" == "$expected_checksum" ]]; then
        log "✓ Checksum verification successful"
        return 0
    else
        echo -e "${RED}✗${NC}  Checksum verification failed" >&2
        echo -e "${RED}Expected: $expected_checksum${NC}" >&2
        echo -e "${RED}Got:      $calculated_checksum${NC}" >&2
        return 1
    fi
}

# Download and install mqv
install_mqv() {
    local version="$1"
    local os="$2"
    local arch="$3"
    local download_url
    local binary_name="mqv"
    local ext=""
    local target=""

    if [[ "$os" == "windows" ]]; then
        ext=".exe"
        binary_name="mqv.exe"
        target="${arch}-pc-windows-msvc"
    elif [[ "$os" == "darwin" ]]; then
        target="${arch}-apple-darwin"
    else
        target="${arch}-unknown-linux-gnu"
    fi

    download_url=$(get_download_url "$version" "$os" "$arch")

    log "Downloading mqv $version for $os/$arch..."
    log "Download URL: $download_url"

    # Download checksums file
    local checksums_file
    checksums_file=$(download_checksums "$version")

    # Create installation directory
    mkdir -p "$MQV_BIN_DIR"

    # Download the binary
    local temp_file
    temp_file=$(mktemp)

    if ! curl -L --progress-bar "$download_url" -o "$temp_file"; then
        error "Failed to download mqv binary"
    fi

    # Verify checksum
    local release_binary_name="mqv-${target}${ext}"
    if [[ -n "$checksums_file" && -f "$checksums_file" ]]; then
        if ! verify_checksum "$temp_file" "$checksums_file" "$release_binary_name"; then
            rm -f "$checksums_file"
            rm -f "$temp_file"
            error "Checksum verification failed, aborting installation"
        fi
        rm -f "$checksums_file"
    else
        error "Checksums file not available"
    fi

    # Move and make executable
    mv "$temp_file" "$MQV_BIN_DIR/$binary_name"
    chmod +x "$MQV_BIN_DIR/$binary_name"

    log "mqv installed successfully to $MQV_BIN_DIR/$binary_name"
}

# Add mqv to PATH by updating shell profile
update_shell_profile() {
    local shell_profile=""
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                shell_profile="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                shell_profile="$HOME/.bash_profile"
            fi
            ;;
        zsh)
            if [[ -f "$HOME/.zshrc" ]]; then
                shell_profile="$HOME/.zshrc"
            fi
            ;;
        fish)
            if [[ -d "$HOME/.config/fish" ]]; then
                shell_profile="$HOME/.config/fish/config.fish"
                mkdir -p "$(dirname "$shell_profile")"
            fi
            ;;
    esac

    if [[ -n "$shell_profile" ]]; then
        local path_export
        if [[ "$shell_name" == "fish" ]]; then
            path_export="set -gx PATH \$PATH $MQV_BIN_DIR"
        else
            path_export="export PATH=\"\$PATH:$MQV_BIN_DIR\""
        fi

        if ! grep -q "$MQV_BIN_DIR" "$shell_profile" 2>/dev/null; then
            echo "" >> "$shell_profile"
            echo "# Added by mqv installer" >> "$shell_profile"
            echo "$path_export" >> "$shell_profile"
            log "Added $MQV_BIN_DIR to PATH in $shell_profile"
        else
            warn "$MQV_BIN_DIR already exists in $shell_profile"
        fi
    else
        warn "Could not detect shell profile to update"
        warn "Please manually add $MQV_BIN_DIR to your PATH"
    fi
}

# Verify installation
verify_installation() {
    # Check mqv installation
    if [[ -x "$MQV_BIN_DIR/mqv" ]] || [[ -x "$MQV_BIN_DIR/mqv.exe" ]]; then
        log "✓ mqv installation verified"
        log "Installation verification successful!"
        return 0
    else
        error "mqv installation verification failed"
    fi
}

# Show post-installation instructions
show_post_install() {
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}✨ mqv installed successfully! ✨${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}🚀 Getting Started:${NC}"
    echo ""
    echo -e "  ${YELLOW}1.${NC} Restart your terminal or run:"
    echo -e "     ${CYAN}source ~/.bashrc${NC} ${BLUE}(or your shell's profile)${NC}"
    echo ""
    echo -e "  ${YELLOW}2.${NC} Verify the installation:"
    echo -e "     ${CYAN}mqv --version${NC}"
    echo ""
    echo -e "  ${YELLOW}3.${NC} Get help:"
    echo -e "     ${CYAN}mqv --help${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}⚡ Quick Examples:${NC}"
    echo -e "  ${GREEN}▶${NC} ${CYAN}mqv README.md         # Render a markdown file${NC}"
    echo -e "  ${GREEN}▶${NC} ${CYAN}echo \"# Hello\" | mqv  # Pipe markdown content${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}📚 Learn More:${NC}"
    echo -e "  ${GREEN}▶${NC} Repository: ${BLUE}https://github.com/$MQV_REPO${NC}"
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Main installation function
main() {
    show_logo

    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed"
    fi

    # Detect system
    local os arch version
    os=$(detect_os)
    arch=$(detect_arch)

    log "Detected system: $os/$arch"

    # Get latest version
    version=$(get_latest_version)
    log "Latest version: $version"

    # Install mqv
    install_mqv "$version" "$os" "$arch"

    # Update shell profile
    update_shell_profile

    # Verify installation
    verify_installation

    # Show post-installation instructions
    show_post_install
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "mqv installation script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help, -h        Show this help message"
            echo "  --version, -v     Show version and exit"
            exit 0
            ;;
        --version|-v)
            echo "mqv installer v1.0.0"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
    shift
done

# Check if we're running in a supported environment
if [[ -z "${BASH_VERSION:-}" ]]; then
    error "This installer requires bash"
fi

# Run the main installation
main "$@"

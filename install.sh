#!/usr/bin/env bash
#
# install.sh - Installation script for makecmd
#
# This script installs makecmd with proper security checks

set -euo pipefail

# Constants
readonly SCRIPT_NAME="install.sh"
readonly INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
readonly LIB_DIR="${LIB_DIR:-/usr/local/lib/makecmd}"
readonly MAN_DIR="${MAN_DIR:-/usr/local/share/man/man1}"
readonly REQUIRED_COMMANDS=("claude")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Functions
print_header() {
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║       makecmd Installation Script        ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Files will be owned by root."
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies:"
        printf '  - %s\n' "${missing_deps[@]}"
        echo
        print_info "Please install Claude Code first:"
        print_info "  https://claude.ai/code"
        exit 1
    fi
    
    print_success "All dependencies satisfied"
}

# Verify installation files
verify_files() {
    print_info "Verifying installation files..."
    
    local required_files=(
        "makecmd"
        "lib/sanitizer.sh"
        "lib/validator.sh"
        "lib/cache.sh"
        "lib/config.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Missing required file: $file"
            exit 1
        fi
    done
    
    print_success "All required files present"
}

# Create directories
create_directories() {
    print_info "Creating installation directories..."
    
    # Create directories with sudo if needed
    for dir in "$INSTALL_DIR" "$LIB_DIR" "$MAN_DIR"; do
        if [[ ! -d "$dir" ]]; then
            if [[ -w "$(dirname "$dir")" ]]; then
                mkdir -p "$dir"
            else
                print_warning "Need sudo to create $dir"
                sudo mkdir -p "$dir"
            fi
        fi
    done
    
    print_success "Directories created"
}

# Install files
install_files() {
    print_info "Installing files..."
    
    # Install main script
    if [[ -w "$INSTALL_DIR" ]]; then
        cp makecmd "$INSTALL_DIR/"
        chmod 755 "$INSTALL_DIR/makecmd"
    else
        print_warning "Need sudo to install to $INSTALL_DIR"
        sudo cp makecmd "$INSTALL_DIR/"
        sudo chmod 755 "$INSTALL_DIR/makecmd"
    fi
    
    # Create mkcmd symlink
    if [[ -w "$INSTALL_DIR" ]]; then
        ln -sf "$INSTALL_DIR/makecmd" "$INSTALL_DIR/mkcmd"
    else
        sudo ln -sf "$INSTALL_DIR/makecmd" "$INSTALL_DIR/mkcmd"
    fi
    
    # Install library files
    for lib in lib/*.sh; do
        if [[ -w "$LIB_DIR" ]]; then
            cp "$lib" "$LIB_DIR/"
            chmod 644 "$LIB_DIR/$(basename "$lib")"
        else
            sudo cp "$lib" "$LIB_DIR/"
            sudo chmod 644 "$LIB_DIR/$(basename "$lib")"
        fi
    done
    
    # Update library paths in main script
    if [[ -w "$INSTALL_DIR/makecmd" ]]; then
        sed -i.bak "s|^\(source \"\${SCRIPT_DIR}/lib/\)|source \"$LIB_DIR/|g" "$INSTALL_DIR/makecmd"
        rm -f "$INSTALL_DIR/makecmd.bak"
    else
        sudo sed -i.bak "s|^\(source \"\${SCRIPT_DIR}/lib/\)|source \"$LIB_DIR/|g" "$INSTALL_DIR/makecmd"
        sudo rm -f "$INSTALL_DIR/makecmd.bak"
    fi
    
    print_success "Files installed"
}

# Install man page if it exists
install_man_page() {
    if [[ -f "docs/makecmd.1" ]]; then
        print_info "Installing man page..."
        
        if [[ -w "$MAN_DIR" ]]; then
            cp "docs/makecmd.1" "$MAN_DIR/"
            gzip -f "$MAN_DIR/makecmd.1"
        else
            sudo cp "docs/makecmd.1" "$MAN_DIR/"
            sudo gzip -f "$MAN_DIR/makecmd.1"
        fi
        
        # Update man database
        if command -v mandb &> /dev/null; then
            sudo mandb -q
        elif command -v makewhatis &> /dev/null; then
            sudo makewhatis "$MAN_DIR"
        fi
        
        print_success "Man page installed"
    fi
}

# Create initial configuration
create_initial_config() {
    print_info "Creating initial configuration..."
    
    local config_dir="${HOME}/.makecmd"
    local config_file="${HOME}/.makecmdrc"
    
    # Create config directory
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"
    
    # Generate default config if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        "$INSTALL_DIR/makecmd" --generate-config 2>/dev/null || true
        print_success "Default configuration created at $config_file"
    else
        print_info "Configuration already exists at $config_file"
    fi
}

# Install shell integrations
install_shell_integrations() {
    print_info "Installing shell integrations..."
    
    # Install zsh integration
    if [[ -f "completions/makecmd.zsh" ]]; then
        local zsh_completions_dir="${HOME}/.makecmd/completions"
        mkdir -p "$zsh_completions_dir"
        cp "completions/makecmd.zsh" "$zsh_completions_dir/"
        chmod +x "$zsh_completions_dir/makecmd.zsh"
        
        # Add to .zshrc if not already present
        if [[ -f "${HOME}/.zshrc" ]]; then
            if ! grep -q "source ~/.makecmd/completions/makecmd.zsh" "${HOME}/.zshrc"; then
                echo "" >> "${HOME}/.zshrc"
                echo "# makecmd zsh integration" >> "${HOME}/.zshrc"
                echo "source ~/.makecmd/completions/makecmd.zsh" >> "${HOME}/.zshrc"
                print_success "Zsh integration installed and added to ~/.zshrc"
                print_info "Reload your shell or run: source ~/.zshrc"
            else
                print_success "Zsh integration already configured in ~/.zshrc"
            fi
        else
            print_success "Zsh integration installed"
            print_info "To enable zsh prefill, add this to your ~/.zshrc:"
            print_info "  source ~/.makecmd/completions/makecmd.zsh"
        fi
    fi
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    # Check if makecmd is in PATH
    if ! command -v makecmd &> /dev/null; then
        print_warning "makecmd is not in your PATH"
        print_info "Add $INSTALL_DIR to your PATH:"
        print_info "  export PATH=\"$INSTALL_DIR:\$PATH\""
    else
        print_success "makecmd is available in PATH"
    fi
    
    # Test basic functionality
    if command -v makecmd &> /dev/null; then
        if makecmd --version &> /dev/null; then
            print_success "makecmd is working correctly"
        else
            print_error "makecmd is not working correctly"
        fi
    fi
}

# Uninstall function
uninstall() {
    print_header
    print_warning "This will remove makecmd from your system"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi
    
    print_info "Uninstalling makecmd..."
    
    # Remove files
    local files_to_remove=(
        "$INSTALL_DIR/makecmd"
        "$INSTALL_DIR/mkcmd"
        "$MAN_DIR/makecmd.1.gz"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ -w "$file" ]]; then
                rm -f "$file"
            else
                sudo rm -f "$file"
            fi
        fi
    done
    
    # Remove library directory
    if [[ -d "$LIB_DIR" ]]; then
        if [[ -w "$LIB_DIR" ]]; then
            rm -rf "$LIB_DIR"
        else
            sudo rm -rf "$LIB_DIR"
        fi
    fi
    
    print_success "makecmd uninstalled"
    print_info "User configuration and cache preserved in ~/.makecmd"
}

# Main installation
main() {
    local uninstall_flag=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --uninstall)
                uninstall_flag=true
                shift
                ;;
            --help|-h)
                echo "Usage: $SCRIPT_NAME [--uninstall]"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ "$uninstall_flag" == "true" ]]; then
        uninstall
        exit 0
    fi
    
    print_header
    
    # Run installation steps
    check_root
    check_dependencies
    verify_files
    create_directories
    install_files
    install_man_page
    create_initial_config
    install_shell_integrations
    verify_installation
    
    echo
    print_success "Installation complete!"
    echo
    print_info "Quick start:"
    print_info "  makecmd \"list all python files\""
    print_info "  mkcmd \"show disk usage\""
    echo
    print_info "For help:"
    print_info "  makecmd --help"
    
    if [[ -f "docs/makecmd.1" ]]; then
        print_info "  man makecmd"
    fi
}

# Run main function
main "$@"
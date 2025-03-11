#!/bin/bash
set -e

# Vector macOS Installer Script
# Adapted from the Linux version at https://sh.vector.dev/index.html

# Color setup
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NO_COLOR='\033[0m'

# Utility functions
info() {
  echo -e "${BLUE}${BOLD}info${NO_COLOR}: $1"
}

error() {
  echo -e "${RED}${BOLD}error${NO_COLOR}: $1"
}

success() {
  echo -e "${GREEN}${BOLD}success${NO_COLOR}: $1"
}

warn() {
  echo -e "${YELLOW}${BOLD}warning${NO_COLOR}: $1"
}

# Check if running on macOS
if [ "$(uname)" != "Darwin" ]; then
  error "This script is intended to run on macOS only"
  exit 1
fi

# Check for Homebrew (required for installation)
if ! command -v brew &> /dev/null; then
  warn "Homebrew is not installed. Vector requires Homebrew on macOS."
  read -p "Would you like to install Homebrew now? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    error "Homebrew is required to install Vector. Please install Homebrew first."
    exit 1
  fi
fi

# Install Vector using Homebrew
install_vector_homebrew() {
  info "Installing Vector using Homebrew..."
  
  # Check if Vector is already installed
  if brew list vector &>/dev/null; then
    warn "Vector is already installed. Updating instead..."
    brew upgrade vector
  else
    brew install vector
  fi
  
  success "Vector has been installed successfully!"
  info "Vector configuration is located at: $(brew --prefix)/etc/vector"
}

# Create Vector service for launchd
setup_vector_service() {
  info "Setting up Vector as a service..."
  
  # Create LaunchAgent directory if it doesn't exist
  mkdir -p ~/Library/LaunchAgents
  
  # Create the plist file
  cat > ~/Library/LaunchAgents/dev.vector.daemon.plist << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.vector.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(brew --prefix)/bin/vector</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$(brew --prefix)/var/log/vector.log</string>
    <key>StandardOutPath</key>
    <string>$(brew --prefix)/var/log/vector.log</string>
</dict>
</plist>
EOL

  # Load the service
  launchctl load ~/Library/LaunchAgents/dev.vector.daemon.plist
  
  success "Vector service has been set up!"
}

# Verify the installation
verify_installation() {
  info "Verifying Vector installation..."
  
  if command -v vector &> /dev/null; then
    VECTOR_VERSION=$(vector --version | head -n 1)
    success "Vector ${VECTOR_VERSION} is installed and available!"
  else
    error "Vector installation verification failed. Please try installing again."
    exit 1
  fi
}

# Main installation process
main() {
  echo -e "${BOLD}Vector Installer for macOS${NO_COLOR}"
  echo "This script will install Vector using Homebrew and set up Vector as a service."
  
  # Ask for confirmation
  read -p "Do you want to proceed with the installation? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Installation cancelled."
    exit 0
  fi
  
  # Install Vector
  install_vector_homebrew
  
  # Ask about setting up as a service
  read -p "Would you like to set up Vector as a service that starts on login? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    setup_vector_service
  fi
  
  # Verify installation
  verify_installation
  
  # Final instructions
  echo
  info "To start Vector manually, run: vector"
  info "To view Vector logs: tail -f $(brew --prefix)/var/log/vector.log"
  info "To edit Vector configuration: open -e $(brew --prefix)/etc/vector/vector.toml"
  echo
  success "Vector installation complete!"
}

# Run the installer
main

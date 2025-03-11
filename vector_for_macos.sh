#!/bin/bash
set -e

# Vector macOS Installer Script (No Homebrew or Xcode)
# Direct binary installation

# Color setup
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NO_COLOR='\033[0m'

# Variables
VECTOR_VERSION="0.36.0"  # Update this to the latest stable version
INSTALL_DIR="/usr/local/vector"
BINARY_DIR="/usr/local/bin"
CONFIG_DIR="/etc/vector"
DATA_DIR="/var/lib/vector"
LOG_DIR="/var/log/vector"

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

# Check if running as root
check_privileges() {
  if [ "$(id -u)" -ne 0 ]; then
    error "This script needs to be run with sudo or as root"
    exit 1
  fi
}

# Check if running on macOS
check_platform() {
  if [ "$(uname)" != "Darwin" ]; then
    error "This script is intended to run on macOS only"
    exit 1
  fi
  
  # Get macOS architecture
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ]; then
    ARCH="x86_64"
  elif [ "$ARCH" = "arm64" ]; then
    ARCH="aarch64"
  else
    error "Unsupported architecture: $ARCH. Vector supports x86_64 or arm64/aarch64."
    exit 1
  fi
  
  info "Detected macOS architecture: $ARCH"
}

# Download Vector binary
download_vector() {
  info "Downloading Vector ${VECTOR_VERSION} for macOS ($ARCH)..."
  
  TEMP_DIR=$(mktemp -d)
  DOWNLOAD_URL="https://packages.timber.io/vector/${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH}-apple-darwin.tar.gz"
  
  # Download the archive
  curl -L --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/vector.tar.gz"
  
  if [ $? -ne 0 ]; then
    error "Failed to download Vector. Please check your internet connection and the version specified."
    exit 1
  fi
  
  # Extract the archive
  info "Extracting Vector..."
  mkdir -p "$TEMP_DIR/extract"
  tar -xzf "$TEMP_DIR/vector.tar.gz" -C "$TEMP_DIR/extract"
  
  # Create installation directories
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
  
  # Copy files to the installation directory
  cp -r "$TEMP_DIR/extract"/*/* "$INSTALL_DIR"
  
  # Create symbolic link to make vector available in PATH
  ln -sf "$INSTALL_DIR/bin/vector" "$BINARY_DIR/vector"
  
  # Copy default config
  if [ -f "$INSTALL_DIR/etc/vector/vector.toml" ]; then
    cp "$INSTALL_DIR/etc/vector/vector.toml" "$CONFIG_DIR/vector.toml"
  elif [ -f "$INSTALL_DIR/config/vector.toml" ]; then
    cp "$INSTALL_DIR/config/vector.toml" "$CONFIG_DIR/vector.toml"
  fi
  
  # Clean up temp files
  rm -rf "$TEMP_DIR"
  
  success "Vector has been downloaded and extracted to $INSTALL_DIR"
}

# Create Vector service for launchd
setup_vector_service() {
  info "Setting up Vector as a service..."
  
  # Create the plist file
  cat > /Library/LaunchDaemons/dev.vector.daemon.plist << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.vector.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY_DIR}/vector</string>
        <string>--config</string>
        <string>${CONFIG_DIR}/vector.toml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/vector.log</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/vector.log</string>
    <key>WorkingDirectory</key>
    <string>/usr/local/vector</string>
</dict>
</plist>
EOL

  # Set proper permissions
  chmod 644 /Library/LaunchDaemons/dev.vector.daemon.plist
  
  # Load the service
  launchctl load /Library/LaunchDaemons/dev.vector.daemon.plist
  
  success "Vector service has been set up!"
}

# Verify the installation
verify_installation() {
  info "Verifying Vector installation..."
  
  if command -v vector &> /dev/null; then
    INSTALLED_VERSION=$(vector --version | head -n 1 || echo "Unknown")
    success "Vector ${INSTALLED_VERSION} is installed and available!"
  else
    error "Vector installation verification failed. Please try installing again."
    exit 1
  fi
}

# Main installation process
main() {
  echo -e "${BOLD}Vector Direct Installer for macOS${NO_COLOR}"
  echo "This script will install Vector directly without using Homebrew or Xcode."
  
  # Check system requirements
  check_privileges
  check_platform
  
  # Ask for confirmation
  read -p "Do you want to proceed with the installation? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Installation cancelled."
    exit 0
  fi
  
  # Download and install Vector
  download_vector
  
  # Ask about setting up as a service
  read -p "Would you like to set up Vector as a system service? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    setup_vector_service
  fi
  
  # Verify installation
  verify_installation
  
  # Final instructions
  echo
  info "Vector has been installed directly on your system without using Homebrew or Xcode."
  info "To start Vector manually, run: vector --config ${CONFIG_DIR}/vector.toml"
  info "To view Vector logs: tail -f ${LOG_DIR}/vector.log"
  info "To edit Vector configuration: nano ${CONFIG_DIR}/vector.toml"
  echo
  success "Vector installation complete!"
}

# Run the installer
main

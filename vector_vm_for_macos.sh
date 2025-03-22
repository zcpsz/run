#!/bin/bash
set -e

# Vector macOS Installer Script (No Homebrew or Xcode)
# Automatically uses the latest stable version

# Variables
INSTALL_DIR="/usr/local/vector"
BINARY_DIR="/usr/local/bin"
CONFIG_DIR="/etc/vector"
DATA_DIR="/var/lib/vector"
LOG_DIR="/var/log/vector"

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
  if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "arm64" ]; then
    error "Unsupported architecture: $ARCH. Vector supports x86_64 or arm64/aarch64."
    exit 1
  fi 

  info "Detected macOS architecture: $ARCH"
}

# Get the latest Vector version
get_latest_version() {
  info "Determining the latest Vector version..."
  
  # Try to get the latest version from GitHub API
  LATEST_VERSION=$(curl -s https://api.github.com/repos/vectordotdev/vector/releases/latest | grep -o '"tag_name": "v[^"]*' | sed 's/"tag_name": "v//')
  
  if [ -z "$LATEST_VERSION" ]; then
    # Fallback to a known recent version if API call fails
    warn "Could not determine the latest version. Using default fallback version."
    LATEST_VERSION="0.45.0"
  fi
  
  info "Latest Vector version: $LATEST_VERSION"
  VECTOR_VERSION=$LATEST_VERSION
}

# Get the latest Vector version
get_latest_version() {
  info "Determining the latest Vector version..."
  
  # Try to get the latest version from GitHub API
  LATEST_VERSION=$(curl -s https://api.github.com/repos/vectordotdev/vector/releases/latest | grep -o '"tag_name": "v[^"]*' | sed 's/"tag_name": "v//')
  
  if [ -z "$LATEST_VERSION" ]; then
    # Fallback to a known recent version if API call fails
    warn "Could not determine the latest version. Using default fallback version."
    LATEST_VERSION="0.37.0"
  fi
  
  info "Latest Vector version: $LATEST_VERSION"
  VECTOR_VERSION=$LATEST_VERSION
}

# Download Vector binary
download_vector() {
  info "Downloading Vector ${VECTOR_VERSION} for macOS ($ARCH)..."
  
  TEMP_DIR=$(mktemp -d)
  DOWNLOAD_URL="https://packages.timber.io/vector/${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH}-apple-darwin.tar.gz"
  
  # Download the archive
  info "Downloading from: $DOWNLOAD_URL"
  curl -L --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/vector.tar.gz"
  
  if [ $? -ne 0 ]; then
    error "Failed to download Vector. Trying alternative download location..."
    
    # Try alternative download URL format
    DOWNLOAD_URL="https://github.com/vectordotdev/vector/releases/download/v${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH}-apple-darwin.tar.gz"
    info "Trying: $DOWNLOAD_URL"
    curl -L --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/vector.tar.gz"
    
    if [ $? -ne 0 ]; then
      error "Failed to download Vector. Please check your internet connection."
      
      # If on ARM and specific version has no ARM binary, try x86_64 with Rosetta
      if [ "$ARCH" = "arm64" ]; then
        warn "ARM binary not available. Attempting to download x86_64 version to use with Rosetta 2..."
        DOWNLOAD_URL="https://github.com/vectordotdev/vector/releases/download/v${VECTOR_VERSION}/vector-${VECTOR_VERSION}-x86_64-apple-darwin.tar.gz"
        curl -L --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/vector.tar.gz"
        
        if [ $? -ne 0 ]; then
          error "All download attempts failed. Please try a different version or installation method."
          exit 1
        fi
        
        info "Downloaded x86_64 version. Will use with Rosetta 2 translation."
      else
        error "Download failed. Please try a different version or installation method."
        exit 1
      fi
    fi
  fi
  
  # Extract the archive
  info "Extracting Vector..."
  mkdir -p "$TEMP_DIR/extract"
  tar -xzf "$TEMP_DIR/vector.tar.gz" -C "$TEMP_DIR/extract"
  
  # Create installation directories
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$BINARY_DIR"
  
  # Find the extracted directory
  EXTRACTED_DIR=$(find "$TEMP_DIR/extract" -type d -name "vector*" -depth 1 2>/dev/null || echo "$TEMP_DIR/extract")
  
  # Find the extracted directory
  EXTRACTED_DIR=$(find "$TEMP_DIR/extract" -type d -name "vector*" -depth 1 2>/dev/null || echo "$TEMP_DIR/extract")
  
  # Copy files to the installation directory
  info "Installing Vector to $INSTALL_DIR"
  cp -r "$EXTRACTED_DIR"/* "$INSTALL_DIR" 2>/dev/null || cp -r "$TEMP_DIR/extract"/* "$INSTALL_DIR"
  
  # Create symbolic link to make vector available in PATH
  info "Creating symbolic link in $BINARY_DIR"
  ln -sf "$INSTALL_DIR/bin/vector" "$BINARY_DIR/vector"
  
  # Copy default config
  if [ -f "$INSTALL_DIR/etc/vector/vector.toml" ]; then
    cp "$INSTALL_DIR/etc/vector/vector.toml" "$CONFIG_DIR/vector.toml"
  elif [ -f "$INSTALL_DIR/config/vector.toml" ]; then
    cp "$INSTALL_DIR/config/vector.toml" "$CONFIG_DIR/vector.toml"
  else
    # Create basic config if none found
    cat > "$CONFIG_DIR/vector.toml" << EOL
# Source: Collect host metrics
[sources.host_metrics]
type = "host_metrics"
collectors = [
    "filesystem",
    "load",
    "host",
    "memory",
    "network",
]
filesystem.mountpoints.includes = [
    "/"
]
network.devices.includes = [
    "en0"
]
scrape_interval_secs = 10

# Sink: Forward to Debian Vector
[sinks.to_debian_vector]
type = "socket"
inputs = ["host_metrics"]
address = "100.70.153.96:9000"
mode = "tcp"
encoding.codec = "json"
EOL
    info "Created basic Vector configuration at $CONFIG_DIR/vector.toml"
  fi
  
  # Set correct permissions
  chown -R root:wheel "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$BINARY_DIR"
  chmod -R 755 "$INSTALL_DIR" "$BINARY_DIR"
  chmod -R 644 "$CONFIG_DIR"/*
  
  # Clean up temp files
  rm -rf "$TEMP_DIR"
  
  success "Vector has been installed to $INSTALL_DIR"
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
    
    # Test that it runs
    vector --version > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      warn "Vector command executed but returned an error. There might be configuration issues."
    fi
  else
    error "Vector installation verification failed. Please try installing again."
    exit 1
  fi
}

# Main installation process
main() {
  echo "This script will install the latest Vector version directly without using Homebrew or Xcode."
  
  # Check system requirements
  check_privileges
  check_platform
  get_latest_version

  # Download and install Vector
  download_vector
  
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

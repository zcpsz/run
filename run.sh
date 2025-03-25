#!/bin/bash

echo admin | sudo -S sh -c "echo 'admin ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/admin-nopasswd"
echo '00000000: 1ced 3f4a bcbc ba2c caca 4e82' | sudo xxd -r - /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser admin
sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0
defaults -currentHost write com.apple.screensaver idleTime 0
sudo systemsetup -setdisplaysleep Off 2>/dev/null
sudo systemsetup -setsleep Off 2>/dev/null
sudo systemsetup -setcomputersleep Off 2>/dev/null
/Applications/Safari.app/Contents/MacOS/Safari &
SAFARI_PID=$!
disown
sleep 30
kill -9 $SAFARI_PID
sudo safaridriver --enable
sysadminctl -screenLock off -password admin
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
softwareupdate --list | sed -n 's/.*Label: \\(Command Line Tools for Xcode-.*\\)/\\1/p' | xargs -I {} softwareupdate --install '{}'
rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress


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

}

# Get the latest Vector version
get_latest_version() {
  
  # Try to get the latest version from GitHub API
  LATEST_VERSION=$(curl -s https://api.github.com/repos/vectordotdev/vector/releases/latest | grep -o '"tag_name": "v[^"]*' | sed 's/"tag_name": "v//')
  
  if [ -z "$LATEST_VERSION" ]; then
    # Fallback to a known recent version if API call fails
    warn "Could not determine the latest version. Using default fallback version."
    LATEST_VERSION="0.45.0"
  fi
  
  VECTOR_VERSION=$LATEST_VERSION
}

# Get the latest Vector version
get_latest_version() {
  
  # Try to get the latest version from GitHub API
  LATEST_VERSION=$(curl -s https://api.github.com/repos/vectordotdev/vector/releases/latest | grep -o '"tag_name": "v[^"]*' | sed 's/"tag_name": "v//')
  
  if [ -z "$LATEST_VERSION" ]; then
    # Fallback to a known recent version if API call fails
    warn "Could not determine the latest version. Using default fallback version."
    LATEST_VERSION="0.37.0"
  fi
  
  VECTOR_VERSION=$LATEST_VERSION
}

# Download Vector binary
download_vector() {
  
  TEMP_DIR=$(mktemp -d)
  DOWNLOAD_URL="https://packages.timber.io/vector/${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH}-apple-darwin.tar.gz"
  
  # Download the archive
  curl -L --progress-bar "$DOWNLOAD_URL" -o "$TEMP_DIR/vector.tar.gz"
  
  if [ $? -ne 0 ]; then
    error "Failed to download Vector. Trying alternative download location..."
    
    # Try alternative download URL format
    DOWNLOAD_URL="https://github.com/vectordotdev/vector/releases/download/v${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${ARCH}-apple-darwin.tar.gz"
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
        
      else
        error "Download failed. Please try a different version or installation method."
        exit 1
      fi
    fi
  fi
  
  # Extract the archive
  mkdir -p "$TEMP_DIR/extract"
  tar -xzf "$TEMP_DIR/vector.tar.gz" -C "$TEMP_DIR/extract"
  
  # Create installation directories
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$BINARY_DIR"
  
  # Find the extracted directory
  EXTRACTED_DIR=$(find "$TEMP_DIR/extract" -type d -name "vector*" -depth 1 2>/dev/null || echo "$TEMP_DIR/extract")
  
  # Find the extracted directory
  EXTRACTED_DIR=$(find "$TEMP_DIR/extract" -type d -name "vector*" -depth 1 2>/dev/null || echo "$TEMP_DIR/extract")
  
  # Copy files to the installation directory
  cp -r "$EXTRACTED_DIR"/* "$INSTALL_DIR" 2>/dev/null || cp -r "$TEMP_DIR/extract"/* "$INSTALL_DIR"
  
  # Create symbolic link to make vector available in PATH
  ln -sf "$INSTALL_DIR/bin/vector" "$BINARY_DIR/vector"
  
  # Set correct permissions
  chown -R root:wheel "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$BINARY_DIR"
  chmod -R 755 "$INSTALL_DIR" "$BINARY_DIR"
  chmod -R 644 "$CONFIG_DIR"/*
  
  # Clean up temp files
  rm -rf "$TEMP_DIR"
}

# Create Getmac guestagent service for launchd
setup_guestagent_service() {
  
  # Create the plist file
  cat > /Library/LaunchDaemons/io.getmac.guestagent.plist << EOL
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.getmac.guestagent.plist</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Volumes/My Shared Files/guestdata/entrypoint.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>Nice</key>
    <integer>0</integer>
    <key>StandardOutPath</key>
    <string>/var/log/io.getmac.guestagent.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/io.getmac.guestagent.log</string>
</dict>
</plist>
EOL

  # Set proper permissions
  chmod 644 /Library/LaunchDaemons/dev.vector.daemon.plist
  
  # Load the service
  launchctl load /Library/LaunchDaemons/dev.vector.daemon.plist
} 

# Verify the installation
verify_installation() {
  
  if command -v vector &> /dev/null; then
    INSTALLED_VERSION=$(vector --version | head -n 1 || echo "Unknown")
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
  
  #Setup getmac guestagent as a service
  setup_guestagent_service
  
  # Verify installation
  verify_installation
  
  # Final instructions
}

# Run the installer
main

#!/bin/bash

# Elevate privileges upfront
echo "admin" | sudo -S true

# --- Configure Passwordless sudo for 'admin' ---
echo "admin ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR="tee" visudo -f /etc/sudoers.d/admin-nopasswd

# --- Configure Auto Login for 'admin' ---
echo '00000000: 1ced 3f4a bcbc ba2c caca 4e82' | sudo xxd -r - /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser admin

# --- System Preferences Tweaks ---
sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0
defaults -currentHost write com.apple.screensaver idleTime 0
sudo systemsetup -settimezone GMT
sudo systemsetup -setdisplaysleep Off 2>/dev/null
sudo systemsetup -setsleep Off 2>/dev/null
sudo systemsetup -setcomputersleep Off 2>/dev/null
sudo systemsetup -setharddisksleep Off
sudo pmset disablesleep 1
defaults write NSGlobalDomain NSAppSleepDisabled -bool YES

# --- Enable Remote Login & Remote Management ---
sudo systemsetup -setremotelogin on
sudo defaults write /Library/Preferences/com.apple.RemoteManagement.plist ARDAllowsAllUsers -bool true
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -allowAccessFor -allUsers -restart -agent

# --- Launch Safari briefly (might trigger permissions/setup) ---
/Applications/Safari.app/Contents/MacOS/Safari &
SAFARI_PID=$!
disown
sleep 30
kill -9 "$SAFARI_PID"

# --- Enable safaridriver ---
sudo safaridriver --enable

# --- Disable screen lock ---
sysadminctl -screenLock off -password admin

# --- Install Xcode Command Line Tools ---
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
softwareupdate --list | sed -n 's/.*Label: \(Command Line Tools for Xcode-.*\)/\1/p' \
  | xargs -I {} softwareupdate --install '{}'
rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH
if [[ -d /opt/homebrew ]]; then
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -d /usr/local/Homebrew ]]; then
  echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
  eval "$(/usr/local/bin/brew shellenv)"
fi

# --- Download & Setup GitHub Actions Runner ---
cd /Users/admin || exit 1
mkdir -p actions-runner && cd actions-runner || exit 1
curl -LO https://github.com/actions/runner/releases/download/v2.323.0/actions-runner-osx-arm64-2.323.0.tar.gz
tar xzf actions-runner-osx-arm64-2.323.0.tar.gz
rm -f actions-runner-osx-arm64-2.323.0.tar.gz

# --- Create LaunchDaemon for custom guest agent ---
sudo tee /Library/LaunchDaemons/io.getmac.guestagent.plist > /dev/null << 'EOL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.getmac.guestagent</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/var/root</string>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Volumes/GETMAC/entrypoint.sh</string>
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

# --- Set permissions and load LaunchDaemon ---
sudo chmod 644 /Library/LaunchDaemons/io.getmac.guestagent.plist
sudo launchctl load /Library/LaunchDaemons/io.getmac.guestagent.plist

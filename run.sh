#!/bin/bash
echo admin | sudo -S sh -c \"echo 'admin ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/admin-nopasswd\"
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

#!/bin/zsh
# Compile Squat.app, l'installe dans ~/Applications, active le lancement automatique et la lance.
set -e
cd "$(dirname "$0")"
APP=Squat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/Squat"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Squat</string>
  <key>CFBundleIdentifier</key><string>local.squat</string>
  <key>CFBundleExecutable</key><string>Squat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "OK → $(pwd)/$APP"

# Installe dans ~/Applications
mkdir -p ~/Applications
rm -rf ~/Applications/Squat.app
ditto "$APP" ~/Applications/Squat.app
rm -rf "$APP"

# Lancement automatique à l'ouverture de session (relancée si elle plante, pas si on la quitte)
AGENT=~/Library/LaunchAgents/local.squat.plist
if [ ! -f "$AGENT" ]; then
  mkdir -p ~/Library/LaunchAgents
  cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.squat</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/Applications/Squat.app/Contents/MacOS/Squat</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
fi
launchctl kickstart -k gui/$(id -u)/local.squat 2>/dev/null || launchctl bootstrap gui/$(id -u) "$AGENT"
echo "Installée et lancée → ~/Applications/Squat.app"

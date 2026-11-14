#!/bin/zsh
# Compile Squat.app, l'installe dans ~/Applications, active le lancement automatique et la lance.
# ./build.sh --mini [hôte] [nom] : version au justaucorps bleu qui suit un autre Mac par SSH
#   (hôte par défaut « mini », un alias de ~/.ssh/config avec clé sans mot de passe ; nom par défaut « Mac mini »).
set -e
cd "$(dirname "$0")"
NAME=Squat; ID=local.squat; ARGS=()
if [ "$1" = "--mini" ]; then
  NAME=SquatMini; ID=local.squatmini; ARGS=(--distant "${2:-mini}" --nom "${3:-Mac mini}")
  ssh -o BatchMode=yes -o ConnectTimeout=8 "${2:-mini}" true || { echo "SSH vers « ${2:-mini} » impossible sans mot de passe : à régler d'abord."; exit 1; }
fi
APP=$NAME.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
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
rm -rf ~/Applications/$APP
ditto "$APP" ~/Applications/$APP
rm -rf "$APP"

# Lancement automatique à l'ouverture de session (relancée si elle plante, pas si on la quitte)
AGENT=~/Library/LaunchAgents/$ID.plist
ARGXML=""; for a in "${ARGS[@]}"; do ARGXML+="<string>$a</string>"; done
if [ ! -f "$AGENT" ]; then
  mkdir -p ~/Library/LaunchAgents
  cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ID</string>
  <key>ProgramArguments</key>
  <array><string>$HOME/Applications/$APP/Contents/MacOS/$NAME</string>$ARGXML</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
fi
launchctl kickstart -k gui/$(id -u)/$ID 2>/dev/null || launchctl bootstrap gui/$(id -u) "$AGENT"
echo "Installée et lancée → ~/Applications/$APP"

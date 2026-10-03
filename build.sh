#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p DimTheLights.app/Contents/MacOS
swiftc -O main.swift -o DimTheLights.app/Contents/MacOS/DimTheLights
cat > DimTheLights.app/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DimTheLights</string>
    <key>CFBundleIdentifier</key><string>com.ashwin.dimthelights</string>
    <key>CFBundleName</key><string>Dim the Lights</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
echo "Built DimTheLights.app"

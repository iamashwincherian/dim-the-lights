#!/bin/sh
set -e
cd "$(dirname "$0")"
VERSION=1.0.0
APP=DimTheLights.app
mkdir -p $APP/Contents/MacOS
# Universal binary (Apple silicon + Intel), runs on macOS 13+.
for arch in arm64 x86_64; do swiftc -O -target $arch-apple-macos13 main.swift -o .build-$arch; done
lipo -create .build-arm64 .build-x86_64 -output $APP/Contents/MacOS/DimTheLights
rm .build-arm64 .build-x86_64
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DimTheLights</string>
    <key>CFBundleIdentifier</key><string>com.ashwin.dimthelights</string>
    <key>CFBundleName</key><string>Dim the Lights</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - $APP   # ad-hoc; no Developer ID, so not notarized
echo "Built $APP"

# ./build.sh dmg  ->  DimTheLights-<version>.dmg with an Applications shortcut
if [ "$1" = dmg ]; then
    rm -rf .dmg && mkdir .dmg && cp -R $APP .dmg/ && ln -s /Applications .dmg/Applications
    hdiutil create -volname "Dim the Lights" -srcfolder .dmg -ov -format UDZO DimTheLights-$VERSION.dmg >/dev/null
    rm -rf .dmg
    echo "Built DimTheLights-$VERSION.dmg"
fi

#!/bin/zsh
# Builds emdi in Release and packages it for people who just want the app:
#   build/emdi-<version>.dmg  a disk image with emdi.app and a link to Applications (drag to install)
#   build/emdi-<version>.pkg  an installer that puts emdi.app in /Applications by itself
#   build/emdi-<version>.zip  the app alone
# Run from the repository root: zsh tools/make-installers.sh
# Uses only tools that come with macOS and Xcode. Nothing is signed with a Developer ID
# (there is none), so macOS asks to confirm the first launch: see the README.
set -euo pipefail

cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -scheme emdi -configuration Release -derivedDataPath build build | tail -1

app=build/Build/Products/Release/emdi.app
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
work=build/installers
rm -rf "$work" build/emdi-"$version".{dmg,pkg,zip}
mkdir -p "$work/dmg"

# Zip
ditto -c -k --keepParent "$app" "build/emdi-$version.zip"

# Disk image: the app, a link to Applications, and a short note about the first launch.
ditto "$app" "$work/dmg/emdi.app"
ln -s /Applications "$work/dmg/Applications"
cat > "$work/dmg/First launch - read me.txt" <<EOF
Installing emdi $version

1. Drag emdi onto the Applications folder.
2. Open emdi from Applications.
   macOS says it could not verify emdi: click Done.
3. Open System Settings > Privacy & Security, scroll down to Security,
   click "Open Anyway" next to the message about emdi, confirm, then click Open.

You only do this once. emdi is not signed by an Apple Developer account,
which is why macOS asks. Requires macOS 26 or later on a Mac with Apple silicon.
EOF
hdiutil create -quiet -volname "emdi $version" -srcfolder "$work/dmg" -fs APFS -format UDZO -ov "build/emdi-$version.dmg"

# Installer package. Not relocatable: Installer must put the app in /Applications, not update
# another copy of emdi it finds elsewhere on the Mac (a build folder, for example).
mkdir -p "$work/root/Applications"
ditto "$app" "$work/root/Applications/emdi.app"
pkgbuild --analyze --root "$work/root" "$work/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$work/component.plist"
pkgbuild --quiet --root "$work/root" --component-plist "$work/component.plist" \
    --identifier local.emdi.app.pkg --version "$version" --install-location / "$work/emdi-component.pkg"
cat > "$work/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>emdi $version</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <volume-check>
        <allowed-os-versions><os-version min="26.0"/></allowed-os-versions>
    </volume-check>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline><line choice="emdi"/></choices-outline>
    <choice id="emdi" title="emdi"><pkg-ref id="local.emdi.app.pkg"/></choice>
    <pkg-ref id="local.emdi.app.pkg" version="$version">emdi-component.pkg</pkg-ref>
</installer-gui-script>
EOF
productbuild --quiet --distribution "$work/distribution.xml" --package-path "$work" "build/emdi-$version.pkg"

rm -rf "$work"
ls -lh build/emdi-"$version".{dmg,pkg,zip}

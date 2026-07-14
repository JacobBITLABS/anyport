#!/bin/bash
set -e

APP_NAME="AnyPort"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

mkdir -p "${MACOS_DIR}"

echo "Compiling..."
swiftc \
    -target arm64-apple-macosx14.0 \
    -swift-version 5 \
    -o "${MACOS_DIR}/${APP_NAME}" \
    Sources/SSHPortBar/App/SSHPortBarApp.swift \
    Sources/SSHPortBar/Models/SSHHost.swift \
    Sources/SSHPortBar/Core/SSHConfigStore.swift \
    Sources/SSHPortBar/Core/Connector.swift \
    Sources/SSHPortBar/Core/HostOrderManager.swift \
    Sources/SSHPortBar/Views/HostListView.swift \
    Sources/SSHPortBar/Views/HostEditorView.swift

sed -e 's/\$(DEVELOPMENT_LANGUAGE)/en/g' \
    -e 's/\$(EXECUTABLE_NAME)/SSHPortBar/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.jacobnielsen.sshportbar/g' \
    -e 's/\$(PRODUCT_NAME)/AnyPort/g' \
    Info.plist > "${CONTENTS_DIR}/Info.plist"

codesign --force --sign - "${APP_DIR}"

echo "Done: ${APP_DIR}"

#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
swift build -c release
mkdir -p dist/Memcheck.app/Contents/MacOS
cp .build/release/Memcheck dist/Memcheck.app/Contents/MacOS/Memcheck
cp Resources/Info.plist dist/Memcheck.app/Contents/Info.plist
memcheck_sign_identity=${MEMCHECK_SIGN_IDENTITY:--}
codesign --force --sign "$memcheck_sign_identity" --identifier com.haydenfd.memcheck dist/Memcheck.app
printf 'Built %s\n' "$PWD/dist/Memcheck.app"

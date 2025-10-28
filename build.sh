#!/usr/bin/env bash
set -euo pipefail
set -x  # debug do runner

NAME=OneKeepAlive
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN_IOS=14.0

mkdir -p build/arm64 build/arm64e out

COMMON_FLAGS="-fobjc-arc -fmodules -g -O2 \
 -framework Foundation -framework UIKit -framework AVFoundation \
 -dynamiclib -install_name @executable_path/Frameworks/${NAME}.dylib"

# arm64
clang -arch arm64  -miphoneos-version-min=${MIN_IOS} \
  -isysroot ${SDK} ${COMMON_FLAGS} PatchMix.m -o build/arm64/${NAME}.dylib

# arm64e
clang -arch arm64e -miphoneos-version-min=${MIN_IOS} \
  -isysroot ${SDK} ${COMMON_FLAGS} PatchMix.m -o build/arm64e/${NAME}.dylib

lipo -create -output out/${NAME}.dylib build/arm64/${NAME}.dylib build/arm64e/${NAME}.dylib
echo "✓ out/${NAME}.dylib"
otool -L out/${NAME}.dylib || true

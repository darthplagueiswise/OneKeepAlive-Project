#!/usr/bin/env bash
set -euo pipefail
NAME=OneKeepAlive   # mantém o nome do artefato esperado no workflow
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS=14.0

mkdir -p build/arm64 build/arm64e out

COMMON="-isysroot \"$SDK\" -fobjc-arc -fmodules -g -O2 \
 -framework Foundation -framework UIKit -framework AVFoundation \
 -dynamiclib -install_name @executable_path/Frameworks/${NAME}.dylib"

clang -arch arm64  -miphoneos-version-min=$MIN_IOS $COMMON PatchMix.m -o build/arm64/${NAME}.dylib
clang -arch arm64e -miphoneos-version-min=$MIN_IOS $COMMON PatchMix.m -o build/arm64e/${NAME}.dylib

lipo -create -output out/${NAME}.dylib build/arm64/${NAME}.dylib build/arm64e/${NAME}.dylib
echo "✓ out/${NAME}.dylib"
otool -L out/${NAME}.dylib || true
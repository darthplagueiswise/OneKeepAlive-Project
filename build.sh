#!/usr/bin/env bash
set -euo pipefail
# Local build (requires Xcode CLT + iPhoneOS SDK). Produces a fat (arm64 + arm64e) dylib.
NAME=OneKeepAlive
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS=14.0

mkdir -p build/arm64 build/arm64e out

clang -isysroot "$SDK" -arch arm64 -miphoneos-version-min=$MIN_IOS \
  -fobjc-arc -fmodules -Os \
  -dynamiclib -install_name @executable_path/Frameworks/${NAME}.dylib \
  -framework Foundation -framework UIKit -framework AVFoundation -framework AudioToolbox \
  OneKeepAlive.m -o build/arm64/${NAME}.dylib

clang -isysroot "$SDK" -arch arm64e -miphoneos-version-min=$MIN_IOS \
  -fobjc-arc -fmodules -Os \
  -dynamiclib -install_name @executable_path/Frameworks/${NAME}.dylib \
  -framework Foundation -framework UIKit -framework AVFoundation -framework AudioToolbox \
  OneKeepAlive.m -o build/arm64e/${NAME}.dylib

lipo -create -output out/${NAME}.dylib build/arm64/${NAME}.dylib build/arm64e/${NAME}.dylib

echo "Built out/${NAME}.dylib"
otool -L out/${NAME}.dylib || true

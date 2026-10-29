#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VER=$(grep '^Version:' layout/DEBIAN/control | awk '{print $2}')
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R layout "$OUT/pkg"
LIB="$OUT/pkg/Library/MobileSubstrate/DynamicLibraries/NXDump.dylib"

xcrun --sdk iphoneos clang -dynamiclib -fobjc-arc -O1 \
  -arch arm64 -arch arm64e -miphoneos-version-min=14.0 \
  -framework Foundation -framework UIKit \
  src/NXDump.m -o "$LIB"

ldid -S "$LIB"
chmod 755 "$OUT/pkg/DEBIAN"
export COPYFILE_DISABLE=1
dpkg-deb -Zgzip --root-owner-group -b "$OUT/pkg" "$OUT/com.ganbi.nxdump_${VER}_iphoneos-arm64e.deb"
ls -l "$OUT"/*.deb

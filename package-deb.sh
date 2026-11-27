#!/usr/bin/env bash
#
# package-deb.sh — assemble the iOS 12 .deb from a built y2k.app
#
# Usage:
#   ./package-deb.sh /path/to/y2k.app [output.deb]
#
# The .app must be the *already built* bundle (Theos `make package` produces one
# in .theos/_/Applications/y2k.app; Xcode puts one in DerivedData). The script
# lays out the Debian archive the way FileZilla/Cydia/Dopamine expect:
#
#   ./Applications/y2k.app/...
#   ./DEBIAN/control
#
# and writes ar(1) container `data.tar` + `control.tar` + `debian-binary`.
# It does not sign the binary — run ldid (or your own codesign step) first.
#
set -euo pipefail

APP_PATH="${1:-}"
OUT="${2:-y2k_2.03_ios12_iphoneos-arm.deb}"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "usage: $0 /path/to/y2k.app [output.deb]" >&2
    exit 1
fi

if [ ! -f "$APP_PATH/y2k" ]; then
    echo "error: $APP_PATH/y2k missing — point this at the built .app bundle" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/root/Applications" "$WORK/control"
cp -R "$APP_PATH" "$WORK/root/Applications/"
chmod 0755 "$WORK/root/Applications/$(basename "$APP_PATH")/$(basename "$APP_PATH" .app)"

cp "$(dirname "$0")/control" "$WORK/control/control"
chmod 0644 "$WORK/control/control"

# Control archive must come first, then data, then the magic version file.
( cd "$WORK/control" && tar --format=gnu -czf "$WORK/control.tar.gz" ./control )
( cd "$WORK/root"    && tar --format=gnu -czf "$WORK/data.tar.gz" ./Applications )

echo "2.0" > "$WORK/debian-binary"

( cd "$WORK" && ar r "$OUT" debian-binary control.tar.gz data.tar.gz )

echo "built $OUT"
echo
echo "Install on a jailbroken iOS 12 device:"
echo "  1. Copy $(basename "$OUT") to the device with FileZilla (SFTP, port 22)."
echo "  2. In an SSH session: dpkg -i $(basename "$OUT") && killall -9 y2k 2>/dev/null; uicache -a"
echo "  3. Respring if the icon does not appear."

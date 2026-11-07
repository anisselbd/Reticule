#!/bin/bash
# Compile le cadran et le copie en USB dans GARMIN/Apps de la montre (macOS, MTP).
#
# Usage : tools/installer-montre.sh [appareil]     appareil : fr165 (défaut) ou fr165m
#         tools/installer-montre.sh --liste        affiche GARMIN/Apps sans rien copier
#
# Prérequis : SDK Connect IQ (connect-iq-sdk-manager), Java 17, developer_key.der,
# libmtp (brew install libmtp) et les outils de compilation Xcode (clang).
# Après la copie, débranchez la montre : elle installe le cadran à ce moment-là.
set -euo pipefail
cd "$(dirname "$0")/.."

# Outil de copie, recompilé si besoin (bin/ est ignoré par git)
LIBMTP="$(brew --prefix libmtp 2>/dev/null || true)"
if [ -z "$LIBMTP" ] || [ ! -f "$LIBMTP/include/libmtp.h" ]; then
    echo "libmtp manquant : brew install libmtp" >&2
    exit 1
fi
TOOL=bin/garminmtp
mkdir -p bin
if [ ! -x "$TOOL" ] || [ tools/garminmtp.c -nt "$TOOL" ]; then
    clang -O2 -Wall -o "$TOOL" tools/garminmtp.c -I"$LIBMTP/include" -L"$LIBMTP/lib" -lmtp
fi

if [ "${1:-}" = "--liste" ]; then
    exec "$TOOL" ls
fi

# Compilation du cadran
DEVICE="${1:-fr165}"
if [ -d /opt/homebrew/opt/openjdk@17/bin ]; then
    export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
fi
export PATH="$(connect-iq-sdk-manager sdk current-path --bin):$PATH"
monkeyc -d "$DEVICE" -f monkey.jungle -o bin/Reticule.prg -y developer_key.der -w

# Copie sur la montre
"$TOOL" put bin/Reticule.prg
echo "Débranchez la montre : elle installe le cadran au débranchement."

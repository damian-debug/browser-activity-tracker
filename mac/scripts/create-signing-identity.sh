#!/bin/bash
# Creates a stable self-signed code-signing identity for local builds.
#
# Why this matters: macOS keys the Accessibility (TCC) grant to the app's code
# signature. Ad-hoc signing produces a different signature every build, so the
# grant is silently dropped — System Settings keeps showing the app as allowed
# while AXIsProcessTrusted() returns false. A stable identity avoids that.
#
# Run once. It needs your password, because marking a certificate as trusted
# for code signing is an admin operation.
set -euo pipefail

NAME="TimeTracker Local Signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "'$NAME' already exists — nothing to do."
    exit 0
fi

echo "==> Generating certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

# Apple's Security framework cannot read OpenSSL 3's default PKCS#12 output,
# so the legacy algorithms are required here.
openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -passout pass:temporary \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> Importing into your login keychain"
security import "$WORK/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P temporary -T /usr/bin/codesign

echo "==> Trusting it for code signing (this is the part that needs your password)"
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain "$WORK/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Done. Rebuild with ./make-app.sh and the signature will stay stable."
else
    echo "The identity still isn't showing as valid. Fall back to Keychain Access:"
    echo "  Keychain Access > Certificate Assistant > Create a Certificate…"
    echo "  Name: $NAME, Identity Type: Self Signed Root, Type: Code Signing"
fi

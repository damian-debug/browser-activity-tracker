#!/bin/bash
# Creates a stable self-signed code-signing identity for local builds.
#
# Why this matters: macOS keys the Accessibility (TCC) grant to the app's code
# signature. Ad-hoc signing produces a different signature every build, so the
# grant is silently dropped — System Settings keeps showing the app as allowed
# while AXIsProcessTrusted() returns false. A stable identity avoids that.
#
# Run once. No password needed: a self-signed certificate with the correct
# key usage can sign straight away, without being added to the system trust
# store.
set -euo pipefail

NAME="TimeTracker Local Signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

can_sign() {
    local probe="$WORK/probe"
    cp /bin/echo "$probe" 2>/dev/null || return 1
    codesign --force --sign "$NAME" "$probe" >/dev/null 2>&1
}

if can_sign; then
    echo "'$NAME' already works — nothing to do."
    exit 0
fi

echo "==> Removing any earlier attempt"
# An earlier certificate missing the right key usage would keep failing, so
# clear it out rather than leaving two identities with the same name.
while security find-certificate -c "$NAME" >/dev/null 2>&1; do
    security delete-certificate -c "$NAME" >/dev/null 2>&1 || break
done

echo "==> Generating certificate"
# BOTH extensions are required. extendedKeyUsage alone yields an identity that
# find-identity lists but codesign refuses with "no identity found", because
# the policy check fails on key usage — a genuinely confusing error to debug.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
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
    -P temporary -T /usr/bin/codesign >/dev/null

echo
if can_sign; then
    echo "Done — '$NAME' can sign."
    echo "Rebuild with ./make-app.sh, then grant Accessibility once. It will"
    echo "now survive every future rebuild."
else
    echo "The identity still cannot sign. Fall back to Keychain Access:"
    echo "  Certificate Assistant > Create a Certificate…"
    echo "  Name: $NAME   Identity Type: Self Signed Root   Type: Code Signing"
    exit 1
fi

#!/bin/bash
# One-time setup (optional): creates a self-signed code-signing certificate "Notchly Local Signing" in your
# login keychain. build.sh then signs every build with it, so the app's identity stays the same across rebuilds
# and macOS remembers "Always Allow" (Keychain, Automation). The certificate never leaves this Mac; delete it in
# Keychain Access → login → My Certificates any time (builds then fall back to ad-hoc signing).
set -euo pipefail
NAME="Notchly Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "Already set up: $NAME"; exit 0; fi
TMP=$(mktemp -d)
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout pass:notchly
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P notchly -T /usr/bin/codesign >/dev/null
rm -f "$TMP/cfg" "$TMP/key.pem" "$TMP/cert.pem" "$TMP/id.p12"; rmdir "$TMP"
echo "Created \"$NAME\" in your login keychain. Now run ./build.sh"

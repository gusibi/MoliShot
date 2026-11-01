#!/bin/bash
# Create once; keep this directory outside the repository and build outputs.
set -euo pipefail
umask 077
SIGNING_DIR="${MOLISHOT_SIGNING_DIR:-$HOME/Library/Application Support/MoliShotSigning}"
if [ -e "$SIGNING_DIR" ]; then
  echo "Signing directory already exists; refusing to replace keys: $SIGNING_DIR" >&2
  exit 1
fi
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
# A stable self-signed identity. No system trust settings are changed.
openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -subj '/CN=MoliShot Release Signing/' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=codeSigning' \
  -keyout "$SIGNING_DIR/code-signing.key" \
  -out "$SIGNING_DIR/code-signing.crt" 2> "$SIGNING_DIR/setup.log"
openssl rand -base64 32 > "$SIGNING_DIR/p12-password.txt"
# Legacy P12 encryption is needed by macOS security import.
openssl pkcs12 -export -legacy -name 'MoliShot Release Signing' \
  -inkey "$SIGNING_DIR/code-signing.key" -in "$SIGNING_DIR/code-signing.crt" \
  -out "$SIGNING_DIR/code-signing.p12" -passout "file:$SIGNING_DIR/p12-password.txt"
openssl x509 -in "$SIGNING_DIR/code-signing.crt" -noout -fingerprint -sha1 \
  | sed 's/.*=//; s/://g' > "$SIGNING_DIR/certificate-sha1.txt"
# Sparkle accepts a base64 encoded 32-byte Ed25519 seed.
openssl genpkey -algorithm ED25519 -out "$SIGNING_DIR/eddsa.pem"
openssl pkey -in "$SIGNING_DIR/eddsa.pem" -outform DER \
  | tail -c 32 | openssl base64 -A > "$SIGNING_DIR/sparkle-private-key.txt"
openssl pkey -in "$SIGNING_DIR/eddsa.pem" -pubout -outform DER \
  | tail -c 32 | openssl base64 -A > "$SIGNING_DIR/sparkle-public-key.txt"
chmod 600 "$SIGNING_DIR"/*
echo "Created signing material in: $SIGNING_DIR"
echo 'Back up this directory securely. Never regenerate these keys for a new release.'
echo 'Public Sparkle key:'
cat "$SIGNING_DIR/sparkle-public-key.txt"
echo

#!/bin/sh
# Creates a self-signed code-signing identity "Sightline Local Signing" in the login keychain,
# so permission grants survive rebuilds. Remove it with:
#   security delete-identity -c "Sightline Local Signing"
set -eu
if security find-identity -p codesigning | grep -q "Sightline Local Signing"; then
    echo "Identity already exists."; exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Sightline Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:sightline 2>/dev/null \
    || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:sightline
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P sightline -T /usr/bin/codesign
echo "Created \"Sightline Local Signing\"."

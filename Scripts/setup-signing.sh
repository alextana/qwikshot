#!/bin/zsh
# Creates a self-signed code signing identity in the login keychain, once.
# Builds signed with it keep the same identity, so macOS keeps their permissions.
set -euo pipefail

NAME="Qwikshot Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASSWORD=$(/usr/bin/openssl rand -hex 16)

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout "pass:$PASSWORD"
security import "$TMP/identity.p12" -k login.keychain-db -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\""

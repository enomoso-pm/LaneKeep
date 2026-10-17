#!/bin/bash
# Creates the self-signed code signing certificate "LaneKeep Self-Signed" (10 years) in the login
# keychain, once per Mac. build_app.sh signs every build with it.
#
#   bash Tools/release/make_cert.sh
#
# Why: macOS remembers the accessibility permission per designated requirement. An ad-hoc signature
# makes it the hash of the build, so every rebuild loses the permission (README, "署名とアクセシビリティ
# の許可について"). Signed with this certificate it is "identifier + this certificate", the same for every
# build. It does not make LaneKeep "notarized": other Macs still ask to confirm it on first launch.
#
# The private key ends up only in the login keychain; the files made here are deleted. The first
# signing asks once whether codesign may use the key: enter the login password and choose "Always Allow".
set -euo pipefail

NAME="${LANEKEEP_SIGN_IDENTITY:-LaneKeep Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl # LibreSSL: writes PKCS#12 files that `security import` can read (OpenSSL 3's default cannot)

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "\"$NAME\" is already in the login keychain"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -passout "pass:$PASS" -out "$TMP/identity.p12"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

security find-identity -p codesigning "$KEYCHAIN" | grep "\"$NAME\""
"$OPENSSL" x509 -in "$TMP/cert.pem" -noout -subject -enddate

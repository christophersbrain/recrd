#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_DIR="$ROOT_DIR/signing"
KEYCHAIN_PATH="$SIGNING_DIR/recrd-signing.keychain-db"
KEYCHAIN_PASSWORD="recrd-local-signing"
CERT_NAME="recrd Local Code Signing"
P12_PASSWORD="recrd-local-signing-p12"
OPENSSL_CONFIG_PATH="$SIGNING_DIR/recrd-signing-openssl.cnf"
KEY_PATH="$SIGNING_DIR/recrd-signing.key"
CERT_PATH="$SIGNING_DIR/recrd-signing.crt"
P12_PATH="$SIGNING_DIR/recrd-signing.p12"

if ! command -v openssl >/dev/null 2>&1; then
    echo "Missing required command: openssl" >&2
    exit 1
fi

mkdir -p "$SIGNING_DIR"

if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

USER_KEYCHAINS=()
while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*"//; s/"$//')"
    if [[ -n "$line" && -f "$line" ]]; then
        USER_KEYCHAINS+=("$line")
    fi
done < <(security list-keychains -d user)

LOGIN_KEYCHAIN="$(security login-keychain | sed -E 's/^[[:space:]]*"//; s/"$//')"
if [[ -n "$LOGIN_KEYCHAIN" && -f "$LOGIN_KEYCHAIN" ]]; then
    USER_KEYCHAINS+=("$LOGIN_KEYCHAIN")
fi

FINAL_KEYCHAINS=("$KEYCHAIN_PATH")
for item in "${USER_KEYCHAINS[@]}"; do
    EXISTS=false
    for existing in "${FINAL_KEYCHAINS[@]}"; do
        if [[ "$existing" == "$item" ]]; then
            EXISTS=true
            break
        fi
    done
    if [[ "$EXISTS" == false ]]; then
        FINAL_KEYCHAINS+=("$item")
    fi
done

security list-keychains -d user -s "${FINAL_KEYCHAINS[@]}"

if ! security find-certificate -c "$CERT_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    cat > "$OPENSSL_CONFIG_PATH" <<'CNF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = recrd Local Code Signing
O = recrd

[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CNF

    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -config "$OPENSSL_CONFIG_PATH" >/dev/null 2>&1

    openssl pkcs12 -export \
        -inkey "$KEY_PATH" \
        -in "$CERT_PATH" \
        -name "$CERT_NAME" \
        -out "$P12_PATH" \
        -passout pass:"$P12_PASSWORD" >/dev/null 2>&1

    security import "$P12_PATH" \
        -k "$KEYCHAIN_PATH" \
        -P "$P12_PASSWORD" \
        -f pkcs12 \
        -T /usr/bin/codesign \
        -T /usr/bin/security >/dev/null

    security set-key-partition-list \
        -S apple-tool:,apple: \
        -s \
        -k "$KEYCHAIN_PASSWORD" \
        "$KEYCHAIN_PATH" >/dev/null

    security add-trusted-cert \
        -d \
        -r trustRoot \
        -k "$KEYCHAIN_PATH" \
        "$CERT_PATH" >/dev/null
fi

IDENTITY_HASH="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk -v cert="$CERT_NAME" '$0 ~ cert { print $2; exit }')"

if [[ -z "$IDENTITY_HASH" && -f "$CERT_PATH" ]]; then
    security add-trusted-cert \
        -d \
        -r trustRoot \
        -k "$KEYCHAIN_PATH" \
        "$CERT_PATH" >/dev/null
    IDENTITY_HASH="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk -v cert="$CERT_NAME" '$0 ~ cert { print $2; exit }')"
fi

if [[ -z "$IDENTITY_HASH" ]]; then
    echo "Could not find code signing identity '$CERT_NAME' in $KEYCHAIN_PATH." >&2
    exit 1
fi

echo "$CERT_NAME"

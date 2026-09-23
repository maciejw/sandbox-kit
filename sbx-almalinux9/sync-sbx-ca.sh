#!/usr/bin/env bash
set -euo pipefail

# SBX supplies this sandbox's public proxy CA at runtime. Never bake it in.
[[ -n ${PROXY_CA_CERT_B64:-} ]] || exit 0
[[ $(id -u) == 0 ]] || { echo 'CA setup must run as root' >&2; exit 1; }

exec 9>/run/sbx-ca.lock
flock 9
candidate=$(mktemp /run/sbx-ca.XXXXXX)
trap 'rm -f "$candidate"' EXIT
printf '%s' "$PROXY_CA_CERT_B64" | base64 --decode > "$candidate"
openssl x509 -in "$candidate" -noout >/dev/null
anchor=/etc/pki/ca-trust/source/anchors/sbx-proxy-ca.crt
if ! cmp -s "$candidate" "$anchor"; then
    install -m 0644 "$candidate" "$anchor"
    update-ca-trust extract
fi

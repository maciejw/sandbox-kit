#!/usr/bin/env bash
set -euo pipefail
sudo -n --preserve-env=PROXY_CA_CERT_B64 /usr/local/sbin/setup-sbx-runtime
exec /bin/bash "$@"

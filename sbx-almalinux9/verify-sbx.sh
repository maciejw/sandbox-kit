#!/usr/bin/env bash
set -euo pipefail
trap 'echo "FAIL at line $LINENO" >&2' ERR

echo '== AlmaLinux and SBX identity =='
source /etc/os-release
[[ $ID == almalinux && $VERSION_ID == 9.* ]]
[[ $(id -u) == 1000 && $(id -g) == 1000 && $(id -un) == agent ]]
[[ $(stat -c %u /home/agent) == 1000 ]]
printf '%s; kernel %s\n' "$PRETTY_NAME" "$(uname -r)"
sudo -n true
for name in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
    [[ -v $name ]]
    [[ $(sudo -n printenv "$name") == "${!name}" ]]
done
echo 'Identity, home ownership, passwordless sudo and proxy preservation: PASS'

echo '== Runtime setup and verified HTTPS =='
# Startup hooks can run concurrently with exec; also verify idempotent setup.
sudo -n --preserve-env=PROXY_CA_CERT_B64 /usr/local/sbin/setup-sbx-runtime
[[ -c /dev/net/tun ]]
[[ -s /etc/pki/ca-trust/source/anchors/sbx-proxy-ca.crt ]]
[[ $(readlink -f "$SSL_CERT_FILE") == /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ]]
registry=https://registry-1.docker.io/v2/
[[ $(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$registry") == 401 ]]
echo 'Registry TLS verification through SBX proxy: PASS (expected HTTP 401)'

echo '== Rootless Podman and native overlay =='
[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]]
[[ $(podman info --format '{{.Store.GraphDriverName}}') == overlay ]]
[[ $(findmnt -n -o FSTYPE -T /home/agent/.local/share/containers) == ext4 ]]
podman info --format '{{.Store.GraphStatus}}'
for map in uid_map gid_map; do
    mapping=$(podman unshare cat "/proc/self/$map")
    printf '%s\n' "$mapping"
    awk 'NR==1 {if ($1!=0 || $2!=1000 || $3!=1) exit 1} NR==2 {if ($1!=1 || $2!=100000 || $3!=65536) exit 1} END {if (NR!=2) exit 1}' <<< "$mapping"
done
base=docker.io/library/alpine:latest
[[ $(podman run --rm "$base" uname -r) == "$(uname -r)" ]]
echo 'Rootless container execution on the SBX kernel: PASS'

echo '== Nested HTTPS =='
[[ $(podman run --rm \
    -v /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem:/run/sbx-ca-bundle.pem:ro \
    docker.io/curlimages/curl:latest --cacert /run/sbx-ca-bundle.pem \
    --max-time 30 -sS -o /dev/null -w '%{http_code}' "$registry") == 401 ]]
echo 'Nested HTTPS with explicit CA mount: PASS'

echo '== Workspace ownership and nested image build =='
workspace=$(realpath -e "${1:-$PWD}")
scratch=$(mktemp -d "$workspace/.sbx-verify.XXXXXX")
test_image="localhost/sbx-verify:verify-$(basename "$scratch" | tr '[:upper:]' '[:lower:]')"
cleanup() {
    podman image rm "$test_image" >/dev/null 2>&1 || true
    rm -f "$scratch/Containerfile" "$scratch/marker" "$scratch/from-container"
    rmdir "$scratch"
}
trap cleanup EXIT
printf 'sbx-workspace-roundtrip\n' > "$scratch/marker"
podman run --rm -v "$scratch:/work" "$base" sh -ec \
    'test "$(cat /work/marker)" = sbx-workspace-roundtrip; cp /work/marker /work/from-container'
cmp "$scratch/marker" "$scratch/from-container"
[[ $(stat -c %u "$scratch/from-container") == 1000 ]]
printf '%s\n' "FROM $base" 'COPY marker /marker' 'RUN test "$(cat /marker)" = sbx-workspace-roundtrip' > "$scratch/Containerfile"
podman build --pull=never -t "$test_image" "$scratch"
[[ $(podman run --rm "$test_image" cat /marker) == sbx-workspace-roundtrip ]]
echo 'Workspace roundtrip, ownership and image build with RUN: PASS'

echo '== Resource-limit diagnostic (not an enforcement guarantee) =='
limits=$(podman run --rm --memory 64m --cpus 0.5 --pids-limit 64 "$base" \
    sh -ec 'cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max /sys/fs/cgroup/pids.max')
printf '%s\n' "$limits"
if [[ $limits == $'67108864\n50000 100000\n64' ]]; then
    echo 'Per-container memory/CPU/PID limits: enforced'
else
    echo 'LIMITATION: per-container limits are not enforced; use SBX VM CPU/memory limits.'
fi
echo 'PASS: AlmaLinux SBX, rootless Podman, storage, TLS, workspace and build checks'

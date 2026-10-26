#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Runtime setup must run as root' >&2; exit 1; }
exec 8>/run/sbx-runtime.lock
flock 8

/usr/local/sbin/sync-sbx-ca

# /dev is recreated on sandbox restart. The guest has TUN support but does not
# populate this device node. Pasta needs it for rootless container networking.
install -d -m 0755 /dev/net
if [[ ! -e /dev/net/tun ]]; then
    mknod -m 0666 /dev/net/tun c 10 200
fi
[[ -c /dev/net/tun ]]

# Keep Podman on the kit's block-backed volume: overlay-on-overlay falls back
# to FUSE, whose device is inaccessible in the tested SBX runtime.
storage=/home/agent/.local/share/containers
mountpoint -q "$storage" || { echo "Missing SBX storage volume: $storage" >&2; exit 1; }
# SBX may create the volume's parent directories as root before mounting it.
# The developer tool store is a sibling of the Podman volume and must remain
# writable by the non-root agent user.
install -d -m 0755 /home/agent/.local /home/agent/.local/share
chown agent:agent /home/agent/.local /home/agent/.local/share
chown agent:agent "$storage"

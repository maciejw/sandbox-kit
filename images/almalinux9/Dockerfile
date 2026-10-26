FROM docker.io/library/almalinux:9 AS sbx-base

USER root

# SBX base-image contract and the Ansible control node used by every sandbox.
RUN <<'INSTALL_BASE'
set -euxo pipefail

dnf -y install \
  sudo shadow-utils procps-ng util-linux iproute curl-minimal ca-certificates diffutils \
  python3.12 python3.12-pip

. /etc/os-release
majorver="${VERSION_ID%%.*}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' \
  "https://packages.microsoft.com/config/rhel/${majorver}/packages-microsoft-prod.rpm" \
  -o "$temporary/packages-microsoft-prod.rpm"
dnf -y install "$temporary/packages-microsoft-prod.rpm"
curl -fsSL --retry 3 --proto '=https' --proto-redir '=https' \
  'https://download.docker.com/linux/centos/docker-ce.repo' \
  -o /etc/yum.repos.d/docker-ce.repo
dnf clean all

groupadd --gid 1000 agent
# Keep the image home empty; runtime Stow owns profile files and avoids
# conflicting with /etc/skel defaults such as .bashrc.
useradd --uid 1000 --gid agent --no-create-home --home-dir /home/agent --shell /bin/bash \
  -K SUB_UID_MIN=100000 -K SUB_UID_COUNT=65536 \
  -K SUB_GID_MIN=100000 -K SUB_GID_COUNT=65536 agent
echo 'agent ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/agent
chmod 0440 /etc/sudoers.d/agent
printf '%s\n' \
  'Defaults:agent env_keep += "HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy"' \
  > /etc/sudoers.d/agent-proxy
chmod 0440 /etc/sudoers.d/agent-proxy
mkdir -p /home/agent/workspace
chown -R 1000:1000 /home/agent
INSTALL_BASE

# Install the pinned control-plane tools into an image-owned virtual environment.
RUN <<'INSTALL_ANSIBLE'
set -euxo pipefail
python3.12 -m venv /opt/ansible
/opt/ansible/bin/python -m pip install --no-cache-dir \
  ansible-core==2.21.4 ansible-lint==26.9.0
ln -s /opt/ansible/bin/ansible /usr/local/bin/ansible
ln -s /opt/ansible/bin/ansible-playbook /usr/local/bin/ansible-playbook
ln -s /opt/ansible/bin/ansible-lint /usr/local/bin/ansible-lint
INSTALL_ANSIBLE

# Fail the build if user creation did not provision rootless mappings/helpers.
RUN <<'VALIDATE_ROOTLESS'
set -euxo pipefail
grep -qx 'agent:100000:65536' /etc/subuid
grep -qx 'agent:100000:65536' /etc/subgid
command -v newuidmap
command -v newgidmap
visudo -cf /etc/sudoers
VALIDATE_ROOTLESS

COPY --chmod=0755 images/almalinux9/verify-sbx.sh /usr/local/bin/verify-sbx
COPY --chmod=0755 images/almalinux9/sync-sbx-ca.sh /usr/local/sbin/sync-sbx-ca
COPY --chmod=0755 images/almalinux9/setup-sbx-runtime.sh /usr/local/sbin/setup-sbx-runtime
COPY --chmod=0755 images/almalinux9/sbx-shell.sh /usr/local/bin/sbx-shell

RUN ln -s /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/pki/tls/certs/ca-certificates.crt

USER agent
ENV HOME=/home/agent
ENV ANSIBLE_FORCE_COLOR=1
ENV PATH="/opt/ansible/bin:/home/agent/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
WORKDIR /home/agent/workspace

CMD ["/bin/bash"]

# Shared development prerequisites. Application tools and personal profile are
# restored after creating a sandbox with the workspace mounted.
FROM sbx-base AS development-runtime
USER root
RUN <<'INSTALL_DEVELOPMENT_RUNTIME'
set -euxo pipefail
dnf -y install epel-release
dnf -y install \
  git jq stow tar gzip xz findutils unzip libicu powershell docker-compose-plugin \
  openssl-libs krb5-libs zlib libstdc++ libgcc lttng-ust \
  podman fuse-overlayfs slirp4netns
dnf -y upgrade --refresh
dnf clean all
INSTALL_DEVELOPMENT_RUNTIME

FROM development-runtime AS development
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
USER agent
ENV HOME=/home/agent
ENV NPM_CONFIG_PREFIX=/home/agent/.local
ENV PATH="/opt/ansible/bin:/home/agent/.local/bin:/home/agent/.dotnet/tools:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
CMD ["/bin/bash"]

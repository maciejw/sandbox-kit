# AlmaLinux 9 image

This directory contains the Dockerfile and scripts installed into the image.
SBX configuration is a separate [base kit](../../kits/almalinux9/spec.yaml).
See the [root quickstart](../../README.md) for creating a sandbox.

Build from the repository root, which remains the Docker build context:

```powershell
podman build --format docker -f images/almalinux9/Dockerfile -t localhost/almalinux9-sbx:dev .
```

`Publish-SbxImage.ps1` builds the same image, exports it, and loads it into the
local SBX image store. It does not publish to a remote registry. Application
tools and the developer profile are provisioned separately at runtime.

For distribution, publish the image to a container registry and reference it
from the base kit. See [Kit distribution](../../kits/README.md).

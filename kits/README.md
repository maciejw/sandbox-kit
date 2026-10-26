# Sandbox kits and distribution

The image and kit are separate artifacts. `images/almalinux9/` supplies the
image build; [almalinux9/spec.yaml](almalinux9/spec.yaml) selects that image and
defines its SBX launch, storage, privilege, network, and setup configuration.
[Team policy mixins](policies/README.md) add optional rules without another image.

Each kit has its own directory containing `spec.yaml`, with an optional
`files/` tree. Our base kit invokes runtime scripts already installed in the
image, so consumers do not need the Dockerfile or script sources to load it.
Multiple kits can reference the same image. Keep kit and image versions
compatible: the image must supply every executable used by the kit.

## Local workflow

From the repository root:

```powershell
.\Publish-SbxImage.ps1
sbx kit validate ./kits/almalinux9 --offline --json
.\New-SbxSandbox.ps1 -Name alma9-dev -WorkspacePath D:\sandbox-workspace
```

The base spec retains `localhost/almalinux9-sbx:dev` for local development.
The publish script loads an archive into SBX's local image store; it does not
upload either artifact to a registry.

## Sharing with others

SBX accepts kit directories, ZIP files, Git references, and OCI registry
references. These are illustrative release commands, separate from the local
quickstart. Replace the example organization and versions.

`registry.example.com` represents your OCI registry endpoint. GitHub Container
Registry (`ghcr.io`) is one option; JFrog Artifactory with Docker/OCI repository
support is another. Use the registry hostname and repository path supplied by
your administrator, not an Artifactory browser UI URL. Configure authentication
for both Podman image uploads and SBX kit uploads. Verify kit push/pull and
signature/provenance support against your deployed Artifactory version; this
repository has not tested that integration.

1. Build and publish the image:

   ```powershell
   podman build --format docker -f images/almalinux9/Dockerfile -t registry.example.com/team/sandbox-almalinux9:1.0 .
   podman push registry.example.com/team/sandbox-almalinux9:1.0
   ```

2. Prepare a release copy of `kits/almalinux9` whose `sandbox.image` references
   the published image, preferably by digest:

   ```yaml
   sandbox:
     image: registry.example.com/team/sandbox-almalinux9@sha256:<published-image-digest>
   ```

   Change only the image reference; retain the entrypoint and other fields.
   Keep the development spec's local reference for the local workflow.

3. Validate and distribute that release kit. For example, if the release copy
   is in `artifacts/almalinux9-kit`:

   ```powershell
   sbx kit validate ./artifacts/almalinux9-kit --offline --json
   sbx kit push ./artifacts/almalinux9-kit registry.example.com/team/almalinux9-kit:1.0 --sign
   sbx kit push ./kits/policies/team-backend registry.example.com/team/backend-policy:1.0 --sign
   ```

   Replace policy placeholder hosts before publishing. Consumers need registry
   access and any signature trust required by their SBX installation.

4. Consumers select the published kits:

   ```powershell
   sbx create --name my-dev --cpus 2 --memory 2g `
     --kit registry.example.com/team/backend-policy:1.0 `
     registry.example.com/team/almalinux9-kit:1.0 D:\my-project
   ```

Alternatively, distribute a ZIP with
`sbx kit pack ./artifacts/almalinux9-kit -o artifacts/almalinux9-kit.zip`, or
commit the release spec and use a pinned Git reference:

```powershell
sbx create "git+https://github.com/myorg/sandbox-kit.git#ref=<commit>&dir=kits/almalinux9" D:\my-project
```

That Git revision must reference a published image rather than our local tag.
Pin released dependencies: signing a kit does not freeze a mutable image tag
or downloads performed by runtime setup.

## Provisioning boundary

Publishing these artifacts provides the SBX runtime, including Ansible and
Stow. It does not automatically install this repository's developer tools or
profile. The consumer command above creates the runtime only.

Our [initializer](../Initialize-SbxSandbox.ps1) expects a read-only mount of
this repository and uses its Ansible playbooks. For the full development
environment, consumers also need a checkout, its read-only mount, and
initialization with its guest path. Follow the [root quickstart](../README.md)
and [team policy example](policies/README.md) for that mount layout. A separately
distributed provisioning/profile mechanism is outside the current workflow.

## Versions and references

This repository retains schema v2. Docker supports v2 and recommends v3 for new
kits; migration is a separate change, not a directory rename.

- [Docker v2 kit format, packaging, and signing](https://docs.docker.com/ai/sandboxes/customize/kits-v2/)
- [JFrog OCI repository support](https://docs.jfrog.com/artifactory/docs/oci-repositories)
- [Team policy customization](policies/README.md)
- [Base kit runtime guide](almalinux9/README.md)

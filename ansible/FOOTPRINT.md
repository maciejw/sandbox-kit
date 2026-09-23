# Ansible footprint

The Ansible implementation is the only sandbox provisioning path. The
inventory owns tool state, `install-tool.yml` owns checksum-verified downloads
and release links, and the profile playbook restores files into the agent home.

The old DSC resource module and JSON documents were removed rather than kept as
a parallel implementation. This leaves one source of truth and one execution
path.

The remaining custom logic is intentionally narrow:

- checksum-derived release directories and per-user command links;
- archive extraction with explicit `stripComponents` values;
- command-path assertions after extraction;
- Ansible check mode for tool/profile verification;
- profile-tree restoration into the agent home.

The image owns Ansible Core `2.21.4` and ansible-lint `26.9.0` in `/opt/ansible`.
The repository is mounted at runtime and supplies only inventory, playbooks,
and the developer profile. The `tasks/` directory contains Ansible task
fragments only.

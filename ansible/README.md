# Ansible Role: `audiomxd_remediation`

Automated deployment role for remediating the macOS Tahoe `audiomxd` runaway loop across fleet Apple Silicon Macs.

## Example Playbook

```yaml
---
- name: Remediate macOS Tahoe audiomxd Spin Loop
  hosts: mac_fleet
  become: true
  roles:
    - audiomxd_remediation
```

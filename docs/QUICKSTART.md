# Quickstart

This walks through deploying Uptime Kuma to a fresh Debian 12/13 VPS using
this collection. Estimated time: ~10 minutes of actual work plus one Let's
Encrypt round-trip.

## Prerequisites

- A Debian 12 or 13 host reachable over SSH (root, or a sudoer with an SSH
  key you control).
- A public DNS record (`A`/`AAAA`) pointing to the host for the status page
  domain you'll use.
- Ansible (`ansible-core`) 2.19+ on your control node (laptop/workstation).
- An SSH keypair you'll use as the deploy user's authorised key.

## 1. Minimal deployment (Kuma only)

Four files on your control node:

```
my-uptime/
├── requirements.yml
├── inventory.yml
├── site.yml
└── (optional) vars.yml
```

### `requirements.yml`

```yaml
---
# Pin versions
collections:
  - name: just_barcodes.uptime_kuma
    source: https://github.com/just-barcodes/uptime-kuma-ansible
    type: git
    version: main # or a release tag (e.g. 0.1.0)
  - name: community.general
    version: "==12.5.0"
  - name: ansible.posix
    version: "==2.1.0"
```

### `inventory.yml`

```yaml
---
all:
  children:
    uptime_kuma:
      hosts:
        my-uptime-box:
          ansible_host: 203.0.113.10
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

### `site.yml`

```yaml
---
- import_playbook: just_barcodes.uptime_kuma.deploy
  vars:
    uptime_kuma_domain: status.example.com
    uptime_kuma_letsencrypt_email: ops@example.com
```

### Run it

```sh
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.yml site.yml
```

After the run completes, visit `https://status.example.com` and complete
Uptime Kuma's first-run setup in the browser.

## 2. Add host hardening

Enable the `harden` role to install baseline security (SSH lockdown, UFW,
fail2ban, unattended-upgrades, a deploy user):

```yaml
# site.yml
- import_playbook: just_barcodes.uptime_kuma.deploy
  vars:
    uptime_kuma_domain: status.example.com
    uptime_kuma_letsencrypt_email: ops@example.com

    harden_enabled: true
    harden_deploy_user_pubkey_file: ~/.ssh/id_ed25519.pub
    harden_timezone: Europe/Berlin
    harden_public_allow_ports:
      - { port: "80", proto: "tcp", comment: "HTTP (Caddy ACME + redirect)" }
      - { port: "443", proto: "tcp", comment: "HTTPS" }
      - { port: "443", proto: "udp", comment: "HTTP/3 (QUIC)" }
```

After the first run, connect as the `deploy` user for subsequent runs — root
SSH is disabled. Update your inventory:

```yaml
ansible_user: deploy
```

## 3. Add Tailscale (and close public SSH)

Enable the `tailscale` role and the optional lockdown step:

```yaml
# site.yml
- import_playbook: just_barcodes.uptime_kuma.deploy
  vars:
    uptime_kuma_domain: status.example.com
    uptime_kuma_letsencrypt_email: ops@example.com

    harden_enabled: true
    harden_deploy_user_pubkey_file: ~/.ssh/id_ed25519.pub
    harden_public_allow_ports:
      - { port: "80", proto: "tcp", comment: "HTTP" }
      - { port: "443", proto: "tcp", comment: "HTTPS" }
      - { port: "443", proto: "udp", comment: "HTTP/3" }

    tailscale_enabled: true
    tailscale_authkey: "{{ lookup('env', 'TS_AUTHKEY') }}" # or sops-encrypted
    tailscale_tags: "tag:uptime"
    tailscale_lock_ssh_to_tailnet: true
```

Get a pre-auth key at <https://login.tailscale.com/admin/settings/keys>. For
production use, encrypt it with
[sops](https://github.com/getsops/sops) or Ansible Vault — don't commit it
plaintext.

After the first run, port 22 is closed on the public internet and future
Ansible runs must go via Tailscale. Update `inventory.yml`:

```yaml
ansible_host: my-uptime-box.tailXXXXX.ts.net # MagicDNS name from admin console
```

## Two-phase bootstrap pattern

Because the first run closes public SSH, many consumers split their inventory
into two files: `bootstrap.yml` (public IP, `ansible_user: root`) for the
first run, and `tailnet.yml` (MagicDNS name, `ansible_user: deploy`) for
every run after that. The collection does not enforce this — it's a consumer
convention. `homelab-uptime` is an example.

## Variables reference

Full variable lists with defaults are in each role's `defaults/main.yml`:

- [`roles/uptime_kuma/defaults/main.yml`](../roles/uptime_kuma/defaults/main.yml)
- [`roles/harden/defaults/main.yml`](../roles/harden/defaults/main.yml)
- [`roles/tailscale/defaults/main.yml`](../roles/tailscale/defaults/main.yml)

## Troubleshooting

**Caddy fails to get a certificate.** DNS for `uptime_kuma_domain` must
resolve to the host's public IPv4 before the first run. Check with
`dig +short status.example.com`. Also verify ports 80/443 are open in any
upstream cloud firewall (Zap, Hetzner, etc.) — UFW alone isn't enough.

**Ansible can't reach the host after Tailscale lockdown.** The lockdown step
runs `tailscale status --json` before touching firewall rules, so you should
never end up locked out — but if it happens, use your provider's web console
(e.g. Zap's VNC) to run `ufw allow 22/tcp` and re-investigate.

**Uptime Kuma setup screen keeps appearing.** Check the container logs:
`ssh deploy@host 'docker logs uptime-kuma'`. Kuma writes its SQLite DB to
the `kuma_data` Docker volume on first-run completion; if the volume was
recreated, setup restarts.


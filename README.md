# just_barcodes.uptime_kuma

Ansible Collection that deploys [Uptime Kuma](https://github.com/louislam/uptime-kuma)
behind [Caddy](https://caddyserver.com/) (automatic HTTPS via Let's Encrypt) on
any Debian host over SSH. Optional roles bundle opinionated SSH/UFW/fail2ban
hardening and Tailscale enrolment with a public-SSH lockdown step.

- **Scope**: one Uptime Kuma instance per host, Debian-only, Caddy as reverse
  proxy, Docker Compose under the hood.
- **Security posture**: key-only SSH, UFW default-deny, fail2ban, unattended
  security upgrades, optional Tailscale-only admin access.
- **Secrets**: none ship with the collection. Bring your own vault.

## Why?

I have an "extensive" homelab which among other things makes services available on the web. Inside it I have various monitors and obervability tools, but of course if the whole cluster goes down they don't help that much... So in addition I wanted an "external" monitor that lives outside the cluster. That monitor is Uptime Kuma, which I run on a small VPS. This collection is the result of my efforts to automate that deployment with Ansible.

## Pre-requisites

- A Debian host with SSH access (I'm currently using a spare VPS from https://zap-hosting.com/).
- A public DNS record for your status-page domain pointing to the host's public IP **before** the first run — Caddy needs it to obtain a Let's Encrypt certificate via the HTTP-01 challenge. Either an `A` record alone, or both `A` and `AAAA` if the host has working IPv6 connectivity (a stale/broken `AAAA` will cause cert issuance to fail).

The reference playbook `just_barcodes.uptime_kuma.deploy` will do the rest: install Docker CE, deploy Uptime Kuma + Caddy in a compose stack, and optionally harden the host and enroll it in Tailscale.

## Quick start

```yaml
# requirements.yml
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

```yaml
# inventory.yml
all:
  hosts:
    my-uptime-box:
      ansible_host: 203.0.113.10 # change to your host's IP or domain
      ansible_user: root
```

```yaml
# site.yml
- import_playbook: just_barcodes.uptime_kuma.deploy
  vars:
    uptime_kuma_domain: status.example.com # change to your domain
    uptime_kuma_letsencrypt_email: ops@example.com # change to your email for Let's Encrypt notifications
```

```sh
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.yml site.yml
```

That deploys just Uptime Kuma + Caddy. For host hardening (highly recommended!) and Tailscale, see
[`docs/QUICKSTART.md`](docs/QUICKSTART.md).

## Roles

| Role                                | Required | Purpose                                                             |
| ----------------------------------- | -------- | ------------------------------------------------------------------- |
| [`uptime_kuma`](roles/uptime_kuma/) | yes      | Docker CE + Uptime Kuma + Caddy compose stack.                      |
| [`harden`](roles/harden/)           | no       | SSH, UFW, fail2ban, unattended-upgrades, sysctl, deploy user.       |
| [`tailscale`](roles/tailscale/)     | no       | Install + `tailscale up`; optional "lock SSH to tailnet" post-step. |

The reference playbook `just_barcodes.uptime_kuma.deploy` composes all three,
gated by `harden_enabled` / `tailscale_enabled` booleans (default `false`).
`uptime_kuma` always runs.

## Supported targets

- Debian 12 (Bookworm), Debian 13 (Trixie). Other Debian-derived distros are
  not tested.
- Single host per play.

## Operational notes

### Backups

**None.** This collection does not configure any backup mechanism. Uptime
Kuma's SQLite database lives in the `kuma_data` Docker volume on the target
host; if the host is lost, monitor history and configuration are lost with
it. If you need durability, snapshot the volume (or the whole VPS) out of
band.

### Monitors and notifications

Uptime Kuma has no declarative config — there is nothing this collection can
pre-seed. After the first deploy, visit `https://<your-domain>`, complete
the first-run admin setup, and add monitors and notification channels in the
UI. They persist in the `kuma_data` volume across re-runs of the playbook.

### Public SSH stays open unless Tailscale lockdown is enabled

`harden_enabled: true` opens port 22 to the public internet during bootstrap
(`harden_allow_public_ssh_during_bootstrap: true` by default). The only thing
that ever _closes_ that rule is the `tailscale` role's optional lockdown step
(`tailscale_enabled: true` + `tailscale_lock_ssh_to_tailnet: true`). If you
deploy `harden_enabled: true` without Tailscale, public SSH remains open for
the lifetime of the host — still key-only and fail2ban-protected, but
reachable from anywhere.

If that's not what you want, set `harden_allow_public_ssh_during_bootstrap:
false` (your control node must already be able to reach the host some other
way — e.g. an existing VPN or provider console) or enable Tailscale lockdown.

### Automatic updates

- **OS packages** (only when `harden_enabled: true`): the `harden` role
  installs and configures `unattended-upgrades` to apply Debian security
  updates daily, and reboots the host automatically at **03:30 local time**
  if a package requires it. Unused dependencies are removed. Adjust your
  monitoring to expect a brief gap around that time.
- **Container images**: not auto-updated. `uptime_kuma_image` is pinned to
  the `louislam/uptime-kuma:2` major tag and `uptime_kuma_caddy_image` to
  `caddy:2-alpine`. Re-running the playbook pulls the latest tag and
  recreates the stack — that is the supported upgrade path.

## Local development

The lint/test toolchain (`ansible-core`, `ansible-lint`, `yamllint`) is pinned
in `pyproject.toml` and managed with [uv](https://github.com/astral-sh/uv).
A `Makefile` wraps the common commands so local runs match CI exactly:

```sh
make help            # list all targets
make lint            # yamllint + ansible-lint
make syntax-check    # ansible-playbook --syntax-check on the reference playbook
make preflight-check # tagged assert tasks in --check mode to catch runtime arg validation bugs
make build           # build the collection tarball into dist/
make test            # full local CI: lint + syntax + preflight + tarball install
make clean           # remove build artifacts and the local collections cache
```

The first run of any target installs `uv`-managed deps and symlinks this
collection into `.ansible/collections/` so Ansible can resolve it by its FQCN
(`just_barcodes.uptime_kuma.*`). CI runs the same targets — see
`.github/workflows/ci.yml`.

## Licence

MIT. See [LICENSE](LICENSE).

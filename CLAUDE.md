# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

`just_barcodes.uptime_kuma` — a public Ansible Collection that deploys
[Uptime Kuma](https://github.com/louislam/uptime-kuma) behind Caddy (auto
HTTPS) on a Debian host over SSH. Opt-in roles bundle SSH/UFW/fail2ban
hardening and Tailscale enrolment with a public-SSH lockdown step.

The collection is the **library**. Consumers supply their own inventory,
variables, and secrets (sops-encrypted or otherwise).

## Design rules

- **Three decoupled roles**, composed by a reference playbook:
  - `uptime_kuma` — required. Docker + Kuma + Caddy.
  - `harden` — opt-in. Baseline host hardening.
  - `tailscale` — opt-in. Tailscale install + enrolment; optional "lock public
    SSH to tailnet0" post-step lives here (gated by
    `tailscale_lock_ssh_to_tailnet`).
- **Role isolation**: a role must not reference another role's variables. The
  one shared cross-role var is `deploy_user` (convention, not coupling).
- **Required vars fail loud**. Roles `assert` their required inputs early
  rather than silently producing broken configs.
- **No secrets in the collection.** Consumers supply their own vault.
- **Debian-only** for now. Don't add conditional branches for RHEL/Ubuntu
  until someone actually asks — and then split the task logic by distro
  cleanly, not with sprinkled `when:` clauses.
- **One host per play.** If a multi-host scenario appears, restructure then,
  not pre-emptively.

## Variable naming

Role-specific variables are prefixed with the role name:

- `uptime_kuma_domain`, `uptime_kuma_install_dir`, `uptime_kuma_image`, …
- `harden_ssh_port`, `harden_fail2ban_*`, `harden_public_allow_ports`, …
- `tailscale_authkey`, `tailscale_tags`, `tailscale_lock_ssh_to_tailnet`, …

Exceptions (cross-role convention):

- `deploy_user` — a shared name for the non-root account the stack runs as.

When adding a new variable, prefix it with the owning role.

## Versioning

- Semver. Breaking variable renames or role removals bump the major.
- `galaxy.yml:version` must match any release tag.

## Testing

- The pinned toolchain lives in `pyproject.toml`; use `make lint` for
  `yamllint` + `ansible-lint`, or `make test` for the full local CI
  (lint + `ansible-playbook --syntax-check` + tarball install smoke test).
  CI runs the same targets on a matrix of ansible-core 2.19/2.20.
- `tests/ci/inventory.yml` and `tests/ci/vars.yml` are stubs for syntax-check
  only — never executed against a real host.
- Molecule is not yet set up. If you add tests, prefer the
  `docker` driver with a Debian image.

## Instructions for Claude

- Don't add "flexibility" the user hasn't asked for (distro switches, extra
  Docker options, alternative reverse proxies). This is a focused deployment
  library, not a framework.
- Any SSH / firewall / Tailscale interaction: think through the lockout path.
  Tests are fine, but a bad role task can lock a real consumer out of their
  VPS.
- Uptime Kuma has no declarative config — monitors and notifiers are
  configured in the UI. Do not try to pre-seed its SQLite DB.
- `Caddyfile.j2` and `docker-compose.yaml.j2` currently ship as `0644` (no
  secrets in them). If a future change templates anything sensitive into
  either (e.g. Caddy basicauth, a notifier token), drop the rendered file to
  `0640 root:caddy` first so local users on the host can't read it.


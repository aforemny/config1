# CLAUDE.md - Agent Instructions

## Context
This repository contains NixOS configurations for multiple systems (ap, apu, x1e, tower, m1) with shared modules and platform definitions.

## Project Structure
```
src/
├── systems/        # Per-host config (systems.<name>.modules)
├── platforms/      # Hardware platform definitions (disko, facter, boot)
├── features/       # Cross-cutting infra modules (state, persistence, rollback-rootfs)
├── conventions/    # Wiring conventions (e.g. tie platforms to systems)
├── options/        # Cake / module-system option declarations
├── users/          # User configurations
└── *.nix           # Individual service/program modules (all of src/ is auto-imported)
```

## Architecture
- Not a flake: `default.nix` evaluates every `src/**/*.nix` with `lib.evalModules` (the "cake" framework); dependencies are pinned with **npins** in `npins/`.
- `cake-module.nix` auto-imports all of `src/` recursively (`*.nix` only — editor `*.nix~` backups are ignored), so a new module is active just by existing.
- Top-level (cake) options live in `src/options/` (`systems`, `platforms`, `nixosModules`, `overlays`, …). Reach a host's evaluated NixOS config at `config.systems.<name>.config`.

## Common Tasks

### System Configuration Updates
- Primary systems: `apu` (router/gateway), `ap` (L2 WiFi access point, bridged to `apu`), `x1e` (laptop), `tower` (headless ZFS NAS/server), `m1` (Apple Silicon Mac)
- Configuration pattern: platforms provide hardware, systems compose features
- After changes: `ASECRET_DRY_RUN= cake build --expr config.systems.<system>.config.system.build.toplevel`

### Code Standards
- Two layers: a top-level `src/*.nix` is a *cake* module (`{ config, lib, pkgs, sources, ... }`) that usually defines `nixosModules.<name> = { config, lib, pkgs, ... }: …`; these apply to every host.
- Scope config to one host with `systems.<name>.modules = [ { /* nixos module */ } ];` (see `radicle.nix`, `dns.nix`).
- Maintain existing code style and indentation; format with `nixfmt` (RFC style, via `treefmt`) before committing.
- Verify changes before committing (see Quick Commands).

## Conventions

### Git Workflow
- Atomic commits with descriptive messages
- Feature branches for major changes
- Test on one system before deploying to all

### Module Organization
- Hardware-specific → `platforms/<name>.nix`
- System composition → `systems/<name>.nix`
- Reusable service/program modules → top-level `src/<name>.nix` (define `nixosModules.<name>`)
- Cross-cutting feature infra → `features/` (e.g. `state`, `persistence`, `rollback-rootfs`)
- User-specific → `users/<name>.nix`

### Security
- Two secret backends: `asecret` (GPG password-store under `secrets/`; `pkgs.asecret-lib.password "<path>"` yields a `LoadCredential` source) and `agenix-rekey` (age, under `secrets1/`).
- agenix-rekey: a secret with a `generator` defaults its `rekeyFile` to `secrets1/generated/<name>.age`; per-host rekeyed copies are `secrets1/rekeyed/<host>/<hash>-<name>.age`. Define reusable generators centrally in `src/agenix-rekey.nix` (`age.generators.<name>`) and reference them via `age.secrets.<name>.generator.script = "<name>"`. A generator may write an adjacent committed `<name>.pub` for eval-time public keys (see `ssh-ed25519-pub`, used by `radicle.nix`).
- Rotate/create secrets with `agenix generate [-f] <name>`, then `agenix rekey` (needs the master identity `~/.ssh/id_ed25519`; master pubkey in `default.nix`, host pubkeys in `src/host-keys.nix`).
- On rollback-rootfs hosts, agenix decrypts with the SSH host key **from `/persist`** — `age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" … ]` (set in `agenix-rekey.nix`, scoped to `fileSystems ? "/persist"`). The agenix *activation script* runs before impermanence bind-mounts `/etc/ssh` on cold boot, so the default `/etc/ssh` path gives "no readable identities" and **every** secret fails to decrypt; `/persist` is `neededForBoot` so it is mounted in time. Don't revert to the `/etc/ssh` default.
- No plaintext passwords in configs.
- Use systemd's `LoadCredential` for runtime secrets.

### Persistence
- Hosts with a rollback rootfs (e.g. `tower`) wipe `/` on boot (`features/rollback-rootfs.nix`); declare survivable paths via `state.directories` / `state.files`, which `features/persistence.nix` collects into `/persist`.
- Any stateful service MUST add its data dir (and `/var/lib/acme` if it terminates TLS), or it loses state every reboot.
- Verify persistence/secret/rollback changes with a **reboot, not `nixos-rebuild switch`** — `switch` hides cold-boot-only behaviour: the agenix host-key ordering (see *Security*), `state.directories` add/removes (impermanence mounts are established at boot), and secret-*content* changes for services that read the secret only at start (e.g. VPN-Confinement's `tvpn.service`, which `switch` does not restart).
- For a `DynamicUser=yes` service, persist `/var/lib/private/<name>`, **never** the public `/var/lib/<name>`: systemd keeps dynamic-user state under `/var/lib/private/`, and persisting the public path makes systemd migrate public→private on start (a `rename()` of a bind-mount) → `EBUSY` / `238/STATE_DIRECTORY`. State ends up owned by the name-derived dynamic UID (stable across boots; re-mints if it drifts). See `keycloak.nix`'s `declarative-keycloak-bootstrap`.

### Public services (DNS & TLS)
- `tower` is the public-facing host; its dynamic IPv6 is published to the `nomath.org` Hetzner zone by `src/dns.nix`.
- A service declares its own label via the `dns.dynamicAAAA` option (e.g. `dns.dynamicAAAA = [ "radicle" ];`); `src/dns.nix` collects every label through the module system and syncs the AAAA records. Don't hardcode record lists in `dns.nix`.
- For HTTPS: `services.nginx.enable`, ACME (`security.acme.acceptTerms` + `defaults.email`), `forceSSL`/`enableACME` on the vhost, open firewall 80/443, and persist `/var/lib/acme`.

## Active Issues
<!-- List any known issues or ongoing work here -->
- IPv6 NAT on apu router (should use proper routing)

## Quick Commands

All eval/build runs **inside the devshell** (`.envrc` = `use nix`, or `nix-shell`): its `shellHook` sets `NIX_CONFIG` (nix-plugins `plugin-files` + asecret `extra-builtins-file`) and `PASSWORD_STORE_DIR`. Outside it, eval fails with `attribute 'extraBuiltins' missing`. Always prefix with `ASECRET_DRY_RUN=` so GPG isn't invoked during eval.

### Build a system
```bash
ASECRET_DRY_RUN= cake build --expr config.systems.<system>.config.system.build.toplevel
```

### Fast verify (eval only, no build)
`cake eval` runs `with (import ./. {}); <expr>` with `--read-write-mode`, so freshly added/rekeyed secret files are picked up.
```bash
ASECRET_DRY_RUN= cake eval --expr 'config.systems.<system>.config.system.build.toplevel.drvPath'
ASECRET_DRY_RUN= cake eval --expr 'config.systems.<system>.config.services.<svc>.enable'
```

## Notes
<!-- Add project-specific notes, decisions, or context here -->

## References
- NixOS Manual: https://nixos.org/manual/nixos/stable/
- NixOS Options: https://search.nixos.org/options
- Systemd Network: https://www.freedesktop.org/software/systemd/man/systemd.network.html

---
*Last updated: 2026-07-03*

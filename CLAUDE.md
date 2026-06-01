# CLAUDE.md - Agent Instructions

## Context
This repository contains NixOS configurations for multiple systems (apu, x1e, tower, m1) with shared modules and platform definitions.

## Project Structure
```
src/
├── systems/        # System-specific configurations
├── platforms/      # Hardware platform definitions  
├── features/       # Reusable feature modules
├── options/        # Custom NixOS options
├── users/          # User configurations
└── *.nix          # Individual service/program modules
```

## Common Tasks

### System Configuration Updates
- Primary systems: `apu` (router), `x1e` (laptop), `tower` (laptop), `m1` (Mac)
- Configuration pattern: platforms provide hardware, systems compose features
- After changes: `ASECRET_DRY_RUN= cake build --expr config.systems.<system>.config.system.build.toplevel`

### Code Standards
- NixOS modules use `config`, `lib`, `pkgs` arguments
- Maintain existing code style and indentation
- Test changes with `ASECRET_DRY_RUN= cake build --expr config.systems.<system>.config.system.build.toplevel` first

## Conventions

### Git Workflow
- Atomic commits with descriptive messages
- Feature branches for major changes
- Test on one system before deploying to all

### Module Organization
- Hardware-specific → `platforms/`
- System composition → `systems/`
- Reusable services → feature modules
- User-specific → `users/<name>.nix`

### Security
- Secrets managed via `asecret` module
- No plaintext passwords in configs
- Use systemd's `LoadCredential` for runtime secrets

## Active Issues
<!-- List any known issues or ongoing work here -->
- IPv6 NAT on apu router (should use proper routing)

## Quick Commands

### Test configuration
```bash
ASECRET_DRY_RUN= cake build --expr config.systems.<system>.config.system.build.toplevel
```

## Notes
<!-- Add project-specific notes, decisions, or context here -->

## References
- NixOS Manual: https://nixos.org/manual/nixos/stable/
- NixOS Options: https://search.nixos.org/options
- Systemd Network: https://www.freedesktop.org/software/systemd/man/systemd.network.html

---
*Last updated: 2024-06-01*

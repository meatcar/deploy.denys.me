## Codebase: Direnv + Nix + Terraform

Infrastructure to collaborate, save time, improve reliability, and simplify maintenance.

```
flake.nix                    # inputs and entry point
.envrc                       # pinned environment and optional local credentials
flake-parts/                 # shell, checks, formatting, packages, hosts, deploy
nixos/modules/               # reusable NixOS services and configuration
nixos/systems/               # host configuration and recovery instructions
packages/cli-proxy-api/       # credential operations, backups, and tests
terraform/                   # Terragrunt workflow and primary infrastructure state
  tf-modules/                # reusable Terraform modules
  bao/                       # AWS KMS, IAM, and backup storage for OpenBao
  bao-config/                # OpenBao auth, policies, and project secrets
  netbird/                   # VPN access policies and private DNS
  ovh-vps/                   # existing OpenBao VPS
  railway/                   # hosted projects, services, volumes, and domains
secrets/                     # encrypted provisioning inputs, see README
output/                      # ignored local provisioning artifacts
```

## Principles

- Red/Green TDD. Conventional Commits: consistent scopes, short titles. Atomic, testable, logically distinct commits.
- Stay in your workspace/environment. Be careful with network or out-of-workspace actions that may affect running systems.
- Practice disciplined product engineering: user-first, simple, maintainable, secure, reliable, and evolvable.
- Self-documenting code and configuration, the absolute minimum of documentation.

## Safety

- Don't edit encrypted files without keys. Use appropriate secret manager/pattern.
- Keep secrets, state, and build outputs safe, out of commits, caches, stores, and logs as applicable. 
- Build modified hosts for verification.

## Commands (repo root)

- Run commands: `direnv exec .`, always from repo root.
- Flake checks: `nix flake check` | `nix build .#checks.<system>.<name>`
    - Format/lint: `nix fmt` (required for commit)
    - Add new lint/checks when tech stack shifts, ensuring fast runtime.
- List outputs: `nix flake show`
- Update input: `nix flake lock --override-input <input> <url+rev>`
- Plan and apply through `terragrunt` (see `./terraform/README.md` for details).

## Nix

- Nixpkgs conventions.
- Use pinned Nixpkgs only for intentional unstable packages.
- New modules: directory + `default.nix`, consistent with neighbors.
- Multi-line scripts in standalone files.
    - Rethink the necessity of big scripts, recommend appropriate tool or implementation approach as needed.
    - Similar things go together. Properly organize and namespace as needed.
- Impermanence where possible to separate runtime state from static config.
- Use git-backed nix flake sources.

## Documentation

- Clarity: Light, terse and focused, just enough to orient a smart developer. Avoid narrative and duplication.
- Progressive disclosure and single source of truth: co-locate guidance with its context, link rather than repeat. Strictly only what code cannot express, keep how-to steps separate from explanation.
- Workflow: inspect the implementation, fix clarity/structure/discoverability there first, write the minimum useful guidance, cut duplication and narrative, verify links and instructions.

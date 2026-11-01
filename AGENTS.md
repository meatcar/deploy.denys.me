## Codebase: Direnv + Nix + Terraform

Infrastructure to collaborate, save time, improve reliability, and simplify maintenance.

Layout and runbooks: [README](README.md). `output/` holds ignored local provisioning artifacts.

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
- Dependencies: `task deps -- list|outdated|upgrade|lint`. Every added or changed version, image, input, or source must appear in `task deps -- list`; pin it per the [conventions](README.md#dependencies). The `deps-lint` check catches pins Renovate cannot see.
- Update input: `nix flake lock --override-input <input> <url+rev>`
- Plan and apply through `tofu`; Terragrunt is an optional bulk runner (see `./terraform/README.md`).

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

## Project Memory

Stored in `docs/memory/`.

**Session start:** Read the `project-memory` skill and follow it.

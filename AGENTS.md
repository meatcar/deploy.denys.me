# Repository conventions

- Keep READMEs as short navigation indexes. Put procedures in `docs/runbooks/` and durable decisions in `docs/design/`. Omit deployment history.
- Put Python commands in `packages/<service>/src/`, with `pyproject.toml`, `package.nix`, and adjacent `tests/`. Expose namespaced entry points instead of loose scripts.
- Group multi-file NixOS services under `nixos/modules/<kind>/<service>/`; keep single-file modules simple. NixOS owns service lifecycle, not application logic.
- Keep Terraform roots independent. Place their test tooling under `terraform/tests/`.
- Nix pins dependencies and exposes checks. Python uses pytest fixtures and Ruff through `nix fmt`; container tests are opt-in and use isolated state.
- Preserve behavior during layout changes. Verify package entry points, NixOS evaluation, Terraform references, and documentation links after moves.

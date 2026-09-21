# Repository conventions

- Validate with `nix flake check`; wire new quality checks into it.
- Plan and apply through Terragrunt; follow [the infrastructure runbook](docs/runbooks/terraform.md). Keep state roots independent.
- Keep READMEs as indexes, procedures in `docs/runbooks/`, and decisions in `docs/design/`. Link to the canonical workflow instead of repeating commands.
- Package Python operations in `packages/<service>/` with namespaced entry points and adjacent tests. NixOS modules own service lifecycle.
- Group multi-file services under `nixos/modules/<kind>/<service>/`; leave single-file modules simple.
- Use Git-backed Nix flake sources. Path flakes copy ignored secrets and state into the store. Preserve ignore rules protecting local data.

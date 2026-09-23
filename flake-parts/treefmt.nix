{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, lib, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          nixfmt.package = pkgs.nixfmt;
          statix.enable = true;
          deadnix.enable = true;
          ruff-format.enable = true;
          ruff-check.enable = true;
          terraform.enable = true;
          hclfmt.enable = true;
          shellcheck.enable = true;
          shfmt.enable = true;
          jsonfmt.enable = true;
          taplo.enable = true;
        };
        settings.formatter.ruff-format.includes = lib.mkForce [
          "packages/**/*.py"
          "terraform/**/*.py"
          "nixos/modules/**/*.py"
        ];
        settings.formatter.ruff-check.includes = lib.mkForce [
          "packages/**/*.py"
          "terraform/**/*.py"
          "nixos/modules/**/*.py"
        ];
        settings.global.excludes = [
          "flake.lock"
          "*.age"
          "nixos/generated/**"
        ];
      };
    };
}

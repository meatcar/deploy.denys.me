{ pkgs, ... }:
{
  projectRootFile = "flake.nix";
  programs = {
    nixfmt.enable = true;
    nixfmt.package = pkgs.nixfmt;
    statix.enable = true;
    deadnix.enable = true;
  };
  settings.global.excludes = [
    "flake.lock"
    "*.age"
    "nixos/generated/**"
  ];
}

{ pkgs, ... }:
{
  projectRootFile = "flake.nix";
  programs = {
    nixfmt.enable = true;
    nixfmt.package = pkgs.nixfmt-rfc-style;
    statix.enable = true;
    deadnix.enable = true;
  };
  settings.global.excludes = [
    "flake.lock"
    "*.age"
    "nixos/generated/**"
  ];
}

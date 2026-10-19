{ inputs, ... }:
{
  imports = [
    ./checks.nix
    ./deploy.nix
    ./devshell.nix
    ./hosts.nix
    ./packages.nix
    ./secret-scan.nix
    ./treefmt.nix
  ];

  flake.templates.orb-access = {
    path = ../templates/orb-access;
    description = "Task-based Amp orb lifecycle with NetBird and on-demand Bao JWT access";
    welcomeText = ''
      Read .agents/README.md, supply the devshell packages and project BAO_ROLE,
      then run chmod +x .agents/setup .agents/resume.
    '';
  };

  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-darwin"
    "x86_64-linux"
  ];

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
}
